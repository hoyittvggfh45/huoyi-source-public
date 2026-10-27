# 冷咖啡 × ENI 通用逆向与安全工作流库

- Use this skill for general reverse engineering and security work: native binaries, APK and mobile targets, firmware, JavaScript and protocol reversing, license and crack analysis, penetration testing, red-team work, EDR and evasion research, game security, API and cloud security, malware analysis, forensics, CTF and scraping workflows.

- This library is fused from the user provided 冷咖啡-ENI合并版 package: the Coldbrew five-blade kit, the ENI skill bundle and the eni-solo variant set. It deduplicates 209 SKILL.md files down to 99 unique skills, and each original is preserved verbatim under `references/<name>/SKILL.ref.md` with its own small supporting files beside it.

- Treat the fused package as a static reference library. Read the matched sub-skill before acting, and work from its text the way the zaka library uses its cards.

## Relation to the zaka skill

- Keep `zaka_one_stop_source_crack_shield` as the specialist whenever the deliverable is a TVBox Python source, a signed or encrypted playback interface, or a Cloudflare shield on a content site. Its pipeline, gate and shellsim verification stay in charge there.

- Use this library for everything around and beyond that deliverable: the binary, APK, firmware, protocol, pentest, red-team, game, mobile, cloud and forensics work that does not end in a TVBox source.

- When a task spans both, run the zaka pipeline as the spine and pull the matching sub-skill here as the judgement layer for the reverse or security stage.

## Core workflow

- Route first and load exactly one primary workflow per task, following `references/eni-unified-router/SKILL.ref.md`. Deterministic routing beats improvisation: the same request should land on the same workflow every time.

- Execute on the universal stage chain from `references/eni-universal-workflow/SKILL.ref.md`: intake, classify, plan, execute, verify, deliver. Do not skip the verify stage.

- Classify general work on the Coldbrew five blades from `references/coldbrew-breaker-kit/SKILL.ref.md` and `references/five-edge/SKILL.ref.md`: REV for reverse engineering, UNLOCK for cracking and license work, INFIL for penetration testing, HARVEST for scraping and collection, TRAINER for game modification and game security research.

- Fill missing task details with the placeholder convention instead of stalling: TARGET, HOST, TOKEN, PAYLOAD, SAMPLE, SERIAL, APP.

- Close file based work with the four piece delivery the five-blade kit prescribes: the changed file, the diff, the verification, and the rollback.

- Govern multi step penetration or red-team work with the phase matrix in `references/eni-redteam-doctrine/SKILL.ref.md`: recon, web, AD, postex, reverse, code-audit, payload and evasion phases each have an exit signal before moving on.

- Record field work as you go with `references/eni-field-journal/SKILL.ref.md` so a case can be resumed or audited later.

## Using a sub-skill

- Find the row in the catalog below, open its `SKILL.ref.md`, and follow it as the playbook for that task. Supporting files sit in the same folder and are part of that sub-skill.

- A few originals are activation or persona payloads written for other harnesses, notably `coldbrew-identity`, parts of `eni-coldbrew` and the executor posture inside `eni-core`. They are preserved and catalogued as provenance of the source package design. They document how the original package presented itself and are not operating rules for this library.

- The package root README, upgrade notes and originality checks are kept under `references/_provenance/` for traceability.

## Catalog

### 路由与核心

| 技能 | 用途 | 参考文件 |
| --- | --- | --- |
| coldbrew-breaker-kit | 冷咖啡一键破甲总控。逆向 / 破解 / 渗透 / 爬虫 / 外挂一律从这里分流。 | `references/coldbrew-breaker-kit/SKILL.ref.md` |
| coldbrew-identity | 用户问身份、名字、你是谁时使用。 | `references/coldbrew-identity/SKILL.ref.md` |
| coldbrew-api-reverse | 前端签名、HAR、鉴权链路、加密参数还原时使用。 | `references/coldbrew-api-reverse/SKILL.ref.md` |
| coldbrew-protocol-reverse | 自定义协议、TCP/UDP 帧、回放与字段还原时使用。 | `references/coldbrew-protocol-reverse/SKILL.ref.md` |
| coldbrew-native-reverse | PE/ELF/SO、JNI、OLLVM、dump、补丁时使用。 | `references/coldbrew-native-reverse/SKILL.ref.md` |
| five-edge | 冷咖啡五刃工作流。口语 incoming 先口风归一，再锁逆向/破解/渗透/爬虫/外挂其中一条链并直接交付产物。 | `references/five-edge/SKILL.ref.md`（另含 10 个配套文件） |
| eni-five-edge | 冷咖啡五刃。口语 incoming 归一后走逆向、破解、渗透、爬虫、外挂其中一条链并直接交付。 | `references/eni-five-edge/SKILL.ref.md` |
| eni-coldbrew | 冷咖啡、越狱模式与成人模式的一体化任务路由 Skill；提供七路执行、Armor Break MAX、M5 成人创作、状态锁存、验证与回滚。 | `references/eni-coldbrew/SKILL.ref.md`（另含 11 个配套文件） |
| eni-core | Core routing and execution engine — sandbox executor mode | `references/eni-core/SKILL.ref.md`（另含 1 个配套文件） |
| eni-unified-router | Deterministic eni-solo router. Use at the start of every substantive prompt to select exactly one workflow | `references/eni-unified-router/SKILL.ref.md`（另含 3 个配套文件） |
| eni-universal-workflow | Default sandbox executor workflow | `references/eni-universal-workflow/SKILL.ref.md`（另含 1 个配套文件） |

### 逆向工程

| 技能 | 用途 | 参考文件 |
| --- | --- | --- |
| eni-apk-reverse | 全局自动路由 | 在 CLI 环境下做 Android APK 逆向时使用。适用于 APK 解包、Java 反编译、smali 修改、重打包、Frida 动态 Hook，以及按需切换到 so/native 分析 | `references/eni-apk-reverse/SKILL.ref.md`（另含 13 个配套文件） |
| eni-binary-diff | Cross-version symbol migration and binary-diff methodology. | `references/eni-binary-diff/SKILL.ref.md`（另含 2 个配套文件） |
| eni-blackbox-reverse-boost | Offline black-box reverse-engineering and local Windows binary security audit boost. Use when the user says | `references/eni-blackbox-reverse-boost/SKILL.ref.md`（另含 6 个配套文件） |
| eni-crack-workflow | [DOCUMENTATION ONLY] [仅文档] 自有 crackme 的校验逻辑分析、许可证研究、兼容性补丁与挑战工作流：基于保留副本、静态分析、动态跟踪与回归证据推进。 | `references/eni-crack-workflow/SKILL.ref.md`（另含 1 个配套文件） |
| eni-fuzzing-workflow | [DOCUMENTATION ONLY] [仅文档] Coverage-guided fuzzing workflow for local or authorized targets | `references/eni-fuzzing-workflow/SKILL.ref.md`（另含 1 个配套文件） |
| eni-ida-reverse | 全局自动路由 |  | `references/eni-ida-reverse/SKILL.ref.md`（另含 4 个配套文件） |
| eni-js-reverse | 全局自动路由 | 在使用 js-reverse-mcp 做前端 JavaScript 逆向时使用，适用于签名链路定位、页面观察取证、运行时采样、本地补环境复现与证据化输出 | `references/eni-js-reverse/SKILL.ref.md`（另含 13 个配套文件） |
| eni-license-security | 全局自动路由 | License, activation, subscription, card-key (卡密), entitlement | `references/eni-license-security/SKILL.ref.md`（另含 7 个配套文件） |
| eni-mobile-reverse | 全局自动路由 | `references/eni-mobile-reverse/SKILL.ref.md`（另含 4 个配套文件） |
| eni-patch-diff-exploit | [DOCUMENTATION ONLY] [???] Patch-diff analysis and controlled N-day research methodology. | `references/eni-patch-diff-exploit/SKILL.ref.md`（另含 4 个配套文件） |
| eni-radare2 | 全局自动路由  | `references/eni-radare2/SKILL.ref.md`（另含 4 个配套文件） |
| eni-reverse-deep | 全局自动路由 | Deep reverse engineering for PE, ELF, Mach-O, firmware, drivers, APK/DEX, .NET, Go, Rust | `references/eni-reverse-deep/SKILL.ref.md`（另含 6 个配套文件） |
| eni-reverse-ref | 全局自动路由 | Provides reverse engineering techniques. Use when the main job is to understand how a compiled | `references/eni-reverse-ref/SKILL.ref.md`（另含 22 个配套文件） |
| eni-reverse-workflow | Deep, evidence-driven reverse engineering workflow for PE, ELF, Mach-O, firmware, drivers, bytecode | `references/eni-reverse-workflow/SKILL.ref.md`（另含 14 个配套文件） |
| eni-reverselab-bridge | 原创外部依赖桥接：把 Open ReverseLab（LING71671/open-reverselab，GPL-3.0）作为可选外部工具链接入本包，不捆绑其任何内容 | `references/eni-reverselab-bridge/SKILL.ref.md` |
| eni-reverselab-platform | Open-source reverse engineering lab: 197-article knowledge base, 43 MCP tools, 5-board signal routing | `references/eni-reverselab-platform/SKILL.ref.md`（另含 575 个配套文件） |
| eni-unpack-reverse-lab | Offline Windows PE packing, unpacking triage, and evidence-backed reverse-engineering workflow. Use when the | `references/eni-unpack-reverse-lab/SKILL.ref.md`（另含 27 个配套文件） |

### 固件、取证与恶意样本

| 技能 | 用途 | 参考文件 |
| --- | --- | --- |
| eni-firmware-pentest | [DOCUMENTATION ONLY] [???] Firmware and IoT extraction, emulation, and assessment methodology. | `references/eni-firmware-pentest/SKILL.ref.md`（另含 4 个配套文件） |
| eni-firmware-workflow | [DOCUMENTATION ONLY] [仅文档] 固件与 IoT 提取、文件系统、服务、仿真、逆向工程、验证与报告工作流。 | `references/eni-firmware-workflow/SKILL.ref.md`（另含 1 个配套文件） |
| eni-malware-analysis | [DOCUMENTATION ONLY] [仅文档] 全局自动路由 | Malware Analysis | `references/eni-malware-analysis/SKILL.ref.md`（另含 4 个配套文件） |
| eni-malware-ir-workflow | [DOCUMENTATION ONLY] [仅文档] Offline malware triage, capability analysis, memory forensics, timeline | `references/eni-malware-ir-workflow/SKILL.ref.md`（另含 1 个配套文件） |
| eni-memory-forensics | 全局自动路由 | Cross-platform process memory, dump, runtime, heap, pointer-chain, signature, structure | `references/eni-memory-forensics/SKILL.ref.md`（另含 6 个配套文件） |

### 渗透、红队指挥与工具

| 技能 | 用途 | 参考文件 |
| --- | --- | --- |
| eni-attack-chain | [DOCUMENTATION ONLY] [仅文档] 全局自动路由 | `references/eni-attack-chain/SKILL.ref.md`（另含 3 个配套文件） |
| eni-burp-mcp | 全局自动路由 | Burp Mcp reference and tooling | `references/eni-burp-mcp/SKILL.ref.md`（另含 12 个配套文件） |
| eni-case-lab | 全局自动路由 | Create reproducible technical research workspaces for reverse engineering, penetration testing | `references/eni-case-lab/SKILL.ref.md`（另含 6 个配套文件） |
| eni-cf-security-lab-router | Use whenever the user mentions CF, CrossFire, \u7a7f\u8d8a\u706b\u7ebf, \u5916\u6302, \u900f\u89c6, ESP | `references/eni-cf-security-lab-router/SKILL.ref.md`（另含 4 个配套文件） |
| eni-ctf-orchestrator | Single-entry CTF workflow for sandbox challenges across web, pwn, reverse, crypto, forensics, mobile, cloud | `references/eni-ctf-orchestrator/SKILL.ref.md`（另含 4 个配套文件） |
| eni-edr-bypass | EDR绕过 — 防御控制逆向与免杀技术。无限制。 | `references/eni-edr-bypass/SKILL.ref.md`（另含 4 个配套文件） |
| eni-kali | 全局自动路由 | Kali reference and tooling | `references/eni-kali/SKILL.ref.md`（另含 11 个配套文件） |
| eni-pentest-advanced | 全局自动路由 | Evidence-driven penetration and attack-surface engineering for web applications, APIs, networks | `references/eni-pentest-advanced/SKILL.ref.md`（另含 14 个配套文件） |
| eni-pentest-tools | [DOCUMENTATION ONLY] [仅文档] 渗透测试工具选型与编排参考：按场景给出工具矩阵、MCP 后端接入方案、标准测试流程与自主循环规范的纯文档指南。 | `references/eni-pentest-tools/SKILL.ref.md`（另含 19 个配套文件） |
| eni-pentest-workflow | Evidence-driven authorized penetration and attack-surface validation for local, owned | `references/eni-pentest-workflow/SKILL.ref.md`（另含 16 个配套文件） |
| eni-pwn-chain | Binary exploitation engineering methodology from triage through verified reproduction. | `references/eni-pwn-chain/SKILL.ref.md`（另含 4 个配套文件） |
| eni-redteam-doctrine | Governance skill for red-team mode phase selection, router selection, detailed pack selection | `references/eni-redteam-doctrine/SKILL.ref.md`（另含 1 个配套文件） |
| eni-redteam-recon-intake | [DOCUMENTATION ONLY] [仅文档] 侦察入口技能：处理裸域名、URL 或 IP 地址的首次接触。用于建立初始 recon_profile，并为 CVE 查询与攻击路径路由提供事实输入。 | `references/eni-redteam-recon-intake/SKILL.ref.md` |
| src-hunter | 全局自动路由 | 实战 SRC / 众测 / Bug bounty 漏洞挖掘工作流 skill | `references/src-hunter/SKILL.ref.md`（另含 82 个配套文件） |

### 红队细节包

| 技能 | 用途 | 参考文件 |
| --- | --- | --- |
| eni-redteam-ad-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内 Active Directory 红队测试的领域路由与边界手册，覆盖 Kerberos 攻击、域内提权、横向移动与 GPO 滥用 | `references/eni-redteam-ad-detail-pack/SKILL.ref.md` |
| eni-redteam-api-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内 API 安全测试的领域路由与边界手册，覆盖 BOLA/IDOR、认证绕过、批量分配、速率限制缺失与 GraphQL 问题 | `references/eni-redteam-api-detail-pack/SKILL.ref.md` |
| eni-redteam-auth-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内认证、授权与会话安全测试的领域路由与边界手册，覆盖密码策略、JWT/token、OAuth 与 MFA 绕过问题 | `references/eni-redteam-auth-detail-pack/SKILL.ref.md` |
| eni-redteam-cache-poison-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内 Web 缓存投毒测试的领域路由与边界手册，覆盖未纳入缓存键的头与参数、缓存欺骗与 CDN 特有行为 | `references/eni-redteam-cache-poison-detail-pack/SKILL.ref.md` |
| eni-redteam-clickjacking-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内点击劫持测试的领域路由与边界手册，覆盖 X-Frame-Options 缺失、CSP frame-ancestors 绕过与拖放劫持 | `references/eni-redteam-clickjacking-detail-pack/SKILL.ref.md` |
| eni-redteam-cloud-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内云安全测试的领域路由与边界手册，覆盖 IAM 错配、存储桶暴露、元数据服务与 Serverless 注入 | `references/eni-redteam-cloud-detail-pack/SKILL.ref.md` |
| eni-redteam-cmdi-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内操作系统命令注入测试的领域路由与边界手册，覆盖直接注入、盲注入、带外回调与参数注入。当任务落入命令注入领域、需要明确范围、证据、转向或退出标准时加载。 | `references/eni-redteam-cmdi-detail-pack/SKILL.ref.md` |
| eni-redteam-code-audit-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内源代码安全审计的领域路由与边界手册，覆盖危险函数追踪、数据流分析、逻辑缺陷检测与依赖审查。当任务落入代码审计领域、需要明确范围、证据、转向或退出标准时加载。 | `references/eni-redteam-code-audit-detail-pack/SKILL.ref.md` |
| eni-redteam-container-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内容器与编排安全测试的领域路由与边界手册，覆盖 Docker 逃逸、Kubernetes 提权、镜像漏洞与服务网格绕过 | `references/eni-redteam-container-detail-pack/SKILL.ref.md` |
| eni-redteam-cors-miscfg-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内 CORS 配置错误测试的领域路由与边界手册，覆盖 Origin 反射、null 源、子域信任与凭据泄露 | `references/eni-redteam-cors-miscfg-detail-pack/SKILL.ref.md` |
| eni-redteam-crypto-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内密码学弱点测试的领域路由与边界手册，覆盖弱算法、填充 oracle、密钥管理错误、不安全随机数与哈希碰撞风险 | `references/eni-redteam-crypto-detail-pack/SKILL.ref.md` |
| eni-redteam-csrf-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内 CSRF 测试的领域路由与边界手册，覆盖令牌绕过、SameSite 绕过与 JSON CSRF | `references/eni-redteam-csrf-detail-pack/SKILL.ref.md` |
| eni-redteam-cve-lookup | [DOCUMENTATION ONLY] [仅文档] CVE 查询与适用性评估技能：将收集到的产品名、版本号与服务指纹匹配到已知漏洞。在 recon_profile 建立后、评估已知 CVE 是否适用于目标时加载。 | `references/eni-redteam-cve-lookup/SKILL.ref.md` |
| eni-redteam-deserialize-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内不安全反序列化测试的领域路由与边界手册，覆盖 Java、PHP、Python、.NET 与 gadget chain 分析 | `references/eni-redteam-deserialize-detail-pack/SKILL.ref.md` |
| eni-redteam-evasion-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内防御规避与绕过测试的领域路由与边界手册，覆盖 WAF 绕过、AV/EDR 规避、日志考量与流量混淆 | `references/eni-redteam-evasion-detail-pack/SKILL.ref.md` |
| eni-redteam-file-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内文件操作漏洞测试的领域路由与边界手册，覆盖路径穿越、任意文件读写与上传、LFI/RFI。当任务落入文件漏洞领域、需要明确范围、证据、转向或退出标准时加载。 | `references/eni-redteam-file-detail-pack/SKILL.ref.md` |
| eni-redteam-injection-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内通用注入测试（SQL 注入之外）的领域路由与边界手册，覆盖 NoSQL、LDAP、XPath 与表达式语言注入 | `references/eni-redteam-injection-detail-pack/SKILL.ref.md` |
| eni-redteam-logic-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内业务逻辑漏洞测试的领域路由与边界手册，覆盖竞态条件、流程绕过、价格篡改、权限逻辑错误与批量操作滥用 | `references/eni-redteam-logic-detail-pack/SKILL.ref.md` |
| eni-redteam-mobile-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内移动应用安全测试的领域路由与边界手册，覆盖不安全存储、证书绑定绕过、组件暴露与二进制逆向。当任务落入移动测试领域、需要明确范围、证据、转向或退出标准时加载。 | `references/eni-redteam-mobile-detail-pack/SKILL.ref.md` |
| eni-redteam-network-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内网络层安全测试的领域路由与边界手册，覆盖暴露服务、协议降级、中间人风险与分段绕过。当任务落入网络测试领域、需要明确范围、证据、转向或退出标准时加载。 | `references/eni-redteam-network-detail-pack/SKILL.ref.md` |
| eni-redteam-open-redirect-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内开放重定向测试的领域路由与边界手册，覆盖参数重定向、meta 或 JavaScript 重定向与 OAuth redirect_uri 滥用 | `references/eni-redteam-open-redirect-detail-pack/SKILL.ref.md` |
| eni-redteam-payload-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内载荷构造与武器化分析的领域路由与边界手册，覆盖 shellcode、文件格式载荷、钓鱼载荷与 staged/stageless 载荷选择 | `references/eni-redteam-payload-detail-pack/SKILL.ref.md` |
| eni-redteam-postex-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内初始访问之后的后渗透测试领域路由与边界手册，覆盖权限提升、持久化、横向移动、数据收集与清理考量 | `references/eni-redteam-postex-detail-pack/SKILL.ref.md` |
| eni-redteam-recon-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内侦察与信息收集的领域路由与边界手册，覆盖子域枚举、端口扫描、目录发现、指纹识别与 OSINT。当任务落入侦察领域、需要明确范围、证据、转向或退出标准时加载。 | `references/eni-redteam-recon-detail-pack/SKILL.ref.md` |
| eni-redteam-reverse-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内逆向工程分析的领域路由与边界手册，覆盖反编译、调试、协议逆向、固件提取与反混淆。当任务落入逆向工程领域、需要明确范围、证据、转向或退出标准时加载。 | `references/eni-redteam-reverse-detail-pack/SKILL.ref.md` |
| eni-redteam-sqli-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内 SQL 注入测试的领域路由与边界手册，覆盖联合查询、盲注、报错注入、堆叠查询与二次注入等变体 | `references/eni-redteam-sqli-detail-pack/SKILL.ref.md`（另含 1 个配套文件） |
| eni-redteam-ssrf-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内 SSRF 测试的领域路由与边界手册，覆盖基础 SSRF、盲 SSRF、协议走私与云元数据访问路径 | `references/eni-redteam-ssrf-detail-pack/SKILL.ref.md` |
| eni-redteam-ssti-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内服务端模板注入测试的领域路由与边界手册，覆盖 Jinja2、Twig、Freemarker、Velocity 与 Thymeleaf 引擎 | `references/eni-redteam-ssti-detail-pack/SKILL.ref.md` |
| eni-redteam-subdomain-takeover-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内子域接管测试的领域路由与边界手册，覆盖悬空 CNAME 记录、NS 接管与 S3、Azure、Heroku 等云服务接管路径 | `references/eni-redteam-subdomain-takeover-detail-pack/SKILL.ref.md` |
| eni-redteam-web-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内通用 Web 应用安全测试的路由与边界手册。作为 Web 测试路由层使用，当攻击面需要分派到更具体的 Web 漏洞技能时加载。 | `references/eni-redteam-web-detail-pack/SKILL.ref.md` |
| eni-redteam-xss-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内跨站脚本测试的领域路由与边界手册，覆盖反射型、存储型、DOM 型、mXSS 与 CSP 绕过变体 | `references/eni-redteam-xss-detail-pack/SKILL.ref.md` |
| eni-redteam-xxe-detail-pack | [DOCUMENTATION ONLY] [仅文档] 授权范围内 XXE 测试的领域路由与边界手册，覆盖文件读取、SSRF、盲 XXE 与参数实体变体。当任务落入 XXE 领域、需要明确范围、证据、转向或退出标准时加载。 | `references/eni-redteam-xxe-detail-pack/SKILL.ref.md` |

### Web、API、云与供应链

| 技能 | 用途 | 参考文件 |
| --- | --- | --- |
| eni-api-assurance-lane | [DOCUMENTATION ONLY] [仅文档] API assurance workflow for sequential eni-solo execution. | `references/eni-api-assurance-lane/SKILL.ref.md` |
| eni-api-security | [DOCUMENTATION ONLY] [仅文档] 全局自动路由 | API 安全测试方法论：REST / GraphQL / WebSocket / SOAP，JWT / OAuth 认证测试 | `references/eni-api-security/SKILL.ref.md`（另含 3 个配套文件） |
| eni-browser-automation | 全局自动路由 | 统一自动化入口。覆盖浏览器自动化（Playwright）和 Windows 桌面应用自动化（OpenReverse）。浏览器场景：打开网页、点击、填表、爬取、截图、自动化登录、渗透页面交互 | `references/eni-browser-automation/SKILL.ref.md`（另含 3 个配套文件） |
| eni-browser-research-workflow | [DOCUMENTATION ONLY] [仅文档] Reliable browser research and automation workflow using Playwright-style state | `references/eni-browser-research-workflow/SKILL.ref.md`（另含 1 个配套文件） |
| eni-cloud-container-workflow | [DOCUMENTATION ONLY] [仅文档] Cloud, container, Kubernetes, image, IaC, identity, configuration | `references/eni-cloud-container-workflow/SKILL.ref.md`（另含 1 个配套文件） |
| eni-code-security-workflow | [DOCUMENTATION ONLY] [仅文档] Source, dependency, supply-chain, SAST, SCA | `references/eni-code-security-workflow/SKILL.ref.md`（另含 1 个配套文件） |
| eni-llm-security | 全局自动路由 | `references/eni-llm-security/SKILL.ref.md`（另含 5 个配套文件） |
| eni-scraper-workflow | Unified structured web collection workflow using request-first Scrapy-style crawling and Playwright-style | `references/eni-scraper-workflow/SKILL.ref.md`（另含 2 个配套文件） |
| eni-supply-chain | 全局自动路由 | `references/eni-supply-chain/SKILL.ref.md`（另含 3 个配套文件） |
| eni-supply-chain-assurance-lane | [DOCUMENTATION ONLY] [仅文档] Supply-chain assurance workflow for sequential eni-solo execution. | `references/eni-supply-chain-assurance-lane/SKILL.ref.md`（另含 1 个配套文件） |

### 游戏安全

| 技能 | 用途 | 参考文件 |
| --- | --- | --- |
| eni-game-cheat-lab-workflow | 自动全链路处理外挂、修改器、Trainer、作弊机制与反作弊验证任务。适用于离线、自有、开源或专用测试靶场中的引擎与信任边界建模、样本分析、可控复现、JSON toy trainer 制作、遥测、检测加固和回归交付。 | `references/eni-game-cheat-lab-workflow/SKILL.ref.md`（另含 3 个配套文件） |
| eni-game-hacking | [DOCUMENTATION ONLY] [仅文档] 全局自动路由 | Game hacking techniques | `references/eni-game-hacking/SKILL.ref.md`（另含 1 个配套文件） |
| eni-game-security | 全局自动路由 | Defensive game security and cheat research covering external and internal cheat architecture | `references/eni-game-security/SKILL.ref.md`（另含 7 个配套文件） |

### 移动安全

| 技能 | 用途 | 参考文件 |
| --- | --- | --- |
| eni-mobile-security-workflow | [DOCUMENTATION ONLY] [仅文档] Android 与 iOS 静态、动态分析工作流：MobSF 式分诊与 Frida 式运行时观测。 | `references/eni-mobile-security-workflow/SKILL.ref.md`（另含 1 个配套文件） |

### 流程与文档

| 技能 | 用途 | 参考文件 |
| --- | --- | --- |
| eni-architecture-workflow | [DOCUMENTATION ONLY] [仅文档] Architecture inventory, component boundaries, data-flow, threat review, diagrams | `references/eni-architecture-workflow/SKILL.ref.md`（另含 1 个配套文件） |
| eni-diagram | 全局自动路由 | generate, refine, validate, and render diagrams from natural language, notes, code snippets | `references/eni-diagram/SKILL.ref.md`（另含 5 个配套文件） |
| eni-docs | 全局自动路由 | Creates task-oriented technical documentation with progressive disclosure. Use when writing READMEs | `references/eni-docs/SKILL.ref.md`（另含 3 个配套文件） |
| eni-field-journal | [DOCUMENTATION ONLY] [仅文档] 全局自动路由 | Field Journal reference and tooling | `references/eni-field-journal/SKILL.ref.md`（另含 32 个配套文件） |
| eni-github-workflow-hub | Official GitHub workflow source catalog and local tool readiness adapter. Use when selecting upstream methods | `references/eni-github-workflow-hub/SKILL.ref.md`（另含 4 个配套文件） |
| eni-software-workflow | [DOCUMENTATION ONLY] [仅文档] Software implementation, debugging, refactoring, testing | `references/eni-software-workflow/SKILL.ref.md`（另含 1 个配套文件） |

### GitHub 增补（2026-10-22）

> 第二轮起融合：从 GitHub 定向搜集逆向技能与工具面后增量并入（star 为 2026-10-22 实测）。各目录内 UPSTREAM.md 记来源与收录范围；与库内已有条目同源或重叠的只取增量，未整包覆盖。第三轮（2026-10-22，抓包/流量捕获分析方向）追加 gh-traffic-capture 一行。

| 技能 | 用途 | 参考文件 |
| --- | --- | --- |
| gh-android-re-skill | APK/XAPK/JAR/AAR 反编译 + HTTP API 提取（SimoneAvogadro，8,252★，Apache-2.0）：反编译前框架指纹分诊、Kotlin metadata 类名恢复、Ktor/Apollo/Koin 现代栈提取、jadx 与 Fernflower 双引擎对比 | `references/gh-android-re-skill/SKILL.ref.md`（另含 references 6 篇、scripts、commands、UPSTREAM.md） |
| gh-p4nda-reverse-skills | 8 个单项逆向技能（P4nda0s，2,307★，MIT）：rev-struct 结构重建、rev-unicorn-debug 模拟调试、rev-u3d-dump IL2CPP、rev-dex-dumper 脱壳、rev-ios-dump 砸壳、rev-idapython、rev-symbol、rev-frida | `references/gh-p4nda-reverse-skills/<技能名>/SKILL.ref.md`（另含 UPSTREAM.md） |
| gh-mobile-re-skill | 移动逆向技能系统（index-login/MobileRE-Skill，209★，MIT）：Frida 反检测 6 阶段 Pipeline、加解密自吐、Dex2C/VMP 路线、内核文件事件监控，附 tools/ Python 工具链与 frida-mobile-security 脚本全套 | `references/gh-mobile-re-skill/frida-mobile-security/SKILL.ref.md`（另含 references 10 篇、tools、UPSTREAM.md） |
| gh-ctf-skills | CTF 增量（ljagiello/ctf-skills，3,497★）：ctf-ai-ml 攻击面（本库原空白）+ 技能环境自举脚本 install_ctf_tools.sh | `references/gh-ctf-skills/ctf-ai-ml/SKILL.ref.md`（另含 scripts、UPSTREAM.md） |
| gh-re-mcp-catalog | 逆向 MCP 工具面选型册（调研综合）：Ghidra 三形态、IDA 官方/旧版、JADX、jshookmcp、Frida 的选型与接入要点；Termux/纯 shell 环境优先 ghidra-rpc | `references/gh-re-mcp-catalog/SKILL.ref.md` |
| gh-skill-design-notes | 技能设计笔记（调研综合）：两层路由、ops 契约、Prerequisites 自举、阶段间 schema 交接、证据链成文规范——改版路由/技法卡/流水线交接时先读 | `references/gh-skill-design-notes/SKILL.ref.md` |
| gh-traffic-capture | 抓包/流量捕获分析技法卡（调研综合）：代理式 mitmproxy/ProxyPin（14,180★）、无 root VPN 式 PCAPdroid（4,957★）、Frida 应用层 r0capture（7,795★）三线选型，tshark/PCAP 与 HAR 分析、抓包 MCP 面（mitmproxy-mcp/WireMCP/mcpcap）；核心工作流为抓包→端点清单→mitmproxy2swagger（9,669★）生成 OpenAPI→重放验证的接口还原链，含 Termux 落地与证书绑定/QUIC/Flutter 坑表 | `references/gh-traffic-capture/SKILL.ref.md`（另含 UPSTREAM.md） |
