import ast
import base64
import hashlib
import importlib.util
import json
import os
import ssl
import sys
import traceback
import types

try:
    _ssl_paths = ssl.get_default_verify_paths()
    _ssl_unverified = not (
        (_ssl_paths.cafile and os.path.exists(_ssl_paths.cafile))
        or (_ssl_paths.capath and os.path.exists(_ssl_paths.capath))
        or os.environ.get("SSL_CERT_FILE")
        or os.environ.get("SSL_CERT_DIR")
    )
except Exception:
    _ssl_unverified = False
if _ssl_unverified:
    ssl._create_default_https_context = ssl._create_unverified_context

# 宿主真实调用面（_dispatch/handle/dispose 逐处核对）：
# 核心方法缺失即不可用，导入校验硬性要求；缺省方法宿主从不调用
# （getDependence/isVideoFormat/manualVideoCheck/action）或仅按需、
# 带兜底调用（destroy 异常吞掉、localProxy 仅代理动作触发），缺失时
# 由 _fill_defaults 在加载期补默认实现，不再拒绝导入（用户 2026-10-24
# 拍板：其自有 py 多为老壳方言，缺的多是这类缺省方法）。
CORE_METHODS = (
    "getName",
    "init",
    "homeContent",
    "homeVideoContent",
    "categoryContent",
    "detailContent",
    "searchContent",
    "playerContent",
)

DEFAULTED_METHODS = (
    "getDependence",
    "destroy",
    "localProxy",
    "isVideoFormat",
    "manualVideoCheck",
    "action",
)

REQUIRED_METHODS = CORE_METHODS + DEFAULTED_METHODS

_instances = {}


def validate_source(text):
    if text.startswith("\ufeff"):
        text = text[1:]
    try:
        tree = ast.parse(text)
    except SyntaxError as error:
        return {
            "ok": False,
            "error": "语法错误：第 %s 行 %s" % (error.lineno or 0, error.msg),
            "missing": list(CORE_METHODS),
            "filled": [],
            "hasSpider": False,
            "mode": "full",
        }
    spider = None
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and node.name == "Spider":
            spider = node
            break
    if spider is None:
        return {
            "ok": False,
            "error": "未找到 class Spider",
            "missing": list(CORE_METHODS),
            "filled": [],
            "hasSpider": False,
            "mode": "full",
        }
    found = []
    for node in spider.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            found.append(node.name)
        elif isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    found.append(target.id)
        elif isinstance(node, ast.AnnAssign):
            if isinstance(node.target, ast.Name):
                found.append(node.target.id)
    missing = [name for name in CORE_METHODS if name not in found]
    filled = [name for name in DEFAULTED_METHODS if name not in found]
    if missing and "playerContent" in found:
        return {
            "ok": True,
            "error": "",
            "missing": [],
            "filled": missing + filled,
            "hasSpider": True,
            "methods": found,
            "mode": "playOnly",
        }
    return {
        "ok": not missing,
        "error": "" if not missing else "缺少核心方法：%s" % "、".join(missing),
        "missing": missing,
        "filled": filled,
        "hasSpider": True,
        "methods": found,
        "mode": "full",
    }


def validate_source_json(text):
    return json.dumps(validate_source(text), ensure_ascii=False)


def _jsonable(value):
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    if isinstance(value, bytes):
        return {"$bytes": base64.b64encode(value).decode("ascii")}
    if isinstance(value, dict):
        return {str(key): _jsonable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_jsonable(item) for item in value]
    return str(value)


def _ensure_base_spider_stub():
    if "base.spider" in sys.modules:
        return
    try:
        import base.spider  # noqa: F401
        return
    except Exception:
        pass
    base_module = types.ModuleType("base")
    spider_module = types.ModuleType("base.spider")

    class BaseSpider:
        pass

    spider_module.BaseSpider = BaseSpider
    base_module.spider = spider_module
    sys.modules["base"] = base_module
    sys.modules["base.spider"] = spider_module


def _default_is_video_format(url=None):
    path = str(url or "").split("?")[0].lower()
    return path.endswith(
        (".m3u8", ".mp4", ".mp3", ".flv", ".mkv", ".mov", ".ts", ".aac")
    )


_DEFAULT_IMPLS = {
    "getName": lambda: "仅播放",
    "init": lambda extend="": None,
    "homeContent": lambda filter=None: {
        "class": [],
        "list": [
            {
                "vod_id": "play",
                "vod_name": "仅播放",
                "vod_pic": "",
                "vod_remarks": "仅播放模式",
            },
        ],
    },
    "homeVideoContent": lambda: {"list": []},
    "categoryContent": lambda tid=None, pg=1, filter=None, extend=None: {
        "list": [],
        "page": pg,
        "pagecount": 1,
    },
    "detailContent": lambda ids=None: {
        "list": [
            {
                "vod_id": "play",
                "vod_name": "仅播放",
                "vod_pic": "",
                "vod_content": "仅播放模式",
                "vod_play_from": "默认",
                "vod_play_url": "正片$play",
            },
        ],
    },
    "searchContent": lambda key=None, quick=False, pg="1": {"list": [], "page": 1},
    "getDependence": lambda: [],
    "destroy": lambda: None,
    "localProxy": lambda param=None: [
        404,
        "text/plain",
        "localProxy not implemented",
        {},
    ],
    "isVideoFormat": _default_is_video_format,
    "manualVideoCheck": lambda: False,
    "action": lambda action=None: "",
}


def _fill_defaults(spider):
    filled = []
    for name, impl in _DEFAULT_IMPLS.items():
        if name == "playerContent":
            continue
        if not callable(getattr(spider, name, None)):
            setattr(spider, name, impl)
            filled.append(name)
    spider._huoyi_filled = filled
    return filled


class _Dummy:
    def __call__(self, *args, **kwargs):
        return _Dummy()

    def __getattr__(self, name):
        return _Dummy()

    def __mro_entries__(self, bases):
        raise ImportError("stubbed module member used as a base class")

    def __iter__(self):
        return iter(())

    def __str__(self):
        return ""

    def __bool__(self):
        return False


def _make_dummy_module(name):
    module = types.ModuleType(name)
    module.__path__ = []
    module.__getattr__ = lambda attr: _Dummy()
    return module


class _RequestsResponse:
    def __init__(self, status, headers, body, url):
        self.status_code = status
        self.headers = headers
        self._body = body
        self.url = url

    @property
    def content(self):
        return self._body

    @property
    def text(self):
        return self._body.decode("utf-8", "ignore")

    def json(self):
        return json.loads(self.text)

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError("HTTP %s" % self.status_code)


def _make_requests_module():
    import urllib.error
    import urllib.request

    def _request(method, url, **kwargs):
        headers = dict(kwargs.get("headers") or {})
        body = kwargs.get("data")
        payload = kwargs.get("json")
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            headers.setdefault("Content-Type", "application/json")
        if isinstance(body, str):
            body = body.encode("utf-8")
        request = urllib.request.Request(
            url, data=body, headers=headers, method=method.upper()
        )
        try:
            with urllib.request.urlopen(
                request, timeout=kwargs.get("timeout")
            ) as response:
                return _RequestsResponse(
                    response.status,
                    dict(response.headers),
                    response.read(),
                    response.url,
                )
        except urllib.error.HTTPError as error:
            return _RequestsResponse(
                error.code, dict(error.headers), error.read(), url
            )

    class _Session:
        def __init__(self):
            self.headers = {}

        def request(self, method, url, **kwargs):
            merged = dict(self.headers)
            merged.update(kwargs.get("headers") or {})
            kwargs["headers"] = merged
            return _request(method, url, **kwargs)

        def get(self, url, **kwargs):
            return self.request("GET", url, **kwargs)

        def post(self, url, **kwargs):
            return self.request("POST", url, **kwargs)

        def close(self):
            return None

    module = types.ModuleType("requests")
    module.get = lambda url, **kwargs: _request("GET", url, **kwargs)
    module.post = lambda url, **kwargs: _request("POST", url, **kwargs)
    module.head = lambda url, **kwargs: _request("HEAD", url, **kwargs)
    module.put = lambda url, **kwargs: _request("PUT", url, **kwargs)
    module.delete = lambda url, **kwargs: _request("DELETE", url, **kwargs)
    module.request = _request
    module.Session = _Session
    exceptions = types.ModuleType("requests.exceptions")

    class _RequestException(Exception):
        pass

    exceptions.RequestException = _RequestException
    exceptions.HTTPError = _RequestException
    exceptions.ConnectionError = _RequestException
    exceptions.Timeout = _RequestException
    module.exceptions = exceptions
    return module


def _ensure_requests_stub():
    if "requests" in sys.modules:
        return False
    try:
        import requests  # noqa: F401
        return False
    except ImportError:
        pass
    sys.modules["requests"] = _make_requests_module()
    return True


def _load_spider(path):
    import os

    mtime = os.path.getmtime(path)
    cached = _instances.get(path)
    if cached is not None and cached[0] == mtime:
        return cached[1]
    _ensure_base_spider_stub()
    stubbed = []
    if _ensure_requests_stub():
        stubbed.append("requests")
    digest = hashlib.md5(path.encode("utf-8")).hexdigest()[:12]
    module_name = "py_spider_%s" % digest
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise ImportError("无法加载蜘蛛文件：%s" % path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    last_error = None
    for _ in range(9):
        try:
            spec.loader.exec_module(module)
            last_error = None
            break
        except ModuleNotFoundError as error:
            last_error = error
            missing_name = error.name or ""
            if not missing_name or missing_name in stubbed:
                raise
            stubbed.append(missing_name)
            sys.modules[missing_name] = _make_dummy_module(missing_name)
    if last_error is not None:
        raise last_error
    spider_class = getattr(module, "Spider", None)
    if spider_class is None:
        raise ImportError("蜘蛛文件缺少 class Spider：%s" % path)
    spider = spider_class()
    _fill_defaults(spider)
    spider._huoyi_stubbed_imports = stubbed
    _instances[path] = (mtime, spider)
    return spider


def _is_arity_error(error):
    message = str(error)
    return ("takes" in message or "missing" in message) and "argument" in message


def _call_arity(func, args):
    variants = []
    current = tuple(args)
    while True:
        variants.append(current)
        if not current:
            break
        current = current[:-1]
    first_error = None
    for variant in variants:
        try:
            return func(*variant)
        except TypeError as error:
            if not _is_arity_error(error):
                raise
            if first_error is None:
                first_error = error
    raise first_error


def _call_home(spider, request):
    result = _call_arity(spider.homeContent, (False,))
    return result if isinstance(result, dict) else {"list": result}


def _dispatch(spider, request):
    action = request.get("action") or ""
    if action == "ping":
        methods = [
            name for name in REQUIRED_METHODS if callable(getattr(spider, name, None))
        ]
        return {
            "name": str(spider.getName() or ""),
            "methods": methods,
            "stubbedImports": list(getattr(spider, "_huoyi_stubbed_imports", [])),
            "filled": list(getattr(spider, "_huoyi_filled", [])),
            "sslUnverified": _ssl_unverified,
        }
    if action == "categories":
        return _call_home(spider, request)
    if action == "catalog":
        query = str(request.get("query") or "").strip()
        page = request.get("page") or 1
        category = str(request.get("category") or "")
        extend = request.get("extend") or {}
        if query:
            result = _call_arity(spider.searchContent, (query, False, str(page)))
            return result if isinstance(result, dict) else {"list": result}
        if category:
            result = _call_arity(
                spider.categoryContent, (category, page, None, extend)
            )
            return result if isinstance(result, dict) else {"list": result}
        home = _call_home(spider, request)
        items = home.get("list") or []
        if not items:
            video = _call_arity(spider.homeVideoContent, ())
            if isinstance(video, dict):
                items = video.get("list") or []
                home = dict(home)
                home["list"] = items
        return home
    if action == "search":
        query = str(request.get("query") or "").strip()
        page = request.get("page") or 1
        result = _call_arity(spider.searchContent, (query, False, str(page)))
        return result if isinstance(result, dict) else {"list": result}
    if action == "detail":
        vod_id = str(request.get("vodId") or "")
        try:
            result = _call_arity(spider.detailContent, ([vod_id],))
        except TypeError as first_error:
            try:
                result = spider.detailContent(vod_id)
            except TypeError:
                raise first_error
        return result if isinstance(result, dict) else {"list": []}
    if action == "resolve":
        flag = str(request.get("flag") or "")
        play_id = str(request.get("playId") or "")
        result = _call_arity(spider.playerContent, (flag, play_id, []))
        return result if isinstance(result, dict) else {}
    if action == "proxy":
        param = request.get("param") or {}
        result = _call_arity(spider.localProxy, (param,))
        if isinstance(result, (list, tuple)) and len(result) >= 3:
            body = result[2]
            if isinstance(body, str):
                body_bytes = body.encode("utf-8")
            elif isinstance(body, bytes):
                body_bytes = body
            else:
                body_bytes = b""
            headers = result[3] if len(result) > 3 and isinstance(result[3], dict) else {}
            return {
                "status": int(result[0]),
                "mime": str(result[1] or ""),
                "bodyBase64": base64.b64encode(body_bytes).decode("ascii"),
                "headers": {str(k): str(v) for k, v in headers.items()},
            }
        raise ValueError("localProxy 返回格式不正确")
    raise ValueError("不支持的动作：%s" % action)


def handle(path, request_json):
    try:
        request = json.loads(request_json) if request_json else {}
        if not isinstance(request, dict):
            raise ValueError("请求格式不正确")
        spider = _load_spider(path)
        if not getattr(spider, "_huoyi_inited", False):
            extend = request.get("extend") or ""
            try:
                spider.init(extend if isinstance(extend, str) else json.dumps(extend))
            except TypeError:
                spider.init()
            spider._huoyi_inited = True
        data = _dispatch(spider, request)
        return json.dumps({"ok": True, "data": _jsonable(data)}, ensure_ascii=False)
    except Exception as error:  # noqa: BLE001
        detail = "".join(traceback.format_exception_only(type(error), error)).strip()
        return json.dumps({"ok": False, "error": detail}, ensure_ascii=False)


def dispose(path):
    cached = _instances.pop(path, None)
    if cached is not None:
        try:
            cached[1].destroy()
        except Exception:
            pass
    return json.dumps({"ok": True}, ensure_ascii=False)
