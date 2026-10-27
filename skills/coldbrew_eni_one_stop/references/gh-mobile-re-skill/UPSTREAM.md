# 来源说明

- 上游仓库：index-login/MobileRE-Skill（https://github.com/index-login/MobileRE-Skill）
- 融合日期：2026-10-22；融合时 star 约 209，版本 v0.7.0，最近推送 2026-10-21，许可 MIT
- 收录范围：references/ 全部文档（anti-detection、api-reference、unpacking、crypto-hook、behavior-analysis、native-analysis、static-analysis、troubleshooting、articles、_index）、tools/ 全部 .py 工具、frida-mobile-security 技能主文件（SKILL.ref.md）及其 scripts/ 全部 JS（bypass/monitors/templates/utils）、AGENTS.md 与 reverser agent 定义（改名 *.upstream.md）
- 未收录：GetAPKInfo.jar、dex-dumper 预编译二进制、图片资源；其 .kilo/skill/rev-* 四个技能与 P4nda0s/reverse-skills 同源，未重复收录（扩展版在上游）
- 吸收重点：Frida 反检测 6 阶段 Pipeline、加解密自吐、Dex2C/VMP 路线、内核文件事件行为监控、tools/ 的 unpack/dex_rebuilder/cipher_lab/emu 工具链
