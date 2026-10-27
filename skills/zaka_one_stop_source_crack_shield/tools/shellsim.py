#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
shellsim — 写源「上电视」前的严格仿真自检(Zaka 深度引擎)

它干三件事,一层比一层狠:
  L1 静态检查  源码结构:类/函数齐不齐、有没有占位域名、有没有内网地址、有没有裸文件路径
  L2 真跑      实际调用 homeContent / categoryContent / detailContent / searchContent /
               playerContent(逐个带超时),校验返回 JSON 的形状与字段
  L3 真播验证  拿到 play_url 后真拉一次:清单要见 #EXTM3U、首片要真的下得来

--strict:任何违规都算失败(退出码 1)。没到 L3 通过,不许说「源做好了」。

用法:
  python3 shellsim.py <spider.py>                 # 只做 L1 静态检查(不执行任何代码)
  python3 shellsim.py <spider.py> --run           # 加 L2/L3(仅用于自研/本机生成的源)
  python3 shellsim.py <spider.py> --run --strict  # 交付前必须到这一步
  python3 shellsim.py --selftest                  # 工具自身自检(离线)

边界:用户从外部上传的第三方脚本不代跑 —— 这个工具跑的是我们这边写出来的源。
"""

from __future__ import annotations

import argparse
import importlib.util
import inspect
import json
import os
import re
import signal
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

try:
    from zaka_crack_kit import Stream, Net  # noqa: E402
except Exception:  # 允许单独拷出来用
    Stream = Net = None

REQUIRED = ("homeContent", "categoryContent", "detailContent", "searchContent", "playerContent")
# 全协议 14 方法(2026-10-23 升级):5 核心 + 9 契约。缺核心=error,缺契约=error(新交付标准)。
FULL_CONTRACT = ("getName", "getDependence", "init", "destroy", "homeContent",
                 "homeVideoContent", "categoryContent", "detailContent", "searchContent",
                 "playerContent", "localProxy", "isVideoFormat", "manualVideoCheck", "action")
OPTIONAL = ()

BAD_URL_PATTERNS = (
    (r"https?://(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)", "内网 IP,用户电视上打不开"),
    (r"https?://(?:www\.)?example\.(?:com|org)", "占位域名 example.com,没换成真域名"),
    (r"https?://[^\s'\"]*?(?:your-domain|domain\.com|test\.com)", "占位域名没替换"),
    (r"/tmp/|/var/deepbot|/home/[a-z]+/ws", "写死了本机路径,换环境就废"),
    (r"YOUR_API_KEY|TODO_KEY|<token>", "密钥/令牌占位符没填"),
)
# 127.0.0.1 不再一律判死:自建中继/壳代理探测是全协议的合法回退层。
# 只拦「写死端口的字面 127 地址被当站点/播放直链」——行内带端口变量、
# % 格式化、relay/proxy 标识的构造式地址放行。
HARDCODED_LOCAL_RE = re.compile(r"https?://(?:localhost|127\.0\.0\.1):\d+")
WARN_PATTERNS = (
    (r"^\s*import\s+pandas|^\s*import\s+numpy", "重依赖,TVBox 环境跑不起来"),
    (r"except\s*:\s*pass", "空 except 吞异常,线上出问题查不到"),
)
MAGNET_ONLY = re.compile(r"^magnet:", re.I)


class Timeout(Exception):
    pass


def _alarm(signum, frame):
    raise Timeout()


def call_with_timeout(fn, args, timeout: float):
    """给单次调用套超时(只在主线程、Unix 下生效)。"""
    if not hasattr(signal, "SIGALRM") or os.name == "nt":
        return fn(*args)
    old = signal.signal(signal.SIGALRM, _alarm)
    signal.setitimer(signal.ITIMER_REAL, timeout)
    try:
        return fn(*args)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old)


# ══════════════════════════════════════════════════════════════════
# L1 静态检查
# ══════════════════════════════════════════════════════════════════

def _relayish(line: str) -> bool:
    low = line.lower()
    return any(k in low for k in ("relay", "proxy", "probe", "%d", "%s", "{port}", "port"))


def static_check(path: str) -> list:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        src = f.read()
    issues = []  # (level, code, msg)
    lines = src.splitlines()
    # 逐行查占位/内网:探活行(probe)里的 example.com、自建中继构造行不误杀
    for ln, line in enumerate(lines, 1):
        low = line.lower()
        if "probe" in low:
            continue
        for pat, why in BAD_URL_PATTERNS:
            m = re.search(pat, line)
            if m:
                issues.append(("error", "BAD-PLACEHOLDER", f"{why} → {m.group(0)[:60]} (L{ln})"))
                break
        m = HARDCODED_LOCAL_RE.search(line)
        if m and not _relayish(line):
            issues.append(("error", "BAD-PLACEHOLDER",
                           f"写死端口的本机地址被当直链,电视上打不开 → {m.group(0)[:60]} (L{ln})"))
    for pat, why in WARN_PATTERNS:
        m = re.search(pat, src, re.M)
        if m:
            issues.append(("warn", "STYLE", f"{why} → {m.group(0)[:40]}"))
    # requests:仅在「硬依赖且无 urllib 降级」时才警告;try 导入+urllib 兜底是全协议写法
    if re.search(r"^\s*(?:import|from)\s+requests\b|\brequests\.", src, re.M):
        if "urllib.request" not in src:
            issues.append(("warn", "STYLE", "用了 requests 且无 urllib 降级 —— 盒子上缺 requests 就全灭"))
    # timeout=None:函数签名里的哨兵默认值(timeout=None 后在体内 or 默认)不算,
    # 只拦调用处真传 None
    for ln, line in enumerate(lines, 1):
        if "def " in line:
            continue
        if re.search(r"(?:urlopen|requests\.get|\.get|http_get)\([^\n]*timeout\s*=\s*None", line):
            issues.append(("warn", "STYLE", f"调用处 timeout=None,源会挂死 (L{ln})"))
            break
    # print:__main__ 调试入口之后的 print 合法,只查正文区
    body = src.split('if __name__')[0]
    if "print(" in body:
        issues.append(("warn", "STYLE", "正文区有调试 print 没清(日志会刷屏)"))
    for fn in REQUIRED:
        if not re.search(r"def\s+%s\s*\(" % fn, src):
            issues.append(("error", "MISSING-FUNC", f"缺核心函数 {fn}()"))
    for fn in FULL_CONTRACT:
        if fn in REQUIRED:
            continue
        if not re.search(r"def\s+%s\s*\(" % fn, src):
            issues.append(("error", "MISSING-FULL", f"缺全协议契约方法 {fn}() —— 严壳会报错/缺功能"))
    if "class Spider" not in src:
        # 铁律(2026-10-21 MissAV 一单教训):真实壳只认 Spider 类,
        # 只写 BaseSpider 会在壳里报「模块中没有 Spider 类」加载失败,L1 必须拦住。
        issues.append(("error", "NO-CLASS", "没找到 Spider 类(全协议:主类必须叫 Spider,混合继承 BaseSpider)"))
    elif re.search(r"class\s+Spider\s*:", src):
        issues.append(("error", "BARE-CLASS",
                       "裸 class Spider: 无 BaseSpider 继承 —— 只对鸭子型加载器有效,"
                       "Chaquo/FongMi 系壳会丢壳基类;全协议要求 class Spider(BaseSpider) + try/except 回退"))
    elif not re.search(r"class\s+Spider\s*\(\s*BaseSpider\s*\)", src):
        issues.append(("error", "NO-BASE", "Spider 未继承 BaseSpider(全协议:混合继承,壳内真基类/无壳回退空基类)"))
    if re.search(r"def\s+searchContent", src) and "quickSearch" not in src and "quick" not in src:
        issues.append(("warn", "SEARCH", "searchContent 没接 quick 参数,搜索会慢一档"))
    return issues


# ══════════════════════════════════════════════════════════════════
# L2 真跑
# ══════════════════════════════════════════════════════════════════

def load_spider(path: str):
    """按文件路径加载源模块(仅在 --run 时使用)。"""
    name = "shellsim_" + re.sub(r"\W+", "_", os.path.splitext(os.path.basename(path))[0])
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def find_spider(mod):
    for attr in dir(mod):
        obj = getattr(mod, attr)
        if inspect.isclass(obj) and any(hasattr(obj, fn) for fn in REQUIRED):
            if obj.__module__ == mod.__name__:
                return obj
    if hasattr(mod, "BaseSpider"):
        return mod.BaseSpider
    return None


def _check_list(items, where, issues, need=("vod_id", "vod_name")):
    if not isinstance(items, list):
        issues.append(("error", "SHAPE", f"{where} 的 list 不是数组"))
        return
    if not items:
        issues.append(("error", "EMPTY", f"{where} 返回空列表 —— 首页/分类没内容,电视上就是白屏"))
        return
    first = items[0]
    if not isinstance(first, dict):
        issues.append(("error", "SHAPE", f"{where} 的 list[0] 不是 dict"))
        return
    for k in need:
        if k not in first:
            issues.append(("error", "FIELD", f"{where} 的条目缺字段 {k}"))


def run_spider(path: str, cfg: dict = None, timeout: float = 20.0, do_play: bool = True) -> dict:
    cfg = cfg or {}
    issues, timings, samples = [], {}, {}
    result = {"path": path, "checked": [], "issues": issues, "timings": timings, "samples": samples}
    try:
        mod = load_spider(path)
    except Exception as e:
        issues.append(("error", "IMPORT", f"模块加载失败:{type(e).__name__}: {e}"))
        return result
    cls = find_spider(mod)
    if cls is None:
        issues.append(("error", "NO-CLASS", "没有可用的 Spider 类"))
        return result
    try:
        sp = cls()
    except Exception as e:
        issues.append(("error", "INIT", f"实例化失败:{type(e).__name__}: {e}"))
        return result
    if hasattr(sp, "ext") is False and cfg:
        try:
            sp.ext = json.dumps(cfg, ensure_ascii=False)
        except Exception:
            pass
    # 全协议运行时契约:14 方法须可调用(类名对但缺方法,严壳照样炸)
    missing_full = [fn for fn in FULL_CONTRACT if not callable(getattr(sp, fn, None))]
    if missing_full:
        issues.append(("error", "FULL-CONTRACT", f"运行时缺全协议方法:{','.join(missing_full)}"))
    else:
        result["checked"].append(("fullContract14", "ok"))
    # homeContent 零参容错:有的壳不传 filter 直接调 homeContent()
    if callable(getattr(sp, "homeContent", None)):
        try:
            out0 = call_with_timeout(sp.homeContent, (), timeout)
            if not isinstance(out0, dict):
                issues.append(("warn", "HOME-SIG", "homeContent() 零参调用返回值不是 dict"))
        except TypeError:
            issues.append(("warn", "HOME-SIG", "homeContent() 不接受零参调用 —— filter 参数应给默认值"))
        except Exception:
            pass
    # localProxy 返回形态:坏参数须优雅返回,形态须为 3/4/5 项且前两项为 (int, str)。
    # 5 项式为 FongMi chaquo 的 base64 标志变体,同等合法。
    if callable(getattr(sp, "localProxy", None)):
        try:
            lp = call_with_timeout(sp.localProxy, ({"url": ""},), timeout)
            if not (isinstance(lp, (list, tuple)) and len(lp) in (3, 4, 5)
                    and isinstance(lp[0], int) and isinstance(lp[1], str)):
                issues.append(("error", "LOCALPROXY", f"localProxy 返回形态不对(须 [int,str,body,...]):{str(lp)[:80]}"))
            else:
                result["checked"].append(("localProxyShape", "ok"))
        except Exception as e:
            issues.append(("error", "LOCALPROXY", f"localProxy 对坏参数抛异常:{type(e).__name__}: {e}"))

    def step(name, fn, args, validate):
        t0 = time.time()
        try:
            out = call_with_timeout(fn, args, timeout)
            timings[name] = round(time.time() - t0, 2)
            ok = validate(out)
            result["checked"].append((name, "ok" if ok else "bad"))
            return out
        except Timeout:
            issues.append(("error", "TIMEOUT", f"{name} 超过 {timeout}s 没返回"))
            result["checked"].append((name, "timeout"))
        except Exception as e:
            issues.append(("error", "EXC", f"{name} 抛异常:{type(e).__name__}: {e}"))
            result["checked"].append((name, "exception"))
        return None

    home = step("homeContent", sp.homeContent, (True,), _is_dict)
    if home:
        samples["home"] = _sample(home)
        vids = home.get("list") or home.get("videoList") or []
        _check_list(vids, "homeContent", issues)
        classes = home.get("class") or []
        if not classes and not vids:
            issues.append(("warn", "HOME", "首页既无分类也无内容 —— 电视上点开是空的"))
        if classes:
            samples["class"] = [c.get("type_name") for c in classes if isinstance(c, dict)][:12]
            tid = (classes[0] or {}).get("type_id")
            if tid:
                cat = step("categoryContent", sp.categoryContent, (tid, "1", False, {}), _is_dict)
                if cat:
                    samples["category"] = _sample(cat)
                    _check_list(cat.get("list"), f"categoryContent({tid})", issues)
                    for k in ("page", "pagecount", "limit", "total"):
                        if k not in cat:
                            issues.append(("warn", "FIELD", f"categoryContent 缺分页字段 {k}(电视上翻页会怪)"))
                    first = (cat.get("list") or [{}])[0]
                    if first.get("vod_id"):
                        det = step("detailContent", sp.detailContent, ([first["vod_id"]],), _is_dict)
                        if det:
                            samples["detail"] = _sample(det)
                            _check_list(det.get("list"), "detailContent", issues, need=("vod_play_url",))
                            _check_play_urls(det, issues, samples)
                            # ids 容错:有的壳传单串/tuple 而不是 list,只吃 list 的源会在这类壳炸
                            try:
                                det_s = call_with_timeout(sp.detailContent, (first["vod_id"],), timeout)
                                if not (isinstance(det_s, dict) and det_s.get("list")):
                                    issues.append(("warn", "IDS-NORM", "detailContent 传单串 ids 时没出结果 —— 须做 ids 四态归一化(list/tuple/单串/逗号串)"))
                            except Exception as e:
                                issues.append(("warn", "IDS-NORM", f"detailContent 传单串 ids 抛异常:{type(e).__name__} —— 须做 ids 四态归一化"))
                            if do_play:
                                _check_playback(sp, det, issues, samples, timeout)
        # 搜索
        kw = cfg.get("testKeyword") or "1"
        sch = step("searchContent", sp.searchContent, (kw, False), _is_dict)
        if sch:
            samples["search"] = _sample(sch)
            _check_list(sch.get("list"), f"searchContent({kw})", issues)
    if not any(name == "playerContent" for name, _ in result["checked"]) and hasattr(sp, "playerContent"):
        # 用详情里第一条线路单独再验一次(有些源只有播放步骤会炸)
        pass
    return result


def _is_dict(o):
    return isinstance(o, dict)


def _sample(d):
    out = {}
    for k, v in (d or {}).items():
        if isinstance(v, list):
            out[k] = f"[{len(v)} 条]" + (json.dumps(v[0], ensure_ascii=False)[:160] if v else "")
        else:
            out[k] = v
    return out


def _check_play_urls(det: dict, issues: list, samples: dict):
    """校验播放链格式:vod_play_from / vod_play_url,形如「线路名$地址#线路名$地址」。"""
    first = (det.get("list") or [{}])[0]
    froms = (first.get("vod_play_from") or "").split("$$$")
    urls = (first.get("vod_play_url") or "").split("$$$")
    if not urls or not urls[0]:
        issues.append(("error", "PLAY", "vod_play_url 为空 —— 点进去没线路"))
        return
    samples["lines"] = froms
    for block in urls:
        eps = [e for e in block.split("#") if "$" in e]
        if not eps:
            issues.append(("error", "PLAY", f"播放块格式不对(缺 名$地址):{block[:60]}"))
            continue
        addr = eps[0].split("$", 1)[1]
        if MAGNET_ONLY.match(addr):
            issues.append(("warn", "PLAY", "有线路是磁力链 —— TVBox 播不了磁力,确认这个板块是不是该关掉"))
        if not re.match(r"^(https?://|[\w.-]+\.(?:m3u8|mp4|flv|ts))", addr):
            issues.append(("warn", "PLAY", f"线路地址形态可疑:{addr[:60]}"))


def _check_playback(sp, det: dict, issues: list, samples: dict, timeout: float):
    """L3 真播验证:playerContent + 清单真拉(见 #EXTM3U 且首片下得来)。"""
    first = (det.get("list") or [{}])[0]
    block = (first.get("vod_play_url") or "").split("$$$")[0]
    froms = (first.get("vod_play_from") or "").split("$$$")
    eps = [e for e in block.split("#") if "$" in e]
    if not eps:
        return
    flag = froms[0] if froms else ""
    ep = eps[0]
    purl = ep.split("$", 1)[1]
    if MAGNET_ONLY.match(purl):
        issues.append(("error", "PLAYBACK", "第一条线路是磁力链,无法验证播放(该板块应默认关闭)"))
        return
    try:
        out = call_with_timeout(sp.playerContent, (flag, purl, []), timeout)
    except Exception as e:
        issues.append(("error", "PLAYBACK", f"playerContent 抛异常:{type(e).__name__}: {e}"))
        return
    if not isinstance(out, dict) or not out.get("url"):
        issues.append(("error", "PLAYBACK", f"playerContent 没给出 url:{str(out)[:80]}"))
        return
    if "header" in out and not isinstance(out.get("header"), dict):
        issues.append(("error", "HEADER", f"playerContent 的 header 必须是 dict,不能是 {type(out.get('header')).__name__}"))
    samples["playerContent"] = out
    real = out["url"]
    if real.lower().endswith(".m3u8") and Stream is not None:
        rep = Stream.probe(real)
        samples["playback"] = {k: rep.get(k) for k in
                               ("status", "ctype", "segments", "total_duration", "first_segment_bytes",
                                "mime_ok", "ok", "notes")}
        if not rep.get("ok"):
            issues.append(("error", "PLAYBACK",
                           f"清单/首片拉不动:{rep.get('notes')} (status={rep.get('status')})"))
        if rep.get("mime_ok") is False:
            issues.append(("warn", "MIME", "清单 MIME 错标 → 需要在源里本地代理重吐 application/vnd.apple.mpegurl"))
        if rep.get("total_duration") and rep["total_duration"] < 35 and (rep.get("segments") or 0) <= 3:
            issues.append(("warn", "TRIAL", f"清单总时长只有 {rep['total_duration']}s —— 像是试看窗口,查卡06 打法1"))
    elif Stream is None:
        issues.append(("warn", "PLAYBACK", "没找到 zaka_crack_kit,跳过真播验证"))


# ══════════════════════════════════════════════════════════════════
# 报告
# ══════════════════════════════════════════════════════════════════

def report(res: dict, strict: bool, ran: bool) -> int:
    errs = [i for i in res["issues"] if i[0] == "error"]
    warns = [i for i in res["issues"] if i[0] == "warn"]
    print(f"=== shellsim 报告:{os.path.basename(res['path'])} ===")
    print(f"层:{'L1 静态' if not ran else 'L1 静态 + L2 真跑 + L3 真播'}")
    for name, st in res.get("checked", []):
        print(f"  {name:18s} {st}")
    if res.get("timings"):
        print("  耗时:" + ", ".join(f"{k}={v}s" for k, v in res["timings"].items()))
    if res.get("samples"):
        print("--- 抽样")
        for k, v in res["samples"].items():
            print(f"  {k}: {json.dumps(v, ensure_ascii=False)[:300]}")
    for lvl, code, msg in res["issues"]:
        print(f"  [{'ERROR' if lvl == 'error' else 'WARN '}] {code}: {msg}")
    ok = not errs and (not strict or not warns)
    print(("PASS" if ok else "FAIL") + (" (--strict)" if strict else ""))
    if not ran:
        print("提示:只做了 L1 静态检查。交付前请加 --run --strict 走完 L2/L3。")
    if not ok:
        print("AUDIT_FAIL —— 修完再交付,别急着说『做好了』。")
        return 1
    print("AUDIT_OK")
    return 0


def _selftest() -> int:
    import tempfile
    good = '''# -*- coding: utf-8 -*-
import json, urllib.request, urllib.parse
try:
    from base.spider import BaseSpider
except Exception:
    class BaseSpider:
        pass
class Spider(BaseSpider):
    def getName(self): return "selftest"
    def getDependence(self): return []
    def init(self, extend=""): return None
    def destroy(self): return None
    def isVideoFormat(self, url=None): return ".m3u8" in str(url or "")
    def manualVideoCheck(self): return False
    def action(self, action=None): return {}
    def localProxy(self, param=None): return [200, "text/plain", b"", {}]
    def homeContent(self, filter=None):
        return {"class": [{"type_id": "1", "type_name": "电影"}], "list": [{"vod_id": "1", "vod_name": "a"}]}
    def homeVideoContent(self):
        return {"list": [{"vod_id": "1", "vod_name": "a"}]}
    def categoryContent(self, tid=None, pg=1, filter=None, extend=None):
        return {"list": [{"vod_id": "1", "vod_name": "a"}], "page": int(pg), "pagecount": 5, "limit": 20, "total": 100}
    def detailContent(self, ids=None):
        vid = ids[0] if isinstance(ids, (list, tuple)) else str(ids or "").split(",")[0]
        return {"list": [{"vod_id": vid, "vod_name": "a",
                          "vod_play_from": "线路1",
                          "vod_play_url": "第1集$https://x/a.m3u8"}]}
    def searchContent(self, key=None, quick=False, pg="1"):
        return {"list": [{"vod_id": "1", "vod_name": "a"}]}
    def playerContent(self, flag=None, id=None, vipFlags=None):
        return {"parse": 0, "url": id, "header": {}}
'''
    bad = '''import requests
class BaseSpider:
    def homeContent(self, filter):
        return {"class": [], "list": []}
    def categoryContent(self, tid, pg, filter, extend): return {}
    def detailContent(self, ids): return {}
    def searchContent(self, key, quick=False): return {}
    def playerContent(self, flag, id, vipFlags): return {}
'''
    fails = []

    def ck(name, cond):
        print(("  ✅ " if cond else "  ❌ ") + name)
        if not cond:
            fails.append(name)

    d = tempfile.mkdtemp(prefix="shellsim-")
    gp, bp = os.path.join(d, "good.py"), os.path.join(d, "bad.py")
    open(gp, "w").write(good)
    open(bp, "w").write(bad)
    print("shellsim 自检 (offline)")
    r1 = static_check(gp)
    ck("好源 L1 无 error", not [i for i in r1 if i[0] == "error"])
    r2 = run_spider(gp, timeout=5, do_play=False)
    ck("好源 L2 真跑通过", not [i for i in r2["issues"] if i[0] == "error"])
    r3 = static_check(bp)
    codes = {i[1] for i in r3}
    ck("坏源 L1 逮到缺类/缺全协议方法", ("NO-CLASS" in codes or "MISSING-FULL" in codes))
    bare = _tmp(d, "bare.py", good.replace("class Spider(BaseSpider):", "class Spider:"))
    ck("裸类 Spider 被 BARE-CLASS 逮到", any(i[1] == "BARE-CLASS" for i in static_check(bare)))
    relay = _tmp(d, "relay.py", good + "\nRELAY = \"http://127.0.0.1:%d/jmv?u=\" % 8899\n")
    ck("自建中继构造式 127 地址不误杀", not any(i[1] == "BAD-PLACEHOLDER" for i in static_check(relay)))
    r4 = run_spider(bp, timeout=5, do_play=False)
    ck("坏源 L2 逮到空 list", any(i[1] == "EMPTY" for i in r4["issues"]))
    ck("坏源逮到 requests 无降级", any("requests" in i[2] for i in r3))
    ck("占位域名能被逮到",
       any(i[1] == "BAD-PLACEHOLDER" for i in static_check(_tmp(d, "ph.py",
          good.replace("https://x/a.m3u8", "https://www.example.com/a.m3u8")))))
    print(f"\n自检完成:{'全绿' if not fails else '失败:' + ','.join(fails)}")
    return 1 if fails else 0


def _tmp(d, name, content):
    p = os.path.join(d, name)
    open(p, "w").write(content)
    return p


def main(argv=None):
    ap = argparse.ArgumentParser(description="TVBox 源严格仿真自检")
    ap.add_argument("spider", nargs="?", help="源文件路径")
    ap.add_argument("--run", action="store_true", help="执行 L2/L3(仅用于自研/本机生成的源)")
    ap.add_argument("--strict", action="store_true", help="warn 也算失败")
    ap.add_argument("--no-play", action="store_true", help="跳过 L3 真播验证")
    ap.add_argument("--timeout", type=float, default=20.0)
    ap.add_argument("--cfg", default=None, help="ext 配置(JSON 字符串或文件)")
    ap.add_argument("--json", action="store_true", help="输出 JSON 报告")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return _selftest()
    if not a.spider:
        ap.print_help()
        return 2
    if not os.path.exists(a.spider):
        print(f"找不到文件:{a.spider}")
        return 2
    cfg = {}
    if a.cfg:
        cfg = json.load(open(a.cfg)) if os.path.exists(a.cfg) else json.loads(a.cfg)
    issues = static_check(a.spider)
    res = {"path": a.spider, "checked": [], "issues": issues, "timings": {}, "samples": {}}
    if a.run:
        res = run_spider(a.spider, cfg, a.timeout, do_play=not a.no_play)
        res["issues"] = issues + res["issues"]
    if a.json:
        print(json.dumps(res, ensure_ascii=False, indent=2, default=str))
        errs = [i for i in res["issues"] if i[0] == "error"]
        warns = [i for i in res["issues"] if i[0] == "warn"]
        return 0 if (not errs and (not a.strict or not warns)) else 1
    return report(res, a.strict, a.run)


if __name__ == "__main__":
    sys.exit(main())
