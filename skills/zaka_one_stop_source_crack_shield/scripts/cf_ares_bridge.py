# -*- coding: utf-8 -*-
"""
CF-Ares 过盾桥接器 —— TVBox 四壳 Spider 过盾集成
=================================================
核心思路（两段式）：
  1. 开发端（PC/服务器）用 CF-Ares 过盾（curl_cffi 指纹 → 懒加载浏览器引擎解 5秒盾/CAPTCHA/Turnstile）
  2. 过盾后固化的 Cookie（cf_clearance / __cf_bm 等）导出 → TVBox 壳内 Spider 直接带 Cookie 访问，
     无需在手机端跑浏览器（chaquo 环境无 selenium/undetected）

用法：
  # 开发端：过盾 + 导出 Cookie（输出 json）
  python3 cf_ares_bridge.py solve "https://目标站.com" -o cf_cookies.json

  # Spider 内：加载 Cookie 后带 Cookie 请求（兜底直连）
  from cf_ares_bridge import load_cookies, cf_get_cookie_jar

用法（库模式）：
  from cf_ares_bridge import cf_solve, cf_get
  r = cf_get("https://目标站.com")            # 全自动过盾（curl → 浏览器）
  jar = cf_solve("https://目标站.com")        # 显式过盾，返回 cookie jar
"""

import argparse
import json
import os
import sys
import time

# ---------- Cookie 存取 ----------
COOKIE_STORE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cf_cookies_store.json")


def load_cookies(path=None):
    """加载已过盾的 Cookie（dict: 域名 -> [{name,value,...}]）"""
    path = path or COOKIE_STORE
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_cookies(store, path=None):
    path = path or COOKIE_STORE
    with open(path, "w", encoding="utf-8") as f:
        json.dump(store, f, ensure_ascii=False, indent=1)
    return path


def cookie_header_for(url, store=None):
    """把某域名已过盾的 Cookie 拼成 header 字符串（Spider 直接塞进请求头）"""
    store = store if store is not None else load_cookies()
    host = _domain_of(url)
    jar = store.get(host, [])
    if not jar:
        return ""
    parts = []
    for c in jar:
        nm, vl = c.get("name"), c.get("value")
        if nm and vl is not None:
            parts.append("%s=%s" % (nm, vl))
    return "; ".join(parts)


def _domain_of(url):
    from urllib.parse import urlparse
    try:
        return urlparse(url).netloc.split(":")[0]
    except Exception:
        return url


# ---------- 核心过盾 ----------
def _try_cf_ares():
    """尝试加载 cf_ares 库（本地库目录或已安装）"""
    here = os.path.dirname(os.path.abspath(__file__))
    local = os.path.join(here, "cf_ares")
    if os.path.isdir(local) and local not in sys.path:
        sys.path.insert(0, local)
    try:
        from cf_ares import AresClient
        return AresClient
    except Exception:
        return None


def cf_solve(url, engine="auto", proxy=None, headless=True, timeout=40, save=True):
    """显式过盾：返回 cookie jar（dict: 域名 -> [{name,value,...}]）"""
    AresClient = _try_cf_ares()
    if AresClient is None:
        print("[cf_ares_bridge] 未找到 cf_ares 库，请放置 cf_ares 库目录到本脚本旁或 pip install cf-ares")
        return {}
    kw = {}
    if proxy:
        kw["proxy"] = proxy
    if engine and engine != "auto":
        kw["browser_engine"] = engine
    kw["headless"] = headless
    client = AresClient(**kw)
    try:
        r = client.solve_challenge(url)
        print("[cf_ares_bridge] 过盾完成: %s -> HTTP %s" % (url, getattr(r, "status_code", "?")))
        host = _domain_of(url)
        cookies = []
        try:
            jar = r.cookies if hasattr(r, "cookies") else {}
            for c in jar:
                cookies.append({"name": getattr(c, "name", c.get("name", "")),
                                "value": getattr(c, "value", c.get("value", "")),
                                "domain": getattr(c, "domain", c.get("domain", host))})
        except Exception:
            cookies = []
        if not cookies:
            # 兜底：取客户端会话 cookie
            try:
                info = client.get_session_info(url)
                ck = info.get("cookies", {}) or {}
                for k, v in ck.items():
                    cookies.append({"name": k, "value": str(v), "domain": host})
            except Exception:
                cookies = []
        store = load_cookies()
        store[host] = cookies
        if save:
            path = save_cookies(store)
            print("[cf_ares_bridge] Cookie 已存: %s (%d 个)" % (path, len(cookies)))
        return store.get(host, [])
    except Exception as e:
        print("[cf_ares_bridge] 过盾失败: %s" % str(e)[:150])
        return {}


def cf_get(url, engine="auto", proxy=None, headers=None, timeout=40):
    """全自动过盾请求：curl 引擎直试 → 遇挑战懒加载浏览器引擎解盾 → 返回 AresResponse"""
    AresClient = _try_cf_ares()
    if AresClient is None:
        raise RuntimeError("cf_ares 库不可用")
    kw = {"timeout": timeout}
    if proxy:
        kw["proxy"] = proxy
    if engine and engine != "auto":
        kw["browser_engine"] = engine
    if headers:
        kw["headers"] = headers
    client = AresClient(**kw)
    return client.get(url)


def cf_get_with_cookies(url, store=None, fallback_cf=True, **kw):
    """带已过盾 Cookie 请求（TVBox Spider 用）；无 Cookie 时可选 fallback_cf 全自动过盾"""
    import requests as _rq
    header = cookie_header_for(url, store)
    h = {"User-Agent": "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"}
    if header:
        h["Cookie"] = header
    try:
        r = _rq.get(url, headers=h, timeout=kw.get("timeout", 25))
        return r
    except Exception:
        if not fallback_cf:
            raise
        rr = cf_get(url, timeout=kw.get("timeout", 25))
        return rr


# ---------- CLI ----------
def main():
    ap = argparse.ArgumentParser(description="CF-Ares 过盾桥接器（TVBox Spider 过盾 Cookie 固化）")
    sub = ap.add_subparsers(dest="cmd")
    p1 = sub.add_parser("solve", help="显式过盾并保存 Cookie")
    p1.add_argument("url")
    p1.add_argument("-o", "--output", default=None, help="Cookie 输出 json 路径")
    p1.add_argument("--engine", default="auto", choices=["auto", "curl", "undetected", "seleniumbase"])
    p1.add_argument("--proxy", default=None)
    p1.add_argument("--headful", action="store_true", help="显示浏览器（默认无头）")
    p2 = sub.add_parser("get", help="全自动过盾 GET")
    p2.add_argument("url")
    p2.add_argument("--engine", default="auto")
    p2.add_argument("--proxy", default=None)
    p3 = sub.add_parser("header", help="输出某域名的过盾 Cookie 请求头")
    p3.add_argument("url")
    args = ap.parse_args()

    if args.cmd == "solve":
        jar = cf_solve(args.url, engine=args.engine, proxy=args.proxy, headless=not args.headful)
        if args.output:
            host = _domain_of(args.url)
            save_cookies({host: jar}, args.output)
            print("已导出: %s" % args.output)
        print("Cookie 数量: %d" % len(jar))
    elif args.cmd == "get":
        r = cf_get(args.url, engine=args.engine, proxy=args.proxy)
        print("HTTP %s len=%d" % (getattr(r, "status_code", "?"), len(getattr(r, "text", "") or "")))
    elif args.cmd == "header":
        h = cookie_header_for(args.url)
        print(h or "（无该域名过盾 Cookie）")
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
