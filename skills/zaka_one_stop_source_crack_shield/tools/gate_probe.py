#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gate_probe.py —— 网关「零区分度」判定器(决定签名该不该靠试错去猜)

要解决的问题:
  有些网关对任何没通过校验的请求,都回同一条固定报文(「违规请求」「系统繁忙」)。
  这时你发 460 种签名拼法 / 换 UA / 换 header 位置,拿到的是同一条回复 ——
  等于闭着眼睛猜,永远收不敛。继续穷举 = 纯烧时间。
  反过来,有些网关会漏出区分度(有的路径 404、有的 code 不同、有的回显缺哪个参数),
  那种就值得试错逼近。

  这一个判断,决定后面是「几小时」还是「几天」。所以做成工具,别靠感觉。

用法:
  python3 gate_probe.py --base https://api.example.com --path /module/x/search --param wd=test
  python3 gate_probe.py --url https://api.example.com/module/x/search?wd=test
  python3 gate_probe.py ... --header "X-Auth-Key: xxx" --json out.json

判定:
  differentiated  多种不同业务报文 → 有区分度,可以试错逼近
  weak            只有通用错误 vs 正常路径两种 → 区分度弱,只能靠"存在性"探针
  zero            全同一条 → 零区分度,停止穷举,转算法提取(blutter / Frida / 静态)

自检:
  python3 gate_probe.py --selftest     # 本地起两种模拟网关,验证判得对
"""
import argparse
import hashlib
import json
import re
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/119 Mobile Safari/537.36"

NUM_RE = re.compile(rb"\d+")
WS_RE = re.compile(rb"\s+")


def normalize(body: bytes) -> str:
    """把易变部分(数字/空白)抹掉,只留结构,用来比对'是不是同一条报文'"""
    b = NUM_RE.sub(b"N", body[:20000])
    b = WS_RE.sub(b" ", b)
    return hashlib.sha1(b).hexdigest()[:10]


def pick_fields(body: bytes):
    """从 JSON 或有 code/msg 的 JS 里抠状态字段,抠不到返回空"""
    try:
        txt = body[:20000].decode("utf-8", "ignore")
    except Exception:
        return {}
    out = {}
    m = re.search(r'"(code|status|errno|errorCode)"\s*:\s*(-?\d+)', txt)
    if m:
        out["code"] = m.group(2)
    m = re.search(r'"(msg|message|errmsg|error)"\s*:\s*"([^"]{0,80})"', txt)
    if m:
        out["msg"] = m.group(2)
    return out


def http_get(url, headers=None, method="GET", timeout=12):
    req = urllib.request.Request(url, method=method)
    req.add_header("User-Agent", UA)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            body = r.read(20000)
            return {"status": r.status, "body": body, "ms": int((time.time() - t0) * 1000)}
    except urllib.error.HTTPError as e:
        try:
            body = e.read(20000)
        except Exception:
            body = b""
        return {"status": e.code, "body": body, "ms": int((time.time() - t0) * 1000)}
    except Exception as e:
        return {"status": 0, "body": str(e).encode(), "ms": int((time.time() - t0) * 1000),
                "error": type(e).__name__}


def variant_urls(base, path, param):
    """一组语义等价、只改认证面的请求。哪一条通了,就说明限制在哪一层。"""
    b = base.rstrip("/")
    p = path if path.startswith("/") else "/" + path
    q = param or ""
    sep = "&" if q else ""
    u = f"{b}{p}" + (f"?{q}" if q else "")
    return [
        ("裸请求(无凭证)", u, {}),
        ("根路径对照", f"{b}/", {}),
        ("不存在的路径", f"{b}{p}_nope_{int(time.time()) % 10000}", {}),
        ("加假 Key", u + f"{sep}X-Auth-Key=deadbeef&X-Auth-TimeStamp=1&X-Auth-Nonce=abc", {}),
        ("加假签名头", u + f"{sep}X-Auth-Key=deadbeef&X-Auth-TimeStamp=1&X-Auth-Nonce=abc",
         {"X-Auth-Sign": "0" * 32}),
        ("换方法 HEAD", u, {"__method__": "HEAD"}),
        ("换 UA", u, {"User-Agent": "okhttp/4.9.0"}),
    ]


def run(base, path, param, headers, method, timeout):
    rows = []
    for label, url, hdr in variant_urls(base, path, param):
        m = hdr.pop("__method__", method)
        send = {}
        for k, v in hdr.items():
            if k.lower() == "user-agent":
                send["_ua_override"] = v
            else:
                send[k] = v
        if "_ua_override" in send:
            global UA
            old, UA = UA, send.pop("_ua_override")
            r = http_get(url, send, m, timeout)
            UA = old
        else:
            r = http_get(url, send, m, timeout)

        fp = normalize(r["body"])
        fields = pick_fields(r["body"])
        rows.append({
            "variant": label,
            "url": url[:120],
            "status": r["status"],
            "len": len(r["body"]),
            "code": fields.get("code", "-"),
            "msg": (fields.get("msg", "-") or "-")[:30],
            "fp": fp,
            "ms": r["ms"],
            "error": r.get("error", ""),
        })
    return rows


def judge(rows):
    """聚类出结论 + 给出下一步该干什么"""
    # HEAD / 204 没有 body,不能拿来比"报文是否相同" —— 否则会把零区分度误判成 weak
    biz = [r for r in rows if r["status"] not in (0,) and not r["error"] and r["len"] > 0]
    fps = {r["fp"] for r in biz}
    codes = {r["code"] for r in biz if r["code"] != "-"}
    msgs = {r["msg"] for r in biz if r["msg"] != "-"}

    if not biz:
        return "unreachable", "全部请求失败(网络/域名/被墙)", \
               ["先确认域名活着:换节点、换 HTTP/HTTPS、查发布页", "别在打不通的网关上做任何判定"]

    if len(fps) == 1:
        return "zero", "所有请求返回同一条报文 —— 零区分度", [
            "停止穷举签名:没有反馈就无法逼近,再试 1000 次也一样",
            "转算法提取:静态(asn/字符串)→ blutter(Fast/Slow)> Frida hook 返回值",
            "把这条写进档案:零区分度是硬判据,不是'再试试'",
        ]

    if len(fps) == 2 and len(codes) <= 2:
        return "weak", f"只有 {len(fps)} 种响应 —— 区分度弱(通用错误 vs 正常路径)", [
            "可以用'路径存在性'做探针,但别指望用它反推签名",
            "真正的签名算法还是得从代码里拿",
        ]

    return "differentiated", f"{len(fps)} 种不同响应 / {len(msgs)} 种提示 —— 有区分度", [
        "可以试错逼近:缺参数/错参数通常会有不同提示",
        "优先用带提示差别的那几条做探针,逐字段补",
        "一旦收敛到'只差签名',再回 Sign.guess() 穷举排序",
    ]


def report(rows, verdict, why, nexts):
    print("=" * 78)
    print(f"{'变体':<16}{'状态':>6}{'长度':>8}{'code':>8}{'耗时':>8}  报文指纹")
    print("-" * 78)
    for r in rows:
        print(f"{r['variant']:<16}{r['status']:>6}{r['len']:>8}{r['code']:>8}{r['ms']:>7}ms  {r['fp']}"
              + (f"  [{r['error']}]" if r.get("error") else ""))
        if r["msg"] != "-":
            print(f"{'':<16}msg: {r['msg']}")
    print("=" * 78)
    print(f"判定  {verdict.upper()}  —— {why}")
    for i, n in enumerate(nexts, 1):
        print(f"  {i}. {n}")


# ---------------------------------------------------------------- 自检(mock 网关)

class _ZeroGate(BaseHTTPRequestHandler):
    """模拟:任何请求都回同一条'违规请求'"""
    def _any(self):
        body = '{"code":400,"msg":"违规请求","data":null}'.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = do_HEAD = do_POST = _any

    def log_message(self, *a):
        pass


class _OpenGate(BaseHTTPRequestHandler):
    """模拟:有区分度 —— 缺哪个参数就提示哪个(真实网关里这种最值得试错)"""
    def do_GET(self):
        q = urllib.parse.urlparse(self.path).query
        has = lambda k: (k + "=") in q
        if self.path.startswith("/ok"):
            body, code = b'{"code":0,"msg":"ok","data":{"id":1}}', 200
        elif not self.path.startswith("/module"):
            body, code = b'{"code":404,"msg":"not found","data":null}', 404
        elif not has("X-Auth-Key"):
            body, code = '{"code":1001,"msg":"missing X-Auth-Key","data":null}'.encode(), 200
        elif not has("X-Auth-TimeStamp"):
            body, code = '{"code":1002,"msg":"missing X-Auth-TimeStamp","data":null}'.encode(), 200
        elif not has("X-Auth-Sign") and "X-Auth-Sign" not in str(self.headers):
            body, code = '{"code":1003,"msg":"bad signature","data":null}'.encode(), 200
        else:
            body, code = b'{"code":1004,"msg":"nonce expired","data":null}', 200
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def selftest():
    print("· 起两个模拟网关,验证判定是否可靠")
    ok = True

    def serve(handler, port):
        srv = HTTPServer(("127.0.0.1", port), handler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        return srv

    s1 = serve(_ZeroGate, 18771)
    rows = run("http://127.0.0.1:18771", "/module/x/search", "wd=1", {}, "GET", 5)
    v, why, _ = judge(rows)
    print(f"  零区分度网关 → {v}  ({why})")
    ok &= (v == "zero")
    s1.shutdown()

    s2 = serve(_OpenGate, 18772)
    rows = run("http://127.0.0.1:18772", "/module/x/search", "wd=1", {}, "GET", 5)
    v2, why2, _ = judge(rows)
    print(f"  有区分度网关 → {v2}  ({why2})")
    ok &= (v2 in ("differentiated", "weak"))
    s2.shutdown()

    # 死站要判 unreachable,不能瞎给结论
    rows = run("http://127.0.0.1:18779", "/x", "", {}, "GET", 2)
    v3, why3, _ = judge(rows)
    print(f"  打不通的站   → {v3}  ({why3})")
    ok &= (v3 == "unreachable")

    print("自检完成:" + ("全绿" if ok else "有失败"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description="网关零区分度判定")
    ap.add_argument("--base", help="网关根,如 https://api.example.com")
    ap.add_argument("--path", default="/", help="被探的路径")
    ap.add_argument("--param", default="", help="业务参数串,如 wd=test")
    ap.add_argument("--url", help="直接给完整 URL(会拆成 base/path/param)")
    ap.add_argument("--header", action="append", default=[], help="额外请求头 k: v")
    ap.add_argument("--method", default="GET")
    ap.add_argument("--timeout", type=int, default=12)
    ap.add_argument("--json", help="把结果写文件")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    base, path, param = args.base, args.path, args.param
    if args.url:
        u = urllib.parse.urlparse(args.url)
        base = f"{u.scheme}://{u.netloc}"
        path = u.path or "/"
        param = u.query

    if not base:
        ap.print_help()
        return 2

    headers = {}
    for h in args.header:
        if ":" in h:
            k, v = h.split(":", 1)
            headers[k.strip()] = v.strip()

    rows = run(base, path, param, headers, args.method, args.timeout)
    verdict, why, nexts = judge(rows)
    report(rows, verdict, why, nexts)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({"base": base, "path": path, "verdict": verdict,
                       "why": why, "next_steps": nexts, "rows": rows},
                      f, ensure_ascii=False, indent=2)
        print(f"[json] {args.json}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
