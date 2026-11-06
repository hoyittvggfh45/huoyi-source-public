import ast
import http.client
import importlib.util
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPIDER_PATH = ROOT / "assets" / "py_spiders" / "tgdrama.py"
HOST_PATH = ROOT / "android" / "app" / "src" / "main" / "python" / "py_spider_host.py"
BACKEND_PATH = Path(os.environ.get(
    "TGDRAMA_FAKE_BACKEND",
    str(ROOT / "scripts" / "tgdrama_fake_backend.py"),
))

TMP = None
PROC = None
SPIDER_MOD = None
HOST_MOD = None
FAKE_PORT = 0
BASE_URL = ""
DB_PATH = ""
EXTEND = {}
SPIDERS = []


def _load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _wait_ready(url, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                if response.status == 200:
                    return True
        except Exception:
            time.sleep(0.5)
    return False


def _free_port():
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return port


def _read_log_tail(path, limit=4000):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            text = handle.read()
    except OSError:
        return "<no backend log>"
    if len(text) > limit:
        text = text[-limit:]
    return text.strip() or "<empty backend log>"


def _start_fake_backend(data_dir, attempts=3):
    global PROC, FAKE_PORT, BASE_URL
    log_path = os.path.join(TMP.name, "fake-backend.log")
    last_error = ""
    for attempt in range(1, attempts + 1):
        FAKE_PORT = _free_port()
        BASE_URL = "http://127.0.0.1:%d" % FAKE_PORT
        env = dict(os.environ)
        env["TGD_FAKE"] = "1"
        env["TGD_HOST"] = "127.0.0.1"
        env["TGD_PORT"] = str(FAKE_PORT)
        env["TGD_DATA"] = data_dir
        log_file = open(log_path, "w", encoding="utf-8")
        PROC = subprocess.Popen(
            [sys.executable, str(BACKEND_PATH)],
            env=env,
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )
        time.sleep(0.5)
        code = PROC.poll()
        if code is not None:
            log_file.close()
            last_error = "attempt %d: exited immediately code=%s log=%s" % (
                attempt, code, _read_log_tail(log_path))
            continue
        if _wait_ready(BASE_URL + "/api/auth/status", timeout=45):
            log_file.close()
            return
        PROC.terminate()
        try:
            PROC.wait(timeout=10)
        except subprocess.TimeoutExpired:
            PROC.kill()
        log_file.close()
        last_error = "attempt %d: not ready on port %d log=%s" % (
            attempt, FAKE_PORT, _read_log_tail(log_path))
    raise RuntimeError("fake backend did not start: %s" % last_error)


def setUpModule():
    global TMP, PROC, SPIDER_MOD, HOST_MOD, FAKE_PORT, BASE_URL, DB_PATH, EXTEND
    TMP = tempfile.TemporaryDirectory(prefix="tgdrama-spider-test-")
    data_dir = os.path.join(TMP.name, "fakehome")
    _start_fake_backend(data_dir)
    DB_PATH = os.path.join(data_dir, "tgdrama.db")
    if not os.path.isfile(DB_PATH):
        raise RuntimeError("fake backend did not create db")
    SPIDER_MOD = _load_module("tgdrama_under_test", SPIDER_PATH)
    HOST_MOD = _load_module("py_spider_host_under_test", HOST_PATH)
    EXTEND = {"base_url": BASE_URL, "db_path": DB_PATH}


def tearDownModule():
    global PROC, TMP
    for spider in SPIDERS:
        try:
            spider.destroy()
        except Exception:
            pass
    if PROC is not None:
        PROC.terminate()
        try:
            PROC.wait(timeout=10)
        except subprocess.TimeoutExpired:
            PROC.kill()
        PROC = None
    if TMP is not None:
        TMP.cleanup()
        TMP = None


def make_spider(db_path=None):
    spider = SPIDER_MOD.Spider()
    extend = dict(EXTEND)
    if db_path is not None:
        extend["db_path"] = db_path
    spider.init(json.dumps(extend, ensure_ascii=False))
    SPIDERS.append(spider)
    return spider


class StubClient:
    def __init__(self, chats_sequence, refresh_error=False):
        self._seq = list(chats_sequence)
        self.refresh_calls = 0
        self.refresh_error = refresh_error

    def chats(self):
        if self._seq:
            return self._seq.pop(0)
        return []

    def refresh_chats(self):
        self.refresh_calls += 1
        if self.refresh_error:
            raise Exception("refresh failed")
        return True

    def tags(self):
        return []

    def shows(self, *args, **kwargs):
        return {"list": [], "total": 0}


REAL_CHATS = [{
    "id": 1,
    "tg_chat_id": -1001234567890,
    "name": "测试短剧频道A",
    "type": "channel",
    "enabled": 1,
    "message_count": 20,
    "source_count": 9,
    "syncing": 0,
}]


class RecordingHandler(BaseHTTPRequestHandler):
    seen = []
    status = 404

    def _handle(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        RecordingHandler.seen.append((self.command, self.path))
        body = b"{}" if RecordingHandler.status == 200 else b'{"error":"not found"}'
        self.send_response(RecordingHandler.status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = _handle
    do_POST = _handle

    def log_message(self, *args):
        pass


class TgdramaSpiderTest(unittest.TestCase):
    def test_house_rules(self):
        src = SPIDER_PATH.read_text(encoding="utf-8")
        tree = ast.parse(src)
        for node in ast.walk(tree):
            if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef)):
                if node.body and isinstance(node.body[0], ast.Expr):
                    value = node.body[0].value
                    if isinstance(value, ast.Constant) and isinstance(value.value, str):
                        self.fail("docstring found at line %s" % node.body[0].lineno)
        for index, line in enumerate(src.splitlines(), 1):
            self.assertFalse(line.strip().startswith("#"), "comment at line %s" % index)
        self.assertNotIn("RE_", src)
        methods = set()
        for node in tree.body:
            if isinstance(node, ast.ClassDef) and node.name == "Spider":
                methods = {item.name for item in node.body if isinstance(item, ast.FunctionDef)}
        for name in (
            "getName", "getDependence", "init", "destroy", "homeContent",
            "homeVideoContent", "categoryContent", "detailContent",
            "searchContent", "playerContent", "localProxy",
            "isVideoFormat", "manualVideoCheck", "action",
        ):
            self.assertIn(name, methods, "missing method %s" % name)

    def test_home_categories(self):
        spider = make_spider()
        classes = spider.homeContent(False)["class"]
        ids = [entry["type_id"] for entry in classes]
        self.assertIn("chan:1", ids)
        self.assertNotIn("chan:2", ids)
        self.assertIn("favorites", ids)
        self.assertIn("history", ids)
        self.assertIn("channels", ids)
        self.assertNotIn("all", ids)
        self.assertFalse(any(item.startswith("chantg:") for item in ids))

    def test_home_filters_tag_group(self):
        spider = make_spider()
        filters = spider.homeContent(False)["filters"]
        for key in ("all", ""):
            group = filters[key][0]
            self.assertEqual(group["key"], "tag")
            values = {item["v"]: item["n"] for item in group["value"]}
            self.assertEqual(values.get(""), "全部")
            self.assertEqual(values.get("测试"), "测试(2)")

    def test_home_video(self):
        spider = make_spider()
        result = spider.homeVideoContent()
        names = [item["vod_name"] for item in result["list"]]
        self.assertEqual(names, ["测试短剧·闪婚首富", "测试短剧·豪门千金"])

    def test_category_all(self):
        spider = make_spider()
        for tid in ("", "all"):
            names = [item["vod_name"] for item in spider.categoryContent(tid, 1)["list"]]
            self.assertEqual(names, ["测试短剧·闪婚首富", "测试短剧·豪门千金"])

    def test_category_channel_db(self):
        spider = make_spider()
        names = sorted(item["vod_name"] for item in spider.categoryContent("chan:1", 1)["list"])
        self.assertEqual(names, sorted(["测试短剧·闪婚首富", "测试短剧·豪门千金"]))
        self.assertEqual(spider.categoryContent("chan:2", 1)["list"], [])

    def test_category_channel_http_scan(self):
        spider = make_spider(db_path="/nonexistent/tgdrama.db")
        names = [item["vod_name"] for item in spider.categoryContent("chan:1", 1)["list"]]
        self.assertEqual(names, ["测试短剧·闪婚首富", "测试短剧·豪门千金"])
        self.assertEqual(spider.categoryContent("chan:2", 1)["list"], [])

    def test_category_channels_page(self):
        spider = make_spider()
        items = spider.categoryContent("channels", 1)["list"]
        self.assertEqual(items[0]["vod_name"], "登录与同步在设置 → Telegram 登录里做")
        self.assertEqual(items[1]["vod_name"], "✅ 测试短剧频道A")
        self.assertEqual(items[2]["vod_name"], "⬜ 测试短剧频道B")
        for item in items:
            self.assertEqual(item["vod_tag"], "action")

    def test_category_favorites_history_empty(self):
        spider = make_spider()
        for tid in ("favorites", "history"):
            result = spider.categoryContent(tid, 1)
            self.assertEqual(result["list"], [])
            self.assertIn("page", result)

    def test_detail_show(self):
        spider = make_spider()
        pack = SPIDER_MOD.TgdramaMapper.pack("show", {"id": 2})
        detail = spider.detailContent([pack])["list"][0]
        self.assertEqual(detail["vod_name"], "测试短剧·闪婚首富")
        self.assertEqual(detail["vod_play_from"], "TG影视库")
        self.assertEqual(len(detail["vod_play_url"].split("#")), 3)
        plain = spider.detailContent(["2"])["list"][0]
        self.assertEqual(plain["vod_name"], "测试短剧·闪婚首富")
        ep_pack = detail["vod_play_url"].split("#")[0].split("$", 1)[1]
        by_ep = spider.detailContent([ep_pack])["list"][0]
        self.assertEqual(by_ep["vod_name"], "测试短剧·闪婚首富")

    def test_detail_channel_info(self):
        spider = make_spider()
        pack = SPIDER_MOD.TgdramaMapper.pack("channel", {"id": 1})
        detail = spider.detailContent([pack])["list"][0]
        self.assertEqual(detail["vod_name"], "测试短剧频道A")
        self.assertIn("已启用", detail["vod_content"])
        self.assertEqual(detail["vod_play_url"], "")

    def test_search(self):
        spider = make_spider()
        names = [item["vod_name"] for item in spider.searchContent("闪婚")["list"]]
        self.assertEqual(names, ["测试短剧·闪婚首富"])
        self.assertEqual(spider.searchContent("")["list"], [])

    def test_player_single_segment_stream(self):
        spider = make_spider()
        detail = spider.detailContent(
            [SPIDER_MOD.TgdramaMapper.pack("show", {"id": 2})])["list"][0]
        ep_pack = detail["vod_play_url"].split("#")[0].split("$", 1)[1]
        result = spider.playerContent("TG影视库", ep_pack)
        self.assertEqual(result["parse"], 0)
        self.assertEqual(result["url"], BASE_URL + "/api/stream/4")
        self.assertEqual(result["playUrl"], BASE_URL + "/api/stream/4")
        self.assertEqual(result["header"], {})
        request = urllib.request.Request(
            result["url"], headers={"Range": "bytes=0-511"})
        with urllib.request.urlopen(request, timeout=10) as response:
            self.assertEqual(response.status, 206)
            self.assertEqual(len(response.read()), 512)

    def test_player_label_prefix_and_old_form(self):
        spider = make_spider()
        detail = spider.detailContent(
            [SPIDER_MOD.TgdramaMapper.pack("show", {"id": 2})])["list"][0]
        ep_pack = detail["vod_play_url"].split("#")[0].split("$", 1)[1]
        for play_id in ("第1集$" + ep_pack, "tgdrama:4"):
            result = spider.playerContent("TG影视库", play_id)
            self.assertEqual(result["url"], BASE_URL + "/api/stream/4")

    def test_action(self):
        spider = make_spider()
        calls = []

        class ClearStub:
            def clear_cache(self):
                calls.append(1)
                return {"ok": True}

            def chats(self):
                return []

            def refresh_chats(self):
                return True

            def tags(self):
                return []

        spider.client = ClearStub()
        self.assertEqual(spider.action("tg_cache_clear"), {"toast": "视频缓存已清空"})
        self.assertEqual(calls, [1])
        login = spider.action("tg_login")
        self.assertIn("设置", login["toast"])
        unknown = spider.action("nothing_here")
        self.assertIn("toast", unknown)

    def test_misc_methods(self):
        spider = make_spider()
        self.assertTrue(spider.isVideoFormat(BASE_URL + "/api/stream/4"))
        self.assertTrue(spider.isVideoFormat(BASE_URL + "/api/episodes/4/lines"))
        self.assertFalse(spider.isVideoFormat("https://example.test/page"))
        self.assertTrue(spider.manualVideoCheck())
        self.assertEqual(spider.localProxy({}), [404, "text/plain", b"", {}])

    def test_host_dispatch(self):
        spider_path = str(SPIDER_PATH)
        extend = dict(EXTEND)

        def call(request):
            return json.loads(HOST_MOD.handle(spider_path, json.dumps(request)))

        result = call({"action": "categories", "extend": extend})
        self.assertTrue(result["ok"], result)
        ids = [entry["type_id"] for entry in result["data"]["class"]]
        self.assertIn("chan:1", ids)
        result = call({"action": "catalog", "category": "chan:1", "page": 1, "extend": extend})
        self.assertTrue(result["ok"], result)
        names = sorted(item["vod_name"] for item in result["data"]["list"])
        self.assertEqual(names, sorted(["测试短剧·闪婚首富", "测试短剧·豪门千金"]))
        detail = call({
            "action": "detail",
            "vodId": SPIDER_MOD.TgdramaMapper.pack("show", {"id": 2}),
            "extend": extend,
        })
        self.assertTrue(detail["ok"], detail)
        self.assertEqual(detail["data"]["list"][0]["vod_name"], "测试短剧·闪婚首富")
        ep_pack = detail["data"]["list"][0]["vod_play_url"].split("#")[0].split("$", 1)[1]
        resolved = call({
            "action": "resolve", "flag": "TG影视库", "playId": ep_pack, "extend": extend,
        })
        self.assertTrue(resolved["ok"], resolved)
        self.assertEqual(resolved["data"]["parse"], 0)
        self.assertEqual(resolved["data"]["url"], BASE_URL + "/api/stream/4")
        self.assertEqual(resolved["data"]["header"], {})
        HOST_MOD.dispose(spider_path)

    def test_fallback_refresh_restores(self):
        spider = make_spider(db_path="/nonexistent/tgdrama.db")
        stub = StubClient([[], REAL_CHATS])
        spider.client = stub
        ids = [entry["type_id"] for entry in spider.homeContent(False)["class"]]
        self.assertIn("chan:1", ids)
        self.assertFalse(any(item.startswith("chantg:") for item in ids))
        self.assertEqual(stub.refresh_calls, 1)

    def test_fallback_list_when_still_empty(self):
        spider = make_spider(db_path="/nonexistent/tgdrama.db")
        stub = StubClient([], refresh_error=True)
        spider.client = stub
        ids = [entry["type_id"] for entry in spider.homeContent(False)["class"]]
        fallback = [item for item in ids if item.startswith("chantg:")]
        self.assertEqual(len(fallback), 52)
        self.assertEqual(len(set(fallback)), 52)
        self.assertFalse(any(item.startswith("chan:") and not item.startswith("chantg:") for item in ids))
        self.assertEqual(fallback[0], "chantg:-1002753266064")
        names = {entry["type_id"]: entry["type_name"]
                 for entry in spider.homeContent(False)["class"]}
        self.assertEqual(names["chantg:-1002753266064"], "日本精品av|中文字幕|Jav")
        for extra in ("favorites", "history", "channels"):
            self.assertIn(extra, ids)
        self.assertEqual(stub.refresh_calls, 1)
        spider.homeContent(False)
        self.assertEqual(stub.refresh_calls, 1)

    def test_fallback_channel_page_honest_empty(self):
        spider = make_spider(db_path="/nonexistent/tgdrama.db")
        spider.client = StubClient([], refresh_error=True)
        page = spider.categoryContent("chantg:-1002753266064", 1)
        self.assertEqual(len(page["list"]), 1)
        card = page["list"][0]
        self.assertEqual(card["vod_name"], "该频道尚未同步")
        self.assertEqual(card["vod_tag"], "action")
        detail = spider.detailContent([card["vod_id"]])["list"][0]
        self.assertEqual(detail["vod_name"], "该频道尚未同步")
        self.assertIn("还没同步到本地库", detail["vod_content"])
        mgmt = spider.categoryContent("channels", 1)["list"]
        self.assertEqual(len(mgmt), 53)
        self.assertEqual(mgmt[1]["vod_remarks"], "未同步 · 去频道管理页查看同步状态")

    def test_fallback_not_shown_when_normal(self):
        spider = make_spider()
        calls = []
        original = spider.client.refresh_chats
        spider.client.refresh_chats = lambda: calls.append(1) or original()
        ids = [entry["type_id"] for entry in spider.homeContent(False)["class"]]
        self.assertEqual(calls, [])
        self.assertFalse(any(item.startswith("chantg:") for item in ids))

    def test_refresh_http_contract(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), RecordingHandler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            client = SPIDER_MOD.TgdramaHttpClient({"base_url": "http://127.0.0.1:%d" % port})
            RecordingHandler.seen = []
            RecordingHandler.status = 404
            self.assertFalse(client.refresh_chats())
            self.assertIn(("POST", "/api/chats/refresh"), RecordingHandler.seen)
            RecordingHandler.seen = []
            RecordingHandler.status = 200
            self.assertTrue(client.refresh_chats())
            self.assertIn(("POST", "/api/chats/refresh"), RecordingHandler.seen)
            RecordingHandler.seen = []
            client.clear_cache()
            self.assertIn(("POST", "/api/cache/clear"), RecordingHandler.seen)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
