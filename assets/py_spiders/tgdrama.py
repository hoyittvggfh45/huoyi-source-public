import base64
import http.client
import json
import ssl
import time
import urllib.parse
from copy import deepcopy

try:
    from base.spider import BaseSpider
except Exception:
    try:
        from base import BaseSpider
    except Exception:
        class BaseSpider:
            pass


DEFAULT_CONFIG = {
    "base_url": "http://127.0.0.1:5278",
    "timeout": 12,
    "page_size": 30,
    "channel_scan_max": 200,
}


HARDCODED_CHANNELS = (
    (2753266064, "日本精品av|中文字幕|Jav", "jav_all"),
    (2698059227, "日本AV|母子乱伦|巨乳调教💯", "JableTVB"),
    (3523242707, "AI成人短剧/黄果短剧/黄豆魔改短剧", "craimgd"),
    (1519261559, "收藏AV", "shoucangav"),
    (2124166721, "中文字幕 | 日本AV即是正义！", "cosfulimax"),
    (3436294431, "无码FC2｜优质精选｜高画质｜磁力链接｜115·迅雷·PikPak", "NEWFC2"),
    (1928340095, "JAV中字", "onlyjavzh"),
    (4327733666, "日本 AV 一本道", "AVkanpian01"),
    (3761040325, "中文字幕👩‍🦯🏃‍♀小日子电影6", ""),
    (4474113674, "母子乱伦|伦理|妈妈", "muziLL01"),
    (3704977995, "绝美反差学生少妇", "JMFCXMG"),
    (1354793440, "日本 AV💋 无码 高清", "AVGQWM8"),
    (1480171113, "AV番号精选-种子磁链下载", "javbest"),
    (1122461141, "AV日报-无码|步兵|种子|磁链|下载|高清|日本", "avpush2"),
    (1219457818, "AV日报-种子|磁链|下载链接|日本|有码|无码|骑兵|步兵", "javday"),
    (4299635687, "推特精选", "bbbjhbgq"),
    (1693277285, "磁力链接精选福利集", "cili8888"),
    (1879901314, "那些极品姐姐", "zfjp1024"),
    (2604815578, "🫦91|麻豆|国产|反差|海角🫦", ""),
    (2648812064, "抖音网红丨色料吃瓜", "seliao212"),
    (3905645410, "黄果漫剧", "hgmanju"),
    (1301075074, "超清AV |中文字幕|热门女优", ""),
    (2591554205, "AV/番号/无码/高清💿", "AV_cao"),
    (4435379058, "成人小说/色情有声小说🔴", "YSxiaoshuo01"),
    (3628483985, "🎥日本AV| JAV |中文字幕|番号资源库", "porncloud004"),
    (2124172984, "🇭🇰男人唔咸濕AV專線", "mic6388av"),
    (1853804800, "日本AV无码🎀fc2素人高清🎀字母圈暗网", "wmav91"),
    (1901957482, "AV无码原片-日本", "avwmjav"),
    (3802482805, "st站每日开票预览", "MXFLJ6"),
    (1981480055, "🎥 色情云|日本AV| JAV |中文字幕|番号资源库", "av8plus"),
    (4422690627, "推特反差淫妻", "tuite905"),
    (4361772103, "AV精选|AI短剧|中文字幕|无码|破解|国产|直播|欧美", "avjx_zongbu"),
    (3418006020, "海角少妇御姐少女", "hing475"),
    (2052699130, "日本AV中文学习资料", "rbav00"),
    (3915334056, "日本精选无码优质av资源分享", "rbjx336"),
    (3684099016, "淫妻反差俱乐部", "lspjsn"),
    (2415398795, "PIKPAK成人磁力资源大全", "pikpaklove"),
    (3479159773, "网红 肛交 直播 泄密", "knapianzhibo"),
    (2347289238, "日本AV｜中文字幕｜无码高清", "misscctav"),
    (3961122432, "国产AV｜优质精选｜@AV114514", "AV114514"),
    (2304875899, "飞鸟社备用", "seqingtvb"),
    (1488881373, "AV收藏|优质精选|无码破解|中文字幕|番号磁力大全", "AV688"),
    (2543598876, "Stymei全网综合分享", ""),
    (3915473772, "人妻|素人|少妇", "SURENrenqi01"),
    (4375112420, "每日大赛|中文福利", "ZWmeiriDS"),
    (2871409701, "短剧在线看(短剧频道）", "DuanJuPD"),
    (2241401720, "Cos涩涩大杂烩", "CosSSDZH"),
    (1563276756, "【番号帝】番号查询", "FLLAVWM"),
    (4305291478, "TG免费高速代理-免费VPN高速节点", "gydlpd"),
    (1853403121, "BiBi色区🔞丨自拍丨熟女丨国产", "bisequcom"),
    (2038170041, "全网精选资源🔞", "xianyu44"),
    (2401842508, "海角社区|偷情乱伦精选", "haijiaojingxuan"),
)


EXT_CHANNELS = (
    ("超清AV", "cctv_av"),
    ("那些极品姐姐", "zfjp1024"),
    ("麻豆 girl", "madougirl"),
    ("黄果漫剧", "hgmanju"),
    ("海角 AV", "hjgc0"),
    ("无码 91", "wmav91"),
    ("收藏 AV", "shoucangav"),
)


IN_ACCOUNT = ("zfjp1024", "hgmanju", "wmav91", "shoucangav")


class TgdramaError(Exception):
    pass


class TgdramaHttpClient:
    _SSL = ssl._create_unverified_context()

    def __init__(self, config):
        self.base_url = str(config.get("base_url") or DEFAULT_CONFIG["base_url"]).rstrip("/")
        self.timeout = self._positive_int(config.get("timeout"), 12, 3, 60)
        self.headers = {
            "User-Agent": "ys-tgdrama/1.0",
            "Accept": "application/json, */*",
        }
        self._conn = {}

    @staticmethod
    def _positive_int(value, fallback, minimum, maximum):
        try:
            number = int(value)
        except (TypeError, ValueError):
            return fallback
        return max(minimum, min(maximum, number))

    def _url(self, path):
        return self.base_url + path

    def _split_target(self, url, params=None):
        parsed = urllib.parse.urlsplit(url)
        authority = "%s:%s" % ((parsed.hostname or "").lower(), parsed.port or 0)
        path = parsed.path or "/"
        query = parsed.query
        if params:
            extra = urllib.parse.urlencode(params)
            query = (query + "&" + extra) if query else extra
        target = path + ("?" + query if query else "")
        return authority, parsed.hostname, parsed.port, target, parsed.scheme

    def _conn_of(self, authority, host, port, scheme):
        entry = self._conn.get(authority)
        if entry is not None and time.time() - entry[0] < 90:
            return entry[1]
        if entry is not None:
            try:
                entry[1].close()
            except Exception:
                pass
            self._conn.pop(authority, None)
        if scheme == "https":
            conn = http.client.HTTPSConnection(host, port, timeout=self.timeout, context=self._SSL)
        else:
            conn = http.client.HTTPConnection(host, port, timeout=self.timeout)
        self._conn[authority] = [time.time(), conn]
        return conn

    def _drop(self, authority):
        entry = self._conn.pop(authority, None)
        if entry is not None:
            try:
                entry[1].close()
            except Exception:
                pass

    def _send(self, method, url, params=None, json_body=None):
        data = None
        headers = dict(self.headers)
        if json_body is not None:
            data = json.dumps(json_body, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        for attempt in (0, 1):
            authority, host, port, target, scheme = self._split_target(url, params)
            try:
                conn = self._conn_of(authority, host, port, scheme)
                conn.request(method, target, body=data, headers=headers)
                response = conn.getresponse()
                body = response.read()
                hdrs = dict(response.getheaders())
                if response.will_close:
                    self._drop(authority)
                return response.status, hdrs, body
            except Exception as error:
                self._drop(authority)
                if attempt == 1:
                    raise TgdramaError("连接 tgdrama 服务失败：%s" % error)
        raise TgdramaError("连接 tgdrama 服务失败")

    def _request(self, method, path, params=None, json_body=None):
        status, _headers, body = self._send(method, self._url(path), params, json_body)
        payload = {}
        if body:
            try:
                payload = json.loads(body.decode("utf-8", "replace"))
            except ValueError:
                payload = {}
        if status >= 400 or (isinstance(payload, dict) and payload.get("error")):
            message = ""
            if isinstance(payload, dict):
                message = str(payload.get("error") or "")
            raise TgdramaError(message or ("请求 %s 失败：HTTP %s" % (path, status)))
        return payload

    def shows(self, page=1, tag="", favorite=False):
        params = {"page": max(int(page or 1), 1)}
        if favorite:
            params["fav"] = "1"
        elif tag:
            params["tag"] = tag
        return self._request("GET", "/api/shows", params=params)

    def show_detail(self, show_id):
        return self._request("GET", "/api/shows/%s" % show_id)

    def episodes_lines(self, episode_id):
        return self._request("GET", "/api/episodes/%s/lines" % episode_id)

    def episode_stream_url(self, episode_id):
        return self._url("/api/episodes/%s/play" % episode_id)

    def segment_stream_url(self, segment_id):
        return self._url("/api/stream/%s" % segment_id)

    def hls_index_url(self, episode_id):
        return self._url("/api/episodes/%s/hls/index.m3u8" % episode_id)

    def hls_playable(self, episode_id):
        try:
            status, _headers, body = self._send("GET", self.hls_index_url(episode_id))
        except TgdramaError:
            return False
        if status != 200 or not body:
            return False
        return body.decode("utf-8", "replace").lstrip().startswith("#EXTM3U")

    def search(self, keyword):
        return self._request("GET", "/api/search", params={"q": keyword})

    def tags(self):
        return self._request("GET", "/api/tags")

    def history(self, limit=10):
        return self._request("GET", "/api/history", params={"limit": max(int(limit or 10), 1)})

    def save_history(self, episode_id, position, duration):
        return self._request("POST", "/api/history", json_body={
            "episode_id": int(episode_id),
            "position": float(position),
            "duration": float(duration),
        })

    def chats(self):
        return self._request("GET", "/api/chats")

    def service_up(self):
        try:
            status, _headers, body = self._send("GET", self._url("/"))
            return status == 200 and bool(body)
        except Exception:
            return False

    def sync_status(self):
        try:
            data = self._request("GET", "/api/sync/status")
        except (TgdramaError, OSError, ValueError):
            return {}
        return data if isinstance(data, dict) else {}

    def refresh_chats(self):
        try:
            self._request("POST", "/api/chats/refresh")
            return True
        except (TgdramaError, OSError, ValueError):
            return False

    def toggle_chat(self, tg_chat_id, enabled):
        return self._request("POST", "/api/chats/toggle", json_body={
            "tg_chat_id": int(tg_chat_id),
            "enabled": bool(enabled),
        })

    def sync_chats(self, tg_chat_id=0):
        return self._request("POST", "/api/chats/sync", json_body={"tg_chat_id": int(tg_chat_id)})

    def clear_cache(self):
        return self._request("POST", "/api/cache/clear", json_body={})

    def close(self):
        for authority in list(self._conn.keys()):
            self._drop(authority)


class TgdramaMapper:
    ID_PREFIX = "tgdrama"

    @classmethod
    def pack(cls, kind, payload=None):
        raw = json.dumps(payload or {}, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        body = base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")
        return "%s:%s:%s" % (cls.ID_PREFIX, kind, body)

    @classmethod
    def unpack(cls, value):
        parts = str(value or "").split(":", 2)
        if len(parts) != 3 or parts[0] != cls.ID_PREFIX:
            return None
        try:
            body = parts[2] + "=" * (-len(parts[2]) % 4)
            data = json.loads(base64.urlsafe_b64decode(body.encode("ascii")).decode("utf-8"))
            return {"kind": parts[1], "data": data if isinstance(data, dict) else {}}
        except (ValueError, TypeError, UnicodeError):
            return None

    @staticmethod
    def text(value, fallback=""):
        if value is None or value == "":
            return fallback
        return str(value)

    @staticmethod
    def label(value):
        return str(value or "").replace("$", "_").replace("#", "_")

    @classmethod
    def show_vod(cls, raw, base_url=""):
        show_id = raw.get("id")
        ep_count = 0
        ep_latest = 0
        try:
            ep_count = int(raw.get("ep_count") or 0)
        except (TypeError, ValueError):
            ep_count = 0
        try:
            ep_latest = int(raw.get("ep_latest") or 0)
        except (TypeError, ValueError):
            ep_latest = 0
        cover = str(raw.get("cover_path") or "")
        return {
            "vod_id": cls.pack("show", {"id": show_id}),
            "vod_name": cls.text(raw.get("name"), "未命名短剧"),
            "vod_pic": base_url + "/api/covers/%s" % show_id if (base_url and cover) else "",
            "vod_remarks": "电影" if ep_count == 1 else ("更新至%d集" % ep_latest if ep_latest > 1 else ("共%d集" % ep_count if ep_count else "")),
            "vod_content": cls.text(raw.get("intro")),
        }

    @classmethod
    def history_vod(cls, raw, base_url=""):
        show_id = raw.get("show_id")
        cover = str(raw.get("cover_path") or "")
        try:
            episode_no = int(raw.get("episode_no") or 0)
        except (TypeError, ValueError):
            episode_no = 0
        try:
            progress = float(raw.get("progress") or 0)
        except (TypeError, ValueError):
            progress = 0
        return {
            "vod_id": cls.pack("episode", {"id": raw.get("episode_id"), "show": show_id}),
            "vod_name": cls.text(raw.get("show_name") or raw.get("name"), "未命名短剧"),
            "vod_pic": base_url + "/api/covers/%s" % show_id if (base_url and cover) else "",
            "vod_remarks": "看到 第%d集 %.0f%%" % (episode_no, progress * 100) if progress else "第%d集" % episode_no,
            "vod_content": "",
        }

    @classmethod
    def info_vod(cls, name, vod_id, remarks="", pic=""):
        return {
            "vod_id": vod_id,
            "vod_name": name,
            "vod_pic": pic,
            "vod_remarks": remarks,
            "vod_tag": "action",
        }


def _as_list(value):
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        for key in ("list", "shows", "items", "data", "tags", "chats"):
            if isinstance(value.get(key), list):
                return value[key]
    return []


def _is_enabled(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    return str(value or "").strip().lower() in ("1", "true", "yes", "on")


def _parse_tags(value):
    rows = _as_list(value)
    seen = set()
    out = []
    for entry in rows:
        if isinstance(entry, str):
            name = entry.strip()
            count = 0
        elif isinstance(entry, dict):
            name = str(entry.get("name") or entry.get("tag") or entry.get("title") or "").strip()
            try:
                count = int(entry.get("count") or 0)
            except (TypeError, ValueError):
                count = 0
        else:
            continue
        if not name or name in seen:
            continue
        seen.add(name)
        out.append((name, count))
    return out


class Spider(BaseSpider):

    def __init__(self):
        try:
            super().__init__()
        except Exception:
            pass
        self.config = deepcopy(DEFAULT_CONFIG)
        self.client = TgdramaHttpClient(self.config)
        self._show_chats = {}
        self._last_chats_refresh = None
        self._home_calls = 0
        self._sync_triggered = set()

    def getName(self):
        return "tgdrama"

    def getDependence(self):
        return []

    def init(self, extend=None):
        options = self._parse_options(extend)
        self._apply_options(options)

    def destroy(self):
        try:
            self.client.close()
        except Exception:
            pass

    @staticmethod
    def _parse_options(value):
        if isinstance(value, dict):
            return dict(value)
        text = str(value or "").strip()
        if not text:
            return {}
        if text.startswith("{"):
            try:
                data = json.loads(text)
                return data if isinstance(data, dict) else {}
            except ValueError:
                return {}
        options = {}
        for part in text.split("&"):
            if "=" in part:
                key, _, val = part.partition("=")
                options[key.strip()] = val.strip()
        return options

    def _apply_options(self, options):
        if not isinstance(options, dict):
            return
        for key in ("base_url",):
            if key in options:
                value = str(options[key]).strip()
                if value:
                    self.config[key] = value
        if "timeout" in options:
            self.config["timeout"] = TgdramaHttpClient._positive_int(options["timeout"], 12, 3, 60)
        if "page_size" in options:
            self.config["page_size"] = TgdramaHttpClient._positive_int(options["page_size"], 30, 1, 100)
        if not str(self.config.get("base_url") or "").startswith("http"):
            self.config["base_url"] = DEFAULT_CONFIG["base_url"]
        self.config["base_url"] = str(self.config["base_url"]).rstrip("/")
        self.client = TgdramaHttpClient(self.config)

    def _chats(self):
        try:
            return _as_list(self.client.chats())
        except Exception:
            return []

    @staticmethod
    def _full_tg_id(bare_id):
        try:
            return -(1000000000000 + int(bare_id))
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _hardcoded_dict(bare_id, title, username):
        full_id = Spider._full_tg_id(bare_id)
        if full_id is None:
            return None
        return {
            "id": None,
            "tg_chat_id": full_id,
            "name": title,
            "username": username,
            "type": "channel",
            "enabled": 0,
            "syncing": 0,
            "message_count": 0,
            "source_count": 0,
            "_hardcoded": True,
        }

    @staticmethod
    def _hardcoded_rows():
        rows = []
        for bare_id, title, username in HARDCODED_CHANNELS:
            row = Spider._hardcoded_dict(bare_id, title, username)
            if row is not None:
                rows.append(row)
        return rows

    @staticmethod
    def _hardcoded_row(tid):
        if tid is None:
            return None
        want = str(tid).strip()
        if not want:
            return None
        lower = want.lower()
        for bare_id, title, username in HARDCODED_CHANNELS:
            if (username and username.lower() == lower) or str(bare_id) == want:
                return Spider._hardcoded_dict(bare_id, title, username)
        return None

    def _find_chat(self, username):
        if username is None:
            return None
        want = str(username).strip().lower()
        if not want:
            return None
        for chat in self._chats():
            if not isinstance(chat, dict):
                continue
            name = str(chat.get("username") or "").strip()
            if name and name.lower() == want:
                return chat
        return None

    def _find_chat_by_hardcoded(self, hard):
        if not isinstance(hard, dict):
            return None
        username = str(hard.get("username") or "").strip()
        if username:
            chat = self._find_chat(username)
            if chat is not None:
                return chat
        target = hard.get("tg_chat_id")
        for chat in self._chats():
            if not isinstance(chat, dict):
                continue
            try:
                if int(chat.get("tg_chat_id")) == int(target):
                    return chat
            except (TypeError, ValueError):
                continue
        return None

    @staticmethod
    def _ext_display(username):
        for name, user in EXT_CHANNELS:
            if user == username:
                return name
        return username

    def _maybe_refresh_chats(self, force=False):
        now = time.monotonic()
        if not force and self._last_chats_refresh is not None and now - self._last_chats_refresh < 300.0:
            return False
        self._last_chats_refresh = now
        try:
            return bool(self.client.refresh_chats())
        except Exception:
            return False

    @staticmethod
    def _add_class(classes, tid, name):
        classes.append({
            "type_id": tid,
            "type_name": name or tid,
            "type_flag": "1",
            "land": 1,
            "ratio": 1.78,
        })

    def _hardcoded_classes(self, classes):
        seen = set()
        for bare_id, title, username in HARDCODED_CHANNELS:
            tid = username if username else str(bare_id)
            self._add_class(classes, tid, title)
            seen.add(username.lower())
        for name, username in EXT_CHANNELS:
            if username.lower() not in seen:
                self._add_class(classes, username, name)

    def _classes(self, service_up):
        classes = []
        if service_up:
            chats = self._chats()
            if not chats:
                self._hardcoded_classes(classes)
            else:
                ext_users = {user.lower() for _name, user in EXT_CHANNELS}
                enabled_users = set()
                for chat in chats:
                    if not isinstance(chat, dict):
                        continue
                    if not _is_enabled(chat.get("enabled")):
                        continue
                    username = str(chat.get("username") or "").strip()
                    if username:
                        enabled_users.add(username.lower())
                for name, username in EXT_CHANNELS:
                    if username.lower() in enabled_users:
                        self._add_class(classes, username, name)
                for chat in chats:
                    if not isinstance(chat, dict):
                        continue
                    if not _is_enabled(chat.get("enabled")):
                        continue
                    username = str(chat.get("username") or "").strip()
                    if not username or username.lower() in ext_users:
                        continue
                    self._add_class(classes, username, str(chat.get("name") or username))
                for name, username in EXT_CHANNELS:
                    if username.lower() not in enabled_users:
                        self._add_class(classes, username, name)
        else:
            self._hardcoded_classes(classes)
        classes.extend([
            {"type_id": "favorites", "type_name": "我的收藏", "type_flag": "1", "land": 1, "ratio": 1.78},
            {"type_id": "history", "type_name": "观看历史", "type_flag": "1", "land": 1, "ratio": 1.78},
            {"type_id": "channels", "type_name": "频道管理", "type_flag": "1", "land": 1, "ratio": 1.78},
        ])
        return classes

    def _filters(self):
        group = {"key": "tag", "name": "标签", "init": "", "value": []}
        try:
            for name, count in _parse_tags(self.client.tags()):
                label = "%s(%s)" % (name, count) if count > 0 else name
                group["value"].append({"n": label, "v": name})
        except Exception:
            pass
        return {"all": [group]}

    def homeContent(self, filter=False):
        self._maybe_refresh_chats(force=bool(filter) and self._home_calls > 0)
        self._home_calls += 1
        up = self._service_up()
        result = {"class": self._classes(up), "filters": self._filters()}
        if up:
            try:
                result.update(self.homeVideoContent())
            except Exception:
                result.update({"list": [], "page": 1, "pagecount": 1, "total": 0})
        else:
            result.update({"list": [self._service_down_card()], "page": 1, "pagecount": 1, "total": 1})
        return result

    def homeVideoContent(self):
        try:
            data = self.client.shows(1)
        except TgdramaError:
            return {"list": [], "page": 1, "pagecount": 1, "total": 0}
        items = [TgdramaMapper.show_vod(raw, self.config["base_url"])
                 for raw in _as_list(data)]
        total = 0
        if isinstance(data, dict):
            try:
                total = int(data.get("total") or len(items))
            except (TypeError, ValueError):
                total = len(items)
        return {"list": items, "page": 1, "pagecount": 1, "total": total}

    def _page_result(self, items, page, limit=30, total=None):
        total = len(items) if total is None else max(int(total), 0)
        limit = max(int(limit), 1)
        pagecount = max(page, (total + limit - 1) // limit) if total else page
        return {"list": items, "page": page, "pagecount": pagecount, "limit": limit, "total": total}

    def _show_chat_ids(self, show_id):
        cached = self._show_chats.get(show_id)
        if cached is not None:
            return cached
        ids = set()
        try:
            detail = self.client.show_detail(show_id)
            episodes = detail.get("episodes") or []
            if episodes:
                lines = self.client.episodes_lines(episodes[0].get("id")).get("lines") or []
                for line in lines:
                    try:
                        ids.add(int(line.get("chat_id")))
                    except (TypeError, ValueError):
                        continue
        except TgdramaError:
            pass
        self._show_chats[show_id] = ids
        return ids

    def _service_down_card(self):
        return TgdramaMapper.info_vod(
            "TG影视库服务未启动",
            TgdramaMapper.pack("info", {"key": "service_down"}),
            "先打开一次 TG影视库启动服务",
        )

    def _not_in_account_card(self, username):
        return TgdramaMapper.info_vod(
            "该频道不在当前账号里",
            TgdramaMapper.pack("info", {"key": "not_in_account:" + username}),
            "频道 @" + username,
        )

    def _not_enabled_card(self, username):
        return TgdramaMapper.info_vod(
            "该频道未启用采集",
            TgdramaMapper.pack("info", {"key": "not_enabled:" + username}),
            "频道 @" + username,
        )

    def _empty_channel_card(self, username):
        return TgdramaMapper.info_vod(
            "该频道暂无已同步视频",
            TgdramaMapper.pack("info", {"key": "empty_channel:" + username}),
            "频道 @" + username,
        )

    def _channel_page_by_id(self, chat_id, page):
        try:
            target = int(str(chat_id).strip())
        except (TypeError, ValueError):
            return self._page_result([], page)
        limit = self.config["page_size"]
        cap = self.config["channel_scan_max"]
        matched = []
        scanned = 0
        p = 1
        while len(matched) < page * limit and scanned < cap:
            try:
                data = self.client.shows(p)
            except TgdramaError:
                break
            batch = _as_list(data)
            if not batch:
                break
            try:
                total = int(data.get("total") or 0) if isinstance(data, dict) else 0
            except (TypeError, ValueError):
                total = 0
            for raw in batch:
                if scanned >= cap:
                    break
                scanned += 1
                show_id = raw.get("id")
                if show_id is None:
                    continue
                if target in self._show_chat_ids(show_id):
                    matched.append(raw)
            if total and scanned >= total:
                break
            p += 1
        start = (page - 1) * limit
        items = [TgdramaMapper.show_vod(raw, self.config["base_url"])
                 for raw in matched[start:start + limit]]
        return self._page_result(items, page, limit, len(matched))

    def _service_up(self):
        probe = getattr(self.client, "service_up", None)
        if probe is None:
            return True
        try:
            return bool(probe())
        except Exception:
            return False

    def _syncing_page(self, page=1):
        remarks = "稍后下拉刷新"
        try:
            status = self.client.sync_status()
        except Exception:
            status = {}
        if isinstance(status, dict) and not status and not self._service_up():
            return self._page_result([self._service_down_card()], page, 1, 1)
        if isinstance(status, dict) and status.get("active"):
            done = status.get("done") or 0
            total = status.get("total") or 0
            current = status.get("current") or ""
            shows = status.get("shows") or 0
            if total > 0:
                remarks = "正在同步第 %s/%s 个频道" % (done + 1, total)
                if current:
                    remarks += "（当前：%s）" % current
                remarks += "，已入库 %s 部视频，稍后下拉刷新" % shows
            else:
                remarks = "正在同步，已入库 %s 部视频，稍后下拉刷新" % shows
        elif isinstance(status, dict) and status:
            remarks = "同步已完成，这个频道暂无视频，稍后再来看看"
        card = TgdramaMapper.info_vod(
            "正在同步",
            TgdramaMapper.pack("info", {"key": "syncing"}),
            remarks,
        )
        return self._page_result([card], page, 1, 1)

    def _trigger_sync(self, tg_chat_id):
        try:
            target = int(str(tg_chat_id).strip())
        except (TypeError, ValueError):
            return
        if target in self._sync_triggered:
            return
        self._sync_triggered.add(target)
        try:
            self.client.sync_chats(target)
        except Exception:
            pass

    def _channel_page_by_name(self, tid, page):
        username = str(tid or "").strip()
        if not self._service_up():
            return self._page_result([self._service_down_card()], page, 1, 1)
        chat = self._find_chat(username)
        if chat is None:
            hard = self._hardcoded_row(username)
            if hard is not None:
                self._trigger_sync(hard["tg_chat_id"])
                chat = self._find_chat_by_hardcoded(hard)
                if chat is None:
                    return self._syncing_page(page)
            else:
                return self._page_result([self._not_in_account_card(username)], page, 1, 1)
        if not _is_enabled(chat.get("enabled")):
            return self._page_result([self._not_enabled_card(username)], page, 1, 1)
        try:
            chat_id = int(chat.get("id"))
        except (TypeError, ValueError):
            return self._page_result([self._not_enabled_card(username)], page, 1, 1)
        result = self._channel_page_by_id(chat_id, page)
        if not result.get("list") and not result.get("total"):
            return self._page_result([self._empty_channel_card(username)], page, 1, 1)
        return result

    def categoryContent(self, tid, pg, filter=False, extend=None):
        page = TgdramaHttpClient._positive_int(pg, 1, 1, 9999)
        options = self._parse_options(extend)
        ref = TgdramaMapper.unpack(tid)
        if ref and ref["kind"] == "show":
            return self.detailContent(tid)
        if tid == "channels":
            return self._channels_page()
        if tid == "history":
            try:
                data = self.client.history(100)
            except TgdramaError:
                return self._page_result([], 1)
            items = [TgdramaMapper.history_vod(raw, self.config["base_url"])
                     for raw in _as_list(data)]
            return self._page_result(items, 1, max(len(items), 1), len(items))
        if isinstance(tid, str) and tid.strip() not in ("", "all", "favorites", "history", "channels"):
            return self._channel_page_by_name(tid, page)
        favorite = tid == "favorites"
        tag = "" if favorite else str(options.get("tag") or "")
        try:
            data = self.client.shows(page, tag=tag, favorite=favorite)
        except TgdramaError:
            return self._page_result([], page)
        items = [TgdramaMapper.show_vod(raw, self.config["base_url"])
                 for raw in _as_list(data)]
        limit = self.config["page_size"]
        total = len(items)
        if isinstance(data, dict):
            try:
                total = int(data.get("total") or len(items))
            except (TypeError, ValueError):
                total = len(items)
            try:
                limit = int(data.get("page_size") or limit)
            except (TypeError, ValueError):
                pass
        return self._page_result(items, page, limit, total)

    def _channels_page(self):
        items = [TgdramaMapper.info_vod(
            "登录与同步在设置 → Telegram 登录里做",
            TgdramaMapper.pack("info", {"key": "login"}),
            "频道由插件自动发现，新频道默认启用",
        )]
        chats = self._chats()
        if chats:
            for chat in chats:
                if not isinstance(chat, dict):
                    continue
                chat_id = chat.get("id")
                if chat_id is None:
                    continue
                enabled = _is_enabled(chat.get("enabled"))
                syncing = bool(chat.get("syncing"))
                meta = ["频道" if chat.get("type") == "channel" else "群组"]
                if chat.get("message_count"):
                    meta.append("消息 %s" % chat.get("message_count"))
                if chat.get("source_count"):
                    meta.append("视频 %s" % chat.get("source_count"))
                meta.append("同步中…" if syncing else ("已启用" if enabled else "未采集"))
                username = str(chat.get("username") or "").strip()
                pack_id = username if username else "tg:%s" % chat.get("tg_chat_id")
                items.append(TgdramaMapper.info_vod(
                    "%s %s" % ("✅" if enabled else "⬜", chat.get("name") or chat.get("tg_chat_id") or chat_id),
                    TgdramaMapper.pack("channel", {"id": pack_id}),
                    " · ".join(meta),
                ))
        else:
            for bare_id, title, username in HARDCODED_CHANNELS:
                pack_id = username if username else str(bare_id)
                items.append(TgdramaMapper.info_vod(
                    "⬜ %s" % title,
                    TgdramaMapper.pack("channel", {"id": pack_id}),
                    "未同步 · 去频道管理页查看同步状态",
                ))
        return self._page_result(items, 1, max(len(items), 1), len(items))

    def _channel_info_detail(self, chat_id):
        text = str(chat_id or "").strip()
        chat = self._find_chat(text) if text else None
        if chat is None and text.startswith("tg:"):
            try:
                target = int(text.split(":", 1)[1])
            except (TypeError, ValueError):
                target = None
            if target is not None:
                for item in self._chats():
                    if not isinstance(item, dict):
                        continue
                    try:
                        if int(item.get("tg_chat_id")) == target:
                            chat = item
                            break
                    except (TypeError, ValueError):
                        continue
        if chat is not None:
            enabled = _is_enabled(chat.get("enabled"))
            syncing = bool(chat.get("syncing"))
            lines = [
                "类型：%s" % ("频道" if chat.get("type") == "channel" else "群组"),
                "状态：%s" % ("同步中…" if syncing else ("已启用" if enabled else "未采集")),
            ]
            if chat.get("username"):
                lines.append("用户名：@%s" % chat.get("username"))
            if chat.get("message_count"):
                lines.append("消息：%s" % chat.get("message_count"))
            if chat.get("source_count"):
                lines.append("视频：%s" % chat.get("source_count"))
            lines.append("点分类里的频道名看该频道的剧；启用与同步由插件自动处理，新频道默认启用。")
            username = str(chat.get("username") or "").strip()
            pack_id = username if username else text
            return {"list": [{
                "vod_id": TgdramaMapper.pack("channel", {"id": pack_id}),
                "vod_name": str(chat.get("name") or chat.get("tg_chat_id") or text),
                "vod_pic": "",
                "vod_remarks": "已启用" if enabled else "未采集",
                "vod_year": "",
                "vod_area": "",
                "vod_actor": "",
                "vod_director": "",
                "vod_content": "\n".join(lines),
                "vod_play_from": "",
                "vod_play_url": "",
            }]}
        row = self._hardcoded_row(text)
        if row is not None:
            lines = ["类型：频道", "状态：尚未同步"]
            if row.get("username"):
                lines.append("用户名：@%s" % row.get("username"))
            lines.append("这个频道还没同步到本地库，里面暂时没有剧。")
            lines.append("插件同步完成后，点分类里的频道名就能看该频道的剧。")
            return {"list": [{
                "vod_id": TgdramaMapper.pack("channel", {"id": text}),
                "vod_name": str(row.get("name") or row.get("tg_chat_id")),
                "vod_pic": "",
                "vod_remarks": "尚未同步",
                "vod_year": "",
                "vod_area": "",
                "vod_actor": "",
                "vod_director": "",
                "vod_content": "\n".join(lines),
                "vod_play_from": "",
                "vod_play_url": "",
            }]}
        return {"list": []}

    def _info_detail(self, key):
        if key == "syncing":
            content = "正在同步这个频道的视频，稍后再下拉刷新看看。\n同步状态去频道管理页查看。"
            title = "正在同步"
        elif key == "service_down":
            content = "TG影视库本地服务（127.0.0.1:5278）没有启动，本频道取数走插件本地服务。\n先打开一次 TG影视库启动服务，再进本频道。\n如果 TG影视库也打不开，去设置 → Telegram 登录里看登录状态。"
            title = "TG影视库服务未启动"
        elif key.startswith("not_in_account:"):
            username = key.split(":", 1)[1]
            name = self._ext_display(username)
            names = "、".join(self._ext_display(user) for user in IN_ACCOUNT)
            content = (
                "频道 @%s（%s）不在当前 Telegram 账号的频道列表里，插件里没有它的数据。\n"
                "在当前账号里的频道：%s。\n"
                "想看这个频道，先在 Telegram 里关注它，等插件同步后再进。"
                % (username, name, names)
            )
            title = "该频道不在当前账号里"
        elif key.startswith("not_enabled:"):
            username = key.split(":", 1)[1]
            name = self._ext_display(username)
            content = (
                "频道 @%s（%s）已在当前账号里，但插件里是停用状态，不采集新消息。\n"
                "去 TG影视库的频道管理页启用它，等同步完成后再进。"
                % (username, name)
            )
            title = "该频道未启用采集"
        elif key.startswith("empty_channel:"):
            username = key.split(":", 1)[1]
            name = self._ext_display(username)
            content = (
                "频道 @%s（%s）已在账号里，插件还没同步到视频。\n"
                "先打开一次 TG影视库，等同步完成后再进。"
                % (username, name)
            )
            title = "该频道暂无已同步视频"
        elif key == "login":
            content = "登录在设置 → Telegram 登录里做（扫码或手机号）。\n频道由插件自动发现，新频道默认启用；同步在插件后台进行。"
            title = "登录与同步"
        elif key == "error":
            content = "读取频道失败，请确认插件服务已启动且已登录。"
            title = "读取频道失败"
        else:
            content = "登录 Telegram 后等插件自动发现频道。"
            title = "还没有频道"
        return {"list": [{
            "vod_id": TgdramaMapper.pack("info", {"key": key}),
            "vod_name": title,
            "vod_pic": "",
            "vod_remarks": "",
            "vod_year": "",
            "vod_area": "",
            "vod_actor": "",
            "vod_director": "",
            "vod_content": content,
            "vod_play_from": "",
            "vod_play_url": "",
        }]}

    def detailContent(self, ids):
        if isinstance(ids, (list, tuple)):
            ids = ids[0] if ids else ""
        vid = str(ids or "").split(",", 1)[0]
        ref = TgdramaMapper.unpack(vid)
        try:
            if ref:
                if ref["kind"] in ("ep", "episode"):
                    return self._detail_by_episode(ref["data"])
                if ref["kind"] == "channel":
                    return self._channel_info_detail(ref["data"].get("id"))
                if ref["kind"] == "info":
                    return self._info_detail(str(ref["data"].get("key") or ""))
                show_id = ref["data"].get("id")
                if not show_id:
                    return {"list": []}
                data = self.client.show_detail(show_id)
                built = self._build_detail(data, None)
                return {"list": [built] if built else []}
            text = vid.strip()
            if text.isdigit():
                data = self.client.show_detail(text)
                built = self._build_detail(data, None)
                return {"list": [built] if built else []}
            return {"list": []}
        except TgdramaError:
            return {"list": []}

    def _detail_by_episode(self, data):
        episode_id = data.get("id")
        show_id = data.get("show")
        if not episode_id:
            return {"list": []}
        lines = self.client.episodes_lines(episode_id)
        show = lines.get("show") or {}
        if not show_id:
            show_id = show.get("id")
        if not show_id:
            return {"list": []}
        detail = self._build_detail(self.client.show_detail(show_id), episode_id)
        return {"list": [detail] if detail else []}

    def _build_detail(self, data, focus_episode=None):
        if not isinstance(data, dict):
            return None
        show = data.get("show") or {}
        if not isinstance(show, dict):
            show = {}
        if not show and ("name" in data or "episodes" in data):
            show = data
        episodes = data.get("episodes") or []
        base = self.config["base_url"]
        cover = str(show.get("cover_path") or "")
        names = []
        tokens = []
        try:
            sorted_eps = sorted(episodes, key=lambda item: int(item.get("episode_no") or 0))
        except (TypeError, ValueError):
            sorted_eps = list(episodes)
        try:
            numbers = [int(item.get("episode_no") or 0) for item in sorted_eps]
        except (TypeError, ValueError):
            numbers = []
        dense = bool(numbers) and numbers == list(range(1, len(numbers) + 1))
        for index, episode in enumerate(sorted_eps, start=1):
            if not isinstance(episode, dict):
                continue
            episode_id = episode.get("id")
            if not episode_id:
                continue
            try:
                raw_no = int(episode.get("episode_no") or 0)
            except (TypeError, ValueError):
                raw_no = 0
            if dense:
                label = TgdramaMapper.label(episode.get("title") or ("第%d集" % raw_no))
            else:
                label = "第%d集" % index
                if raw_no and raw_no != index:
                    label += "(原%s)" % raw_no
            if focus_episode and episode_id == focus_episode:
                label = "▶ " + label
            names.append("%s$%s" % (label, TgdramaMapper.pack("ep", {"id": episode_id})))
            tokens.append(episode)
        if not names:
            return None
        if len(names) == 1:
            names = ["直接播放$%s" % names[0].split("$", 1)[1]]
        progress = data.get("progress") or []
        if progress:
            first = progress[0] if isinstance(progress[0], dict) else {}
            try:
                pct = float(first.get("progress") or 0) * 100
            except (TypeError, ValueError):
                pct = 0
            remark = "上次看到 第%s集 %.0f%%" % (first.get("episode_no") or "?", pct)
        elif len(tokens) == 1:
            remark = "电影"
        else:
            try:
                ep_latest = int(show.get("ep_latest") or 0)
            except (TypeError, ValueError):
                ep_latest = 0
            remark = "更新至%d集" % ep_latest if ep_latest else "共%d集" % len(tokens)
        return {
            "vod_id": TgdramaMapper.pack("show", {"id": show.get("id")}),
            "vod_name": TgdramaMapper.text(show.get("name"), "未命名短剧"),
            "vod_pic": base + "/api/covers/%s" % show.get("id") if cover else "",
            "vod_remarks": remark,
            "vod_year": "",
            "vod_area": "",
            "vod_actor": "",
            "vod_director": "",
            "vod_content": TgdramaMapper.text(show.get("intro")),
            "vod_play_from": "TG影视库",
            "vod_play_url": "#".join(names),
        }

    def searchContent(self, key, quick=False, pg=1):
        keyword = str(key or "").strip()
        if not keyword:
            return self._page_result([], 1)
        try:
            data = self.client.search(keyword)
        except TgdramaError:
            return self._page_result([], 1)
        items = [TgdramaMapper.show_vod(raw, self.config["base_url"])
                 for raw in _as_list(data)]
        return self._page_result(items, 1, max(len(items), 50), len(items))

    def playerContent(self, flag, id, vipFlags=None):
        raw = str(id or "")
        if "$" in raw:
            raw = raw.split("$", 1)[1]
        ref = TgdramaMapper.unpack(raw)
        episode_id = None
        if ref and ref["kind"] == "ep":
            episode_id = ref["data"].get("id")
        elif raw.startswith("tgdrama:"):
            rest = raw.split(":", 1)[1].strip()
            if rest.isdigit():
                episode_id = rest
        if not episode_id:
            return {"parse": 0, "playUrl": "", "url": "", "header": {}}
        try:
            lines = self.client.episodes_lines(episode_id)
        except TgdramaError as error:
            return {"parse": 0, "playUrl": "", "url": "", "header": {}, "msg": str(error)}
        groups = [line for line in (lines.get("lines") or []) if line.get("segments")]
        if not groups:
            url = self.client.episode_stream_url(episode_id)
            return {"parse": 0, "playUrl": url, "url": url, "header": {}}
        segments = groups[0].get("segments") or []
        url = ""
        if len(segments) > 1 and self.client.hls_playable(episode_id):
            url = self.client.hls_index_url(episode_id)
        if not url:
            first = segments[0]
            url = self.client.segment_stream_url(first.get("id"))
        try:
            duration = 0.0
            if segments:
                duration = float(segments[0].get("duration") or 0)
            self.client.save_history(episode_id, 0.0, duration)
        except TgdramaError:
            pass
        return {
            "parse": 0,
            "playUrl": url,
            "url": url,
            "header": {},
            "msg": "第%s集 · %s" % (
                lines.get("episode", {}).get("episode_no", "?"),
                groups[0].get("chat_name") or "TG直连",
            ),
        }

    def action(self, action=None, params=None):
        name = ""
        value = {}
        if isinstance(action, dict):
            name = str(action.get("action") or "")
            value = action.get("value") or {}
        elif isinstance(action, str):
            text = action.strip()
            if text.startswith("{"):
                try:
                    data = json.loads(text)
                    name = str(data.get("action") or "")
                    value = data.get("value") or {}
                except ValueError:
                    name = text
            else:
                name = text
        if isinstance(params, dict):
            value = params
        if isinstance(value, dict) and isinstance(value.get("menu"), str):
            try:
                inner = json.loads(value["menu"])
            except ValueError:
                inner = None
            if isinstance(inner, dict) and inner.get("action"):
                name = inner.get("action") or name
                value = inner.get("value") or {}
        try:
            if name == "tg_chats_sync":
                tg_chat_id = (value or {}).get("tg_chat_id")
                if tg_chat_id is None:
                    return {"toast": "缺少频道 ID"}
                self.client.sync_chats(tg_chat_id)
                return {"toast": "已提交同步，稍后自动刷新"}
            if name == "tg_chat_set":
                values = value if isinstance(value, dict) else {}
                tg_chat_id = values.get("tg_chat_id")
                if not tg_chat_id:
                    return {"toast": "缺少频道 ID"}
                want = str(values.get("enabled")).lower() in ("1", "true", "yes", "on")
                self.client.toggle_chat(tg_chat_id, want)
                return {"toast": "已启用，正在后台同步…" if want else "已停用，不再采集新消息"}
            if name == "tg_cache_clear":
                self.client.clear_cache()
                self._show_chats = {}
                return {"toast": "视频缓存已清空"}
            if name in ("tg_login", "tg_login_status", "tg_password", "tg_login_refresh"):
                return {"toast": "请到设置 → Telegram 登录里操作"}
            return {"toast": "未知操作"}
        except (TgdramaError, OSError, ValueError) as error:
            return {"toast": "操作失败：%s" % error}

    def isVideoFormat(self, url):
        text = str(url or "").lower()
        if not text:
            return False
        return any(k in text for k in ("/api/stream/", "/api/episodes/", ".m3u8", ".mp4"))

    def manualVideoCheck(self):
        return True

    def localProxy(self, param=None):
        return [404, "text/plain", b"", {}]
