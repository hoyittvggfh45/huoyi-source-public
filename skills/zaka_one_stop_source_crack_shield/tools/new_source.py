#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
new_source.py — 一条龙写源的脚手架(全协议版,2026-10-23 升级)

生成一个 TVBox python 源的骨架:全协议 14 方法、容错签名、混合继承
(壳内继承 base.spider.BaseSpider、无壳回退空基类=裸跑)、域名候选
探活、requests 可选优先 + urllib 自动降级、播放直链+header dict。
只留「站点档案」一段给你填 —— 填完即能跑。

用户偏好(2026-10-22):生成的源文件里不写判型记录之类的头部注释块,
保持文件干净;判型结论与证据链记到工作目录的摸站笔记,不进源文件。

用法:
  python3 new_source.py 番仓 --url https://a.com --domain 番号视频,国产视频 --fid 4,5
  python3 new_source.py 番仓 --url https://a.com --type json --out fanclt2.py
  python3 new_source.py --selftest        # 生成一个样例并跑 L1 自检
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

# 模板用 __TOKEN__ 占位 + replace 填充,不走 str.format,避免花括号转义出错。
TEMPLATE = r'''# -*- coding: utf-8 -*-
import gzip
import json
import re
import sys
import time
import urllib.parse
import urllib.request

# 全协议(铁律):类名必须叫 Spider,混合继承 —— 壳内继承壳提供的
# BaseSpider(base.spider),无壳环境(本地自检/鸭子型加载器)走回退空基类,
# 同一文件两种环境都能实例化。不许裸 class Spider 交付,也不许自带
# BaseSpider 当主类交付(真实壳会报「模块中没有 Spider 类」)。
try:
    sys.path.append("..")
    from base.spider import BaseSpider
except Exception:
    class BaseSpider:
        pass

# 可选依赖:requests 有就优先用,缺失/出错自动降级 urllib,零硬三方依赖。
try:
    import requests as _requests
except Exception:
    _requests = None

# ──────────────────────────────────────────────────────────────
# 卷一 站点档案:换站只改这一段
# ──────────────────────────────────────────────────────────────
SITE = {
    "name": __NAME_JSON__,
    # 域候选表:按顺序探活取首个可用(结果缓存);301 自动跟随
    "domains": __DOMAINS_JSON__,
    # 列表页:{fid}/{pg}/{kw} 会被替换
    "list_path": __LIST_PATH_JSON__,
    "search_path": __SEARCH_PATH_JSON__,
    # 列表条目正则:group(1)=链接 group(2)=标题
    "list_item_re": __LIST_ITEM_RE__,
    # 详情页取播放地址(可多条线路)
    "detail_m3u8_re": __DETAIL_RE__,
    # 有的站要带 cookie 门,没有就留空 dict
    "cookie_gate": {},
    # 标题/正文是 base64 的站,打开这条
    "b64_text": False,
    "headers": {"Referer": __HOME_JSON__},
}

CATS = __CATS_JSON__

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
TIMEOUT = 12
RETRY = 3

_HOST_CACHE = ""


# ──────────────────────────────────────────────────────────────
# 卷二 通用工具:参数归一化 + HTTP(requests 优先,urllib 降级)
# ──────────────────────────────────────────────────────────────
def _dec(raw):
    for enc in ("utf-8", "gb18030"):
        try:
            return raw.decode(enc)
        except Exception:
            continue
    return raw.decode("utf-8", "ignore")


def _norm_ids(ids):
    """detailContent 的 ids 四态归一化:list / tuple / 单串 / 逗号串。"""
    if isinstance(ids, (list, tuple)):
        parts = [str(x) for x in ids]
    else:
        parts = str(ids or "").split(",")
    return [p.strip() for p in parts if p and p.strip()]


def _norm_extend(extend):
    if not extend:
        return {}
    if isinstance(extend, dict):
        return extend
    try:
        out = json.loads(str(extend))
        return out if isinstance(out, dict) else {}
    except Exception:
        return {}


def _norm_pg(pg, default=1):
    try:
        n = int(str(pg))
        return n if n >= 1 else default
    except Exception:
        return default


def _fetch(url):
    """返回 (status, content_type, body_bytes, final_url)。"""
    headers = {"User-Agent": UA}
    headers.update(SITE["headers"])
    for k, v in SITE["cookie_gate"].items():
        headers["Cookie"] = "%s=%s" % (k, v)
    if _requests is not None:
        try:
            r = _requests.get(url, headers=headers, timeout=TIMEOUT)
            return r.status_code, (r.headers.get("Content-Type") or ""), r.content, r.url
        except Exception:
            pass
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        raw = r.read()
        if raw[:2] == b"\x1f\x8b":
            raw = gzip.decompress(raw)
        return r.status, (r.headers.get("Content-Type") or ""), raw, r.geturl()


def _base():
    """域候选探活:依次试,首个能通的缓存下来;全灭回退第一个。"""
    global _HOST_CACHE
    if _HOST_CACHE:
        return _HOST_CACHE
    for d in SITE["domains"]:
        try:
            st, ct, body, final = _fetch(d.rstrip("/") + "/")
            if st and st < 500 and body:
                _HOST_CACHE = d.rstrip("/")
                return _HOST_CACHE
        except Exception:
            continue
    _HOST_CACHE = SITE["domains"][0].rstrip("/")
    return _HOST_CACHE


def http_get(path, base=None):
    """带重试的 GET, 返回 (文本, 最终URL)。抖动退避重试。"""
    urls = []
    if path.startswith("http"):
        urls = [path]
    else:
        for d in ([base] if base else []) + [_base()]:
            urls.append((d or "").rstrip("/") + path)
    for u in urls:
        for attempt in range(RETRY):
            try:
                st, ct, raw, final = _fetch(u)
                if st and st < 400 and raw:
                    return _dec(raw), final
            except Exception:
                pass
            time.sleep(0.5 * (attempt + 1))
    return "", None


def txt_of(s):
    s = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", s or "")
    s = re.sub(r"(?s)<[^>]+>", " ", s)
    import html as _h
    return re.sub(r"\s+", " ", _h.unescape(s)).strip()


def maybe_b64(s):
    if not SITE["b64_text"] or not s:
        return s
    import base64
    try:
        return base64.b64decode(s + "=" * ((4 - len(s) % 4) % 4)).decode("utf-8", "ignore")
    except Exception:
        return s


def grab_list(html_text, base):
    out, seen = [], set()
    for m in re.finditer(SITE["list_item_re"], html_text or "", re.S):
        href, title = m.group(1), maybe_b64(txt_of(m.group(2)))
        if not href or not title:
            continue
        if href.startswith("/"):
            href = urllib.parse.urljoin(base or _base(), href)
        if href in seen:
            continue
        seen.add(href)
        out.append({"vod_id": href, "vod_name": title[:80]})
    return out


def grab_play(html_text, base):
    urls = re.findall(SITE["detail_m3u8_re"], html_text or "", re.S)
    lines = []
    for i, u in enumerate(urls[:5]):
        if u.startswith("//"):
            u = "https:" + u
        elif u.startswith("/"):
            u = urllib.parse.urljoin(base or _base(), u)
        if u:
            lines.append("线路%d$%s" % (i + 1, u))
    return "#".join(lines)


# ──────────────────────────────────────────────────────────────
# 卷三 TVBox 源接口(全协议 14 方法)
# ──────────────────────────────────────────────────────────────
class Spider(BaseSpider):
    def __init__(self):
        self.ext = {}
        self.site = SITE["domains"][0]

    # ── 契约方法 ──────────────────────────────────────────────
    def getName(self):
        return SITE["name"]

    def getDependence(self):
        return []

    def init(self, extend=""):
        self.ext = _norm_extend(extend)
        h = self.ext.get("host") or self.ext.get("url") or self.ext.get("site")
        if h and str(h).startswith("http"):
            global _HOST_CACHE
            _HOST_CACHE = str(h).rstrip("/")
        return None

    def destroy(self):
        return None

    def isVideoFormat(self, url=None):
        u = str(url or "").lower()
        return (".m3u8" in u) or (".mp4" in u) or (".flv" in u)

    def manualVideoCheck(self):
        return False

    def action(self, action=None):
        return {}

    def localProxy(self, param=None):
        """全协议默认四项式 [status, mime, body, headers]。

        FongMi proxy:// 图片链且 body 为 base64 串时,改用五项式并在
        末位加 1(壳按该标志把 body 当 base64 解码),见技能 SKILL.md。
        """
        try:
            p = param
            if isinstance(p, str):
                try:
                    p = json.loads(p)
                except Exception:
                    p = dict(urllib.parse.parse_qsl(p))
            if not isinstance(p, dict):
                p = {}
            target = p.get("url") or p.get("u") or ""
            if isinstance(target, list):
                target = target[0] if target else ""
            target = urllib.parse.unquote(str(target or "").strip())
            if not target.startswith("http"):
                return [404, "text/plain", b"bad url", {}]
            st, ct, body, final = _fetch(target)
            return [int(st), ct or "application/octet-stream", body, {}]
        except Exception:
            return [502, "text/plain", b"proxy error", {}]

    # ── 内容方法(签名全带默认值,兼容少参/位置/关键字调用) ────
    def homeContent(self, filter=None):
        return {"class": CATS, "list": [], "filters": {}}

    def homeVideoContent(self):
        html_text, base = http_get(SITE["list_path"].format(fid=CATS[0]["type_id"], pg=1, kw=""))
        return {"list": grab_list(html_text, base)}

    def categoryContent(self, tid=None, pg=1, filter=None, extend=None):
        pg = _norm_pg(pg)
        html_text, base = http_get(SITE["list_path"].format(fid=tid, pg=pg, kw=""))
        items = grab_list(html_text, base)
        return {"list": items, "page": pg, "pagecount": 9999 if items else pg,
                "limit": len(items), "total": 999999}

    def detailContent(self, ids=None):
        vids = _norm_ids(ids)
        if not vids:
            return {"list": []}
        vid = vids[0]
        html_text, base = http_get(vid)
        play = grab_play(html_text, base)
        title = ""
        m = re.search(r"<title>(.*?)</title>", html_text or "", re.S)
        if m:
            title = maybe_b64(txt_of(m.group(1)))
        return {"list": [{"vod_id": vid, "vod_name": title, "vod_play_from": "线路",
                          "vod_play_url": play or "无法解析$"}]}

    def searchContent(self, key=None, quick=False, pg="1"):
        pg = _norm_pg(pg)
        html_text, base = http_get(SITE["search_path"].format(pg=pg, kw=urllib.parse.quote(str(key or ""))))
        return {"list": grab_list(html_text, base), "page": pg}

    def playerContent(self, flag=None, id=None, vipFlags=None):
        # 全协议:header 必须是 dict,不要拼字符串;id 可能还带「名$」前缀
        url = str(id or "")
        if "$" in url and not url.startswith("http"):
            url = url.split("$", 1)[1]
        return {"parse": 0, "jx": 0, "playUrl": "", "url": url,
                "header": dict(SITE["headers"])}
'''


def build(name: str, url: str, domains: list, cats: list, kind: str,
          list_path: str, search_path: str, path_note: str) -> str:
    Q = "'"
    if kind == "json":
        item_re = "r" + Q + '"id"\\s*:\\s*"?([^",]+)"?.{0,400}?"name"\\s*:\\s*"([^"]+)"' + Q
        m3u8_re = "r" + Q + '"https?://[^"\\s]+\\.m3u8[^"\\s]*"' + Q
    elif kind == "spa":
        item_re = "r" + Q + '<script[^>]+id="__NEXT_DATA__"[^>]*>(.*?)</script>' + Q
        m3u8_re = "r" + Q + '"https?://[^"\\s]+\\.m3u8[^"\\s]*"' + Q
    else:
        item_re = "r" + Q + '<a[^>]+href="([^"]+)"[^>]*>([^<]{2,80})</a>' + Q
        m3u8_re = "r" + Q + '<(?:source|video)[^>]+src="([^"]+\\.m3u8[^"]*)"' + Q
    cats_src = [{"type_id": str(i + 1), "type_name": c} for i, c in enumerate(cats)]
    # fid 覆盖在 main() 里处理后以 cats 传入时已带 type_id 的情况:保持简单,
    # cats 参数允许是 (type_id, type_name) 元组或纯名称字符串。
    cats_norm = []
    for i, c in enumerate(cats):
        if isinstance(c, (list, tuple)) and len(c) == 2:
            cats_norm.append({"type_id": str(c[0]), "type_name": str(c[1])})
        else:
            cats_norm.append({"type_id": str(i + 1), "type_name": str(c)})
    out = TEMPLATE
    out = out.replace("__NAME_JSON__", json.dumps(name, ensure_ascii=False))
    out = out.replace("__DOMAINS_JSON__", json.dumps([d.rstrip("/") for d in domains], ensure_ascii=False))
    out = out.replace("__LIST_PATH_JSON__", json.dumps(list_path, ensure_ascii=False))
    out = out.replace("__SEARCH_PATH_JSON__", json.dumps(search_path, ensure_ascii=False))
    out = out.replace("__LIST_ITEM_RE__", item_re)
    out = out.replace("__DETAIL_RE__", m3u8_re)
    out = out.replace("__HOME_JSON__", json.dumps(url.rstrip("/") + "/", ensure_ascii=False))
    out = out.replace("__CATS_JSON__", json.dumps(cats_norm, ensure_ascii=False))
    return out


def _selftest() -> int:
    d = tempfile.mkdtemp(prefix="newsrc-")
    out = os.path.join(d, "sample.py")
    code = build("样例站", "https://demo.local", ["https://demo.local"], ["电影", "剧集"],
                 "html", "/list-{fid}-{pg}.html", "/search-{pg}.html?q={kw}", None)
    open(out, "w", encoding="utf-8").write(code)
    print("生成样例:", out)
    here = os.path.dirname(os.path.abspath(__file__))
    r1 = subprocess.run([sys.executable, os.path.join(here, "shellsim.py"), out],
                        capture_output=True, text=True)
    print(r1.stdout.strip()[-800:])
    ok_static = "PASS" in r1.stdout
    r2 = subprocess.run([sys.executable, "-m", "py_compile", out], capture_output=True, text=True)
    ok_syntax = r2.returncode == 0
    print(("  ✅ " if ok_static else "  ❌ ") + "生成的骨架过 L1 静态检查(全协议)")
    print(("  ✅ " if ok_syntax else "  ❌ ") + "生成的骨架语法可编译")
    return 0 if (ok_static and ok_syntax) else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description="TVBox 源脚手架(全协议版)")
    ap.add_argument("name", nargs="?", help="源名称,如 番仓")
    ap.add_argument("--url", default="https://example.local")
    ap.add_argument("--domain", default="", help="分类,逗号分隔")
    ap.add_argument("--domains", default="", help="域候选表,逗号分隔(域轮换用)")
    ap.add_argument("--fid", default="", help="板块 id,逗号分隔(和 --domain 一一对应)")
    ap.add_argument("--type", default="html", choices=("html", "json", "spa"))
    ap.add_argument("--list-path", default="/list-{fid}-{pg}.html")
    ap.add_argument("--search-path", default="/search-{pg}.html?q={kw}")
    ap.add_argument("--path-note", default=None, help="（兼容旧参数，已不写入源文件）")
    ap.add_argument("--out", default=None)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return _selftest()
    if not a.name:
        ap.print_help()
        return 2
    names = [c.strip() for c in a.domain.split(",") if c.strip()]
    fids = [c.strip() for c in a.fid.split(",") if c.strip()]
    cats = list(zip(fids, names)) if (fids and len(fids) == len(names)) else names
    domains = [d.strip() for d in (a.domains or a.url).split(",") if d.strip()]
    code = build(a.name, a.url, domains, cats, a.type, a.list_path, a.search_path, a.path_note)
    out = a.out or re.sub(r"\W+", "_", a.name) + "_spider.py"
    open(out, "w", encoding="utf-8").write(code)
    print(f"已生成 {out}")
    print("下一步:")
    print(f"  1. 判型:python3 zaka_crack_kit.py probe {a.url}   (结论记入工作目录摸站笔记,不写进源文件)")
    print(f"  2. 填 SITE 档案:列表正则 / 详情取流正则 / cookie 门 / 域候选表")
    print(f"  3. 自检:python3 shellsim.py {out} --run --strict   (要 AUDIT_OK)")
    print("  4. 交付:把源 + 配置片段 + 使用说明一起给用户")
    return 0


if __name__ == "__main__":
    sys.exit(main())
