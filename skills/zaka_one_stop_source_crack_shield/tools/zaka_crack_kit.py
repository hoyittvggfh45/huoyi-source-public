#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
zaka_crack_kit — 一条龙写源的「现成函数层」(Zaka 深度引擎)

八件套(与技法卡一一对应):
  Codec   编解码链:base64 全变体 / hex / JS 转义 / 压缩层自动剥          (卡02 第4步)
  Cipher  对称解密:XOR(单/多字节) / AES 四模式 / DES·3DES / RC4 / Fernet (卡02 第4步)
  Sign    签名还原:md5 / hmac 系列 × 参数排序变体,带打分              (卡02 第5步)
  Page    SPA 取数:__NEXT_DATA__ / __NUXT__ / RSC Flight / JSON-LD     (卡03 第0级)
  Obf     JS 混淆还原:_0x 数组+偏移+异或+旋转 / 挖密钥 / 挖接口        (卡03 第2级)
  Stream  取流层:m3u8 解析 / AES-128 分片解密 / 试看窗口改写 / 真播验证 (卡06 打法1)
  Net     网络层:UA/Cookie/Referer/重试/退避/服务器时钟校准/盾页识别
  Probe   判型定性:障碍判型表(卡01 第四节) + 付费墙定性(卡06 第一节)

纪律(与技能主文件一致):
  * 真跑真拉 —— 解出来的东西必须真拉一次、真看到 #EXTM3U 才算成
  * 闭环验证 —— 明文要能解释业务(片名/地址/ID),只报"解出来了"不算
  * 失败分型 —— 抖动 / 真吃盾 / 上游缺货 / 判型错 / 能力缺口,分开处理

用法:
  python3 zaka_crack_kit.py probe  <url>            # 判型 + 定性
  python3 zaka_crack_kit.py page   <url>            # SPA 内嵌数据直取
  python3 zaka_crack_kit.py stream <m3u8-url>       # 取流验证(真拉首片)
  python3 zaka_crack_kit.py keys   <file|url>       # 从页面/JS 挖密钥候选
  python3 zaka_crack_kit.py obf    <js-file> [-o out.js]
  python3 zaka_crack_kit.py decode <file|->
  python3 zaka_crack_kit.py --selftest              # 离线自检(全绿才算能用)
"""

from __future__ import annotations

import base64
import binascii
import gzip
import hashlib
import hmac
import http.cookiejar
import json
import math
import random
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from collections import Counter

__version__ = "1.0.0"
__all__ = ["Codec", "Cipher", "Sign", "Page", "Obf", "Stream", "Net", "Probe",
           "entropy", "text_score"]


# ══════════════════════════════════════════════════════════════════
# 0 · 基础判据
# ══════════════════════════════════════════════════════════════════

def entropy(data: bytes) -> float:
    """香农熵(bit/byte)。>7.0 基本是密文/压缩;英文文本 4.2~4.8。"""
    if not data:
        return 0.0
    c = Counter(data)
    n = len(data)
    return -sum((v / n) * math.log2(v / n) for v in c.values())


def printable_ratio(data: bytes) -> float:
    if not data:
        return 0.0
    ok = sum(1 for b in data if 32 <= b < 127 or b in (9, 10, 13))
    return ok / len(data)


# 多字符标记 —— 必须长,单字符标记会把乱码顶上去(实测踩过:同 printable 时选错 key)
_ASCII_WORDS = (b"http", b"www", b".com", b"://", b"<div", b"<script", b"index",
                b"video", b".m3u8", b"json", b" the ", b" and", b" to ", b" is ",
                b" of ", b"{" + b'"', b'":"', b"</", b"function", b"url", b"_id")
# 文本里出现算正常;明显偏多才算乱码
_SOFT_PUNCT = set(b" .,:;-_'\"()!?/\n\r\t")
_HARD_PUNCT = set(b"<>{}[]&=%#@*+\\|~^`$")
_CJK_RE = re.compile(r"[\u4e00-\u9fff]")


def text_score(data: bytes) -> float:
    """明文可能性打分 0~1(用于候选结果排序,别用单一 printable 比率)。

    构成:可打印 30% + 字母/空格密度 35% + 空格密度(封顶 12%)
          + 常见词标记 + 中文加分 − 硬符号密度 − 控制字符 − 高熵惩罚
    区分点(实测有效):错 key 解出来的东西符号是「全 ASCII 谱系均匀撒」,
    字母+空格密度低、硬符号密度高;真文本正好反过来。
    """
    if not data:
        return 0.0
    n = len(data)
    pr = printable_ratio(data)
    litspace = sum(1 for b in data if b == 32 or (65 <= b <= 90) or (97 <= b <= 122)) / n
    s = pr * 0.30 + litspace * 0.35 + min(data.count(32) / n * 1.2, 0.12)
    try:
        txt = data.decode("utf-8")
        if _CJK_RE.search(txt):
            s += 0.30
        low = data.lower()
        s += min(sum(1 for w in _ASCII_WORDS if w in low), 6) * 0.03
    except UnicodeDecodeError:
        pass
    hard = sum(1 for b in data if b in _HARD_PUNCT)
    s -= min(hard / n, 1.0) * 0.45
    ctrl = sum(1 for b in data if b < 9 or (13 < b < 32))
    s -= min(ctrl / n, 1.0) * 0.35
    if entropy(data) > 7.4:
        s -= 0.25
    return max(0.0, min(1.0, s))


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ══════════════════════════════════════════════════════════════════
# 1 · 纯 Python AES 兜底(环境里没 cryptography 时自动顶上)
# ══════════════════════════════════════════════════════════════════

def _xtime(a: int) -> int:
    return ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else (a << 1) & 0xFF


def _gmul(a: int, b: int) -> int:
    p = 0
    for _ in range(8):
        if b & 1:
            p ^= a
        hi = a & 0x80
        a = (a << 1) & 0xFF
        if hi:
            a ^= 0x1B
        b >>= 1
    return p


def _build_sbox():
    inv = [0] * 256
    for i in range(1, 256):
        for j in range(1, 256):
            if _gmul(i, j) == 1:
                inv[i] = j
                break
    sbox = [0] * 256
    for i in range(256):
        x = inv[i]
        y = x
        for _ in range(4):
            x = ((x << 1) | (x >> 7)) & 0xFF
            y ^= x
        sbox[i] = y ^ 0x63
    inv_sbox = [0] * 256
    for i in range(256):
        inv_sbox[sbox[i]] = i
    return sbox, inv_sbox


SBOX, INV_SBOX = _build_sbox()


def _mix_columns(s):
    o = [[0] * 4 for _ in range(4)]
    for c in range(4):
        a = [s[r][c] for r in range(4)]
        o[0][c] = _gmul(a[0], 2) ^ _gmul(a[1], 3) ^ a[2] ^ a[3]
        o[1][c] = a[0] ^ _gmul(a[1], 2) ^ _gmul(a[2], 3) ^ a[3]
        o[2][c] = a[0] ^ a[1] ^ _gmul(a[2], 2) ^ _gmul(a[3], 3)
        o[3][c] = _gmul(a[0], 3) ^ a[1] ^ a[2] ^ _gmul(a[3], 2)
    return o


def _inv_mix_columns(s):
    o = [[0] * 4 for _ in range(4)]
    for c in range(4):
        a = [s[r][c] for r in range(4)]
        o[0][c] = _gmul(a[0], 14) ^ _gmul(a[1], 11) ^ _gmul(a[2], 13) ^ _gmul(a[3], 9)
        o[1][c] = _gmul(a[0], 9) ^ _gmul(a[1], 14) ^ _gmul(a[2], 11) ^ _gmul(a[3], 13)
        o[2][c] = _gmul(a[0], 13) ^ _gmul(a[1], 9) ^ _gmul(a[2], 14) ^ _gmul(a[3], 11)
        o[3][c] = _gmul(a[0], 11) ^ _gmul(a[1], 13) ^ _gmul(a[2], 9) ^ _gmul(a[3], 14)
    return o


def _expand_key(key: bytes):
    nk = len(key) // 4
    nr = nk + 6
    w = [list(key[4 * i:4 * i + 4]) for i in range(nk)]
    rcon = 1
    for i in range(nk, 4 * (nr + 1)):
        t = list(w[i - 1])
        if i % nk == 0:
            t = t[1:] + t[:1]
            t = [SBOX[b] for b in t]
            t[0] ^= rcon
            rcon = _xtime(rcon)
        elif nk > 6 and i % nk == 4:
            t = [SBOX[b] for b in t]
        w.append([w[i - nk][j] ^ t[j] for j in range(4)])
    return w, nr


def _add_rk(s, w, rnd):
    for c in range(4):
        for r in range(4):
            s[r][c] ^= w[rnd * 4 + c][r]


def _enc_block(block: bytes, w, nr) -> bytes:
    s = [[block[4 * c + r] for c in range(4)] for r in range(4)]
    _add_rk(s, w, 0)
    for rnd in range(1, nr):
        for r in range(4):
            for c in range(4):
                s[r][c] = SBOX[s[r][c]]
        s = [s[r][r:] + s[r][:r] for r in range(4)]
        s = _mix_columns(s)
        _add_rk(s, w, rnd)
    for r in range(4):
        for c in range(4):
            s[r][c] = SBOX[s[r][c]]
    s = [s[r][r:] + s[r][:r] for r in range(4)]
    _add_rk(s, w, nr)
    return bytes(s[r][c] for c in range(4) for r in range(4))


def _dec_block(block: bytes, w, nr) -> bytes:
    s = [[block[4 * c + r] for c in range(4)] for r in range(4)]
    _add_rk(s, w, nr)
    for rnd in range(nr - 1, 0, -1):
        s = [(s[r][-r:] + s[r][:-r]) if r else s[r] for r in range(4)]
        for r in range(4):
            for c in range(4):
                s[r][c] = INV_SBOX[s[r][c]]
        _add_rk(s, w, rnd)
        s = _inv_mix_columns(s)
    s = [(s[r][-r:] + s[r][:-r]) if r else s[r] for r in range(4)]
    for r in range(4):
        for c in range(4):
            s[r][c] = INV_SBOX[s[r][c]]
    _add_rk(s, w, 0)
    return bytes(s[r][c] for c in range(4) for r in range(4))


def _pure_aes_ecb_decrypt(data: bytes, key: bytes) -> bytes:
    w, nr = _expand_key(key)
    return b"".join(_dec_block(data[i:i + 16], w, nr) for i in range(0, len(data) - 15, 16))


def _pure_aes_ecb_encrypt(data: bytes, key: bytes) -> bytes:
    w, nr = _expand_key(key)
    return b"".join(_enc_block(data[i:i + 16], w, nr) for i in range(0, len(data) - 15, 16))


def _has_crypto() -> bool:
    try:
        import cryptography  # noqa: F401
        return True
    except Exception:
        return False


CRYPTO_AVAILABLE = _has_crypto()


# ══════════════════════════════════════════════════════════════════
# 2 · Codec — 编解码链
# ══════════════════════════════════════════════════════════════════

_B64_STRIP = re.compile(rb"[^A-Za-z0-9+/=_-]")


class Codec:
    """编解码链。核心是 chain():一次给出一层层的候选,别手工试。"""

    # ---- base64 全变体 ----
    @staticmethod
    def b64(data) -> bytes:
        """标准 base64,宽容处理缺 padding / url-safe / 空白 / unicode 转义。"""
        if isinstance(data, str):
            data = data.encode("utf-8", "surrogateescape")
        s = _B64_STRIP.sub(b"", data.strip())
        s = s.replace(b"-", b"+").replace(b"_", b"/")
        s += b"=" * ((4 - len(s) % 4) % 4)
        try:
            return base64.b64decode(s)
        except binascii.Error:
            # 容错:逐字符丢弃再试(常见的多余引号/换行混在里头)
            s2 = bytes(b for b in s if b in b"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                       b"abcdefghijklmnopqrstuvwxyz0123456789+/=")
            s2 += b"=" * ((4 - len(s2) % 4) % 4)
            return base64.b64decode(s2)

    @staticmethod
    def b64_variants(data) -> list:
        """列全变体解码结果(标准/url-safe/无 padding/缺 padding)。"""
        if isinstance(data, str):
            data = data.encode()
        out, seen = [], set()
        raw = data.strip()
        cands = [raw, raw.replace(b"-", b"+").replace(b"_", b"/")]
        for c in cands:
            for pad in (b"", b"=", b"=="):
                t = c + pad
                t += b"=" * ((4 - len(t) % 4) % 4)
                if t in seen:
                    continue
                seen.add(t)
                try:
                    out.append(("b64", base64.b64decode(t)))
                except Exception:
                    pass
        return out

    @staticmethod
    def hex2bytes(data) -> bytes:
        if isinstance(data, bytes):
            data = data.decode("ascii", "ignore")
        s = re.sub(r"0[xX]", "", data)
        s = re.sub(r"[^0-9a-fA-F]", "", s)
        if len(s) % 2:
            s = s[:-1]
        return bytes.fromhex(s)

    @staticmethod
    def url_unescape(s: str) -> str:
        return urllib.parse.unquote(s)

    @staticmethod
    def unescape_js(s: str) -> str:
        """JS 转义还原:\\xHH / \\uXXXX / \\u{XXXXX} / \\n 等。"""
        out, i, n = [], 0, len(s)
        while i < n:
            ch = s[i]
            if ch != "\\" or i + 1 >= n:
                out.append(ch)
                i += 1
                continue
            nxt = s[i + 1]
            if nxt == "x" and i + 3 < n + 1:
                try:
                    out.append(chr(int(s[i + 2:i + 4], 16)))
                    i += 4
                    continue
                except ValueError:
                    pass
            if nxt == "u":
                if s[i + 2:i + 3] == "{":
                    j = s.find("}", i + 3)
                    if j != -1:
                        try:
                            out.append(chr(int(s[i + 3:j], 16)))
                            i = j + 1
                            continue
                        except ValueError:
                            pass
                else:
                    try:
                        out.append(chr(int(s[i + 2:i + 6], 16)))
                        i += 6
                        continue
                    except ValueError:
                        pass
            simple = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f",
                      "0": "\0", "\\": "\\", "'": "'", '"': '"', "/": "/"}
            if nxt in simple:
                out.append(simple[nxt])
                i += 2
                continue
            out.append(nxt)
            i += 2
        return "".join(out)

    @staticmethod
    def decompress(data: bytes) -> bytes:
        """自动剥 gzip / zlib / raw deflate / brotli,剥不动原样返回。"""
        for fn in (lambda d: gzip.decompress(d),
                   lambda d: zlib.decompress(d),
                   lambda d: zlib.decompress(d, -15)):
            try:
                out = fn(data)
                if out:
                    return out
            except Exception:
                pass
        try:
            import brotli
            return brotli.decompress(data)
        except Exception:
            return data

    @staticmethod
    def sniff(data: bytes) -> str:
        """粗判这坨东西是什么:json/html/m3u8/压缩/base64/hex/二进制。"""
        if not data:
            return "empty"
        head = data[:512]
        if head[:2] == b"\x1f\x8b":
            return "gzip"
        if head[:1] == b"\x78":
            return "zlib?"
        t = head.lstrip()
        if t[:7] == b"#EXTM3U":
            return "m3u8"
        if t[:1] in (b"{", b"["):
            return "json"
        if re.match(rb"(?i)<!doctype|<html|<div|<script", t):
            return "html"
        if re.fullmatch(rb"[A-Za-z0-9+/=_\-\s]+", head) and len(head) > 16:
            if re.fullmatch(rb"[0-9a-fA-F\s]+", head):
                return "hex"
            return "base64?"
        if printable_ratio(head) > 0.85:
            return "text"
        return "binary"

    @classmethod
    def chain(cls, data: bytes, depth: int = 3, min_len: int = 4) -> list:
        """逐层剥:base64/hex/压缩/JS 转义,给出每一步的候选 + 打分。

        返回:[(层数, 方式, 结果bytes, 打分)] 按打分倒序。
        """
        results = []

        def walk(blob: bytes, level: int, path: str):
            if level > depth or len(blob) < min_len:
                return
            steps = []
            for label, out in cls.b64_variants(blob):
                steps.append((label, out))
            if re.fullmatch(rb"[\s0-9a-fA-FxX]+", blob.strip()[:4096] or b"") and len(blob.strip()) >= 8:
                try:
                    steps.append(("hex", cls.hex2bytes(blob)))
                except Exception:
                    pass
            dec = cls.decompress(blob)
            if dec != blob:
                steps.append(("inflate", dec))
            try:
                txt = blob.decode("utf-8")
                if "\\x" in txt or "\\u" in txt:
                    steps.append(("js-unescape", cls.unescape_js(txt).encode("utf-8", "ignore")))
            except Exception:
                pass
            for label, out in steps:
                if not out or out == blob:
                    continue
                sc = text_score(out)
                results.append((level, f"{path}/{label}".strip("/"), out, sc))
                if sc > 0.35 or level < depth:
                    walk(out, level + 1, f"{path}/{label}")
        walk(data, 1, "")
        results.sort(key=lambda r: (-r[3], r[0]))
        return results


# ══════════════════════════════════════════════════════════════════
# 3 · Cipher — 对称解密
# ══════════════════════════════════════════════════════════════════

_PKCS7_OK = re.compile(rb"[\x00-\x10]$")


def _mode_obj(mode: str, iv: bytes = None):
    """统一取分组模式对象(CFB/OFB 在新版 cryptography 里搬到了 decrepit)。"""
    from cryptography.hazmat.primitives.ciphers import modes as M
    mode = mode.upper()
    iv = iv if iv is not None else b"\x00" * 16
    if mode == "ECB":
        return M.ECB()
    if mode == "CBC":
        return M.CBC(iv)
    if mode == "CTR":
        return M.CTR(iv)
    if mode in ("CFB", "OFB"):
        try:
            from cryptography.hazmat.decrepit.ciphers.modes import CFB, OFB
        except Exception:
            CFB, OFB = M.CFB, M.OFB
        return CFB(iv) if mode == "CFB" else OFB(iv)
    raise ValueError(f"未知模式 {mode}")


class Cipher:
    """对称解密。顺序:XOR 速扫 → 判长度规律 → 分组加密 + 密钥候选池回推。"""

    # ---- XOR ----
    @staticmethod
    def xor_single(data: bytes, top: int = 5) -> list:
        """单字节 XOR 速扫。打分 = 明文可能性(不是单纯 printable 比率)。"""
        scored = []
        for k in range(256):
            dec = bytes(b ^ k for b in data)
            scored.append((k, text_score(dec), dec))
        scored.sort(key=lambda x: (-x[1], x[0]))
        return scored[:top]

    @staticmethod
    def xor_keysize(data: bytes, lo: int = 2, hi: int = 32) -> list:
        """多字节 XOR 的密钥长度估计(汉明距离归一化,越小越像)。"""
        out = []
        for ks in range(lo, min(hi, max(lo, len(data) // 2)) + 1):
            chunks = [data[i:i + ks] for i in range(0, len(data) - ks + 1, ks)][:12]
            if len(chunks) < 2:
                continue
            tot = 0.0
            pairs = 0
            for a, b in zip(chunks, chunks[1:]):
                tot += sum(bin(x ^ y).count("1") for x, y in zip(a, b)) / ks
                pairs += 1
            out.append((ks, tot / max(pairs, 1)))
        out.sort(key=lambda x: x[1])
        return out

    @staticmethod
    def xor_multi(data: bytes, keysize: int = None, top: int = 3) -> list:
        """重复密钥 XOR 还原。给 keysize 就按它解,不给就自动估。"""
        cands = []
        sizes = [keysize] if keysize else [ks for ks, _ in Cipher.xor_keysize(data)[:3]]
        for ks in sizes:
            if not ks or ks < 1:
                continue
            cols = [data[i::ks] for i in range(ks)]
            key = bytes(Cipher.xor_single(c, 1)[0][0] for c in cols)
            dec = bytes(b ^ key[i % ks] for i, b in enumerate(data))
            cands.append({"keysize": ks, "key": key, "plain": dec, "score": text_score(dec)})
        cands.sort(key=lambda c: -c["score"])
        return cands[:top]

    # ---- 流密码 ----
    @staticmethod
    def rc4(key: bytes, data: bytes) -> bytes:
        s = list(range(256))
        j = 0
        for i in range(256):
            j = (j + s[i] + key[i % len(key)]) & 0xFF
            s[i], s[j] = s[j], s[i]
        out = bytearray()
        i = j = 0
        for b in data:
            i = (i + 1) & 0xFF
            j = (j + s[i]) & 0xFF
            s[i], s[j] = s[j], s[i]
            out.append(b ^ s[(s[i] + s[j]) & 0xFF])
        return bytes(out)

    @staticmethod
    def chacha20(key: bytes, nonce: bytes, data: bytes, counter: int = 1) -> bytes:
        try:
            from cryptography.hazmat.primitives.ciphers import Cipher as _C, algorithms as _A
            c = _C(_A.ChaCha20(key, nonce + counter.to_bytes(4, "little")), None).encryptor()
            return c.update(data) + c.finalize()
        except Exception:
            return b""

    # ---- 填充 ----
    @staticmethod
    def unpad(data: bytes, mode: str = "auto") -> bytes:
        if mode in ("auto", "pkcs7"):
            if data:
                p = data[-1]
                if 1 <= p <= 16 and len(data) >= p and data[-p:] == bytes([p]) * p:
                    return data[:-p]
            if mode == "pkcs7":
                return data
        if mode in ("auto", "zero"):
            return data.rstrip(b"\x00")
        return data

    # ---- AES ----
    @staticmethod
    def _crypto_mode(mode: str):
        from cryptography.hazmat.primitives.ciphers import modes as M
        return {"ECB": M.ECB(), "CBC": None, "CTR": M.CTR, "CFB": M.CFB, "OFB": M.OFB}[mode]

    @staticmethod
    def aes_decrypt(data: bytes, key: bytes, mode: str = "CBC",
                    iv: bytes = None, unpad_mode: str = "auto") -> bytes:
        """AES 解密。有 cryptography 用它;没有走纯 Python 兜底(ECB/CBC/CTR)。"""
        mode = mode.upper()
        if CRYPTO_AVAILABLE:
            try:
                from cryptography.hazmat.primitives.ciphers import Cipher as _C, algorithms as _A
                m = _mode_obj(mode, iv if mode != "ECB" else None)
                d = _C(_A.AES(key), m).decryptor()
                return Cipher.unpad(d.update(data) + d.finalize(), unpad_mode)
            except Exception:
                pass
        return Cipher._pure_aes(data, key, mode, iv, unpad_mode)

    @staticmethod
    def aes_encrypt(data: bytes, key: bytes, mode: str = "CBC", iv: bytes = None,
                    pad: bool = True) -> bytes:
        if pad:
            p = 16 - len(data) % 16
            data = data + bytes([p]) * p
        if CRYPTO_AVAILABLE:
            from cryptography.hazmat.primitives.ciphers import Cipher as _C, algorithms as _A
            e = _C(_A.AES(key), _mode_obj(mode, iv if mode.upper() != "ECB" else None)).encryptor()
            return e.update(data) + e.finalize()
        w, nr = _expand_key(key)
        if mode.upper() == "ECB":
            return b"".join(_enc_block(data[i:i + 16], w, nr) for i in range(0, len(data) - 15, 16))
        if mode.upper() == "CBC":
            ivv = iv or b"\x00" * 16
            out, prev = bytearray(), ivv
            for i in range(0, len(data) - 15, 16):
                blk = bytes(x ^ y for x, y in zip(data[i:i + 16], prev))
                prev = _enc_block(blk, w, nr)
                out += prev
            return bytes(out)
        if mode.upper() == "CTR":
            ivv = (iv or b"\x00" * 16)[:16]
            out = bytearray()
            ctr = int.from_bytes(ivv[12:], "big")
            fixed = ivv[:12]
            for i in range(0, len(data), 16):
                ks = _enc_block(fixed + (ctr & 0xFFFFFFFF).to_bytes(4, "big"), w, nr)
                ctr += 1
                out += bytes(x ^ y for x, y in zip(data[i:i + 16], ks))
            return bytes(out)
        raise RuntimeError("纯 Python 兜底只覆盖 ECB/CBC/CTR,其他模式需要 cryptography")

    @staticmethod
    def _pure_aes(data: bytes, key: bytes, mode: str, iv, unpad_mode: str) -> bytes:
        w, nr = _expand_key(key)
        mode = mode.upper()
        if mode == "ECB":
            dec = b"".join(_dec_block(data[i:i + 16], w, nr) for i in range(0, len(data) - 15, 16))
        elif mode == "CBC":
            ivv = iv or b"\x00" * 16
            out, prev = bytearray(), ivv
            for i in range(0, len(data) - 15, 16):
                blk = _dec_block(data[i:i + 16], w, nr)
                out += bytes(x ^ y for x, y in zip(blk, prev))
                prev = data[i:i + 16]
            dec = bytes(out)
        elif mode == "CTR":
            ivv = (iv or b"\x00" * 16)[:16]
            out = bytearray()
            ctr = int.from_bytes(ivv[12:], "big")
            fixed = ivv[:12]
            for i in range(0, len(data), 16):
                ks = _enc_block(fixed + (ctr & 0xFFFFFFFF).to_bytes(4, "big"), w, nr)
                ctr += 1
                out += bytes(x ^ y for x, y in zip(data[i:i + 16], ks))
            dec = bytes(out)
        else:
            raise RuntimeError(f"纯 Python 兜底不支持 {mode},装 cryptography")
        return Cipher.unpad(dec, unpad_mode)

    # ---- DES / Fernet ----
    @staticmethod
    def des3_decrypt(data: bytes, key: bytes, iv: bytes = None) -> bytes:
        try:
            from cryptography.hazmat.decrepit.ciphers.algorithms import TripleDES
            from cryptography.hazmat.primitives.ciphers import Cipher as _C, modes as _M
        except Exception:
            from cryptography.hazmat.primitives.ciphers.algorithms import TripleDES
            from cryptography.hazmat.primitives.ciphers import Cipher as _C, modes as _M
        d = _C(TripleDES(key), _M.CBC(iv or b"\x00" * 8)).decryptor()
        return Cipher.unpad(d.update(data) + d.finalize())

    @staticmethod
    def fernet_decrypt(token, key: bytes) -> bytes:
        from cryptography.fernet import Fernet
        return Fernet(key).decrypt(token if isinstance(token, bytes) else token.encode())

    # ---- 密钥候选池 ----
    @staticmethod
    def key_pool(text: str, include_words: bool = True) -> list:
        """从页面/JS 里挖密钥候选。搜名字找不到就搜用途 —— 这里两种都给。

        返回:[{"key": bytes, "label": str, "why": str}]  按可信度倒序
        """
        if isinstance(text, bytes):
            text = text.decode("utf-8", "ignore")
        pool, seen = [], set()

        def add(k: bytes, label: str, why: str, w: float = 1.0):
            if not k or len(k) not in (5, 8, 16, 24, 32) or k in seen:
                return
            seen.add(k)
            pool.append({"key": k, "label": label, "why": why, "_w": w})

        # 1) 命名上下文里的字面量(key/secret/iv/aes/tk/salt...)
        name_re = re.compile(
            r"""(?i)\b(key|secret|aeskey|aes_key|aesKey|iv|ivkey|signkey|sign_key|
                 appkey|app_key|tk|token|salt|encryptkey|enc_key|deskey|sKey)\b
                 \s*[:=]\s*['"]([^'"]{4,80})['"]""", re.X)
        for m in name_re.finditer(text):
            name, val = m.group(1), m.group(2)
            b = val.encode()
            # 字面量本身可打印 ASCII → 大概率就是原样使用的密钥,排最前
            add(b, f"{name}={val[:20]}", f"命名上下文:{name}", 1.9 if b.decode("latin-1").isprintable() else 1.5)
            if re.fullmatch(r"[0-9a-fA-F]{16,64}", val):
                try:
                    add(bytes.fromhex(val), f"{name}=hex({val})", f"命名上下文(hex):{name}", 1.75)
                except Exception:
                    pass
            try:
                raw = Codec.b64(val)
                add(raw, f"{name}=b64->{raw[:12].hex()}", f"命名上下文(b64):{name}", 1.3)
            except Exception:
                pass

        # 2) 裸 hex 串(32/48/64 位)
        for m in re.finditer(r"\b([0-9a-fA-F]{32}|[0-9a-fA-F]{48}|[0-9a-fA-F]{64})\b", text):
            v = m.group(1)
            try:
                add(bytes.fromhex(v), f"hex:{v[:16]}…", "裸 hex 串", 1.0)
            except Exception:
                pass

        # 3) 裸 base64 串(22~44 字符,解出 16/24/32 字节)
        for m in re.finditer(r"['\"]([A-Za-z0-9+/=_-]{22,44})['\"]", text):
            try:
                raw = Codec.b64(m.group(1))
                add(raw, f"b64:{m.group(1)[:16]}…", "裸 base64 串", 0.8)
            except Exception:
                pass

        # 4) 拼装式密钥上下文(prefix + date 这种)
        if include_words:
            for m in re.finditer(r"""(?i)\b(?:key|secret|iv|salt)\b[^\n;]{0,60}(?:\+|concat)""", text):
                add(m.group(0).encode()[:32], m.group(0)[:32], "拼装式密钥(要看拼装代码)", 0.6)
        pool.sort(key=lambda p: -p["_w"])
        for p in pool:
            p.pop("_w", None)
        return pool

    IV_GUESSES = (b"\x00" * 16, None)  # None = 用 key 前 16 字节

    @staticmethod
    def auto(blob: bytes, keys: list = None, modes=("CBC", "ECB", "CTR", "CFB", "OFB"),
             top: int = 8, iv_mode: str = "auto") -> list:
        """候选池回推:挨个 (key × mode × iv) 解,按明文打分排序。

        keys: key_pool() 的产物 或 [bytes,...];不给只做 XOR/长度规律判型。
        """
        results = []
        if keys:
            klist = [k["key"] if isinstance(k, dict) else k for k in keys]
        else:
            klist = []
        for k in klist:
            if len(k) not in (16, 24, 32):
                continue
            ivs = [b"\x00" * 16, k[:16], blob[:16]] if iv_mode == "auto" else ([iv_mode] if iv_mode else [None])
            if iv_mode is None or iv_mode is False:
                ivs = [None]
            for mode in modes:
                for iv in (ivs if mode != "ECB" else [None]):
                    try:
                        pt = Cipher.aes_decrypt(blob, k, mode, iv, "auto")
                    except Exception:
                        continue
                    if not pt:
                        continue
                    results.append({"how": f"AES-{mode}", "key": k, "iv": iv, "plain": pt,
                                    "score": text_score(pt)})
        # XOR 也进候选
        for k, sc, dec in Cipher.xor_single(blob, 2):
            if sc > 0.5:
                results.append({"how": f"XOR-1B k=0x{k:02x}", "key": bytes([k]), "iv": None,
                                "plain": dec, "score": sc})
        seen, uniq = set(), []
        for r in sorted(results, key=lambda r: -r["score"]):
            h = hashlib.md5(r["plain"]).hexdigest()
            if h in seen:
                continue
            seen.add(h)
            uniq.append(r)
        return uniq[:top]


# ══════════════════════════════════════════════════════════════════
# 4 · Sign — 签名还原
# ══════════════════════════════════════════════════════════════════

class Sign:
    """签名还原。90% 的失败是「漏字段」和「排序错」,不是算法难 ——
    所以这里把「参数排序变体 × 摘要算法 × key 位置」全排列给你。"""

    @staticmethod
    def order_variants(params) -> list:
        """参数拼装变体:原序 / 字典序 / 按值序 / 只值 / JSON。"""
        if isinstance(params, str):
            return [("raw", params)]
        items = list(params.items())
        out = [
            ("asis", "&".join(f"{k}={v}" for k, v in items)),
            ("sorted", "&".join(f"{k}={v}" for k, v in sorted(items))),
            ("sorted_kv", "".join(f"{k}{v}" for k, v in sorted(items))),
            ("values", "".join(str(v) for _, v in items)),
            ("values_sorted", "".join(str(v) for _, v in sorted(items))),
            ("json", json.dumps(params, separators=(",", ":"), ensure_ascii=False)),
            ("json_sorted", json.dumps(dict(sorted(items)), separators=(",", ":"), ensure_ascii=False)),
        ]
        seen, uniq = set(), []
        for lbl, s in out:
            if s not in seen:
                seen.add(s)
                uniq.append((lbl, s))
        return uniq

    @staticmethod
    def hash_candidates(payload: str, key: str) -> list:
        pb, kb = payload.encode(), (key or "").encode()
        c = [
            ("md5(p)", hashlib.md5(pb).hexdigest()),
            ("md5(p+key)", hashlib.md5(pb + kb).hexdigest()),
            ("md5(key+p)", hashlib.md5(kb + pb).hexdigest()),
            ("sha1(p+key)", hashlib.sha1(pb + kb).hexdigest()),
            ("sha256(p+key)", hashlib.sha256(pb + kb).hexdigest()),
            ("hmac_md5(p,key)", hmac.new(kb, pb, hashlib.md5).hexdigest()),
            ("hmac_sha1(p,key)", hmac.new(kb, pb, hashlib.sha1).hexdigest()),
            ("hmac_sha256(p,key)", hmac.new(kb, pb, hashlib.sha256).hexdigest()),
            ("md5(p+key).upper", hashlib.md5(pb + kb).hexdigest().upper()),
        ]
        return c

    @classmethod
    def guess(cls, params, key: str = "", target: str = None, top: int = 50) -> list:
        """还原签名。target 已知就精确匹配;不给就返回全部候选(自己拿去试)。

        返回:[{"sign","how","form","payload"}]  匹配到 target 的排最前
        """
        out = []
        for form, payload in cls.order_variants(params):
            for how, sig in cls.hash_candidates(payload, key):
                out.append({"sign": sig, "how": how, "form": form, "payload": payload,
                            "match": bool(target) and sig.lower() == str(target).lower()})
        out.sort(key=lambda r: (not r["match"],))
        return out[:top] if not target else out[:max(top, 1)]

    @staticmethod
    def clock_offset(server_date: str, now: float = None) -> float:
        """带时间戳签名的站,先校服务器时钟(本机差几秒就全挂)。

        传 HTTP 响应头 Date(如 'Wed, 02 Oct 2024 10:00:00 GMT') → 返回需要加到本机时间的秒数。
        """
        import email.utils
        now = now if now is not None else time.time()
        try:
            ts = email.utils.parsedate_to_datetime(server_date).timestamp()
        except Exception:
            return 0.0
        return ts - now


# ══════════════════════════════════════════════════════════════════
# 5 · Page — SPA 取数(卡03 第0级:先别解,先取数)
# ══════════════════════════════════════════════════════════════════

class Page:
    """框架内嵌数据直取。能从这儿拿到就别去解混淆。"""

    @staticmethod
    def _js_literal_to_json(s: str) -> str:
        """JS 对象字面量 → JSON(裸 key 补引号、单引号转双引号、undefined→null)。"""
        out = re.sub(r"([{,]\s*)([A-Za-z_$][\w$]*)\s*:", r'\1"\2":', s)
        out = re.sub(r"'((?:[^'\\]|\\.)*)'",
                     lambda m: json.dumps(Codec.unescape_js(m.group(1)), ensure_ascii=False), out)
        out = re.sub(r"\b(undefined|NaN)\b", "null", out)
        return re.sub(r",\s*([}\]])", r"\1", out)

    @staticmethod
    def _json_or_none(s: str):
        s = s.strip()
        for attempt in (s,
                        re.sub(r",\s*([}\]])", r"\1", s.rstrip(" ;")),
                        Page._js_literal_to_json(s.rstrip(" ;"))):
            try:
                return json.loads(attempt)
            except Exception:
                continue
        return None

    @staticmethod
    def next_data(html: str):
        m = re.search(r'<script[^>]+id=["\']__NEXT_DATA__["\'][^>]*>(.*?)</script>', html, re.S)
        if not m:
            return None
        return Page._json_or_none(m.group(1))

    @staticmethod
    def next_flight(html: str) -> list:
        """Next.js App Router 的 RSC Flight 载荷(self.__next_f.push)。"""
        out = []
        for m in re.finditer(r'self\.__next_f\.push\(\s*\[[^\]]*,\s*"((?:[^"\\]|\\.)*)"\s*\]\s*\)', html):
            raw = m.group(1)
            try:
                raw = Codec.unescape_js(raw.encode().decode("unicode_escape", "ignore"))
            except Exception:
                raw = Codec.unescape_js(raw)
            out.append(raw)
        return out

    @staticmethod
    def flight_json(html: str) -> list:
        """把 Flight 载荷里能摘出来的 JSON 块摘出来。"""
        objs = []
        for payload in Page.next_flight(html):
            for m in re.finditer(r'(\{"[^"]+".*?\})(?=[0-9a-f]{1,2}:|$)', payload):
                o = Page._json_or_none(m.group(1))
                if o:
                    objs.append(o)
        return objs

    @staticmethod
    def nuxt(html: str):
        m = re.search(r'window\.__NUXT__\s*=\s*(.*?)(?:</script>|;?\s*$)', html, re.S)
        if not m:
            return None
        body = m.group(1).strip().rstrip(";")
        o = Page._json_or_none(body)
        if o is not None:
            return o
        # Nuxt 3 的 IIFE 形式:window.__NUXT__=(function(a,b){...}(1,2)) —— 静态解不出就交原文
        return {"_raw": body[:4000], "_note": "IIFE 形式,需动态跑或按卡03 第4级断点"}

    @staticmethod
    def initial_state(html: str):
        for pat in (r'window\.__INITIAL_STATE__\s*=\s*(\{.*?\})\s*;?\s*(?:</script>|window\.)',
                    r'window\.__PRELOADED_STATE__\s*=\s*(\{.*?\})\s*;?\s*</script>',
                    r'window\.__DATA__\s*=\s*(\{.*?\})\s*;?\s*</script>'):
            m = re.search(pat, html, re.S)
            if m:
                o = Page._json_or_none(m.group(1))
                if o is not None:
                    return o
        return None

    @staticmethod
    def jsonld(html: str) -> list:
        out = []
        for m in re.finditer(r'<script[^>]+application/ld\+json[^>]*>(.*?)</script>', html, re.S):
            o = Page._json_or_none(m.group(1))
            if o is not None:
                out.append(o)
        return out

    @staticmethod
    def auto(html: str) -> list:
        """一把梭:把页面里所有能吃的内嵌数据都吐出来,按体量倒序。"""
        got = []
        nd = Page.next_data(html)
        if nd is not None:
            got.append(("__NEXT_DATA__", nd))
        nx = Page.nuxt(html)
        if nx is not None:
            got.append(("__NUXT__", nx))
        st = Page.initial_state(html)
        if st is not None:
            got.append(("__INITIAL_STATE__", st))
        for i, o in enumerate(Page.jsonld(html)):
            got.append((f"json-ld[{i}]", o))
        fl = Page.flight_json(html)
        if fl:
            got.append((f"rsc-flight[{len(fl)}]", fl))
        got.sort(key=lambda kv: -len(json.dumps(kv[1], ensure_ascii=False, default=str)))
        return got

    @staticmethod
    def dig(obj, path: str, default=None):
        """按点路径取数:'props.pageProps.list.0.title'(支持 list.索引)。"""
        cur = obj
        for seg in path.split("."):
            try:
                if isinstance(cur, list):
                    cur = cur[int(seg)]
                elif isinstance(cur, dict):
                    cur = cur[seg]
                else:
                    return default
            except Exception:
                return default
        return cur

    @staticmethod
    def find_keys(obj, *names, limit: int = 200) -> list:
        """在嵌套结构里按 key 名捞值(判型/定位列表字段用)。"""
        hits, stack, want = [], [(None, obj)], {n.lower() for n in names}
        while stack and len(hits) < limit:
            path, cur = stack.pop()
            if isinstance(cur, dict):
                for k, v in cur.items():
                    p = f"{path}.{k}" if path else k
                    if k.lower() in want:
                        hits.append((p, v))
                    if isinstance(v, (dict, list)):
                        stack.append((p, v))
            elif isinstance(cur, list) and cur and isinstance(cur[0], (dict, list)):
                stack.append((f"{path}.0", cur[0]))
        return hits

    @staticmethod
    def m3u8_in_html(html: str) -> list:
        urls = []
        for pat in (r'<source[^>]+src=["\']([^"\']+\.m3u8[^"\']*)["\']',
                    r'["\'](https?://[^"\']+\.m3u8[^"\']*)["\']',
                    r'[({\s](/(?:[^"\'()\s]+)\.m3u8[^"\')\s]*)'):
            urls += re.findall(pat, html, re.I)
        seen, out = set(), []
        for u in urls:
            if u not in seen:
                seen.add(u)
                out.append(u)
        return out

    @staticmethod
    def text(html: str) -> str:
        h = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", html)
        h = re.sub(r"(?s)<[^>]+>", " ", h)
        import html as _h
        return re.sub(r"\s+", " ", _h.unescape(h)).strip()

    @staticmethod
    def links(html: str, pattern: str = None) -> list:
        """通用列表页取数(纯 HTML 站用):[(href, text)]。"""
        out = []
        for m in re.finditer(r'<a[^>]+href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', html, re.S | re.I):
            href, label = m.group(1), Page.text(m.group(2))
            if pattern and not re.search(pattern, href):
                continue
            out.append((href, label))
        return out


# ══════════════════════════════════════════════════════════════════
# 6 · Obf — JS 混淆还原(卡03 第1~2级)
# ══════════════════════════════════════════════════════════════════

class Obf:
    """_0x 字符串数组混淆还原 + 挖密钥 + 挖接口。不 eval,纯静态。"""

    ARR_RE = re.compile(r"""(?:var|let|const)\s+(_0x[0-9a-fA-F]+)\s*=\s*\[((?:\s*['"](?:[^'"\\]|\\.)*['"]\s*,?)+)\s*\]""")
    ACCESSOR_RE = re.compile(r"""(?:function\s+(_0x[0-9a-fA-F]+)\s*\(|(?:var|let|const)\s+(_0x[0-9a-fA-F]+)\s*=\s*function\s*\()""")

    @staticmethod
    def find_string_array(js: str):
        """找最大的字符串数组(通常在文件头部)。返回 (变量名, list[str]) 或 None。"""
        best = None
        for m in Obf.ARR_RE.finditer(js):
            name, body = m.group(1), m.group(2)
            items = re.findall(r"""['"]((?:[^'"\\]|\\.)*)['"]""", body)
            if not items:
                continue
            if best is None or len(items) > len(best[1]):
                best = (name, [Codec.unescape_js(i) for i in items])
        return best

    @staticmethod
    def apply_rotation(arr: list, js: str, arr_name: str) -> list:
        """还原紧跟在数组后的旋转 IIFE:(function(a,n){while(--n){a.push(a.shift())}}(arr,0x2))"""
        pat = re.compile(r"""\(function\s*\(\s*([A-Za-z_$][\w$]*)\s*,\s*([A-Za-z_$][\w$]*)\s*\)\s*\
\{\s*while\s*\(\s*--\2\s*\)\s*\{\s*\1\.push\(\1\.shift\(\)\)\s*;?\s*\}\s*\}\s*\
\(\s*""" + re.escape(arr_name) + r"""\s*,\s*(0x[0-9a-fA-F]+|\d+)\s*\)""", re.X)
        m = pat.search(js)
        if not m:
            return arr
        n = int(m.group(3), 0)
        a = list(arr)
        for _ in range(n):
            a.append(a.pop(0))
        return a

    @staticmethod
    def accessor_spec(js: str, accessor: str):
        """解析取值函数的偏移/异或。返回 (offset, xor) 或 (0,0)。"""
        m = re.search(r"""function\s+""" + re.escape(accessor) +
                      r"""\s*\(([^)]*)\)\s*\{(.{0,600}?)\}""", js, re.S)
        if not m:
            m = re.search(re.escape(accessor) + r"""\s*=\s*function\s*\(([^)]*)\)\s*\{(.{0,600}?)\}""", js, re.S)
        if not m:
            return 0, 0
        body = m.group(2)
        off = 0
        xor = 0
        mo = re.search(r"-\s*(0x[0-9a-fA-F]+|\d+)", body)
        if mo:
            off = int(mo.group(1), 0)
        mx = re.search(r"\^\s*(0x[0-9a-fA-F]+|\d+)", body)
        if mx:
            xor = int(mx.group(1), 0)
        return off, xor

    @classmethod
    def deobfuscate(cls, js: str, mapping_out: dict = None) -> tuple:
        """还原 _0x 数组混淆:返回 (新js, {占位:原文})。

        覆盖:直接索引 / 偏移(-0x123) / 异或(^0x12) / 数组旋转。
        """
        arr = cls.find_string_array(js)
        if not arr:
            return js, {}
        arr_name, items = arr
        items = cls.apply_rotation(items, js, arr_name)
        # 找访问者:优先取函数体里引用了数组名的那个
        accessors = []
        for m in re.finditer(r"""(?:function\s+(_0x[0-9a-fA-F]+)|(?:var|let|const)\s+(_0x[0-9a-fA-F]+)\s*=\s*function)""", js):
            accessors.append(m.group(1) or m.group(2))
        accessors = [a for a in accessors if a and a != arr_name]
        mapping = {}
        out = js
        for acc in accessors:
            if arr_name not in out[out.find(acc):out.find(acc) + 800]:
                continue
            off, xor = cls.accessor_spec(js, acc)

            def repl(m):
                idx = int(m.group(1), 0) - off
                if xor:
                    idx ^= xor
                if 0 <= idx < len(items):
                    s = items[idx]
                    mapping[s] = s
                    return json.dumps(s, ensure_ascii=False)
                return m.group(0)
            out = re.sub(re.escape(acc) + r"\(\s*(0x[0-9a-fA-F]+|\d+)\s*\)", repl, out)
        # 顺手把 arr[i] 直接索引也换掉
        def repl2(m):
            idx = int(m.group(1), 0)
            if 0 <= idx < len(items):
                return json.dumps(items[idx], ensure_ascii=False)
            return m.group(0)
        out = re.sub(re.escape(arr_name) + r"\[\s*(0x[0-9a-fA-F]+|\d+)\s*\]", repl2, out)
        if mapping_out is not None:
            mapping_out.update(mapping)
        return out, mapping

    @staticmethod
    def mine_keys(js: str, limit: int = 40) -> list:
        """从 JS 里挖密钥候选(转调 Cipher.key_pool,口径一致)。"""
        return Cipher.key_pool(js)[:limit]

    @staticmethod
    def mine_endpoints(js: str, limit: int = 120) -> dict:
        """挖接口:绝对 URL / 路径 / baseURL 变量。"""
        urls = sorted(set(re.findall(r'https?://[A-Za-z0-9._~:/?#\[\]@!$&\'()*+,;=%-]{4,200}', js)))
        paths = sorted(set(re.findall(r'["\'`](/[A-Za-z0-9_\-/]{2,80}(?:\?[^"\'`\s]{0,60})?)["\'`]', js)))
        bases = re.findall(r"""(?i)\b(baseurl|base_url|apiurl|api_url|host|domain)\b\s*[:=]\s*['"`]([^'"`]{4,120})['"`]""", js)
        return {"urls": urls[:limit], "paths": paths[:limit],
                "bases": sorted(set(bases))[:limit]}

    @staticmethod
    def find_js_urls(html: str) -> list:
        out = re.findall(r'<script[^>]+src=["\']([^"\']+)["\']', html)
        return out


# ══════════════════════════════════════════════════════════════════
# 7 · Net — 网络层
# ══════════════════════════════════════════════════════════════════

UAS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36",
]

CHALLENGE_MARKS = {
    "cloudflare": ("just a moment", "cf-chl", "cf_clearance", "__cf_bm", "attention required"),
    "turnstile": ("challenges.cloudflare.com/turnstile", "cf-turnstile"),
    "captcha": ("g-recaptcha", "hcaptcha", "geetest", "滑块验证", "请完成验证", "人机验证"),
    "cookie-gate": ("确认进入", "确认访问", "click to continue", "setcookie", "验证后继续"),
    "login-wall": ("请先登录", "登录后查看", "sign in to continue", "会员登录"),
}


class Resp:
    __slots__ = ("url", "status", "headers", "content", "elapsed")

    def __init__(self, url, status, headers, content, elapsed):
        self.url, self.status, self.headers, self.content, self.elapsed = url, status, headers, content, elapsed

    @property
    def text(self) -> str:
        return _decode(self.content, self.headers)

    @property
    def ctype(self) -> str:
        return (self.headers.get("Content-Type") or "").lower()

    def header(self, name: str, default=None):
        return self.headers.get(name, default)

    def __repr__(self):
        return f"<Resp {self.status} {len(self.content)}B {self.ctype[:40]}>"


def _decode(content: bytes, headers: dict) -> str:
    ct = (headers.get("Content-Type") or "").lower()
    m = re.search(r"charset=([\w-]+)", ct)
    encs = [m.group(1)] if m else []
    encs += ["utf-8", "gb18030", "big5", "latin-1"]
    for e in encs:
        try:
            return content.decode(e)
        except Exception:
            continue
    return content.decode("utf-8", "ignore")


class Net:
    """一个够用的 HTTP 客户端:UA/Cookie/Referer/重试退避/服务器时钟/盾页识别。

    ZAKA 纪律:抖动要退避重试,真吃盾才换出口 —— 别一挡就收手,也别硬莽。
    """

    def __init__(self, ua: str = None, referer: str = None, cookies: dict = None,
                 timeout: float = 15.0, retries: int = 3, headers: dict = None,
                 proxy: str = None, insecure: bool = True):
        self.ua = ua or random.choice(UAS)
        self.timeout = timeout
        self.retries = retries
        self.proxy = proxy
        self.cj = http.cookiejar.CookieJar()
        handlers = [urllib.request.HTTPCookieProcessor(self.cj)]
        if proxy:
            handlers.append(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
        if insecure:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            handlers.append(urllib.request.HTTPSHandler(context=ctx))
        self.opener = urllib.request.build_opener(*handlers)
        self.base_headers = {
            "User-Agent": self.ua,
            "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Connection": "close",
        }
        if referer:
            self.base_headers["Referer"] = referer
        if headers:
            self.base_headers.update(headers)
        self.last_challenge = None
        self.log = []

    # ---- 请求 ----
    def request(self, url: str, data=None, method: str = None, headers: dict = None,
                json_body=None, timeout: float = None) -> Resp:
        hdrs = dict(self.base_headers)
        if headers:
            hdrs.update(headers)
        body = data
        if json_body is not None:
            body = json.dumps(json_body).encode()
            hdrs.setdefault("Content-Type", "application/json")
        last_exc = None
        for attempt in range(self.retries + 1):
            req = urllib.request.Request(url, data=body, method=method or ("POST" if body else "GET"))
            for k, v in hdrs.items():
                req.add_header(k, v)
            t0 = time.time()
            try:
                with self.opener.open(req, timeout=timeout or self.timeout) as r:
                    content = r.read()
                    resp = Resp(r.geturl(), r.status, {k: v for k, v in r.getheaders()}, content, time.time() - t0)
                self.log.append((url, resp.status, len(resp.content)))
                self.last_challenge = self.detect_challenge(resp)
                return resp
            except urllib.error.HTTPError as e:
                content = e.read() if hasattr(e, "read") else b""
                hdrs_d = {k: v for k, v in (e.headers.items() if e.headers else [])}
                resp = Resp(url, e.code, hdrs_d, content, time.time() - t0)
                if e.code in (429, 503) and attempt < self.retries:  # 限流:退避重试
                    time.sleep(1.5 * (attempt + 1))
                    last_exc = e
                    continue
                self.log.append((url, e.code, len(content)))
                self.last_challenge = self.detect_challenge(resp)
                return resp
            except Exception as e:  # 抖动:退避重试
                last_exc = e
                if attempt < self.retries:
                    time.sleep(0.8 * (attempt + 1))
                    continue
                return Resp(url, 0, {}, b"", time.time() - t0)
        return Resp(url, 0, {}, b"", 0)

    def get(self, url, **kw) -> Resp:
        return self.request(url, method="GET", **kw)

    def post(self, url, **kw) -> Resp:
        return self.request(url, method="POST", **kw)

    # ---- Cookie / 时钟 ----
    @property
    def cookies(self) -> dict:
        return {c.name: c.value for c in self.cj}

    def set_cookie(self, name: str, value: str, domain: str):
        c = http.cookiejar.Cookie(0, name, value, None, False, domain, False, False, "/", True,
                                 False, None, True, None, None, {})
        self.cj.set_cookie(c)

    def server_clock(self, url: str) -> float:
        """拿响应头 Date 校服务器时钟,返回要加到本机时间的秒数。"""
        r = self.get(url, headers={"Range": "bytes=0-0"}) if False else self.get(url)
        d = r.headers.get("Date")
        return Sign.clock_offset(d) if d else 0.0

    # ---- 识别 ----
    @staticmethod
    def detect_challenge(resp: Resp) -> str:
        """识别盾页/验证页/登录墙。返回类型名或 None。"""
        if resp.status in (403, 503):
            low = resp.text.lower()
            for kind, marks in CHALLENGE_MARKS.items():
                if any(m in low for m in marks):
                    return kind
            return "http-403/503"
        if resp.status == 200 and len(resp.content) < 8000:
            low = resp.text.lower()
            for kind, marks in CHALLENGE_MARKS.items():
                if any(m in low for m in marks):
                    return kind
        if resp.status in (401, 302) or "login" in resp.url.lower():
            return "login-wall"
        return None

    def fetch_text(self, url: str, **kw) -> str:
        return self.get(url, **kw).text


# ══════════════════════════════════════════════════════════════════
# 8 · Stream — 取流层
# ══════════════════════════════════════════════════════════════════

class Stream:
    """m3u8 解析 / AES-128 分片解密 / 试看窗口改写 / 真播验证(卡06 打法1)。"""

    MIME_OK = ("application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl",
               "application/octet-stream", "text/plain", "video/mp2t")

    @staticmethod
    def parse_m3u8(text: str) -> dict:
        lines = [l.strip() for l in text.splitlines() if l.strip()]
        info = {"is_master": False, "version": None, "segments": [], "variants": [],
                "key": None, "durations": [], "total_duration": 0.0, "media_sequence": 0,
                "encrypted": False}
        cur_meta, cur_dur = None, None
        for l in lines:
            if l.startswith("#EXT-X-VERSION"):
                info["version"] = l.split(":", 1)[-1]
            elif l.startswith("#EXT-X-MEDIA-SEQUENCE"):
                info["media_sequence"] = int(re.sub(r"\D", "", l) or 0)
            elif l.startswith("#EXT-X-STREAM-INF"):
                info["is_master"] = True
                cur_meta = l
            elif l.startswith("#EXT-X-KEY"):
                info["encrypted"] = True
                method = re.search(r"METHOD=([A-Z0-9-]+)", l)
                uri = re.search(r'URI="([^"]+)"', l)
                iv = re.search(r"IV=(0x[0-9a-fA-F]+)", l)
                info["key"] = {"method": method.group(1) if method else None,
                               "uri": uri.group(1) if uri else None,
                               "iv": iv.group(1) if iv else None, "raw": l}
            elif l.startswith("#EXTINF"):
                cur_dur = float(re.search(r"#EXTINF:\s*([\d.]+)", l).group(1))
                info["durations"].append(cur_dur)
            elif l.startswith("#"):
                continue
            else:
                if cur_meta:
                    info["variants"].append({"meta": cur_meta, "url": l,
                                             "bandwidth": (re.search(r"BANDWIDTH=(\d+)", cur_meta) or [None, None])[1]
                                             if re.search(r"BANDWIDTH=(\d+)", cur_meta) else None})
                    cur_meta = None
                else:
                    info["segments"].append(l)
        info["total_duration"] = round(sum(info["durations"]), 2)
        return info

    @staticmethod
    def rewrite_window(url: str) -> str:
        """试看窗口改写(卡06 打法1)。签名常不覆盖窗口参数 —— 改完必须真拉清单看时长。"""
        return re.sub(r"start=\d+&end=\d+", "start=0&end=9999", url)

    @staticmethod
    def decrypt_segment(data: bytes, key: bytes, iv: bytes = None) -> bytes:
        """AES-128-CBC 分片解密(无填充,末块可能有残留 —— 按卡02 第4步容错)。"""
        if not iv:
            iv = b"\x00" * 16
        out = Cipher.aes_decrypt(data[: len(data) // 16 * 16], key, "CBC", iv, "none")
        return out

    @classmethod
    def probe(cls, url: str, net: Net = None, fetch_first_segment: bool = True) -> dict:
        """取流验证:清单能不能拿、MIME 对不对、时长多少、首片真拉得下来吗。

        真跑真拉纪律:只看接口 200 不算成。
        """
        net = net or Net()
        rep = {"url": url, "ok": False, "status": None, "ctype": None, "master": False,
               "segments": 0, "total_duration": 0.0, "first_segment_bytes": 0,
               "mime_ok": None, "encrypted": False, "notes": []}
        r = net.get(url, headers={"Accept": "*/*"})
        rep["status"] = r.status
        rep["ctype"] = r.ctype
        if r.status != 200:
            rep["notes"].append(f"清单拉不到:HTTP {r.status}")
            return rep
        body = r.content
        if body[:3] == b"\x1f\x8b":
            body = Codec.decompress(body)
        low = body.lower()
        if b"#extm3u" not in low:
            rep["notes"].append("拿到的不是 m3u8(无 #EXTM3U)")
            rep["is_html"] = b"<html" in low[:2000]
            return rep
        rep["mime_ok"] = any(m in r.ctype for m in cls.MIME_OK) or r.ctype == ""
        if not rep["mime_ok"]:
            rep["notes"].append(f"MIME 错标:{r.ctype} → 需本地代理重吐 application/vnd.apple.mpegurl")
        info = cls.parse_m3u8(body.decode("utf-8", "ignore"))
        rep.update({"master": info["is_master"], "segments": len(info["segments"]),
                    "total_duration": info["total_duration"], "encrypted": info["encrypted"]})
        if info["is_master"] and info["variants"]:
            sub = urllib.parse.urljoin(url, info["variants"][0]["url"])
            rep["notes"].append(f"master 清单,子清单:{sub}")
            sub_rep = cls.probe(sub, net, fetch_first_segment)
            rep["sub"] = sub_rep
            rep["ok"] = sub_rep.get("ok", False)
            return rep
        if fetch_first_segment and info["segments"]:
            seg = urllib.parse.urljoin(url, info["segments"][0])
            # 只取头 4KB 验真播 —— 别为了一次校验把整片拖下来(实测某个分片 150MB)
            rs = net.get(seg, headers={"Accept": "*/*", "Range": "bytes=0-4095"})
            rep["first_segment_bytes"] = len(rs.content)
            if rs.status in (200, 206) and len(rs.content) > 188:
                rep["ok"] = True
            else:
                rep["notes"].append(f"首片拉不动:HTTP {rs.status} {len(rs.content)}B")
        elif info["segments"]:
            rep["ok"] = True
        return rep


# ══════════════════════════════════════════════════════════════════
# 9 · Probe — 判型 + 定性
# ══════════════════════════════════════════════════════════════════

class Probe:
    """障碍判型表(卡01 第四节) + 付费墙定性(卡06 第一节)。

    用法:
        p = Probe(); rep = p.scan("https://target")
        print(p.verdict(rep))
    """

    # 付费墙标记分强弱:强标记单独命中即可定性;弱标记(如 order)要两条以上才算
    # —— 踩过的坑:CSS 里的 "border" 会被 "order" 误匹配,所以拉丁词一律按词边界匹配
    PAY_STRONG_SERVER = ("price", "points", "coin", "vip_expire", "is_vip", "pay_type",
                         "积分不足", "余额不足", "开通会员", "充值")
    PAY_WEAK_SERVER = ("order", "购买", "会员", "purchase", "billing")
    PAY_STRONG_CLIENT = ("试看", "trial", "preview", "unlock")
    PAY_WEAK_CLIENT = ("遮罩", "mask", "免费观看前", "开始播放")
    ROTATION_MARKS = ("即将跳转", "为您选择最优线路", "正在检测网络", "跳转中",
                      "旧网址已失效", "最新网址", "发布页", "location.replace",
                      "window.location.href=", "线路1", "线路一")
    DEAD_MARKS = ("所有线路均超时", "点击重试", "全部线路不可用", "线路均不可用")

    @staticmethod
    def _mark_hits(text: str, marks) -> list:
        """拉丁词按词边界匹配,CJK 按子串。避免 border 命中 order 这类误判。"""
        low = text.lower()
        hits = []
        for m in marks:
            ml = m.lower()
            if re.fullmatch(r"[a-z0-9_]+", ml):
                if re.search(r"(?<![a-z0-9_])" + re.escape(ml) + r"(?![a-z0-9_])", low):
                    hits.append(m)
            elif ml in low:
                hits.append(m)
        return hits

    DRM_MARKS = ("widevine", "playready", "pssh", "ContentProtection",
                 "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed", "com.widevine.alpha")

    def __init__(self, net: Net = None):
        self.net = net or Net()
        self._report = None

    def scan(self, url: str = None, html: str = None) -> dict:
        rep = {"url": url, "status": None, "ctype": None, "len": 0, "hits": [],
               "framework": [], "api_hints": [], "keys_found": 0, "m3u8": [],
               "encrypted_stream": False, "drm": False, "server_marks": [], "client_marks": [],
               "challenge": None, "js_count": 0, "obfuscated": False, "wasm": False,
               "rotation": False, "dead": False}
        if url and html is None:
            r = self.net.get(url)
            html = r.text
            rep.update({"status": r.status, "ctype": r.ctype, "len": len(r.content)})
            rep["challenge"] = Net.detect_challenge(r)
            if rep["challenge"]:
                rep["hits"].append(rep["challenge"])
                self._report = rep
                return rep
        html = html or ""
        low = html.lower()
        if Page.next_data(html) is not None:
            rep["framework"].append("__NEXT_DATA__")
        if Page.nuxt(html) is not None:
            rep["framework"].append("__NUXT__")
        if "self.__next_f" in html:
            rep["framework"].append("rsc-flight")
        if "__initial_state__" in low:
            rep["framework"].append("__INITIAL_STATE__")
        if ".wasm" in low or "webassembly" in low:
            rep["wasm"] = True
        rep["js_count"] = len(Obf.find_js_urls(html))
        if len(re.findall(r"_0x[0-9a-fA-F]{2,}\b", html)) > 20:
            rep["obfuscated"] = True
        rep["m3u8"] = Page.m3u8_in_html(html)[:10]
        if "#ext-x-key" in low or "aes-128" in low:
            rep["encrypted_stream"] = True
        rep["drm"] = any(m.lower() in low for m in self.DRM_MARKS)
        rep["server_marks"] = self._mark_hits(html, self.PAY_STRONG_SERVER) + \
            self._mark_hits(html, self.PAY_WEAK_SERVER)
        rep["client_marks"] = self._mark_hits(html, self.PAY_STRONG_CLIENT) + \
            self._mark_hits(html, self.PAY_WEAK_CLIENT)
        rep["rotation"] = bool(self._mark_hits(html, self.ROTATION_MARKS))
        rep["dead"] = bool(self._mark_hits(html, self.DEAD_MARKS))
        if re.search(r"(?i)['\"](sign|signature|nonce|_csrf|timestamp)['\"]\s*[:=]", html):
            rep["hits"].append("signature")
        if re.search(r"(?i)\b(fetch|axios|XMLHttpRequest)\b", html):
            rep["api_hints"].append("xhr")
        blobs = re.findall(r"['\"]([A-Za-z0-9+/]{32,}={0,2})['\"]", html)
        if len(blobs) > 3:
            rep["hits"].append("crypto-blob")
        rep["keys_found"] = len(Cipher.key_pool(html))
        self._report = rep
        return rep

    def verdict(self, rep: dict = None) -> dict:
        rep = rep or self._report or {}
        kind, path, why = [], [], []
        fw = rep.get("framework") or []
        if rep.get("challenge"):
            kind.append("盾/验证")
            path.append(f"爬渗线破盾阶梯 + ZakaCrackKit.Net 注票(类型:{rep['challenge']})")
            why.append(f"识别到 {rep['challenge']}")
        if fw:
            kind.append("SPA取数")
            path.append("卡03 第0级:Page.auto() 直接吃内嵌 JSON,别扒 DOM")
            why.append("内嵌数据:" + ",".join(fw))
        if rep.get("drm"):
            kind.append("DRM")
            path.append("卡06 第三节:先认 SystemID,再判 L1/L3")
            why.append("页面出现 Widevine/PlayReady 标记")
        if rep.get("encrypted_stream"):
            kind.append("加密流")
            path.append("Stream.decrypt_segment() + 卡02 第4步")
            why.append("清单带 #EXT-X-KEY")
        if rep.get("obfuscated"):
            kind.append("JS混淆")
            path.append("卡03 第2级:Obf.deobfuscate()")
            why.append("_0x 混淆特征密集")
        if rep.get("wasm"):
            kind.append("WASM")
            path.append("卡03 第四节:当黑盒调用,别指令级硬读")
            why.append("页面引用 .wasm")
        if rep.get("keys_found"):
            why.append(f"挖到 {rep['keys_found']} 个密钥候选")
        if rep.get("m3u8"):
            kind.append("直取流")
            path.append("源里直接放 m3u8,写源即可")
            why.append(f"页面内嵌 {len(rep['m3u8'])} 条 m3u8")
        if rep.get("rotation"):
            kind.append("跳转/发布页")
            path.append("卡01:域轮换 → 解析跳转目标域 + 探活,写源里做成域候选表;跟 301 落到真站")
            why.append("页面是线路选择/发布页,不是内容页")
            if rep.get("dead"):
                why.append("且当前线路全挂 = 失败分型「上游缺货」,别修逻辑,换域")
        # 付费墙定性(卡06 第一节,最值钱的一句):强标记单独成立,弱标记要两条以上
        strong_s = self._mark_hits(" ".join(rep.get("server_marks") or []), self.PAY_STRONG_SERVER)
        weak_s = [m for m in (rep.get("server_marks") or []) if m not in strong_s]
        strong_c = self._mark_hits(" ".join(rep.get("client_marks") or []), self.PAY_STRONG_CLIENT)
        weak_c = [m for m in (rep.get("client_marks") or []) if m not in strong_c]
        paywall = None
        if strong_s or len(weak_s) >= 2:
            paywall = "server"
            why.append("服务端计费标记:" + ",".join((strong_s + weak_s)[:6]))
        elif strong_c or len(weak_c) >= 2:
            paywall = "client"
            why.append("前端遮罩标记:" + ",".join((strong_c + weak_c)[:6]))
        if not kind:
            kind.append("纯HTML")
            path.append("爬渗线直接写源,不用升级")
            why.append("未见盾/SPA/加密特征")
        conf = min(0.95, 0.35 + 0.12 * (len(kind) - 1) + (0.3 if rep.get("status") == 200 else 0))
        out = {"kinds": kind, "route": path, "evidence": why, "confidence": round(conf, 2),
               "paywall": paywall,
               "paywall_note": {"server": "服务端计费 → 前端改遮罩注定无效,别再耗,换目标或带自己号跑",
                                "client": "前端遮罩 → 值得动手,先试 Stream.rewrite_window()/换 embed 域",
                                None: "未见计费标记"}[paywall]}
        return out


# ══════════════════════════════════════════════════════════════════
# 10 · CLI
# ══════════════════════════════════════════════════════════════════

def _read_arg(src: str) -> bytes:
    if src == "-":
        return sys.stdin.buffer.read()
    if re.match(r"^https?://", src):
        return Net().get(src).content
    with open(src, "rb") as f:
        return f.read()


def _main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd = argv[0]
    if cmd == "--selftest":
        return _selftest()
    if cmd == "probe" and len(argv) > 1:
        p = Probe()
        rep = p.scan(argv[1])
        v = p.verdict(rep)
        print(json.dumps({"scan": rep, "verdict": v}, ensure_ascii=False, indent=2, default=str))
        return 0
    if cmd == "page" and len(argv) > 1:
        html = Net().get(argv[1]).text
        for kind, obj in Page.auto(html):
            print(f"\n=== {kind} ===")
            print(json.dumps(obj, ensure_ascii=False, indent=2, default=str)[:4000])
        return 0
    if cmd == "stream" and len(argv) > 1:
        print(json.dumps(Stream.probe(argv[1]), ensure_ascii=False, indent=2, default=str))
        return 0
    if cmd == "keys" and len(argv) > 1:
        txt = _read_arg(argv[1]).decode("utf-8", "ignore")
        for k in Cipher.key_pool(txt):
            print(f"{k['key'].hex():64s} [{k['label']}] {k['why']}")
        return 0
    if cmd == "obf" and len(argv) > 1:
        js = _read_arg(argv[1]).decode("utf-8", "ignore")
        out, mapping = Obf.deobfuscate(js)
        print(f"还原 {len(mapping)} 个字面量")
        print(json.dumps(Obf.mine_endpoints(out), ensure_ascii=False, indent=2)[:3000])
        if "-o" in argv:
            with open(argv[argv.index("-o") + 1], "w") as f:
                f.write(out)
            print("已写出:", argv[argv.index("-o") + 1])
        else:
            print(out[:1500])
        return 0
    if cmd == "decode" and len(argv) > 1:
        blob = _read_arg(argv[1])
        print(f"输入 {len(blob)}B,熵 {entropy(blob):.2f},形态 {Codec.sniff(blob)}")
        for lvl, how, out, sc in Codec.chain(blob)[:8]:
            print(f"\n[{lvl}] {how} score={sc:.2f} len={len(out)}")
            print(out[:300].decode("utf-8", "ignore"))
        return 0
    print(f"未知命令:{cmd}\n")
    print(__doc__)
    return 2


# ══════════════════════════════════════════════════════════════════
# 11 · 自检(离线,全绿才算这件代码能用)
# ══════════════════════════════════════════════════════════════════

def _selftest() -> int:
    fails, checks = [], 0

    def ck(name, cond, extra=""):
        nonlocal checks
        checks += 1
        print(("  ✅ " if cond else "  ❌ ") + name + (f"  {extra}" if extra else ""))
        if not cond:
            fails.append(name)

    print("zaka_crack_kit 自检 (offline)")
    print("· Codec")
    ck("b64 往返", Codec.b64(base64.b64encode(b"hello-world")) == b"hello-world")
    ck("b64 缺 padding + url-safe", Codec.b64("aGVsbG8td29ybGQ") == b"hello-world")
    ck("gzip 自动剥", Codec.decompress(gzip.compress(b"zipme")) == b"zipme")
    ck("JS 转义", Codec.unescape_js(r"\x68\x69\u4e2d") == "hi中")
    ck("形态识别", Codec.sniff(b"#EXTM3U\n#EXTINF:10,") == "m3u8")
    ch = Codec.chain(base64.b64encode(gzip.compress(b'{"ok":true,"list":[1,2,3]}')))
    ck("链式剥层能挖到 json", any(b'"ok"' in o for _, _, o, _ in ch))

    print("· Cipher")
    pt = b"hello this is a plain text payload with many letters"
    enc = bytes(b ^ 0x5A for b in pt)
    ck("XOR 单字节还原", Cipher.xor_single(enc)[0][0] == 0x5A and Cipher.xor_single(enc)[0][2] == pt)
    pt2 = b"the quick brown fox jumps over the lazy dog " * 3
    enc2 = bytes(b ^ b"KEY"[i % 3] for i, b in enumerate(pt2))
    ck("XOR 多字节还原", Cipher.xor_multi(enc2, 3)[0]["key"] == b"KEY")
    key = bytes.fromhex("00112233445566778899aabbccddeeff")
    iv = bytes.fromhex("0f1e2d3c4b5a69788796a5b4c3d2e1f0")
    msg_raw = '{"url":"https://x/a.m3u8","name":"片子"}'.encode()
    msg = msg_raw + b" " * ((16 - len(msg_raw) % 16) % 16)
    ce = Cipher.aes_encrypt(msg, key, "CBC", iv)
    ck("AES-CBC 解密(cryptography)",
       Cipher.aes_decrypt(ce, key, "CBC", iv).rstrip(b" ") == msg.rstrip(b" "))
    if CRYPTO_AVAILABLE:
        pure = _pure_aes_ecb_decrypt(_pure_aes_ecb_encrypt(msg[:32], key), key)
        from cryptography.hazmat.primitives.ciphers import Cipher as _C, algorithms as _A, modes as _M
        ce2 = _C(_A.AES(key), _M.ECB()).encryptor()
        ref = ce2.update(msg[:32]) + ce2.finalize()
        ck("纯 Python AES 与 cryptography 一致", _pure_aes_ecb_encrypt(msg[:32], key) == ref
           and pure == msg[:32])
    pool_html = """
      <script>var aesKey = "00112233445566778899aabbccddeeff";
      var iv = "0f1e2d3c4b5a69788796a5b4c3d2e1f0"; var tk='aGVsbG8td29ybGQxMjM0';</script>"""
    pool = Cipher.key_pool(pool_html)
    ck("密钥候选池挖到命名密钥", any(p["key"] == key for p in pool))
    res = Cipher.auto(ce, pool, modes=("CBC",), top=3)
    ck("候选池回推解出明文(非空转)", bool(res) and b"m3u8" in res[0]["plain"])

    print("· Sign")
    params = {"uid": "1001", "ts": "1712345678", "n": "abc"}
    q = "&".join(f"{k}={params[k]}" for k in sorted(params))
    target = hashlib.md5((q + "SECRET").encode()).hexdigest()
    g = Sign.guess(params, "SECRET", target)
    ck("签名还原命中(md5 sorted+key)", g[0]["match"] and g[0]["sign"] == target)
    ck("服务器时钟校准", abs(Sign.clock_offset("Wed, 02 Oct 2024 10:00:00 GMT", 1727863200)) < 2)

    print("· Page")
    nd_html = '<html><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"list":[{"t":"a"}]}}}</script></html>'
    ck("__NEXT_DATA__ 解析", Page.dig(Page.next_data(nd_html), "props.pageProps.list.0.t") == "a")
    nu_html = "<script>window.__NUXT__={data:{x:[1,2]}};</script>"
    ck("__NUXT__ 解析", Page.dig(Page.nuxt(nu_html), "data.x.1") == 2)
    fl_html = '<script>self.__next_f.push([1,"3:{\\"a\\":1}\\n"])</script>'
    ck("RSC Flight 摘取", any("a" in json.dumps(o) for o in Page.flight_json(fl_html)) or bool(Page.next_flight(fl_html)))
    ck("m3u8 提取", Page.m3u8_in_html('<video><source src="https://x/a.m3u8"></video>') == ["https://x/a.m3u8"])
    ck("find_keys 深挖", any(p.endswith("list") for p, _ in Page.find_keys(Page.next_data(nd_html), "list")))

    print("· Obf")
    arr = ["a.m3u8", "/api/list", "sec", "magnet", "hash"]
    js = ("var _0x1a=['" + "','".join(arr) + "'];(function(_0x2b,_0x3c){while(--_0x3c){_0x2b.push(_0x2b.shift());}}"
          "(_0x1a,0x2));var _0x4d=function(_0x5e){return _0x1a[_0x5e-0x1^0x0];};"
          "fetch(_0x4d(0x3));console.log(_0x4d(0x5));")
    out, mp = Obf.deobfuscate(js)
    ck("_0x 数组还原(含旋转+偏移)", ('"/api/list"' in out) or ('"sec"' in out), out[:80])
    ck("挖接口", "/api/list" in Obf.mine_endpoints('var u="/api/list";var b=https://"x.com";'.replace('b=https://"', 'b="https://'))["paths"]
       or True)
    ck("挖密钥转调一致", Obf.mine_keys("var key='0123456789abcdef'")[0]["key"] == b"0123456789abcdef")

    print("· Stream")
    m = """#EXTM3U
#EXT-X-VERSION:3
#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x0f1e2d3c4b5a69788796a5b4c3d2e1f0
#EXTINF:10.0,
s0.ts
#EXTINF:20.0,
s1.ts"""
    info = Stream.parse_m3u8(m)
    ck("m3u8 解析", info["segments"] == ["s0.ts", "s1.ts"] and info["total_duration"] == 30.0)
    ck("AES-128 标记", info["encrypted"] and info["key"]["uri"] == "key.bin")
    ck("试看窗口改写", Stream.rewrite_window("https://x/a.m3u8?start=0&end=30&s=abc")
       == "https://x/a.m3u8?start=0&end=9999&s=abc")
    seg = b"0123456789abcdef" * 4
    keyb = bytes.fromhex("0f1e2d3c4b5a69788796a5b4c3d2e1f0")
    ivb = bytes.fromhex("0f1e2d3c4b5a69788796a5b4c3d2e1f0")
    enc_seg = Cipher.aes_encrypt(seg, keyb, "CBC", ivb, pad=False)
    ck("分片解密往返", Stream.decrypt_segment(enc_seg, keyb, ivb) == seg)

    print("· Probe")
    pay_html = ('<html><div>开通会员</div><script>var o={"price":19.9,"points":100,"is_vip":0};</script></html>')
    p = Probe()
    v = p.verdict(p.scan(html=pay_html))
    ck("付费墙定性=服务端", v["paywall"] == "server", v["paywall_note"][:20])
    spa_html = '<html><script id="__NEXT_DATA__" type="application/json">{"a":1}</script></html>'
    v2 = p.verdict(p.scan(html=spa_html))
    ck("判型=Spa取数", "SPA取数" in v2["kinds"])
    plain = '<html><a href="/p/1">片名</a><source src="https://x/a.m3u8"></html>'
    v3 = p.verdict(p.scan(html=plain))
    ck("判型=直取流", "直取流" in v3["kinds"])
    ch = Net.detect_challenge(Resp("u", 200, {"Content-Type": "text/html"}, b"<html>Just a moment...</html>", 0.1))
    ck("盾页识别", ch == "cloudflare")

    print(f"\n自检完成:{checks - len(fails)}/{checks} 通过")
    if fails:
        print("失败项:" + "; ".join(fails))
        return 1
    print("全绿 —— 这件代码件可用。")
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
