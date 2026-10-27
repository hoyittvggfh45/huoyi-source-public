# -*- coding: utf-8 -*-
"""
avbox_probe.py —— AvBox 聚合壳网关探测器

用途
    1) 体检域名池:哪些节点还活着、各自返回什么
    2) 遍历 93 条 /module/ 路由,把网关响应归个类
    3) 签名引擎是可插拔的:以后你要是把 _generateSign 反汇编出来了,
       直接把算法填进 make_sign(),整个脚本立刻变成通吃客户端
    4) 响应解密探针:换密钥/算法试

用法
    python3 avbox_probe.py hosts              # 体检网关节点
    python3 avbox_probe.py routes             # 遍历路由
    python3 avbox_probe.py trial <host>       # 在指定 host 上试签名

注意
    当前 make_sign() 里放的是常见拼法,实测不成立(网关对错误签名一律
    返回同一条"违规请求",没有区分度)。留着是给算法到手后直接替换用。

只依赖标准库。
"""

import base64
import concurrent.futures as cf
import hashlib
import hmac
import json
import os
import random
import ssl
import sys
import time
import urllib.error
import urllib.request

APP_KEY = "368480924a6c78e2e8681551a7cf4c21"

API_HOSTS = [
    "https://api.3459381.com", "https://api.61c76a0.com", "https://api.6b18726.com",
    "https://api.7d87e17.com", "https://api.87735d5.com", "https://api.b3d530f.com",
    "https://api.b7f3192.com", "https://api.c6dd5cc.com", "https://api.c9wgdr.com",
    "https://api.em1oifd0.com", "https://api.0yhxyky2v099lb9.com", "https://api.he0jys.com",
    "https://api.j7y675.com", "https://api-al.yuytyr.online",
    "http://172.247.132.138",
]

NODE_HOSTS = [
    "http://122.10.20.249:6868", "http://38.46.10.2:6868", "http://38.46.10.3:6868",
    "http://38.46.10.4:6868", "http://38.46.10.5:6868", "http://38.46.10.6:6868",
    "http://198.44.248.101:6868", "http://198.44.248.102:6868",
    "http://202.95.22.200:6868", "http://202.95.22.201:6868",
    "http://202.95.22.202:6868", "http://202.95.22.203:6868",
    "http://202.95.22.204:6868",
]

UA = "okhttp/3.12.0"
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

HERE = os.path.dirname(os.path.abspath(__file__))


def http_get(url, headers=None, timeout=10):
    h = {"User-Agent": UA, "Accept": "application/json"}
    if headers:
        h.update(headers)
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=timeout, context=CTX)
        return r.status, r.read(2000).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read(1000).decode("utf-8", "replace")
    except Exception as e:
        return -1, "ERR " + str(e)[:100]


# ----------------------------------------------------------------------
# 签名引擎 —— 算法到手后只需要改这一个函数
# ----------------------------------------------------------------------
def make_sign(path, query_params, ts, nonce):
    """返回 (sign, extra_headers, extra_query_suffix)

    默认实现是"猜"的常见拼法,实测不成立。签名算法从 _generateSign
    反汇编出来之后,在这里照抄即可,函数签名保持不变。
    """
    items = sorted(query_params.items())
    base = "&".join("%s=%s" % (k, v) for k, v in items)
    raw = "%s&%s&%s&%s" % (base, ts, nonce, APP_KEY)
    sign = hashlib.md5(raw.encode()).hexdigest()
    headers = {"X-Auth-Sign": sign}
    suffix = "&X-Auth-Key=%s&X-Auth-TimeStamp=%s&X-Auth-Nonce=%s" % (APP_KEY, ts, nonce)
    return sign, headers, suffix


def call(host, path, params=None, signed=True):
    params = params or {}
    qs = "&".join("%s=%s" % (k, v) for k, v in params.items())
    url = host + path + (("?" + qs) if qs else "")
    headers = None
    if signed:
        ts = str(int(time.time()))
        nonce = "".join(random.choice("0123456789") for _ in range(8))
        _, headers, suffix = make_sign(path, params, ts, nonce)
        url += ("&" if qs else "?") + suffix.lstrip("&")
    code, body = http_get(url, headers=headers)
    return code, body


# ----------------------------------------------------------------------
# 子命令
# ----------------------------------------------------------------------
def cmd_hosts():
    hosts = API_HOSTS + NODE_HOSTS
    probe_path = "/module/javdb/search?wd=test"

    def one(h):
        code, body = http_get(h + probe_path)
        code2, _ = http_get(h + "/")
        return h, code, body[:130].replace("\n", " "), code2

    print("%-34s %-5s %-5s %s" % ("HOST", "路由", "根路径", "响应"))
    print("-" * 100)
    with cf.ThreadPoolExecutor(16) as ex:
        for h, c, b, c2 in ex.map(one, hosts):
            print("%-34s %-5s %-5s %s" % (h, c, c2, b))


def cmd_routes(host="http://122.10.20.249:6868"):
    fp = os.path.join(HERE, "routes.json")
    if not os.path.exists(fp):
        print("缺 routes.json")
        return
    routes = json.load(open(fp, encoding="utf-8"))

    def one(r):
        code, body = call(host, r)
        return r, code, body[:100].replace("\n", " ")

    print("目标:", host, "| 路由数:", len(routes))
    buckets = {}
    with cf.ThreadPoolExecutor(12) as ex:
        for r, code, b in ex.map(one, routes):
            buckets.setdefault(b[:40], []).append(r)
    for sig, rs in sorted(buckets.items(), key=lambda kv: -len(kv[1])):
        print("\n[%d 条] %s" % (len(rs), sig))
        for r in rs[:6]:
            print("   ", r)
        if len(rs) > 6:
            print("    ...")


def cmd_trial(host):
    print("在", host, "上试签名 —— 只要出现非『违规请求』的响应就算有戏\n")
    path = "/module/javdb/search"
    ts = str(int(time.time()))
    nonce = "".join(random.choice("0123456789") for _ in range(8))
    sign, headers, suffix = make_sign(path, {"wd": "test"}, ts, nonce)
    print("当前算法算出的 sign:", sign)
    for tag, kwargs in [("带签名", dict(signed=True)), ("不带签名", dict(signed=False))]:
        code, body = call(host, path, {"wd": "test"}, **kwargs)
        print("%-8s → %s %s" % (tag, code, body[:160]))


# ----------------------------------------------------------------------
# 响应解密探针(capi:1 的 data 字段)
# ----------------------------------------------------------------------
def try_decrypt(blob):
    """把 data 字段的 base64 密文拿去试解,打印所有能出可读明文的结果"""
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    except ImportError:
        print("没装 cryptography,跳过")
        return
    ct = base64.b64decode(blob)
    print("密文长度:", len(ct), ct.hex())
    key_srcs = {
        "key_utf8": APP_KEY.encode(),
        "key_bytes": bytes.fromhex(APP_KEY),
        "md5_key_utf8": hashlib.md5(APP_KEY.encode()).hexdigest().encode(),
        "md5_key_raw": hashlib.md5(APP_KEY.encode()).digest(),
        "sha256_key_raw": hashlib.sha256(APP_KEY.encode()).digest(),
    }
    for name, raw in key_srcs.items():
        for klen in (16, 24, 32):
            if len(raw) < klen:
                continue
            k = raw[:klen]
            modes_list = [
                ("ECB", modes.ECB()),
                ("CBC0", modes.CBC(b"\x00" * 16)),
                ("CBCk", modes.CBC(k[:16])),
            ]
            for mname, mode in modes_list:
                try:
                    d = Cipher(algorithms.AES(k), mode).decryptor()
                    pt = d.update(ct) + d.finalize()
                except Exception:
                    continue
                printable = sum(32 <= x < 127 for x in pt)
                if printable >= max(6, len(pt) // 2):
                    print(">>> 命中", name, klen, mname, repr(pt[:60]))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)
    cmd = sys.argv[1]
    if cmd == "hosts":
        cmd_hosts()
    elif cmd == "routes":
        cmd_routes(sys.argv[2] if len(sys.argv) > 2 else "http://122.10.20.249:6868")
    elif cmd == "trial":
        cmd_trial(sys.argv[2] if len(sys.argv) > 2 else "http://122.10.20.249:6868")
    elif cmd == "decrypt":
        try_decrypt(sys.argv[2])
    else:
        print(__doc__)
