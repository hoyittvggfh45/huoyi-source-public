---
name: gh-traffic-capture
description: 抓包与流量捕获分析技法卡（GitHub 2026-10-22 调研综合）：代理式（mitmproxy / ProxyPin）、VPN 无 root 式（PCAPdroid）、Frida 应用层（r0capture）三条捕获路线选型，tshark / PCAP 与 HAR 分析，抓包 MCP 面（mitmproxy-mcp / WireMCP / mcpcap），以及从抓包还原 API 接口的完整工作流（mitmproxy2swagger 生成 OpenAPI → 重放验证）。写源或逆向前需要摸清目标 App / 站点的真实接口、鉴权与签名头时先读本卡。
---

# 抓包 / 流量捕获分析技法卡

> 本卡为助手 2026-10-22 在 GitHub 实测调研后的选型与工作流综合（star 为当日仓库页实测值，来源明细见同目录 `UPSTREAM.md`），不是上游原文。库内已有：`eni-burp-mcp`（Burp 协作面）、`gh-mobile-re-skill`（Frida 反检测 Pipeline 与流量镜像模板）、`gh-re-mcp-catalog`（逆向 MCP 选型）。本卡补的是此前空白的一段：**把目标的真实流量抓下来，并还原成可重放的接口清单**——这正是写源（zaka 流水线）与协议逆向的上游环节。
> 共同边界：抓包只做观测与还原；签名/加密算法的还原交协议逆向与写源流水线，付费墙类目标按既有口径不碰。
> **用户口径修正（2026-10-22 晚，覆盖本卡默认落点）：用户本地不安装任何抓包工具，抓包由助手自己完成。** 下文 ProxyPin/PCAPdroid「装在用户手机」只作工具知识保留、不再是默认路线。默认走助手方工作台 `~/workspace/capture_lab/`（mitmproxy+日志插件+mitmproxy2swagger+frida-tools，已冒烟验活）：A 档静态提取端点后用 Python 按 App 真实参数重放、流量过我方 mitmdump 自抓；B 档 VM 模拟器实跑（本 VM 无 KVM、2 核 7.7G，仅 x86_64 软件加速，按单尝试）；C 档 apk-mitm/Frida gadget 插桩重打包。硬堵点（真机证明、ARM-only 反模拟器、须用户手机号登录、服务端全封机房出口）如实报，不转嫁用户装工具。

## 一、三条捕获路线（先选路线，再选工具）

| 路线 | 原理 | 代表工具 | 适用 | 代价/前提 |
| --- | --- | --- | --- | --- |
| A. 代理式 | 设备流量走本地代理，代理解密 TLS | mitmproxy、ProxyPin | 网页端、未做证书绑定的 App；要改包/重放/脚本化时首选 | 需装 CA；Android 7+ App 默认不信用户 CA（见坑表）；有 pinning 即全灭 |
| B. VPN 式 | 本地 VPN 接管全流量落 PCAP | PCAPdroid | 无 root 手机抓全量包（含非 HTTP 协议分诊） | 默认只见密文；解密要配它的 mitm 插件（基于 mitmproxy）或导出 SSLKEYLOGFILE |
| C. Frida 应用层 | hook App 的 SSL 读写，明文在加密前/解密后截获 | r0capture | 有 pinning、无视证书的硬骨头 App；要顺带导客户端证书时 | 需 frida-server（root 机或已部署环境）；Flutter/WebView 自研 SSL 不支持 |

选型口诀：**先 A（最省事、能改能重放）→ A 被 pinning 挡转 C → 只想先看清目标在跟谁说话、有哪些协议，用 B 落一份 PCAP 再分析。**

## 二、工具面（star 为 2026-10-22 实测）

### 捕获端

- **ProxyPin**（wanghongenpin/proxypin，14,180★，Apache-2.0）——开源免费的跨平台 HTTP(S) 抓包，Flutter 编写，Windows/Mac/Android/iOS/Linux 全平台。手机扫码连接、多设备同步、移动端 VPN 模式抓包、JS 脚本、请求/响应重写与映射、拦截屏蔽、AES 等加解密工具箱、HAR 导入导出。**用户的落点是安卓手机，ProxyPin 移动端可直接装在本机当抓包端**，是代理路线在手机侧的首选；仓库根目录自带 `SKILL.md`（供 agent 驱动用）。配套生态有把其 CA 装进系统证书的 Magisk 模块（ProxyPinCA）。
- **mitmproxy**（mitmproxy 官方）——代理路线的基线工具：`mitmproxy` 交互 TUI、`mitmweb` 网页界面、`mitmdump` 无头落 flow 文件；脚本化（Python addon）、重放、改包都靠它。抓包→还原流水线的标准落点格式就是它的 flow 文件。文档 docs.mitmproxy.org。
- **PCAPdroid**（emanuele-f/PCAPdroid，4,957★，GPL-3.0）——无 root 安卓抓包：VPN 模式捕获全流量、导出 PCAP、PCAP-over-IP 实时流给 Wireshark、导出 HAR；TLS 解密由其 mitm 插件（PCAPdroid-mitm，基于 mitmproxy）承担，也可导出 SSLKEYLOGFILE 供 tshark 解密。**无 root 时唯一能拿到全量 PCAP 的路线。**
- **r0capture**（r0ysue/r0capture，7,795★，Apache-2.0）——安卓应用层抓包通杀脚本（Frida）：hook 在应用层，无视全部证书校验与绑定，通杀 HTTP/WebSocket/FTP/XMPP/IMAP/SMTP/Protobuf 及各自 SSL 版本与 OkHttp/Retrofit 等主流框架。Spawn `-U -f 包名 -v` / Attach 模式；`-p out.pcap` 直接落 PCAP 供 Wireshark 分析；默认开启收发包函数定位与**客户端证书导出**（Spawn 模式，导出到 /sdcard/Download/，p12 默认密码 r0ysue）；frida-server 开非标端口时用 `-H` 连接。已测安卓 7–16；版本搭配：frida17/安卓16、frida16.5.2/安卓14、frida15.2.2/安卓12。局限（README 明示）：Flutter/WebView/小程序等自研 SSL 暂不支持，HTTP/2、HTTP/3 不完整，默认不支持多进程子进程，建议真机不用模拟器。
- 闭源商业面仅作对照提及：Reqable、Charles（用户若已在用，其 HAR 导出同样可喂下面的还原流水线）。

### 分析端

- **tshark**（Wireshark CLI）——PCAP 分析基线，常用式：
  - 协议分层先看全貌：`tshark -r cap.pcap -q -z io,phs`
  - 会话清单：`tshark -r cap.pcap -q -z conv,tcp`
  - 只抽 HTTP 请求：`tshark -r cap.pcap -Y http.request -T fields -e http.host -e http.request.method -e http.request.uri`
  - 跟随一条流：`tshark -r cap.pcap -q -z follow,http,ascii,0`（TLS 流加 `-o tls.keylog_file:keys.log` 先喂密钥日志）
  - 导出 HTTP 对象（图片/文件）：`tshark -r cap.pcap --export-objects http,./obj`
- **HAR**——浏览器 DevTools、ProxyPin、PCAPdroid 都能导出；是跨工具交换抓包结果的通用格式，也可直接喂 mitmproxy2swagger。

### 抓包 MCP 面（给 agent 驱动时）

- **mitmproxy-mcp**（PyPI 包）——把 mitmproxy 包成 MCP：启停代理、`get_traffic_summary` 流量总览、`inspect_flow` 看单条流（附等价 curl）、`search_traffic` 检索、拦截规则（inject_header / replace_body / block）、`replay_flow` 重放（带 curl-cffi 浏览器 TLS 指纹模拟）、会话变量提取；另有 **API Discovery**（端点归类 → 导出 OpenAPI JSON）与 **Scraper Bootstrapping**（从流量直接生成 curl-cffi 抓取代码）两个直击接口还原的功能。（注：本轮其 GitHub 仓与 star 未能核实，特性据 PyPI 索引摘要，见 UPSTREAM.md。）
- **WireMCP**（0xkoda/WireMCP，MIT）——Node + tshark 的 MCP：`capture_packets` 实时抓包、`get_summary_stats` 协议统计、`get_conversations` 会话、`analyze_pcap` 离线分析、`extract_credentials` 从 PCAP 扫明文凭据（HTTP Basic/FTP/Telnet）、`check_threats` 用 URLhaus 查 IOC。偏取证/威胁狩猎向。
- **mcpcap**（mcpcap/mcpcap，MIT）——Python（scapy + FastMCP）实现，**不依赖 tshark**，纯 Python 可跑；Termux 这类装 tshark 吃力的环境优先考虑它做 PCAP 的 MCP 化分析。

### 还原端

- **mitmproxy2swagger**（alufers/mitmproxy2swagger，9,669★，MIT）——**本卡核心工具**：把 mitmproxy flow 文件或 HAR 自动转成 OpenAPI 3.0 规范，即「跑一遍 App、抓下流量、接口文档就出来了」。`pip install mitmproxy2swagger`。两遍工作流：第一遍生成带 `x-path-templates` 的骨架（每条路径默认 `ignore:` 前缀），人工去掉想保留端点的 `ignore:` 并修路径参数（如把具体 id 折成 `{id}`），第二遍生成完整端点描述；可对多份抓包重复运行合并进同一 schema。细节注意：`--examples` / `--headers` 会把真实样例与头写进 schema，可能带 token 等敏感数据，交付前必须脱敏（见坑表）。

## 三、抓包 → 接口还原流水线（主用例）

1. **选路线抓全程**：按第一节选路线，把目标业务动作完整走一遍——登录、首页/列表、详情、播放或核心动作、搜索、翻页——每类动作分开时段操作，便于事后按时间切分流量。网页端目标优先浏览器 DevTools 直接导 HAR，最省事。
2. **落标准格式**：代理路线落 mitmproxy flow 文件；VPN/Frida 路线落 PCAP；已有工具只给 HAR 也行。三者都可进下一步。
3. **端点清单**：按 host + method + 路径模板归类，数字/UUID 路径段折叠为 `{id}`；剔除统计打点、广告、CDN 静态资源等噪声域名，先得到「目标 API 全景」。
4. **鉴权与会话分析**：逐端点标注 Authorization / Cookie / 签名头 / 时间戳 / nonce，区分三类：静态头（固定字符串）、会话变量（登录换取的 token，需记录换取流程）、算法签名（需还原算法——交协议逆向处理，本卡只负责定位到「哪个头、随什么变」）。
5. **生成 OpenAPI**：`mitmproxy2swagger -i <flow或har> -o api.yaml -p <API 前缀>` 两遍法（见第二节还原端）；或用 mitmproxy-mcp 的 API Discovery 直接导出。
6. **重放验证**：逐端点脱离 App 重放（curl-cffi 带浏览器 TLS 指纹，或 mitmproxy-mcp 的 `replay_flow`），响应与抓包一致才算还原成功；重放不过先查会话变量是否过期、签名头是否漏项，不要急着判定接口不可用。
7. **交棒**：端点清单 + OpenAPI + 重放证据交给写源流水线（zaka 技能）落成 TVBox 源，或交给协议逆向继续啃签名。抓包产物（flow/HAR/PCAP）按工作目录归档备查，含凭据的先脱敏再出工作目录。

## 四、Termux / VM 落地要点

- **手机本机就是抓包端**：ProxyPin（安卓版）或 PCAPdroid 直接装在用户手机上抓本机 App 流量，产物（HAR / PCAP）再进 Termux 或 VM 分析——不需要电脑中转。
- **Termux 内**：`pip install mitmproxy mitmproxy2swagger`（mitmproxy 依赖较重，预留空间与时间；本机 VM 受 PEP-668 限制，用工作目录 venv 装）。tcpdump 需 root 才有意义，无 root 时以 PCAPdroid 导出的 PCAP 为准；tshark 在 Termux 上包重且未必顺畅，装不上时退纯 Python 的 mcpcap/scapy，或把 PCAP 拷到 VM 用 tshark 分析。
- **Frida 路线**：r0capture 的 Python 端可跑在 Termux（`pip install frida-tools`，版本必须与设备端 frida-server 严格对齐，按安卓版本选 frida 大版本，见第二节搭配表）；frida-server 本身需 root 设备或已部署环境。无 root 且目标有 pinning 时的退路：代理/VPN 路线 + 改包去 pinning（apk-mitm 类工具自动 patch APK 的 networkSecurityConfig 与常见 pinning 代码，无需 Frida）。
- **VM 侧技巧**：目标程序不认代理环境变量时，可用 graftcp（ptrace 强制任意 Linux 程序的 TCP 走代理）把流量逼进 mitmproxy；抓本机浏览器/脚本流量则直接给进程设 HTTP(S)_PROXY 最省事。

## 五、坑表

| 坑 | 现象 | 解法 |
| --- | --- | --- |
| Android 7+ 不信用户 CA | 装了代理 CA 仍抓不到 App 的 HTTPS，只见 CONNECT | 把 CA 升为系统证书（root/Magisk，如 ProxyPinCA、MoveCertificate 类模块），或改走 Frida 应用层路线 |
| 证书绑定（pinning） | 代理一开 App 就断网/报错 | 不要在代理路线硬耗：转 r0capture（明文在加密前后截获），或按 `gh-mobile-re-skill` 的 Frida 流程先脱 pinning |
| Flutter / WebView 自研 SSL | 系统代理无效、r0capture 也抓不到 | 先试 ProxyPin（对 Flutter 场景有专门处理）；仍不行转静态逆向找接口定义（`gh-android-re-skill`），抓包只作旁证 |
| QUIC / HTTP3 | 只有 UDP 443 流量，代理侧全盲 | 阻断目标 App 的 UDP 443 逼其回落 TCP/TLS；或应用层 hook |
| App 检测代理 / VPN | 检测到系统代理或 VPN 标志后拒绝服务 | Frida 层抓包最隐蔽；frida-server 改非标端口并用 r0capture `-H` 连接，降低被扫端口发现的概率 |
| 抓包产物含凭据 | flow / HAR / PCAP 与 mitmproxy2swagger 的 `--examples`、`--headers` 输出含真实 token、Cookie、密码 | 出工作目录前脱敏；schema 交付版删除 examples；抓包文件按敏感材料管理，不外发、不进公开仓 |
| 盾站 clearance 误用 | 抓包里看到浏览器请求就以为能复刻 | cf_clearance 与 UA + 出口 IP 绑定，复用铁律见 zaka 技能卡 09 与 pitfalls，本卡不重复 |

## 六、与库内其他条目的分工

- 抓到流量后的**改包/重放/接口安全测试**：`eni-burp-mcp`（Burp 面）与红队 API 细目包。
- Frida **反检测、脱壳、加解密自吐**：`gh-mobile-re-skill`；本卡的 r0capture 只管「把明文流量截下来」。
- **签名/加密算法还原**：协议逆向相关条目与 zaka 流水线；本卡流水线第 4 步只定位签名头与变化规律。
- **从接口清单落成 TVBox 源**：zaka_one_stop_source_crack_shield（写源 + shellsim 验证 + 推送规范）。
