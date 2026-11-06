# coding=utf-8
"""
tgdrama 后端（Python 版，实现 tgdrama1.py 依赖的 /api/* 契约）

用途：在你自己的机器/手机上提供一个 127.0.0.1:5278 的本地服务，
让 FongMi 里的 `tgdrama1.py` 有数据可读。

两个运行模式：
1) 真实模式（默认）：用 Telethon 登录你自己的 Telegram 账号，读你已加入的
   频道里的视频消息，登记成剧库，并把视频以支持 Range 的 http 流吐给播放器。
   需要 TGD_APP_ID / TGD_APP_HASH（my.telegram.org 申请），首次扫码登录。
2) 自测模式（TGD_FAKE=1）：不连 Telegram，内置假数据 + 假视频文件，
   用来验证 HTTP 契约、SQLite、Range 是否正常。

只依赖标准库；真实模式额外依赖 telethon（pip install telethon）。
"""

import asyncio
import json
import math
import os
import re
import socketserver
import sqlite3
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlsplit

# ---------------- 配置（全部走环境变量，避免把密钥写进代码） ----------------
HOST = os.environ.get("TGD_HOST", "127.0.0.1")
PORT = int(os.environ.get("TGD_PORT", "5278"))
DATA_DIR = os.environ.get("TGD_DATA", os.path.expanduser("~/.tgdrama"))
DB_PATH = os.path.join(DATA_DIR, "tgdrama.db")
SESSION_PATH = os.path.join(DATA_DIR, "session")
MEDIA_DIR = os.path.join(DATA_DIR, "media")
APP_ID = os.environ.get("TGD_APP_ID", "").strip()
APP_HASH = os.environ.get("TGD_APP_HASH", "").strip()
PROXY = os.environ.get("TGD_PROXY", "").strip()       # 例：socks5://127.0.0.1:7890
FAKE = os.environ.get("TGD_FAKE", "") == "1"

PAGE_SIZE = 30

os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(MEDIA_DIR, exist_ok=True)


# ---------------- SQLite ----------------
SCHEMA = """
CREATE TABLE IF NOT EXISTS chats(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tg_chat_id INTEGER UNIQUE,
  name TEXT,
  type TEXT,
  enabled INTEGER DEFAULT 0,
  message_count INTEGER DEFAULT 0,
  source_count INTEGER DEFAULT 0,
  syncing INTEGER DEFAULT 0,
  updated_at INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS shows(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE,
  cover_path TEXT DEFAULT '',
  intro TEXT DEFAULT '',
  updated_at INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS episodes(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  show_id INTEGER,
  episode_no INTEGER,
  title TEXT,
  UNIQUE(show_id, episode_no)
);
CREATE TABLE IF NOT EXISTS sources(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  episode_id INTEGER,
  chat_id INTEGER,
  message_id INTEGER,
  file_size INTEGER DEFAULT 0,
  duration REAL DEFAULT 0,
  mime TEXT DEFAULT 'video/mp4',
  file_path TEXT DEFAULT '',
  created_at INTEGER DEFAULT 0,
  UNIQUE(episode_id, chat_id, message_id)
);
CREATE TABLE IF NOT EXISTS favorites(
  show_id INTEGER PRIMARY KEY,
  created_at INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS history(
  episode_id INTEGER PRIMARY KEY,
  show_id INTEGER,
  position REAL DEFAULT 0,
  duration REAL DEFAULT 0,
  updated_at INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_ep_show ON episodes(show_id);
CREATE INDEX IF NOT EXISTS idx_src_ep ON sources(episode_id);
CREATE INDEX IF NOT EXISTS idx_src_chat ON sources(chat_id);
"""


def db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db():
    conn = db()
    try:
        conn.executescript(SCHEMA)
        conn.commit()
    finally:
        conn.close()


def query(sql, args=(), many=False):
    conn = db()
    try:
        cur = conn.execute(sql, args)
        if many:
            return [dict(row) for row in cur.fetchall()]
        row = cur.fetchone()
        return dict(row) if row is not None else None
    finally:
        conn.close()


def execute(sql, args=()):
    conn = db()
    try:
        cur = conn.execute(sql, args)
        conn.commit()
        return cur.lastrowid
    finally:
        conn.close()


# ---------------- 剧集名解析（从消息文字/文件名里抠剧名和集号） ----------------
EP_PATTERNS = [
    re.compile(r"第\s*(\d{1,4})\s*[集话期]"),
    re.compile(r"[Ee][Pp]\s*[\.\-]?\s*(\d{1,4})"),
    re.compile(r"(?<![A-Za-z0-9])\b(\d{1,4})\s*[集话]"),
    re.compile(r"\[(\d{1,4})\]"),
]
NOISE = re.compile(r"[【】\[\]（）()《》<>|｜/\\]+")


def parse_episode(text, fallback_no):
    """返回 (剧名, 集号)。识别不出来时剧名取前 20 字，集号用消息序号兜底。"""
    raw = (text or "").strip()
    if not raw:
        return "", fallback_no
    line = raw.splitlines()[0].strip()
    pos, number = None, None
    for pattern in EP_PATTERNS:
        match = pattern.search(line)
        if match:
            number = int(match.group(1))
            break
    # 剧名 = 集号标记之前的部分；没有标记就把整行当剧名
    show_candidates = []
    for pattern in EP_PATTERNS:
        match = pattern.search(line)
        if match:
            show_candidates.append(line[:match.start()])
    name = max(show_candidates, key=len).strip() if show_candidates else line
    name = NOISE.sub(" ", name)
    name = re.sub(r"\s{2,}", " ", name).strip(" -_·.,:：")
    if len(name) > 40:
        name = name[:40].strip()
    if not name:
        name = raw.splitlines()[0][:20].strip() or "未命名短剧"
    return name, (number if number else fallback_no)


def upsert_show(name):
    row = query("SELECT id FROM shows WHERE name=?", (name,))
    if row:
        return row["id"]
    return execute("INSERT INTO shows(name, updated_at) VALUES(?,?)", (name, int(time.time())))


def upsert_episode(show_id, episode_no, title):
    row = query("SELECT id FROM episodes WHERE show_id=? AND episode_no=?", (show_id, episode_no))
    if row:
        return row["id"]
    return execute("INSERT INTO episodes(show_id, episode_no, title) VALUES(?,?,?)",
                   (show_id, episode_no, title))


# ---------------- Telegram 数据源 ----------------
class BaseSource(object):
    """数据源接口：真实模式与自测模式共用。"""

    name = "base"

    def status(self):
        return {"authorized": False, "phase": "error", "message": "未实现"}

    def qr(self):
        raise NotImplementedError

    def submit_password(self, password):
        raise NotImplementedError

    def chats(self):
        return []

    def sync(self, tg_chat_id=None):
        return {"ok": True, "synced": 0}

    def fetch_media(self, source_id):
        """确保本地有该分段的文件，返回 (路径, 是否就绪)。"""
        return "", False

    def close(self):
        pass


class FakeSource(BaseSource):
    """自测模式：不连 Telegram，造两套剧、三个集、一个假视频文件。"""

    name = "fake"

    def __init__(self):
        self.media_file = os.path.join(MEDIA_DIR, "fake.mp4")
        if not os.path.exists(self.media_file):
            with open(self.media_file, "wb") as handle:
                # 1MB 假数据，够验证 Range 与 206
                handle.write(b"\x00\x00\x00\x18ftypmp42" + os.urandom(1024 * 1024))
        self._seed()

    def _seed(self):
        """造两条剧、各 3 集，写进库，让接口有真实数据可读。"""
        for chat in self.chats():
            row = query("SELECT id FROM chats WHERE tg_chat_id=?", (chat["tg_chat_id"],))
            if not row:
                execute("INSERT INTO chats(tg_chat_id, name, type, enabled, message_count, updated_at) "
                        "VALUES(?,?,?,?,?,?)",
                        (chat["tg_chat_id"], chat["name"], chat["type"], chat["enabled"],
                         chat["message_count"], int(time.time())))
        chat_a = query("SELECT id FROM chats WHERE tg_chat_id=?", (-1001234567890,))["id"]
        for name, count in (("测试短剧·豪门千金", 3), ("测试短剧·闪婚首富", 3)):
            show_id = upsert_show(name)
            for number in range(1, count + 1):
                episode_id = upsert_episode(show_id, number, "第%d集" % number)
                execute("INSERT OR IGNORE INTO sources(episode_id, chat_id, message_id, file_size, mime, created_at) "
                        "VALUES(?,?,?,?,?,?)",
                        (episode_id, chat_a, 1000 + number, os.path.getsize(self.media_file),
                         "video/mp4", int(time.time())))

    def status(self):
        return {"authorized": True, "phase": "ready", "message": "自测模式，未连接 Telegram"}

    def qr(self):
        return {"url": "tg://login?token=fake-token"}

    def submit_password(self, password):
        return {"ok": True}

    def chats(self):
        return [
            {"id": 1, "tg_chat_id": -1001234567890, "name": "测试短剧频道A", "type": "channel",
             "enabled": 1, "message_count": 20, "source_count": 9, "syncing": 0},
            {"id": 2, "tg_chat_id": -1009876543210, "name": "测试短剧频道B", "type": "channel",
             "enabled": 0, "message_count": 8, "source_count": 3, "syncing": 0},
        ]

    def sync(self, tg_chat_id=None):
        return {"ok": True, "synced": 3}

    def fetch_media(self, source_id):
        return self.media_file, True


class TelethonSource(BaseSource):
    """真实模式：Telethon 登录 + 读频道 + 下载视频。"""

    name = "telethon"

    def __init__(self):
        from telethon import TelegramClient                     # 延迟导入，自测模式不需要
        proxy = None
        if PROXY:
            parts = urlsplit(PROXY)
            proxy = {
                "proxy_type": (parts.scheme or "socks5"),
                "addr": parts.hostname,
                "port": parts.port or 1080,
            }
        self.client = TelegramClient(SESSION_PATH, int(APP_ID), APP_HASH, proxy=proxy)
        self.loop = asyncio.new_event_loop()
        threading.Thread(target=self.loop.run_forever, daemon=True).start()
        self._qr = None
        self._qr_task = None
        self._run(self.client.connect())

    # ---- 异步桥 ----
    def _run(self, coro, timeout=30):
        return asyncio.run_coroutine_threadsafe(coro, self.loop).result(timeout)

    def _spawn(self, coro):
        return asyncio.run_coroutine_threadsafe(coro, self.loop)

    # ---- 登录 ----
    def status(self):
        try:
            if self._run(self.client.is_user_authorized(), 10):
                return {"authorized": True, "phase": "ready", "message": ""}
            if self._qr is not None:
                return {"authorized": False, "phase": "qr", "message": "请扫码"}
            return {"authorized": False, "phase": "init", "message": "未登录，请点扫码登录"}
        except Exception as error:
            return {"authorized": False, "phase": "error", "message": str(error)}

    def qr(self):
        async def _new_qr():
            qr = await self.client.qr_login()
            self._qr = qr

            async def _waiter():
                try:
                    await qr.wait()
                except Exception:
                    pass
            self._qr_task = asyncio.ensure_future(_waiter())
            return qr.url

        try:
            if self._qr is not None and not getattr(self._qr, "expired", True) and self._qr.url:
                return {"url": self._qr.url}
        except Exception:
            pass
        url = self._run(_new_qr(), 30)
        return {"url": url}

    def submit_password(self, password):
        def _do():
            return self._run(self.client.sign_in(password=password), 30)
        _do()
        return {"ok": True}

    # ---- 频道 ----
    def chats(self):
        rows = query("SELECT * FROM chats ORDER BY id", (), many=True)
        for row in rows:
            row["syncing"] = 1 if row.get("syncing") else 0
            row["enabled"] = 1 if row.get("enabled") else 0
        return rows

    def refresh_dialogs(self):
        from telethon import utils as tg_utils              # -100 前缀由官方工具算，别自己拼

        async def _list():
            dialogs = await self.client.get_dialogs(limit=200)
            items = []
            for dialog in dialogs:
                entity = dialog.entity
                if getattr(entity, "id", None) is None:
                    continue
                try:
                    tg_id = int(tg_utils.get_peer_id(entity))
                except Exception:
                    continue
                kind = "group" if getattr(entity, "megagroup", False) else "channel"
                items.append({
                    "tg_chat_id": tg_id,
                    "name": dialog.name or str(tg_id),
                    "type": kind,
                    "message_count": int(dialog.message_count or 0),
                })
            return items
        return self._run(_list(), 60)

    def sync(self, tg_chat_id=None):
        if tg_chat_id:
            rows = [row for row in query("SELECT * FROM chats WHERE tg_chat_id=?", (int(tg_chat_id),), many=True)]
        else:
            rows = query("SELECT * FROM chats WHERE enabled=1", (), many=True)
        total = 0
        for chat in rows:
            execute("UPDATE chats SET syncing=1 WHERE id=?", (chat["id"],))
            try:
                total += self._sync_one(chat)
            finally:
                execute("UPDATE chats SET syncing=0, updated_at=? WHERE id=?",
                        (int(time.time()), chat["id"]))
        return {"ok": True, "synced": total}

    def _sync_one(self, chat):
        """把一个频道的视频消息登记成剧集：靠 caption/文件名里的"第N集"归集。"""

        async def _iter():
            messages = await self.client.get_messages(int(chat["tg_chat_id"]), limit=500)
            payload = []
            for message in messages:
                if not message or not message.document:
                    continue
                mime = getattr(message.document, "mime_type", "") or ""
                if not mime.startswith("video/"):
                    continue
                payload.append({
                    "message_id": message.id,
                    "text": (message.message or "").strip(),
                    "file_name": next((getattr(attr, "file_name", None)
                                       for attr in (message.document.attributes or [])
                                       if getattr(attr, "file_name", None)), "") or "",
                    "file_size": int(getattr(message.document, "size", 0) or 0),
                    "duration": 0,
                })
            return payload

        items = self._run(_iter(), 90)
        count, seen = 0, {}
        for item in items:
            title = item["text"] or item["file_name"]
            name, episode_no = parse_episode(title, item["message_id"])
            if episode_no in seen:
                continue
            seen[episode_no] = True
            show_id = upsert_show(name)
            episode_id = upsert_episode(show_id, episode_no, title or ("第%d集" % episode_no))
            execute(
                "INSERT OR IGNORE INTO sources(episode_id, chat_id, message_id, file_size, duration, mime, created_at) "
                "VALUES(?,?,?,?,?,?,?)",
                (episode_id, chat["id"], item["message_id"], item["file_size"], item["duration"],
                 "video/mp4", int(time.time())))
            count += 1
        execute("UPDATE chats SET source_count=(SELECT COUNT(*) FROM sources WHERE chat_id=?) WHERE id=?",
                (chat["id"], chat["id"]))
        return count

    # ---- 拉流 ----
    def fetch_media(self, source_id):
        row = query("SELECT * FROM sources WHERE id=?", (source_id,))
        if not row:
            return "", False
        if row["file_path"] and os.path.exists(row["file_path"]):
            return row["file_path"], True
        target = os.path.join(MEDIA_DIR, "ep%s_%s.mp4" % (row["episode_id"], row["message_id"]))

        async def _download():
            chat = query("SELECT * FROM chats WHERE id=?", (row["chat_id"],))
            if not chat:
                return False
            message = await self.client.get_messages(int(chat["tg_chat_id"]), ids=int(row["message_id"]))
            if not message:
                return False
            await self.client.download_media(message, file=target)
            return os.path.exists(target)

        try:
            ok = self._run(_download(), 300)
        except Exception:
            return "", False
        if ok:
            execute("UPDATE sources SET file_path=? WHERE id=?", (target, source_id))
            return target, True
        return "", False

    def close(self):
        try:
            self._run(self.client.disconnect(), 10)
        except Exception:
            pass


# ---------------- 业务逻辑 ----------------
class Store(object):
    def __init__(self, source):
        self.source = source
        self._downloading = set()
        self._lock = threading.Lock()

    # --- 首页/列表 ---
    def shows_page(self, page=1, tag="", favorite=False):
        page = max(int(page or 1), 1)
        offset = (page - 1) * PAGE_SIZE
        where = ""
        if favorite:
            where = " WHERE sh.id IN (SELECT show_id FROM favorites)"
        elif tag:
            where = " WHERE sh.name LIKE ?"
        args = ("%" + tag + "%",) if (tag and not favorite) else ()
        rows = query(
            "SELECT sh.id, sh.name, sh.cover_path, sh.intro, "
            "(SELECT COUNT(*) FROM episodes e WHERE e.show_id=sh.id) AS ep_count, "
            "(SELECT COALESCE(MAX(e.episode_no),0) FROM episodes e WHERE e.show_id=sh.id) AS ep_latest "
            "FROM shows sh" + where + " ORDER BY sh.updated_at DESC, sh.id DESC LIMIT ? OFFSET ?",
            args + (PAGE_SIZE, offset), many=True)
        total = query("SELECT COUNT(*) AS n FROM shows sh" + where, args)
        return {"list": rows, "total": int(total["n"] if total else 0),
                "page": page, "page_size": PAGE_SIZE}

    def show_detail(self, show_id):
        show = query("SELECT * FROM shows WHERE id=?", (show_id,))
        if not show:
            return {"error": "短剧不存在"}
        episodes = query("SELECT id, episode_no, title FROM episodes WHERE show_id=? ORDER BY episode_no",
                         (show_id,), many=True)
        progress = query("SELECT h.*, e.episode_no FROM history h JOIN episodes e ON e.id=h.episode_id "
                         "WHERE h.show_id=? ORDER BY h.updated_at DESC LIMIT 1", (show_id,), many=True)
        show["ep_count"] = len(episodes)
        show["ep_latest"] = max([row["episode_no"] or 0 for row in episodes] or [0])
        return {"show": show, "episodes": episodes, "progress": progress}

    def episode_lines(self, episode_id):
        episode = query("SELECT * FROM episodes WHERE id=?", (episode_id,))
        if not episode:
            return {"error": "剧集不存在"}
        show = query("SELECT * FROM shows WHERE id=?", (episode["show_id"],)) or {}
        rows = query(
            "SELECT s.*, c.name AS chat_name, c.tg_chat_id FROM sources s "
            "JOIN chats c ON c.id=s.chat_id WHERE s.episode_id=? ORDER BY s.id", (episode_id,), many=True)
        lines = []
        for row in rows:
            # 每集一个"分段"（id 即 source id）：这样 tgdrama1.py 会走正常播放分支，
            # 顺带把观看历史写回后端；本后端不做切片，一个分段就是整集。
            lines.append({
                "source_id": row["id"],
                "chat_id": row["chat_id"],
                "chat_name": row.get("chat_name") or "",
                "segments": [{
                    "id": row["id"],
                    "index": 1,
                    "duration": row.get("duration") or 0,
                    "size": row.get("file_size") or 0,
                }],
            })
        return {"episode": episode, "show": show, "lines": lines}

    def tags(self):
        rows = query("SELECT name FROM shows", (), many=True)
        # 没有真实标签体系，按剧名前两个字聚一下，给筛选一个可用维度
        counts = {}
        for row in rows:
            key = (row["name"] or "")[:2]
            if key:
                counts[key] = counts.get(key, 0) + 1
        return [{"name": key, "count": value} for key, value in sorted(counts.items())]

    def search(self, keyword):
        if not keyword:
            return {"list": [], "total": 0}
        rows = query(
            "SELECT sh.id, sh.name, sh.cover_path, sh.intro, "
            "(SELECT COUNT(*) FROM episodes e WHERE e.show_id=sh.id) AS ep_count, "
            "(SELECT COALESCE(MAX(e.episode_no),0) FROM episodes e WHERE e.show_id=sh.id) AS ep_latest "
            "FROM shows sh WHERE sh.name LIKE ? LIMIT 100",
            ("%" + keyword + "%",), many=True)
        return {"list": rows, "total": len(rows)}

    # --- 收藏 / 历史 ---
    def favorites(self):
        rows = query(
            "SELECT sh.id, sh.name, sh.cover_path, sh.intro, "
            "(SELECT COUNT(*) FROM episodes e WHERE e.show_id=sh.id) AS ep_count, "
            "(SELECT COALESCE(MAX(e.episode_no),0) FROM episodes e WHERE e.show_id=sh.id) AS ep_latest "
            "FROM favorites f JOIN shows sh ON sh.id=f.show_id ORDER BY f.created_at DESC", (), many=True)
        return {"list": rows}

    def toggle_favorite(self, show_id):
        row = query("SELECT show_id FROM favorites WHERE show_id=?", (show_id,))
        if row:
            execute("DELETE FROM favorites WHERE show_id=?", (show_id,))
            return {"ok": True, "favorite": False}
        execute("INSERT OR IGNORE INTO favorites(show_id, created_at) VALUES(?,?)",
                (show_id, int(time.time())))
        return {"ok": True, "favorite": True}

    def history(self, limit=10):
        limit = max(int(limit or 10), 1)
        rows = query(
            "SELECT h.episode_id, h.show_id, h.position, h.duration, e.episode_no, "
            "sh.name AS show_name, sh.cover_path FROM history h "
            "JOIN episodes e ON e.id=h.episode_id JOIN shows sh ON sh.id=h.show_id "
            "ORDER BY h.updated_at DESC LIMIT ?", (limit,), many=True)
        result = []
        for row in rows:
            duration = float(row["duration"] or 0)
            row["progress"] = (float(row["position"] or 0) / duration) if duration else 0.0
            result.append(row)
        return {"list": result}

    def save_history(self, episode_id, position, duration):
        episode = query("SELECT show_id FROM episodes WHERE id=?", (episode_id,))
        if not episode:
            return {"error": "剧集不存在"}
        execute("INSERT INTO history(episode_id, show_id, position, duration, updated_at) VALUES(?,?,?,?,?) "
                "ON CONFLICT(episode_id) DO UPDATE SET position=excluded.position, "
                "duration=excluded.duration, updated_at=excluded.updated_at",
                (episode_id, episode["show_id"], float(position), float(duration), int(time.time())))
        return {"ok": True}

    # --- 频道 ---
    def chats(self):
        rows = self.source.chats()
        if not rows:
            rows = query("SELECT * FROM chats ORDER BY id", (), many=True)
            for row in rows:
                row["enabled"] = 1 if row.get("enabled") else 0
                row["syncing"] = 1 if row.get("syncing") else 0
        return rows

    def sync_chats(self, tg_chat_id=None):
        return self.source.sync(tg_chat_id)

    def refresh_chats(self):
        if not hasattr(self.source, "refresh_dialogs"):
            return {"ok": True, "count": len(self.chats())}
        items = self.source.refresh_dialogs()
        for item in items:
            row = query("SELECT id FROM chats WHERE tg_chat_id=?", (item["tg_chat_id"],))
            if row:
                execute("UPDATE chats SET name=?, type=?, message_count=? WHERE id=?",
                        (item["name"], item["type"], item["message_count"], row["id"]))
            else:
                execute("INSERT INTO chats(tg_chat_id, name, type, enabled, message_count, updated_at) "
                        "VALUES(?,?,?,0,?,?)",
                        (item["tg_chat_id"], item["name"], item["type"],
                         item["message_count"], int(time.time())))
        return {"ok": True, "count": len(items)}

    def toggle_chat(self, tg_chat_id, enabled):
        row = query("SELECT id FROM chats WHERE tg_chat_id=?", (int(tg_chat_id),))
        if not row:
            return {"error": "频道不存在，请先刷新对话列表"}
        execute("UPDATE chats SET enabled=? WHERE id=?", (1 if enabled else 0, row["id"]))
        return {"ok": True, "syncing": False}

    def clear_cache(self):
        for name in os.listdir(MEDIA_DIR):
            try:
                os.remove(os.path.join(MEDIA_DIR, name))
            except OSError:
                pass
        conn = db()
        try:
            conn.execute("UPDATE sources SET file_path=''")
            conn.commit()
        finally:
            conn.close()
        return {"ok": True}

    def download_status(self):
        return {"active": len(self._downloading), "items": []}

    # --- 媒体 ---
    def media_path(self, source_id):
        row = query("SELECT * FROM sources WHERE id=?", (source_id,))
        if not row:
            return "", False
        path, ready = self.source.fetch_media(source_id)
        return path, ready

    def cover_png(self):
        # 1x1 灰色 PNG，占位够用；真实封面需要从消息里缩略图取，本版没做
        return (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
                b"\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00"
                b"\x00\x03\x01\x01\x00\x18\xdd\x8d\xb0\x00\x00\x00\x00IEND\xaeB`\x82")


# ---------------- HTTP ----------------
class Handler(BaseHTTPRequestHandler):
    store = None
    server_version = "tgdrama-py/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("[tgdrama] " + (fmt % args) + "\n")

    # ---- 工具 ----
    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _error(self, message, code=400):
        self._json({"error": message}, code)

    def _read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8", "replace"))
            return data if isinstance(data, dict) else {}
        except ValueError:
            return {}

    def _serve_file(self, path, mime="video/mp4"):
        size = os.path.getsize(path)
        ranges = self.headers.get("Range")
        start, end = 0, size - 1
        code = 200
        if ranges:
            match = re.match(r"bytes=(\d*)-(\d*)", ranges)
            if match:
                if match.group(1):
                    start = int(match.group(1))
                if match.group(2):
                    end = min(int(match.group(2)), size - 1)
                if start > end or start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", "bytes */%d" % size)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                code = 206
        length = end - start + 1
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if code == 206:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.end_headers()
        with open(path, "rb") as handle:
            handle.seek(start)
            remaining = length
            while remaining > 0:
                chunk = handle.read(min(262144, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    return
                remaining -= len(chunk)

    # ---- GET ----
    def do_GET(self):
        try:
            self._route_get()
        except Exception as error:
            self.log_message("GET %s 出错: %s", self.path, error)
            try:
                self._error("服务端异常：%s" % error, 500)
            except Exception:
                pass

    def _route_get(self):
        parts = urlsplit(self.path)
        path = parts.path
        qs = parse_qs(parts.query)

        def q(name, default=""):
            return (qs.get(name) or [default])[0]

        if path == "/api/auth/status":
            return self._json(self.store.source.status())
        if path == "/api/auth/qr":
            try:
                return self._json(self.store.source.qr())
            except Exception as error:
                return self._error("二维码不可用：%s" % error, 404)
        if path == "/api/auth/qr.png":
            return self._error("本后端不提供 PNG，前端会用 qr 字段本地渲染", 404)
        if path == "/api/bootstrap":
            data = self.store.shows_page(1)
            return self._json({"shows": data["list"]})
        if path == "/api/shows":
            return self._json(self.store.shows_page(q("page", "1"), q("tag"), q("fav") in ("1", "true")))
        if path.startswith("/api/shows/"):
            rest = path[len("/api/shows/"):]
            if rest.endswith("/fill"):
                return self._json({"ok": True})
            if rest.isdigit():
                return self._json(self.store.show_detail(int(rest)))
            return self._error("bad show id", 404)
        if path.startswith("/api/episodes/") and path.endswith("/lines"):
            episode_id = path[len("/api/episodes/"):-len("/lines")]
            if episode_id.isdigit():
                return self._json(self.store.episode_lines(int(episode_id)))
            return self._error("bad episode id", 404)
        if path.startswith("/api/episodes/") and path.endswith("/play"):
            episode_id = path[len("/api/episodes/"):-len("/play")]
            if not episode_id.isdigit():
                return self._error("bad episode id", 404)
            rows = query("SELECT id FROM sources WHERE episode_id=? ORDER BY id", (int(episode_id),), many=True)
            for row in rows:
                path_on_disk, ready = self.store.media_path(row["id"])
                if ready and os.path.exists(path_on_disk):
                    return self._serve_file(path_on_disk)
            return self._error("媒体尚未就绪（可能需要先在频道页同步/等下载）", 404)
        if path.startswith("/api/episodes/") and path.endswith("/hls/index.m3u8"):
            body = "# 本后端未实现切片，请用 /api/episodes/{id}/play 整集直连\n".encode("utf-8")
            self.send_response(404)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path.startswith("/api/stream/"):
            seg_id = path[len("/api/stream/"):]
            if not seg_id.isdigit():
                return self._error("bad stream id", 404)
            path_on_disk, ready = self.store.media_path(int(seg_id))
            if ready and os.path.exists(path_on_disk):
                return self._serve_file(path_on_disk)
            return self._error("媒体尚未就绪（可能需要先在频道页同步/等下载）", 404)
        if path.startswith("/api/covers/"):
            body = self.store.cover_png()
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/search":
            return self._json(self.store.search(q("q")))
        if path == "/api/tags":
            return self._json(self.store.tags())
        if path == "/api/favorites":
            return self._json(self.store.favorites())
        if path == "/api/history":
            return self._json(self.store.history(q("limit", "10")))
        if path == "/api/chats":
            return self._json({"list": self.store.chats()})
        if path == "/api/download/status":
            return self._json(self.store.download_status())
        if path in ("/", "/index.html"):
            return self._json({"name": "tgdrama-py", "mode": self.store.source.name,
                               "endpoints": ["/api/auth/status", "/api/bootstrap", "/api/shows"]})
        return self._error("not found: %s" % path, 404)

    # ---- POST ----
    def do_POST(self):
        try:
            self._route_post()
        except Exception as error:
            self.log_message("POST %s 出错: %s", self.path, error)
            try:
                self._error("服务端异常：%s" % error, 500)
            except Exception:
                pass

    def _route_post(self):
        path = urlsplit(self.path).path
        body = self._read_json()
        if path == "/api/auth/password":
            try:
                self.store.source.submit_password(str(body.get("password") or ""))
                return self._json({"ok": True})
            except Exception as error:
                return self._error(str(error), 400)
        if path == "/api/shows/".rstrip("/") or path.startswith("/api/shows/"):
            if path.endswith("/fill"):
                return self._json({"ok": True})
            return self._error("bad path", 404)
        if path == "/api/chats/sync":
            if "tg_chat_id" not in body:
                return self._error("请求格式错误：需要 tg_chat_id", 400)
            try:
                return self._json(self.store.sync_chats(body.get("tg_chat_id")))
            except Exception as error:
                return self._error(str(error), 400)
        if path == "/api/chats/refresh":
            return self._json(self.store.refresh_chats())
        if path == "/api/chats/toggle":
            if "tg_chat_id" not in body:
                return self._error("请求格式错误：需要 tg_chat_id", 400)
            result = self.store.toggle_chat(body.get("tg_chat_id"), bool(body.get("enabled")))
            if "error" in result:
                return self._error(result["error"], 400)
            return self._json(result)
        if path == "/api/favorites/toggle":
            show_id = body.get("show_id")
            if not show_id:
                return self._error("请求格式错误：需要 show_id", 400)
            return self._json(self.store.toggle_favorite(int(show_id)))
        if path == "/api/history":
            if not body.get("episode_id"):
                return self._error("请求格式错误：需要 episode_id", 400)
            return self._json(self.store.save_history(int(body["episode_id"]),
                                                      body.get("position") or 0,
                                                      body.get("duration") or 0))
        if path == "/api/cache/clear":
            return self._json(self.store.clear_cache())
        if path == "/api/chats/refresh":
            return self._json(self.store.refresh_chats())
        return self._error("not found: %s" % path, 404)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    init_db()
    if FAKE:
        source = FakeSource()
    else:
        if not APP_ID or not APP_HASH:
            print("缺少 TGD_APP_ID / TGD_APP_HASH，无法登录 Telegram。", file=sys.stderr)
            print("先到 https://my.telegram.org 申请，再设置环境变量；", file=sys.stderr)
            print("只想验证接口的话用 TGD_FAKE=1 跑自测模式。", file=sys.stderr)
            sys.exit(2)
        source = TelethonSource()
    Handler.store = Store(source)
    server = Server((HOST, PORT), Handler)
    print("tgdrama-py 已启动：http://%s:%d   模式=%s" % (HOST, PORT, source.name), flush=True)
    print("FongMi 里 tgdrama1.py 的 base_url 填这个地址。", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        source.close()
        server.server_close()


if __name__ == "__main__":
    main()
