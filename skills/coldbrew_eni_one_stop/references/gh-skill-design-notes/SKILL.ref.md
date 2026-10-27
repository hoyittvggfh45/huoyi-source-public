---
name: gh-skill-design-notes
description: 技能库组织与编排设计笔记（GitHub 2026-10-22 调研综合）：两层路由、ops 契约、环境自举、阶段间结构化交接、证据链成文规范。改版主 SKILL.md 路由、技法卡格式或 zaka 流水线阶段交接时先读本笔记。
---

# 技能设计与编排笔记（GitHub 调研综合）

> 助手 2026-10-22 综合以下上游的设计做法，供本库与 zaka 库日后改版时取用；均为设计层借鉴，不含技法内容本身。
> 出处：zhaoxuya520/reverse-skill（42,936★）、ljagiello/ctf-skills（3,497★）、Fausto-404/ai-mobile-reverse-skills（171★）、LING71671/open-reverselab（1,293★，其平台本体已在库内 eni-reverselab-platform）。

## 1. 两层路由（reverse-skill）

- 快速路由表（MASTER-ROUTING，一屏内命中）+ 完整路由文档（routing.md，按需展开）的两层结构：主 SKILL.md 只放快表，细节下沉，避免路由文件本身膨胀到没人读。
- 配套 README_AI Bootstrap：让 agent 首次进入仓库先读一个自举文件完成环境认知，再进路由。

## 2. Ops 契约（reverse-skill 的 skills/ops/）

- 每个技能除流程外再写一份契约：输入、输出、验收条件三段。现有技法卡普遍缺「验收」的形式化定义；给 zaka 的卡和高频子技能补契约段，是性价比最高的改版动作。

## 3. 环境自举（ctf-skills）

- 每个 SKILL.md 内嵌 **Prerequisites** 段落声明依赖；中央一个 `install_ctf_tools.sh` 支持分组安装、`--dry-run`、`--verify`（实物已收于 `gh-ctf-skills/scripts/`）。
- 对照本库现状：子技能里散记工具版本（如 eni-apk-reverse 的 jadx/apktool 版本），但没有统一自举入口；用户落点是 Termux，自举脚本的价值更高。

## 4. 阶段间结构化交接（ai-mobile-reverse-skills）

- 根总控 Skill（阶段识别/模式/路由/约束）+ 每阶段一个 Agent 文件（静态侦察→流量与代码对齐→SO/JNI 深析→加密与漏洞综合→最小验证 POC→报告交付），阶段产物用 `schemas/` 定义的 JSON/Markdown 格式向下游传递。
- 可直接映射 zaka 流水线：摸站→过门→提取→还原→写源→验真六阶段若各有 schema 交接，长任务断点续跑和子代理接手都会稳得多。

## 5. 证据链成文规范（open-reverselab）

- 每篇技法固定结构：`Scenario → Input signal → Method → Attack chain → MCP tool mapping`——从任意入口信号沿证据链走到结论。
- 适合给现有技法卡改版时作模板：先写「看到什么信号」再写「用什么方法」，比纯步骤列表更抗场景漂移。

## 6. 重型弹药外置（ctf-skills 的组织法）

- PayloadsAllTheThings 这类重型参考以浅克隆外挂，技法文件只留引用 + 少量示例。库体积敏感（本机内存/上下文都紧）时，用「索引在本库、正文在上游」给低频重型内容瘦身。

## 落点小结

- 短期可做：给 zaka 技法卡补 Prerequisites + 验收两段；coldbrew 主 SKILL.md 路由保持一屏快表。
- 中期可做：zaka 六阶段各定义一份交接 schema；大工具面（MCP）统一按 `gh-re-mcp-catalog` 的懒加载原则接入。
