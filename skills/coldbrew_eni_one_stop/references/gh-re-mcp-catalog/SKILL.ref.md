---
name: gh-re-mcp-catalog
description: 逆向工程 MCP 工具面选型册（GitHub 2026-10-22 调研综合）：Ghidra/IDA/JADX/JS/Frida 的 MCP 服务器与非 MCP 自动化形态的选型、接入与适用边界。做工具选型、给 agent 接逆向工具面、或在 Termux/无 GUI 环境规划 Ghidra 自动化时先读本册。
---

# 逆向工程 MCP 工具面选型册

> 本册为助手 2026-10-22 在 GitHub 实测调研后的选型综合（star 为当日 API 实测值），不是上游原文。库内已有：`eni-burp-mcp`（Burp MCP）、`eni-reverselab-platform` / `eni-reverselab-bridge`（Open ReverseLab，含其 MCP 工具面）。本册补的是 Ghidra / IDA / JADX / JS / Frida 五个面。
> 共同边界：这些 server 都要跑在装有对应工具的机器上（用户手机 Termux 或日后其他设备）；本机 VM 不托管 IDA/Ghidra GUI。接入配置以各仓 README 为准，本册只做选型与要点。

## Ghidra 面（三选一，按环境）

| 方案 | 形态 | 选它当 |
| --- | --- | --- |
| LaurieWired/GhidraMCP（11,470★，Apache-2.0，活跃，对应 Ghidra 12.1.4） | 插件 + Python 桥，uvx 一行接入 | 默认基线：只需要反编译、自动改名、列 methods/classes/imports/exports 的常规自主分析 |
| bethington/ghidra-mcp（5,834★，非常活跃） | 200+ 工具，GUI 插件 + headless 双形态，工具懒加载 | 需要批量分析、跨二进制操作、无 GUI 批处理；工具太多时靠 lazy loading 防上下文爆炸 |
| cellebrite-labs/ghidra-rpc（388★，Cellebrite Labs 官方） | **非 MCP**：常驻守护进程 + CLI 返回结构化 JSON，多实例 attach | **Termux/纯 shell 环境的首选**——任何能跑 shell 的 agent 都能驱动；自带类型恢复工作流、BSim 跨版本函数匹配（追 App 更新后的偏移迁移）、SLEIGH 汇编 patch |

## IDA 面

- **基准：HexRaysSA/ida-mcp（1,338★，Hex-Rays 官方）**。需 IDA 9.4+ 与 idalib；`hcli mcp install` 一键装 GUI 插件与各 agent 插件；无插件时 headless 亦可。
- **兼容备选：mrexodia/ida-pro-mcp（13,077★）**。支持 IDA 8.3+ 老版本；其 README 已置顶推荐改用官方版——只有目标环境是老 IDA 时才选它。
- 不走 MCP 的 IDA 工作流见 `gh-p4nda-reverse-skills/rev-idapython`（导出反编译结果喂 AI 的 IDA-NO-MCP 路线）。

## JADX 面（APK 交互深挖）

- **zinja-coder/jadx-ai-mcp（2,928★，活跃，有文档站）**：JADX 插件 + 独立 MCP server，agent 实时读取当前打开的反编译上下文做漏洞分析/代码审查。与 `gh-android-re-skill` 的批量 API 提取互补：一个管批量、一个管交互深挖。
- 备选：jadx-mcp-server（808★）；jadx-headless-mcp（116★，基于 jadx-core 的无头批处理）。

## JS / Web 逆向面

- **vmoranv/jshookmcp（2,059★，当日仍在更新，AGPLv3）**：735 个工具、36 个域，一个 server 覆盖页面 hook、网络捕获、bundle 反混淆、WASM 反汇编、进程插桩。对协议逆向/签名还原最对口。设计要点：search-first 工具发现（不让 schema 淹没模型）——任何大工具集融合都应借鉴。注意 AGPLv3 许可，分发衍生品时留意。

## Frida 面

- dnakov/frida-mcp（459★）：最简 Frida MCP，但 2025-05 后未更新，仅作形态参考，不作主力推荐。
- 实战脚本面优先用库内现货：`gh-mobile-re-skill/frida-mobile-security`（绕过/监控脚本全套）、CreditTone/hooker（5,329★，Frida 安卓工作台：通杀 unpinning 含 boringssl、hook 脚本自动生成、socks5 无感代理；工具本体回上游取）、httptoolkit/frida-interception-and-unpinning（2,323★，HTTP Toolkit 官方拦截+unpinning 脚本集）。

## 选型速决

- 目标是 APK 接口还原：jadx-ai-mcp（交互） + gh-android-re-skill（批量提取） + frida-mobile-security（动态）。
- 目标是原生二进制：有 GUI 机器用 GhidraMCP 基线或 ida-mcp 官方；只有 shell/Termux 用 ghidra-rpc。
- 目标是网页签名/协议：jshookmcp；已在库内的 eni-js-reverse 是流程规范，与之配套。
- 工具数 >50 的 server 一律要求懒加载或 search-first 发现，否则上下文先爆。
