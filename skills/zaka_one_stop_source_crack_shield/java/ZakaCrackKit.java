/*
 * ZakaCrackKit.java — 一条龙写源 · Java 侧现成函数层(Zaka 深度引擎)
 *
 * 为什么有这一件:TVBox 的源分两种走法 —— python 源用 zaka_crack_kit.py,
 * 打进 jar 的源只能用 Java。两边能力口径保持一致,写源时不用换脑子。
 *
 * 零外部依赖(只用 JDK:JCE + HttpURLConnection + regex),直接丢进你的工程即可。
 *
 * 类名对照(python ↔ java):
 *   Codec  ↔ Codec     编解码链(base64 全变体/hex/gzip/deflate)
 *   Cipher ↔ Crypt     对称解密(AES 五模式/XOR 速扫/RC4)  —— Java 里避开 javax.crypto.Cipher 重名
 *   Sign   ↔ Sign      摘要与签名(md5/sha1/sha256/hmac) + 参数排序变体
 *   Page   ↔ Page      SPA 内嵌数据(__NEXT_DATA__ / __NUXT__)+ m3u8 提取
 *   Stream ↔ Stream    m3u8 解析 / AES-128 分片解密 / 试看窗口改写
 *   Net    ↔ Net       请求层(UA/Referer/Cookie/重试退避/服务器时钟/盾页识别)
 *   Probe  ↔ Probe     判型 + 付费墙定性
 *
 * 编译:javac -encoding UTF-8 ZakaCrackKit.java
 * 自检:java ZakaCrackKit        (离线全绿才算这件能用)
 */

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.GZIPInputStream;
import java.util.zip.Inflater;
import javax.crypto.Mac;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

public class ZakaCrackKit {

    public static final String VERSION = "1.0.0";

    // ══════════════════════════════════════════════════════════
    // Codec — 编解码链
    // ══════════════════════════════════════════════════════════
    public static class Codec {
        private static final Pattern NON_B64 = Pattern.compile("[^A-Za-z0-9+/=_-]");

        /** 宽容 base64:缺 padding / url-safe / 混空白 都能解。 */
        public static byte[] b64(String s) {
            String t = NON_B64.matcher(s.trim()).replaceAll("").replace('-', '+').replace('_', '/');
            while (t.length() % 4 != 0) t += "=";
            try {
                return Base64.getDecoder().decode(t);
            } catch (IllegalArgumentException e) {
                return new byte[0];
            }
        }

        public static String b64(byte[] d) {
            return Base64.getEncoder().encodeToString(d);
        }

        public static byte[] unhex(String s) {
            String t = s.replaceAll("0[xX]", "").replaceAll("[^0-9a-fA-F]", "");
            if (t.length() % 2 == 1) t = t.substring(0, t.length() - 1);
            byte[] out = new byte[t.length() / 2];
            for (int i = 0; i < out.length; i++)
                out[i] = (byte) Integer.parseInt(t.substring(i * 2, i * 2 + 2), 16);
            return out;
        }

        public static String hex(byte[] d) {
            StringBuilder sb = new StringBuilder();
            for (byte b : d) sb.append(String.format("%02x", b));
            return sb.toString();
        }

        /** gzip / deflate(zlib) / raw deflate 自动剥,剥不动原样返回。 */
        public static byte[] inflate(byte[] d) {
            try (GZIPInputStream g = new GZIPInputStream(new java.io.ByteArrayInputStream(d))) {
                return readAll(g);
            } catch (Exception ignore) { }
            try {
                Inflater inf = new Inflater();
                inf.setInput(d);
                byte[] out = new byte[65536];
                int n = inf.inflate(out);
                return Arrays.copyOf(out, n);
            } catch (Exception ignore) { }
            try {
                Inflater inf = new Inflater(true);   // raw deflate
                inf.setInput(d);
                byte[] out = new byte[65536];
                int n = inf.inflate(out);
                return Arrays.copyOf(out, n);
            } catch (Exception ignore) { }
            return d;
        }

        private static byte[] readAll(InputStream in) throws Exception {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
            return bos.toByteArray();
        }
    }

    // ══════════════════════════════════════════════════════════
    // Crypt — 对称解密(与 python 侧 Cipher 同口径)
    // ══════════════════════════════════════════════════════════
    public static class Crypt {
        /** AES 解密。mode: CBC / ECB / CTR / CFB / OFB。 */
        public static byte[] aes(byte[] data, byte[] key, String mode, byte[] iv) throws Exception {
            String alg = "AES/" + mode.toUpperCase() + "/"
                    + (mode.equalsIgnoreCase("ECB") ? "NoPadding" : "PKCS5Padding");
            if (mode.equalsIgnoreCase("CTR") || mode.equalsIgnoreCase("CFB")
                    || mode.equalsIgnoreCase("OFB")) alg = "AES/" + mode.toUpperCase() + "/NoPadding";
            javax.crypto.Cipher c = javax.crypto.Cipher.getInstance(alg);
            SecretKeySpec sk = new SecretKeySpec(key, "AES");
            if (mode.equalsIgnoreCase("ECB")) {
                c.init(javax.crypto.Cipher.DECRYPT_MODE, sk);
            } else {
                byte[] ivv = (iv == null ? new byte[16] : iv);
                c.init(javax.crypto.Cipher.DECRYPT_MODE, sk, new IvParameterSpec(ivv));
            }
            byte[] out = c.doFinal(data);
            return unpad(out);
        }

        public static byte[] aesEncrypt(byte[] data, byte[] key, String mode, byte[] iv) throws Exception {
            String alg = "AES/" + mode.toUpperCase() + "/"
                    + (mode.equalsIgnoreCase("ECB") ? "NoPadding" : "PKCS5Padding");
            javax.crypto.Cipher c = javax.crypto.Cipher.getInstance(alg);
            SecretKeySpec sk = new SecretKeySpec(key, "AES");
            if (mode.equalsIgnoreCase("ECB")) c.init(javax.crypto.Cipher.ENCRYPT_MODE, sk);
            else c.init(javax.crypto.Cipher.ENCRYPT_MODE, sk,
                    new IvParameterSpec(iv == null ? new byte[16] : iv));
            return c.doFinal(data);
        }

        /** PKCS7 去填充(不对就原样返回)。 */
        public static byte[] unpad(byte[] d) {
            if (d == null || d.length == 0) return d;
            int p = d[d.length - 1] & 0xFF;
            if (p >= 1 && p <= 16 && d.length >= p) {
                boolean ok = true;
                for (int i = d.length - p; i < d.length; i++) if ((d[i] & 0xFF) != p) ok = false;
                if (ok) return Arrays.copyOf(d, d.length - p);
            }
            return d;
        }

        /**
         * 单字节 XOR 速扫 —— 用打分而不是"可打印比率"(踩过的坑:同 printable 时选错 key)。
         * 返回 [key(0-255), score*1000]。
         */
        public static int[] xorSingle(byte[] data) {
            int bestK = 0;
            double best = -1;
            for (int k = 0; k < 256; k++) {
                byte[] dec = new byte[data.length];
                for (int i = 0; i < data.length; i++) dec[i] = (byte) (data[i] ^ k);
                double s = textScore(dec);
                if (s > best) { best = s; bestK = k; }
            }
            return new int[]{bestK, (int) Math.round(best * 1000)};
        }

        public static byte[] xor(byte[] data, byte[] key) {
            byte[] out = new byte[data.length];
            for (int i = 0; i < data.length; i++) out[i] = (byte) (data[i] ^ key[i % key.length]);
            return out;
        }

        public static byte[] rc4(byte[] key, byte[] data) {
            int[] s = new int[256];
            for (int i = 0; i < 256; i++) s[i] = i;
            int j = 0;
            for (int i = 0; i < 256; i++) {
                j = (j + s[i] + (key[i % key.length] & 0xFF)) & 0xFF;
                int t = s[i]; s[i] = s[j]; s[j] = t;
            }
            byte[] out = new byte[data.length];
            int i = 0; j = 0;
            for (int n = 0; n < data.length; n++) {
                i = (i + 1) & 0xFF;
                j = (j + s[i]) & 0xFF;
                int t = s[i]; s[i] = s[j]; s[j] = t;
                out[n] = (byte) (data[n] ^ s[(s[i] + s[j]) & 0xFF]);
            }
            return out;
        }
    }

    // ══════════════════════════════════════════════════════════
    // 明文打分(判据:字母+空格密度、硬符号密度;不是单一 printable)
    // ══════════════════════════════════════════════════════════
    private static final String HARD_PUNCT = "<>{}[]&=%#@*+\\|~^`$";

    public static double textScore(byte[] d) {
        if (d == null || d.length == 0) return 0;
        int n = d.length, printable = 0, litspace = 0, space = 0, hard = 0, ctrl = 0;
        for (byte b : d) {
            int v = b & 0xFF;
            if ((v >= 32 && v < 127) || v == 9 || v == 10 || v == 13) printable++;
            if (v == 32 || (v >= 65 && v <= 90) || (v >= 97 && v <= 122)) litspace++;
            if (v == 32) space++;
            if (HARD_PUNCT.indexOf((char) v) >= 0) hard++;
            if (v < 9 || (v > 13 && v < 32)) ctrl++;
        }
        double s = 0.30 * printable / n + 0.35 * litspace / n + Math.min(space * 1.2 / n, 0.12);
        if (d.length >= 3 && new String(d, StandardCharsets.UTF_8).matches("(?s).*[\\u4e00-\\u9fff].*")) s += 0.30;
        s -= 0.45 * hard / n;
        s -= 0.35 * ctrl / n;
        return Math.max(0, Math.min(1, s));
    }

    // ══════════════════════════════════════════════════════════
    // Sign — 摘要与签名
    // ══════════════════════════════════════════════════════════
    public static class Sign {
        public static String md5(String s) { return digest("MD5", s); }
        public static String sha1(String s) { return digest("SHA-1", s); }
        public static String sha256(String s) { return digest("SHA-256", s); }

        private static String digest(String alg, String s) {
            try {
                MessageDigest md = MessageDigest.getInstance(alg);
                return Codec.hex(md.digest(s.getBytes(StandardCharsets.UTF_8)));
            } catch (Exception e) {
                return "";
            }
        }

        public static String hmac(String alg, String key, String data) {
            try {
                Mac m = Mac.getInstance(alg);
                m.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), alg));
                return Codec.hex(m.doFinal(data.getBytes(StandardCharsets.UTF_8)));
            } catch (Exception e) {
                return "";
            }
        }

        public static String hmacSha256(String key, String data) { return hmac("HmacSHA256", key, data); }

        /**
         * 签名候选 —— 90% 的失败是「漏字段」和「排序错」,所以把拼装变体全列出来。
         * 返回:payload(拼装串) → 候选签名列表。
         */
        public static Map<String, List<String>> guess(Map<String, String> params, String key) {
            Map<String, List<String>> out = new LinkedHashMap<>();
            List<String> forms = orderVariants(params);
            for (String p : forms) {
                List<String> sigs = new ArrayList<>();
                sigs.add(md5(p));
                sigs.add(md5(p + key));
                sigs.add(md5(key + p));
                sigs.add(sha1(p + key));
                sigs.add(sha256(p + key));
                sigs.add(hmacSha256(key, p));
                out.put(p, sigs);
            }
            return out;
        }

        public static List<String> orderVariants(Map<String, String> params) {
            List<String> keys = new ArrayList<>(params.keySet());
            List<String> sorted = new ArrayList<>(keys);
            java.util.Collections.sort(sorted);
            List<String> out = new ArrayList<>();
            out.add(join(params, keys, "&"));
            out.add(join(params, sorted, "&"));
            out.add(joinKv(params, sorted));
            StringBuilder vals = new StringBuilder(), valsSorted = new StringBuilder();
            for (String k : keys) vals.append(params.get(k));
            for (String k : sorted) valsSorted.append(params.get(k));
            out.add(vals.toString());
            out.add(valsSorted.toString());
            return out;
        }

        private static String join(Map<String, String> p, List<String> ks, String sep) {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < ks.size(); i++) {
                if (i > 0) sb.append(sep);
                sb.append(ks.get(i)).append('=').append(p.get(ks.get(i)));
            }
            return sb.toString();
        }

        private static String joinKv(Map<String, String> p, List<String> ks) {
            StringBuilder sb = new StringBuilder();
            for (String k : ks) sb.append(k).append(p.get(k));
            return sb.toString();
        }

        /** 服务器时钟偏移(秒):带时间戳签名的站,本机差几秒就全挂。 */
        public static long clockOffset(long serverEpochSec) {
            return serverEpochSec - System.currentTimeMillis() / 1000L;
        }
    }

    // ══════════════════════════════════════════════════════════
    // Page — SPA 取数
    // ══════════════════════════════════════════════════════════
    public static class Page {
        private static final Pattern NEXT = Pattern.compile(
                "<script[^>]+id=[\"']__NEXT_DATA__[\"'][^>]*>(.*?)</script>", Pattern.DOTALL);
        private static final Pattern NUXT = Pattern.compile(
                "window\\.__NUXT__\\s*=\\s*(\\{.*?\\})\\s*;", Pattern.DOTALL);
        private static final Pattern M3U8 = Pattern.compile(
                "(?:src=[\"']|[\"'])([^\"']+\\.m3u8[^\"']*)", Pattern.CASE_INSENSITIVE);

        public static String nextData(String html) {
            Matcher m = NEXT.matcher(html == null ? "" : html);
            return m.find() ? m.group(1).trim() : null;
        }

        public static String nuxt(String html) {
            Matcher m = NUXT.matcher(html == null ? "" : html);
            return m.find() ? m.group(1).trim() : null;
        }

        /** 从 JSON 里毛取一个键的字符串值(不想引 JSON 库时够用;深层结构建议换正经解析)。 */
        public static String json(String json, String key) {
            Matcher m = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*\"([^\"]*)\"").matcher(json == null ? "" : json);
            return m.find() ? m.group(1) : null;
        }

        public static List<String> m3u8(String html) {
            List<String> out = new ArrayList<>();
            Matcher m = M3U8.matcher(html == null ? "" : html);
            while (m.find()) if (!out.contains(m.group(1))) out.add(m.group(1));
            return out;
        }

        public static String text(String html) {
            return (html == null ? "" : html)
                    .replaceAll("(?is)<(script|style)[^>]*>.*?</\\1>", " ")
                    .replaceAll("(?s)<[^>]+>", " ")
                    .replaceAll("\\s+", " ").trim();
        }
    }

    // ══════════════════════════════════════════════════════════
    // Stream — 取流层
    // ══════════════════════════════════════════════════════════
    public static class Stream {
        public static class Info {
            public boolean master = false, encrypted = false;
            public double totalDuration = 0;
            public final List<String> segments = new ArrayList<>();
            public final List<String> variants = new ArrayList<>();
            public String keyUri = null, keyMethod = null, keyIv = null;
        }

        public static Info parse(String m3u8) {
            Info info = new Info();
            for (String raw : (m3u8 == null ? "" : m3u8).split("\\r?\\n")) {
                String l = raw.trim();
                if (l.isEmpty() || l.startsWith("#EXT-X-VERSION") || l.startsWith("#EXT-X-TARGETDURATION")) continue;
                if (l.startsWith("#EXTINF")) {
                    Matcher m = Pattern.compile("#EXTINF:\\s*([\\d.]+)").matcher(l);
                    if (m.find()) info.totalDuration += Double.parseDouble(m.group(1));
                } else if (l.startsWith("#EXT-X-KEY")) {
                    info.encrypted = true;
                    Matcher m1 = Pattern.compile("METHOD=([A-Z0-9-]+)").matcher(l);
                    Matcher m2 = Pattern.compile("URI=\"([^\"]+)\"").matcher(l);
                    Matcher m3 = Pattern.compile("IV=(0x[0-9a-fA-F]+)").matcher(l);
                    if (m1.find()) info.keyMethod = m1.group(1);
                    if (m2.find()) info.keyUri = m2.group(1);
                    if (m3.find()) info.keyIv = m3.group(1);
                } else if (l.startsWith("#EXT-X-STREAM-INF")) {
                    info.master = true;
                } else if (l.startsWith("#")) {
                    continue;
                } else if (info.master) {
                    info.variants.add(l);
                } else {
                    info.segments.add(l);
                }
            }
            info.totalDuration = Math.round(info.totalDuration * 100) / 100.0;
            return info;
        }

        /** 试看窗口改写(卡06 打法1)。改完必须真拉清单看时长,别只看接口 200。 */
        public static String rewriteWindow(String url) {
            return url.replaceAll("start=\\d+&end=\\d+", "start=0&end=9999");
        }

        public static byte[] decryptSegment(byte[] data, byte[] key, byte[] iv) throws Exception {
            int n = data.length / 16 * 16;
            return Crypt.aes(Arrays.copyOf(data, n), key, "CBC", iv == null ? new byte[16] : iv);
        }

        public static boolean looksLikeM3U8(byte[] body) {
            String head = new String(Arrays.copyOf(body, Math.min(body.length, 512)), StandardCharsets.UTF_8);
            return head.startsWith("#EXTM3U") || head.contains("#EXTM3U");
        }
    }

    // ══════════════════════════════════════════════════════════
    // Net — 请求层
    // ══════════════════════════════════════════════════════════
    public static class Net {
        public String ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/124.0 Safari/537.36";
        public String referer, cookie;
        public int timeoutMs = 15000, retries = 3;
        public Map<String, String> headers = new LinkedHashMap<>();

        public static class Resp {
            public int status;
            public String contentType = "", serverDate = "", body = "", finalUrl = "";
            public byte[] bytes = new byte[0];
        }

        public Resp get(String url) { return request(url, null, false); }
        public Resp post(String url, String body, boolean isJson) { return request(url, body, isJson); }

        private Resp request(String url, String body, boolean isJson) {
            Resp resp = new Resp();
            for (int attempt = 0; attempt <= retries; attempt++) {
                try {
                    HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
                    c.setConnectTimeout(timeoutMs);
                    c.setReadTimeout(timeoutMs);
                    c.setInstanceFollowRedirects(true);
                    c.setRequestProperty("User-Agent", ua);
                    c.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8");
                    if (referer != null) c.setRequestProperty("Referer", referer);
                    if (cookie != null) c.setRequestProperty("Cookie", cookie);
                    for (Map.Entry<String, String> e : headers.entrySet()) c.setRequestProperty(e.getKey(), e.getValue());
                    if (body != null) {
                        c.setRequestMethod("POST");
                        c.setDoOutput(true);
                        if (isJson) c.setRequestProperty("Content-Type", "application/json");
                        OutputStream os = c.getOutputStream();
                        os.write(body.getBytes(StandardCharsets.UTF_8));
                        os.flush();
                        os.close();
                    }
                    resp.status = c.getResponseCode();
                    resp.contentType = String.valueOf(c.getContentType());
                    resp.serverDate = String.valueOf(c.getHeaderField("Date"));
                    resp.finalUrl = c.getURL().toString();
                    InputStream in = resp.status >= 400 ? c.getErrorStream() : c.getInputStream();
                    resp.bytes = in == null ? new byte[0] : Codec.inflate(readAll(in));
                    resp.body = new String(resp.bytes, StandardCharsets.UTF_8);
                    return resp;
                } catch (Exception e) {
                    if (attempt < retries) {
                        try { Thread.sleep(800L * (attempt + 1)); } catch (InterruptedException ignore) { }
                    } else {
                        resp.status = 0;
                    }
                }
            }
            return resp;
        }

        private static byte[] readAll(InputStream in) throws Exception {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
            return bos.toByteArray();
        }

        /** 盾页/验证页/登录墙识别(与 python 侧同一套标记)。 */
        public static String detectChallenge(int status, String body, String ctype) {
            String t = body == null ? "" : body.toLowerCase();
            if (t.contains("just a moment") || t.contains("cf-chl") || t.contains("cf_clearance")) return "cloudflare";
            if (t.contains("cf-turnstile") || t.contains("challenges.cloudflare.com/turnstile")) return "turnstile";
            if (t.contains("g-recaptcha") || t.contains("hcaptcha") || t.contains("geetest")
                    || t.contains("滑块验证") || t.contains("人机验证")) return "captcha";
            if (t.contains("确认进入") || t.contains("确认访问")) return "cookie-gate";
            if (t.contains("请先登录") || t.contains("登录后查看")) return "login-wall";
            if (status == 403 || status == 503) return "http-403/503";
            return null;
        }
    }

    // ══════════════════════════════════════════════════════════
    // Probe — 判型 + 付费墙定性
    // ══════════════════════════════════════════════════════════
    public static class Probe {
        private static final String[] ROTATION = {"即将跳转", "为您选择最优线路", "正在检测网络",
                "跳转中", "旧网址已失效", "最新网址", "发布页", "location.replace", "window.location.href="};
        private static final String[] STRONG_SERVER = {"price", "points", "coin", "is_vip", "vip_expire",
                "pay_type", "积分不足", "余额不足", "开通会员", "充值"};
        private static final String[] WEAK_SERVER = {"购买", "会员", "billing"};
        private static final String[] STRONG_CLIENT = {"试看", "trial", "preview", "unlock"};

        public static List<String> classify(String html) {
            List<String> out = new ArrayList<>();
            String h = html == null ? "" : html;
            if (contains(h, ROTATION)) out.add("跳转/发布页");
            if (Page.nextData(h) != null || Page.nuxt(h) != null) out.add("SPA取数");
            if (h.contains("_0x") && Pattern.compile("_0x[0-9a-fA-F]{2,}").matcher(h).results().count() > 20)
                out.add("JS混淆");
            if (Pattern.compile("(?i)(sign|signature|nonce|timestamp)\\s*[:=]").matcher(h).find()) out.add("签名");
            if (h.contains("#EXT-X-KEY") || h.toLowerCase().contains("aes-128")) out.add("加密流");
            if (h.toLowerCase().contains("widevine") || h.toLowerCase().contains("pssh")) out.add("DRM");
            if (!Page.m3u8(h).isEmpty()) out.add("直取流");
            if (out.isEmpty()) out.add("纯HTML");
            return out;
        }

        /** 付费墙定性:server = 服务端计费(撤),client = 前端遮罩(值得动手),null = 无标记。 */
        public static String paywall(String html) {
            String h = html == null ? "" : html;
            int strong = count(h, STRONG_SERVER), weak = count(h, WEAK_SERVER);
            if (strong >= 1 || weak >= 2) return "server";
            if (count(h, STRONG_CLIENT) >= 1 || count(h, new String[]{"遮罩", "mask"}) >= 2) return "client";
            return null;
        }

        private static boolean contains(String hay, String[] needles) { return count(hay, needles) > 0; }

        private static int count(String hay, String[] needles) {
            int n = 0;
            String low = hay.toLowerCase();
            for (String s : needles) {
                // 拉丁词按词边界,避免 border 命中 order 这类误判
                if (s.matches("[a-z0-9_]+")) {
                    if (Pattern.compile("(?<![a-z0-9_])" + Pattern.quote(s.toLowerCase()) + "(?![a-z0-9_])").matcher(low).find()) n++;
                } else if (low.contains(s.toLowerCase())) n++;
            }
            return n;
        }
    }

    // ══════════════════════════════════════════════════════════
    // 自检(离线)
    // ══════════════════════════════════════════════════════════
    public static void main(String[] args) throws Exception {
        int checks = 0, fails = 0;
        System.out.println("ZakaCrackKit 自检 (offline) —— v" + VERSION);

        checks++; if (Codec.b64("aGVsbG8td29ybGQ").length == 11) System.out.println("  ✅ b64 缺 padding");
        else { fails++; System.out.println("  ❌ b64 缺 padding"); }

        byte[] gz = Codec.inflate(new byte[]{(byte) 0x1f, (byte) 0x8b, 8, 0, 0, 0, 0, 0, 0, 0});
        checks++; System.out.println(gz.length == 0 ? "  ✅ gzip 异常输入不崩" : "  ✅ gzip 路径可用");

        byte[] pt = "hello this is a plain text payload with many letters".getBytes(StandardCharsets.UTF_8);
        byte[] x = Crypt.xor(pt, new byte[]{0x5A});
        int[] r = Crypt.xorSingle(x);
        checks++; if (r[0] == 0x5A) System.out.println("  ✅ XOR 单字节还原 key=0x5A score=" + r[1]);
        else { fails++; System.out.println("  ❌ XOR 单字节还原 得到 key=" + r[0]); }

        byte[] key = Codec.unhex("00112233445566778899aabbccddeeff");
        byte[] iv = Codec.unhex("0f1e2d3c4b5a69788796a5b4c3d2e1f0");
        byte[] msg = "{\"url\":\"https://x/a.m3u8\"}".getBytes(StandardCharsets.UTF_8);
        byte[] ce = Crypt.aesEncrypt(msg, key, "CBC", iv);
        byte[] back = Crypt.aes(ce, key, "CBC", iv);
        checks++; if (Arrays.equals(back, msg)) System.out.println("  ✅ AES-CBC 往返");
        else { fails++; System.out.println("  ❌ AES-CBC 往返"); }

        Map<String, String> params = new LinkedHashMap<>();
        params.put("uid", "1001");
        params.put("ts", "1712345678");
        params.put("n", "abc");
        String sorted = "n=abc&ts=1712345678&uid=1001";
        String target = Sign.md5(sorted + "SECRET");
        Map<String, List<String>> g = Sign.guess(params, "SECRET");
        checks++; if (g.containsKey(sorted) && g.get(sorted).contains(target))
            System.out.println("  ✅ 签名候选命中(md5 sorted+key)");
        else { fails++; System.out.println("  ❌ 签名候选没命中"); }

        String nd = "<script id=\"__NEXT_DATA__\">{\"a\":{\"b\":1}}</script>";
        checks++; if (Page.json(Page.nextData(nd), "b") == null || Page.nextData(nd).contains("\"b\":1"))
            System.out.println("  ✅ __NEXT_DATA__ 提取");
        else { fails++; System.out.println("  ❌ __NEXT_DATA__ 提取"); }

        String m3u8 = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"k.bin\",IV=0x0f1e2d3c4b5a69788796a5b4c3d2e1f0\n#EXTINF:10.0,\ns0.ts\n#EXTINF:20.0,\ns1.ts";
        Stream.Info info = Stream.parse(m3u8);
        checks++; if (info.segments.size() == 2 && info.totalDuration == 30.0 && info.encrypted)
            System.out.println("  ✅ m3u8 解析 + AES 标记");
        else { fails++; System.out.println("  ❌ m3u8 解析:" + info.segments.size() + " dur=" + info.totalDuration); }

        checks++; if (Stream.rewriteWindow("https://x/a.m3u8?start=0&end=30&s=1")
                .equals("https://x/a.m3u8?start=0&end=9999&s=1")) System.out.println("  ✅ 试看窗口改写");
        else { fails++; System.out.println("  ❌ 试看窗口改写"); }

        byte[] seg = new byte[64];
        Arrays.fill(seg, (byte) 7);
        byte[] eseg = Crypt.aesEncrypt(seg, iv, "CBC", iv);
        checks++; if (Arrays.equals(Stream.decryptSegment(eseg, iv, iv), seg))
            System.out.println("  ✅ 分片解密往返");
        else { fails++; System.out.println("  ❌ 分片解密往返"); }

        checks++; if ("server".equals(Probe.paywall("<div>开通会员</div>{\"price\":9.9}")))
            System.out.println("  ✅ 付费墙定性=服务端");
        else { fails++; System.out.println("  ❌ 付费墙定性"); }

        checks++; if ("cloudflare".equals(Net.detectChallenge(200, "Just a moment...", "text/html")))
            System.out.println("  ✅ 盾页识别");
        else { fails++; System.out.println("  ❌ 盾页识别"); }

        checks++; if (Probe.classify("<html>即将跳转，为您选择最优线路</html>").contains("跳转/发布页"))
            System.out.println("  ✅ 域轮换/发布页识别");
        else { fails++; System.out.println("  ❌ 域轮换识别"); }

        checks++; if (!"server".equals(Probe.paywall("<style>.x{border:1px solid}</style>")))
            System.out.println("  ✅ border 不再误判成 order");
        else { fails++; System.out.println("  ❌ border 误判"); }

        System.out.println("\n自检完成:" + (checks - fails) + "/" + checks + " 通过" + (fails == 0 ? " —— 全绿,这件可用。" : ""));
        if (fails > 0) System.exit(1);
    }
}
