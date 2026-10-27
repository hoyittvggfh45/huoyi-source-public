# UPSTREAM — gh-traffic-capture 来源与核实记录

本目录为 2026-10-22 第三轮 GitHub 定向搜集（抓包 / 流量捕获分析方向）的融合产物。技法卡 `SKILL.ref.md` 为助手调研综合、自研成文，非上游原文复制；下表为选型依据与核实状态。star 数均为 2026-10-22 当日打开 GitHub 仓库页实测，未实测的一律标注，不估算、不引用第三方榜单数字。

## 已核实（仓库页实测）

| 仓库 | Star | 许可 | 核实内容 | 收录形态 |
| --- | --- | --- | --- | --- |
| wanghongenpin/proxypin | 14,180 | Apache-2.0 | 仓库页 + README_CN 全文：跨平台 HTTP(S) 抓包、JS 脚本、重写/映射、AES 工具箱、HAR 导入导出、扫码连接；仓库根目录含 SKILL.md（存在已确认，本轮未逐字收录其原文） | 技法卡选型条目（代理路线手机侧首选） |
| emanuele-f/PCAPdroid | 4,957 | GPL-3.0 | 仓库页：无 root VPN 抓包、PCAP 导出与 PCAP-over-IP、HAR 导出；TLS 解密经 PCAPdroid-mitm 插件（基于 mitmproxy）与 SSLKEYLOGFILE | 技法卡选型条目（VPN 路线） |
| r0ysue/r0capture | 7,795 | Apache-2.0 | 仓库页 + README 全文：Frida 应用层通杀、spawn/attach 用法、`-p` 落 PCAP、客户端证书导出、frida 版本搭配、局限（Flutter/WebView/HTTP2·3）；README 标注 2026-03 更新 frida17 支持 | 技法卡选型条目（Frida 路线） |
| alufers/mitmproxy2swagger | 9,669 | MIT | 仓库页 + README 全文：flow/HAR → OpenAPI 3.0、两遍工作流（x-path-templates 的 ignore 编辑）、`--examples`/`--headers` 敏感数据警示、pip 安装 | 技法卡核心工具（还原端） |

## 特性已核、star 未核（卡内已如实标注）

| 项目 | 状态 |
| --- | --- |
| mitmproxy（官方基线工具） | 本轮未取其 star 数；卡内只述功能与文档站，不引数字 |
| mitmproxy-mcp（PyPI 包） | 特性据两条 PyPI 索引摘要（API Discovery、Scraper Bootstrapping、replay_flow 等）；PyPI 页本轮被客户端挑战页拦截，其 GitHub 仓与 star 未核实 |
| WireMCP（0xkoda/WireMCP） | 工具清单据其 MCP 目录页全文（tshark 后端、extract_credentials、URLhaus 查威胁）；star 未核实 |
| mcpcap（mcpcap/mcpcap） | 据 PyPI/目录信息：Python scapy + FastMCP、无 tshark 依赖、PyPI 0.6.0（2025-09）；star 未核实 |
| graftcp（hmgle/graftcp）、apk-mitm | 仅作目录级提及（ptrace 强制代理 / APK 自动去 pinning），本轮未逐仓核实，不引数字 |

## 评估后未收录

- **bx33661/Wireshark-MCP 及 lobehub 上的 zebbern wireshark 技能条目**：检索环节出现来源核查异常信号，未能独立核实其内容与出处，谨慎起见不收录、不引用；PCAP/MCP 选型改以 WireMCP、mcpcap 等可核实条目为准。
- **REA（morluto/rea）**：第三方文章宣称的 star 数（约 113k）与 GitHub Trending 名次未能在本轮以仓库页证实，数字异常，不收录。
- **Reqable / Charles**：闭源商业工具，非 GitHub 仓库；卡内仅作对照提及（其 HAR 导出可喂还原流水线）。

## 纪律执行情况

- 未下载、未执行任何候选仓库的二进制、安装脚本或代码；仅阅读仓库页、README 与文档类文本。
- 本轮只入 coldbrew_eni_one_stop，未改动 zaka 技能。
