#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
flutter_triage.py —— Flutter / 混合壳 App 体检 + 取数面提取(只读,不执行包内任何代码)

用途:
  拿到一个 apk,先判断它是不是 Flutter(Dart AOT)壳、业务面和签名面在哪、
  能不能不啃机器码就拿到接口;并把能直接复用的东西(域名池/路由/头名/疑似密钥)一次刨出来。

为什么要有它:
  这类包 java 层基本空壳,dex 反编译出来啥也没有。人肉 strings + grep 一遍要十几分钟,
  而且容易漏掉"签名在 Dart 快照里"这个致命判据 —— 它决定这条线是几小时还是几天的活。

用法:
  python3 flutter_triage.py app.apk
  python3 flutter_triage.py app.apk --json out.json --dump-dir out/

输出:
  1) 引擎判定(flutter / rn-hermes / webview / native / 加固 / 未知)
  2) 取数面:URL、域名池、路由前缀、模块名、认证头名、疑似密钥
  3) 结论 + 下一步(能不能不啃 asm;要啃的话前置条件是什么)

纪律:
  - 只做 zip 读取 + 二进制字符串扫描,不执行、不安装、不加载包内任何东西。
  - 判不出就是判不出,输出 unknown,不硬猜。
"""
import argparse
import json
import os
import re
import sys
import zipfile
from collections import Counter, OrderedDict

# ---------------------------------------------------------------- 特征表

FLUTTER_MARKERS = ("libapp.so", "libflutter.so", "flutter_assets", "kernel_blob.bin")
RN_MARKERS = ("index.android.bundle", "libhermes.so", "libreactnativejni.so")
WEBVIEW_HINTS = ("assets/www/", "assets/public/", "cordova", "uniapp", "www/index.html")
PACKER_SO = {
    "libjiagu.so": "360加固", "libjiagu_a64.so": "360加固",
    "libDexHelper.so": "梆梆", "libsecexe.so": "梆梆",
    "libexec.so": "爱加密", "libexecmain.so": "爱加密",
    "libmobisec.so": "阿里聚安全", "libnesec.so": "网易易盾",
    "libtup.so": "腾讯乐固", "libshella.so": "腾讯乐固",
}

AUTH_HEADER_RE = re.compile(r"[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+){1,4}")
KEYISH_RE = re.compile(r"^[0-9a-fA-F]{16,64}$")
URL_RE = re.compile(r"https?://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]{4,200}")
DART_SRC_RE = re.compile(r"package:([A-Za-z0-9_]+)/([A-Za-z0-9_./-]{3,120})")
ROUTE_RE = re.compile(r"/(?:module|api|v\d)/[A-Za-z0-9_/{}\-]{2,80}")

# 只认这些前缀的"头名",避免把 CSS 类名/普通单词当认证头
AUTH_PREFIXES = ("x-", "auth", "sign", "token", "api-", "app-", "device-", "client-")

MAX_SCAN_BYTES = 96 * 1024 * 1024   # 单个 so 最多扫 96MB,防超大包卡死
MIN_STR_LEN = 6


def printable_strings(blob: bytes, min_len: int = MIN_STR_LEN):
    """等价于 strings -n:扫可打印 ASCII 串(只读,不反汇编)"""
    out, cur = [], bytearray()
    for b in blob:
        if 32 <= b < 127:
            cur.append(b)
        else:
            if len(cur) >= min_len:
                out.append(cur.decode("ascii", "ignore"))
            cur = bytearray()
    if len(cur) >= min_len:
        out.append(cur.decode("ascii", "ignore"))
    return out


# ---------------------------------------------------------------- 包体体检

def inspect_zip(path):
    info = OrderedDict()
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        info["entries"] = len(names)
        info["size_mb"] = round(sum(i.file_size for i in z.infolist()) / 1048576, 2)
        so_files = [n for n in names if n.endswith(".so")]
        info["so_files"] = so_files
        info["has_dex"] = any(n.endswith(".dex") for n in names)
        info["dex_count"] = sum(1 for n in names if n.endswith(".dex"))
        info["flutter_markers"] = [m for m in FLUTTER_MARKERS if any(m in n for n in names)]
        info["rn_markers"] = [m for m in RN_MARKERS if any(m in n for n in names)]
        info["webview_hints"] = [m for m in WEBVIEW_HINTS if any(m.lower() in n.lower() for n in names)]
        info["packers"] = sorted({PACKER_SO[os.path.basename(n)]
                                  for n in so_files if os.path.basename(n) in PACKER_SO})
        info["abis"] = sorted({n.split("/")[1] for n in so_files if n.startswith("lib/") and "/" in n[4:]})
        info["_names"] = names
    return info


def pick_libapp(names):
    """优先 arm64,其次任意 ABI 的 libapp.so"""
    cands = [n for n in names if os.path.basename(n) == "libapp.so"]
    if not cands:
        return None
    for n in cands:
        if "arm64" in n:
            return n
    return cands[0]


def engine_verdict(info):
    if info["flutter_markers"]:
        return "flutter"
    if info["rn_markers"]:
        return "rn-hermes"
    if info["webview_hints"]:
        return "webview"
    if info["packers"]:
        return "packed"
    if info["so_files"]:
        return "native"
    if info["has_dex"]:
        return "java-only"
    return "unknown"


# ---------------------------------------------------------------- 取数面提取

def mine(strings):
    urls, hosts, routes, mods, auth, keyish, dart_srcs = set(), set(), set(), set(), set(), set(), set()

    for s in strings:
        for m in URL_RE.findall(s):
            urls.add(m)
            host = re.sub(r"^https?://", "", m).split("/")[0].split(":")[0]
            if host and "." in host and not host.endswith((".png", ".jpg", ".svg", ".css", ".js")):
                hosts.add(host)
        for m in ROUTE_RE.findall(s):
            routes.add(m)
        for pkg, rel in DART_SRC_RE.findall(s):
            dart_srcs.add(f"package:{pkg}/{rel}")
            seg = rel.split("/")
            if len(seg) >= 2 and seg[0] == "module":
                mods.add(seg[1])
            elif len(seg) >= 3 and seg[0] == "util":
                pass

        low = s.lower()
        if any(low.startswith(p) for p in AUTH_PREFIXES) or re.search(r"x-[a-z]+-[a-z]+", low):
            if 3 <= len(s) <= 48 and " " not in s and "=" not in s:
                auth.add(s)

        if KEYISH_RE.match(s) and len({c for c in s.lower()}) >= 8:
            keyish.add(s)

    # 头名收敛:去掉明显不是头的(single word / 纯数字 / 版本号)
    auth = {a for a in auth if "-" in a or a.lower() in ("authorization", "token", "sign")}

    return {
        "urls": sorted(urls),
        "hosts": sorted(hosts),
        "routes": sorted(routes),
        "modules": sorted(mods),
        "auth_tokens": sorted(auth),
        "key_candidates": sorted(keyish),
        "dart_sources": sorted(dart_srcs),
    }


def group_hosts(hosts):
    """按注册域聚类,拆出"分发域名池"和"业务域" """
    pools = Counter()
    for h in hosts:
        parts = h.split(".")
        pools[".".join(parts[-2:]) if len(parts) >= 2 else h] += 1
    return dict(pools.most_common())


# ---------------------------------------------------------------- 结论

def conclude(engine, face, info):
    notes, nexts = [], []

    if engine == "flutter":
        notes.append("Flutter(Dart AOT):java 层是空壳,dex 反编译无效,业务逻辑在 "
                     + (info["flutter_markers"][0] if info["flutter_markers"] else "libapp.so"))
        if face["dart_sources"]:
            mods = face["modules"]
            notes.append(f"快照里保留了 Dart 源文件路径 {len(face['dart_sources'])} 条"
                         + (f",可辨识模块 {len(mods)} 个" if mods else ""))
        if face["auth_tokens"] or face["routes"]:
            notes.append("明文里能拿到路由/头名 → **先走静态面**(字符串/对象池),别急着上反汇编")
        nexts.append("静态面拿不到算法时:blutter 反汇编 → 搜签名函数符号 → 翻译成 Python")
        nexts.append("上 blutter 前先做环境预检(见下),不够就别开")
        if info.get("dex_count", 0) and info["dex_count"] <= 2:
            notes.append("dex 数量极少 → 印证 java 层无业务代码,别再在 dex 上耗")
    elif engine == "rn-hermes":
        notes.append("React Native(Hermes):走 hbc-decompiler / hasm,别啃 so")
        nexts.append("hbc-disassembler index.android.bundle out.hasm")
    elif engine == "webview":
        notes.append("WebView / uni-app 壳:业务在前端层,走技法卡 03")
        nexts.append("找 addJavascriptInterface 桥对象 = 前端可调能力清单")
    elif engine == "packed":
        notes.append(f"加固({','.join(info['packers'])}):先脱壳,走技法卡 05")
        nexts.append("Frida spawn 抓启动期解密,或脱壳机")
    elif engine == "native":
        notes.append("原生 so 为主:从 JNI_OnLoad / RegisterNatives 找入口")
    else:
        notes.append("没识别出引擎 → 按未知处理,先补样本再判,别硬猜")

    if face["hosts"]:
        notes.append(f"明文域名/主机 {len(face['hosts'])} 个,注册域 {len(group_hosts(face['hosts']))} 类")
    if face["key_candidates"]:
        notes.append(f"疑似密钥串 {len(face['key_candidates'])} 个(hex 16~64 位)→ 直接进 Cipher/Sign 试")

    nexts.append("拿到明文接口先直接打一发:能出数据就停,别为'看起来复杂'去解算法")
    nexts.append("所有节点对错误请求回同一条报文 → 立刻做零区分度判定,停止穷举")

    return notes, nexts


ENV_HINT = """\
上 blutter(或任何需要本地编译的工具)之前,先量这几个数,不够就别开:
  1) 进程真实可用内存上限(不是机器总内存):看 cgroup 限额
       cat /sys/fs/cgroup/memory.max            # cgroup v2
       cat /sys/fs/cgroup/memory/memory.limit_in_bytes   # v1
  2) 当前可用:free -m 的 available 列
  3) 峰值需求:blutter 会拉 Dart SDK 源码并本地编译反汇编组件,预留 2G 起步,多人并行编译留 8G
  4) 剩余时间预算:编译 + 反汇编 11MB 的 libapp.so,不是一两分钟的事
判据:限额 < 峰值需求 → 直接判定"这条路在当前环境不成立",写进档案 + 给替代方案,
      不要开跑再说"内存不够"——跑一半被打死比不开更亏(用户白等一轮)。
"""


def main():
    ap = argparse.ArgumentParser(description="Flutter / 混合壳 App 体检(只读)")
    ap.add_argument("apk")
    ap.add_argument("--json", help="把结构化结果写到这个文件")
    ap.add_argument("--dump-dir", help="把提取到的路由/域名等落成单独文件")
    ap.add_argument("--max-mb", type=int, default=96, help="单文件扫描上限(MB)")
    args = ap.parse_args()

    global MAX_SCAN_BYTES
    MAX_SCAN_BYTES = args.max_mb * 1048576

    if not os.path.isfile(args.apk):
        print(f"[x] 找不到文件: {args.apk}")
        return 2

    info = inspect_zip(args.apk)
    engine = engine_verdict(info)
    libapp = pick_libapp(info["_names"])

    face = {"urls": [], "hosts": [], "routes": [], "modules": [],
            "auth_tokens": [], "key_candidates": [], "dart_sources": []}

    if libapp:
        with zipfile.ZipFile(args.apk) as z:
            with z.open(libapp) as f:
                blob = f.read(MAX_SCAN_BYTES)
        face = mine(printable_strings(blob))
        info["scanned"] = libapp
        info["scanned_mb"] = round(len(blob) / 1048576, 2)

    notes, nexts = conclude(engine, face, info)

    print("=" * 62)
    print(f"样本   {os.path.basename(args.apk)}  ({info['size_mb']} MB)")
    print(f"引擎   {engine}")
    if info["packers"]:
        print(f"加固   {', '.join(info['packers'])}")
    print(f"dex    {info['dex_count']} 个   so  {len(info['so_files'])} 个   ABI {','.join(info['abis']) or '-'}")
    if info.get("scanned"):
        print(f"扫描   {info['scanned']}  ({info['scanned_mb']} MB)")
    print("=" * 62)

    for n in notes:
        print(f"  · {n}")

    print("\n取数面")
    print(f"  路由       {len(face['routes'])}")
    print(f"  域名/主机  {len(face['hosts'])}")
    print(f"  模块名     {len(face['modules'])}  {', '.join(face['modules'][:12])}"
          + (" …" if len(face["modules"]) > 12 else ""))
    print(f"  认证头名   {', '.join(face['auth_tokens'][:12]) or '-'}")
    print(f"  疑似密钥   {', '.join(face['key_candidates'][:6]) or '-'}")

    if face["hosts"]:
        print("\n注册域聚类")
        for d, c in list(group_hosts(face["hosts"]).items())[:12]:
            print(f"  {d:<28} {c}")

    print("\n下一步")
    for i, n in enumerate(nexts, 1):
        print(f"  {i}. {n}")

    if engine == "flutter":
        print("\n" + ENV_HINT)

    if args.json:
        payload = {
            "sample": os.path.basename(args.apk),
            "engine": engine,
            "info": {k: v for k, v in info.items() if k != "_names"},
            "surface": face,
            "notes": notes,
            "next_steps": nexts,
        }
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        print(f"\n[json] {args.json}")

    if args.dump_dir:
        os.makedirs(args.dump_dir, exist_ok=True)
        for key in ("routes", "hosts", "modules", "auth_tokens", "key_candidates"):
            with open(os.path.join(args.dump_dir, f"{key}.txt"), "w", encoding="utf-8") as f:
                f.write("\n".join(face[key]))
        print(f"[dump] {args.dump_dir}/")

    return 0


if __name__ == "__main__":
    sys.exit(main())
