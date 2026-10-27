# rev-skills 122 技能 · ZAKA 相关度分级

总量:入口 1 + 网关 12 + 原子 109 = 122

- **A 级(直接对应你的业务,要融)**:42 个
- **B 级(参考/备用)**:82 个
- **C 级(与业务无关,仅存档)**:1 个

---

## A 级清单(逐条:为什么对你有用)

### `re-analyze`  [entry]
- **为什么有用**:逆向唯一入口:探针→偏好→分诊→路由状态机。方法论骨架,爬渗线可直接对位
- 体量:正文 118 行 / 参考 11 份(1252 行)

### `re-feedback`  [gateway]
- **为什么有用**:经验反馈元网关:会话复盘/文章扫描→蒸馏脱敏→归域入库。做「自动升级流水线」的正主
- 体量:正文 58 行 / 参考 3 份(89 行)

### `re-anti-analysis`  [gateway]
- **为什么有用**:网关:带壳样本先脱壳再分析
- 体量:正文 202 行 / 参考 0 份(0 行)

### `re-packer-id`  [atomic]
- **为什么有用**:壳识别(节名/熵/导入表/EP)。对应「这站/这App加壳了没」
- 体量:正文 134 行 / 参考 0 份(0 行)

### `re-unpack-simple`  [atomic]
- **为什么有用**:轻壳脱壳
- 体量:正文 106 行 / 参考 0 份(0 行)

### `re-unpack-advanced`  [atomic]
- **为什么有用**:强壳脱壳(VM壳/titan)
- 体量:正文 105 行 / 参考 0 份(0 行)

### `re-deobfuscate`  [atomic]
- **为什么有用**:控制流平坦化/花指令/字符串加密还原
- 体量:正文 126 行 / 参考 0 份(0 行)

### `re-evasion`  [atomic]
- **为什么有用**:反分析对抗(反调试/反虚拟机识别)
- 体量:正文 116 行 / 参考 0 份(0 行)

### `re-cracking`  [gateway]
- **为什么有用**:网关:授权定位→补丁/注册机
- 体量:正文 70 行 / 参考 0 份(0 行)

### `re-license`  [atomic]
- **为什么有用**:授权校验点定位与算法还原
- 体量:正文 121 行 / 参考 2 份(144 行)

### `re-patching`  [atomic]
- **为什么有用**:二进制补丁:失败跳转改成功。对应「破VIP」最小改动
- 体量:正文 113 行 / 参考 0 份(0 行)

### `re-keygen`  [atomic]
- **为什么有用**:注册机:从校验算法逆推生成
- 体量:正文 121 行 / 参考 2 份(120 行)

### `re-drm`  [atomic]
- **为什么有用**:DRM(Widevine/PlayReady)许可证与内容解密。对应「免登入DRM」
- 体量:正文 114 行 / 参考 2 份(276 行)

### `re-protocol`  [gateway]
- **为什么有用**:网关:抓包→协议还原→加密识别→密钥提取
- 体量:正文 67 行 / 参考 0 份(0 行)

### `re-netcap`  [atomic]
- **为什么有用**:抓包与流量还原
- 体量:正文 149 行 / 参考 2 份(154 行)

### `re-proto-rev`  [atomic]
- **为什么有用**:协议逆向:字段/状态机/序列还原
- 体量:正文 141 行 / 参考 0 份(0 行)

### `re-crypto-id`  [atomic]
- **为什么有用**:加密算法识别(从字节特征判 AES/RC4/XOR...)
- 体量:正文 139 行 / 参考 0 份(0 行)

### `re-crypto-keys`  [atomic]
- **为什么有用**:密钥提取与定位
- 体量:正文 124 行 / 参考 0 份(0 行)

### `re-crypto-decrypt`  [atomic]
- **为什么有用**:解密实施与明文恢复
- 体量:正文 120 行 / 参考 0 份(0 行)

### `re-tls`  [atomic]
- **为什么有用**:TLS层分析:截获/解密/指纹
- 体量:正文 137 行 / 参考 0 份(0 行)

### `re-whitebox`  [atomic]
- **为什么有用**:白盒密码学:密钥嵌入在算法里怎么打
- 体量:正文 113 行 / 参考 0 份(0 行)

### `re-mobile`  [gateway]
- **为什么有用**:网关:移动端逆向
- 体量:正文 69 行 / 参考 1 份(11 行)

### `re-apk`  [atomic]
- **为什么有用**:APK 静态逆向:dex/资源/签名/清单
- 体量:正文 134 行 / 参考 2 份(145 行)

### `re-frida`  [atomic]
- **为什么有用**:Frida 动态插桩
- 体量:正文 166 行 / 参考 1 份(224 行)

### `re-frida-script-author`  [atomic]
- **为什么有用**:Frida 脚本编写规范(hook 点/参数改写)
- 体量:正文 122 行 / 参考 2 份(109 行)

### `re-android-native`  [atomic]
- **为什么有用**:Android so 层逆向(原生库/NDK)
- 体量:正文 144 行 / 参考 2 份(72 行)

### `re-android-crypto`  [atomic]
- **为什么有用**:Android 加密审计:定位 App 里的加密实现
- 体量:正文 105 行 / 参考 0 份(0 行)

### `re-hybrid-app`  [atomic]
- **为什么有用**:混合App(WebView/Cordova/RN):桥接层逆向。对应蚂蚁小程序/壳
- 体量:正文 185 行 / 参考 0 份(0 行)

### `re-mobile-pack`  [atomic]
- **为什么有用**:移动端打包/壳(App加固)
- 体量:正文 120 行 / 参考 0 份(0 行)

### `re-managed`  [gateway]
- **为什么有用**:网关:托管代码(Java/JS/.NET/WASM/Electron)
- 体量:正文 62 行 / 参考 0 份(0 行)

### `re-java`  [atomic]
- **为什么有用**:Java 逆向(字节码/反编译/jar)。对应 jar 层与后端逻辑
- 体量:正文 126 行 / 参考 0 份(0 行)

### `re-script-deob`  [atomic]
- **为什么有用**:脚本反混淆(JS/Python 等)。对应「JS 打散了怎么还原」
- 体量:正文 155 行 / 参考 0 份(0 行)

### `re-browser-ext`  [atomic]
- **为什么有用**:浏览器扩展逆向。对应油猴脚本/扩展类站
- 体量:正文 120 行 / 参考 2 份(124 行)

### `re-electron`  [atomic]
- **为什么有用**:Electron 应用逆向
- 体量:正文 170 行 / 参考 0 份(0 行)

### `re-wasm`  [atomic]
- **为什么有用**:WASM 逆向。对应前端把逻辑编进 wasm 的站
- 体量:正文 123 行 / 参考 0 份(0 行)

### `re-binary-core`  [gateway]
- **为什么有用**:网关:二进制核心(反编译/调试/转储)
- 体量:正文 154 行 / 参考 0 份(0 行)

### `re-ghidra`  [atomic]
- **为什么有用**:Ghidra 用法
- 体量:正文 129 行 / 参考 2 份(157 行)

### `re-ida`  [atomic]
- **为什么有用**:IDA 用法
- 体量:正文 119 行 / 参考 2 份(137 行)

### `re-radare2`  [atomic]
- **为什么有用**:radare2/r2 用法
- 体量:正文 145 行 / 参考 2 份(152 行)

### `re-gdb`  [atomic]
- **为什么有用**:GDB 动态调试
- 体量:正文 136 行 / 参考 2 份(177 行)

### `re-memdump`  [atomic]
- **为什么有用**:内存转储取密钥/明文
- 体量:正文 141 行 / 参考 2 份(145 行)

### `re-tracing`  [atomic]
- **为什么有用**:strace/ltrace 系统调用追踪
- 体量:正文 118 行 / 参考 2 份(158 行)

---

## B 级清单

- `re-address-space` [atomic] — > 地址空间换算统一处理：PIE/ASLR 基址确定、RVA/VA 转换、loader offset（固件加载地址 vs 链接地址）、 跨工具地址对齐（Ghidra/angr/frida/gdb）。 触发词：PIE、AS
- `re-ai-attack` [atomic] — > AI 模型安全评估与取证（行为层）：extraction assessment（API 黑盒提取评估）、 fingerprint verification（行为指纹与归属验证）、privacy leakage eva
- `re-ai-model` [atomic] — > AI 模型文件逆向与静态分析：ONNX/PyTorch/Safetensors/TFLite 格式解析、 网络结构还原、权重提取、文件级水印分析（权重 pattern/metadata/tensor hash/emb
- `re-ai-triage` [atomic] — > AI 模型分析第一入口（分流器）：识别输入形态——模型文件走文件层逆向（re-ai-model）、 仅有 API 走行为层评估（re-ai-attack）、恶意行为走恶意分析。 触发词：AI模型分析、AI模型安全、模
- `re-angr` [atomic] — angr 符号执行：符号化输入、求解。触发词：angr、符号执行、自动解题、constraint
- `re-anti-cheat` [atomic] — > 反作弊对抗分析：EAC/BattlEye 驱动、内存校验、检测机制还原。 触发词：反作弊、EAC、BattlEye、内存校验、anti-cheat
- `re-arm` [atomic] — > ARM 架构逆向（非 Android）：Cortex-M/A 向量表、Thumb/ARM 切换、AAPCS 调用约定、位置相关代码重定位、MMIO 外设寄存器交叉。 触发词：ARM、arm32、Cortex-M、Co
- `re-attribution` [atomic] — > 威胁归因方法论：钻石模型、基础设施图谱、置信度分级与归因报告。 触发词：归因、APT、attribution、攻击者身份、基础设施图谱、钻石模型、威胁组织。
- `re-automotive` [atomic] — > 汽车逆向：CAN 总线、ECU 固件、AUTOSAR Classic（RTE/runnable/BSW）与 Adaptive（执行管理/清单）。 触发词：汽车、CAN、ECU、车载、OBD、UDS、AUTOSAR、R
- `re-behavior` [atomic] — > 恶意行为分析：持久化、注入、进程树、文件/注册表、ATT&CK 映射。 触发词：行为分析、持久化、注册表、进程注入、它在干什么
- `re-binaryninja` [atomic] — > Binary Ninja 工作流：MLIL、脚本 API。触发词：Binary Ninja、binaryninja、bn、MLIL
- `re-blockchain` [atomic] — > EVM 智能合约逆向：字节码反编译、漏洞分析。 触发词：智能合约、EVM、Solidity、字节码、合约漏洞、ABI、Solana、Move、BPF
- `re-browser-ext` [atomic] — > 浏览器扩展逆向：权限清单、恶意行为定位、混淆还原、上架审查绕过面。 触发词：浏览器扩展、Chrome扩展、Firefox扩展、恶意扩展、extension。
- `re-console` [atomic] — > 现代主机与复古平台逆向：Switch NSO/NPDM 容器与加密分区、PS4/PS5 ORBIS 结构、SDK 库指纹；复古 ROM 头/卡带格式/存档与 Cheat 码。 触发词：主机逆向、Switch、NSO、
- `re-cpp-abi` [atomic] — > 现代 C++ 二进制逆向：RTTI/异常/虚表恢复、ABI 识别、mangling 解码。 触发词：C++逆向、RTTI、虚表恢复、异常处理、C++ ABI、mangling、C++反编译。
- `re-crash-triage` [atomic] — > 崩溃/漏洞样本分析：确定性复现、ASAN/UBSAN 报告解读、输入最小化 (afl-tmin/cmin)、gdb 回溯定位、rr 录制重放、PoC 产出。 触发词：崩溃、crash、ASAN、UAF、堆溢出、越界、
- `re-ctf` [gateway] — > CTF 实践网关。编排：题型识别 → 简单题直接 [[re-binary-core]] → 需自动化 [[re-angr]]/[[re-z3]] → 混淆 [[re-deobfuscate]]。
- `re-disk-forensics` [atomic] — > 磁盘/文件系统取证：删除恢复、时间线、可疑文件定位。 触发词：磁盘取证、文件系统、删除恢复、时间线、ext4、NTFS
- `re-doc-malware` [atomic] — > 恶意文档分析：PDF/Office 武器化、宏链、文档漏洞利用、载荷提取。 触发词：恶意文档、钓鱼文档、PDF恶意、宏文档、docm、文档漏洞、恶意附件。
- `re-dotnet` [atomic] — .NET CIL 逆向：dnSpy/ILSpy 反编译、de4dot 去混淆、ConfuserEx。触发词：.NET、dnSpy、ILSpy、de4dot、CIL、ConfuserEx
- `re-ebpf` [atomic] — > eBPF 程序逆向与对抗分析：BPF-64 指令集、progs/maps 关联、bpftool 反汇编、跟踪取证/恶意样本/EDR 对抗三用途。 触发词：eBPF、BPF、bpftool、bcc、libbpf、xla
- `re-emulation` [atomic] — > 模拟执行：Unicorn/Qiling 框架。触发词：Unicorn、Qiling、模拟执行、emulate、无硬件运行
- `re-evasion` [atomic] — > 检测规避/EDR 对抗分析：AMSI/ETW 绕过、无文件、lolbin 链。 触发词：规避、evasion、AMSI、ETW、无文件、lolbin、EDR绕过
- `re-exploit` [atomic] — > 利用开发：ROP 链构造、堆利用。 触发词：ROP、堆利用、fastbin、tcache、利用开发、exploit
- `re-fileless` [atomic] — > 无文件恶意软件：内存执行、持久化、PowerShell 链。 触发词：无文件、fileless、内存执行、PowerShell 无文件、注册表持久化
- `re-firmware` [gateway] — > 固件/嵌入式/硬件分析网关。编排：提取 → rootfs → 仿真 → 硬件接口。
- `re-flutter` [atomic] — Flutter/Dart AOT 逆向：libapp.so 快照分区解析、符号还原、Dart VM 动态分析。触发词：Flutter、Dart、libapp.so、AOT snapshot、kernel_blob、flu
- `re-forensics` [gateway] — > 内存取证/威胁情报网关。编排：转储来源 → 内存取证 → 线索提取 → 情报关联。
- `re-format-elf` [atomic] — > ELF 格式解析：ehdr/phdr/shdr、GOT/PLT、init_array、符号恢复。 触发词：ELF、解析so、dynamic section
- `re-format-macho` [atomic] — > Mach-O 格式解析：mach_header、LC_*、segment、dyld 信息。 触发词：Mach-O、解析mac程序、dyld
- `re-format-pe` [atomic] — > PE 格式解析：DOS/NT 头、节表、导入导出、TLS 回调、Rich Header、证书表。 触发词：PE格式、解析exe、section表、Delphi、VB6、vmt、MSVBVM60、RTTI、老程序
- `re-fp-runtime` [atomic] — > 函数式语言运行时逆向（Haskell/OCaml）：闭包/堆对象模型、调用约定、数据流优先策略。 触发词：Haskell逆向、OCaml逆向、GHC RTS、thunk、STG、OCaml runtime、闭包、函数
- `re-fuzzing` [atomic] — > 覆盖率引导模糊测试：AFL++/libFuzzer/honggfuzz、插桩与语料初始化、 afl-fuzz 运行参数、覆盖率(afl-cov)、字典/结构化输入。 触发词：fuzz、模糊测试、AFL、afl-fuz
- `re-fw-emulate` [atomic] — > 固件仿真：QEMU 用户态/全系统。 触发词：仿真、QEMU、firmadyne、跑固件
- `re-fw-extract` [atomic] — > 固件提取与解包：binwalk/unblob、magic 扫描、字节序。 触发词：固件、binwalk、解包固件、firmware、IoT、MCU、8051、AVR、PIC、MSP430、Intel HEX、.hex
- `re-fw-rootfs` [atomic] — > 固件文件系统分析：rootfs、配置、密钥、启动脚本。 触发词：rootfs、文件系统分析、squashfs、cramfs、配置文件
- `re-game` [atomic] — > 游戏逆向：Unity/Unreal、Cheat Engine、Lua 脚本引擎、图形 Shader。触发词：游戏逆向、Unity、Unreal、Cheat Engine、内存修改、反作弊、Lua、LuaJIT、.lu
- `re-go` [atomic] — Go 二进制逆向：符号保留、字符串表、goroutine。触发词：Go、golang、Go二进制、goroutine、go build
- `re-hardware-io` [atomic] — > 硬件接口：JTAG/UART/flash 读取。 触发词：JTAG、UART、串口、flash芯片、硬件提取、逻辑分析仪
- `re-hunting` [atomic] — > 威胁狩猎方法论：假设驱动、遥测源选择、基线对比与验证闭环。 触发词：威胁狩猎、狩猎、hunting、假设驱动、遥测分析、异常检测。
- `re-hw-chip` [atomic] — > 物理层硬件逆向：去封装、裸片分析、探针与 FIB、PCB 电路分析、硬件木马检测。 触发词：芯片逆向、去封装、decapping、PCB、硬件木马、电路分析、裸片、FIB、侧信道、SPA、DPA、故障注入、时钟毛刺、
- `re-hypervisor` [atomic] — > 虚拟化逆向：VT-x/SVM、hypervisor 检测、VMCS/EPT 分析， 以及 Xen / QNX Hypervisor / Jailhouse / ACRN / Bao / Hyper-V·VMBus /
- `re-ics` [atomic] — > 工控协议逆向：Modbus/DNP3/OPC UA。 触发词：工控、ICS、Modbus、DNP3、OPC UA、SCADA、PLC
- `re-imports` [atomic] — > 导入导出表与库指纹：IAT/EAT、DLL/so 指纹、FLIRT 思路。 触发词：导入表、IAT、库指纹、链接了哪些库
- `re-ioc` [atomic] — > IOC 提取与 YARA 规则、报告结构。 触发词：IOC、YARA、写规则、分析报告、hash列表
- `re-ios` [atomic] — > iOS 应用分析：Mach-O、class-dump、越狱环境。 触发词：ios逆向、ipa、class-dump、越狱
- `re-ios-jb` [atomic] — > iOS 越狱逆向环境：越狱检测识别与绕过、tweak 分析与开发。 触发词：越狱、jailbreak、tweak、Theos、LLDB 远程
- `re-iot-proto` [atomic] — > 物联网协议：MQTT/CoAP/BLE/Zigbee；BLE 链路层（广播解析/配对加密）与 NFC/智能卡（ISO14443/APDU/MIFARE）。 触发词：MQTT、CoAP、BLE、Zigbee、物联网协议
- `re-javacard` [atomic] — > Java Card / SIM 卡 applet 逆向：CAP 文件组件解析（规范 12 组件）、CAP 字节码（Java 子集）还原、AID 与安装参数、process(APDU) 分派。 触发词：Java Car
- `re-kernel` [atomic] — > 内核逆向（跨平台）：Windows 驱动（.sys/IRP/SSDT）、Linux 内核模块（.ko/ET_REL/LKM/rootkit）、 macOS KEXT 与 System Extension/Driver
- `re-lldb` [atomic] — > lldb 调试（macOS/iOS）：attach、expr、image。 触发词：lldb、macOS调试、iOS调试
- `re-loader` [atomic] — > 加载器/投放器分析：多层下载、内存加载、模块拼接。 触发词：加载器、loader、dropper、投放器、内存加载、模块拼接
- `re-macos` [atomic] — > macOS 原生应用逆向：App Bundle/签名公证、entitlements、沙箱与 TCC、钥匙串与 Secure Enclave。 触发词：macOS逆向、mac app、entitlements、Secu
- `re-malware` [gateway] — > 恶意软件分析网关。编排：默认沙箱 → 静态初勘 → 行为分析 → C2/协议 → IOC/报告。
- `re-mem-forensics` [atomic] — > Volatility 3 内存取证：进程/内核对象/网络/凭据线索。 触发词：内存取证、Volatility、memdump分析、进程列表、mimikatz线索
- `re-mips` [atomic] — > MIPS 架构逆向与路由器固件分析方法论：延迟槽、$gp 调用约定、大小端判断、httpd 定位。 触发词：MIPS、mipsel、路由器固件、嵌入式、延迟槽、big-endian、大端、小端、httpd、busyb
- `re-mobile-forensics` [atomic] — > 移动设备取证：Android/iOS 备份解析、应用数据提取、删除恢复与时间线。 触发词：移动取证、手机取证、ADB备份、iTunes备份、手机数据提取。
- `re-nim` [atomic] — > Nim 编译产物逆向：运行时识别、NimString 结构、异常与 GC 路径。 触发词：Nim逆向、nim、NimString、NimMain、nim 产物。
- `re-plugin-dev` [atomic] — > Ghidra/IDA 插件开发：脚本→插件工程化。 触发词：插件开发、Ghidra插件、IDA插件、插件工程
- `re-pwn` [atomic] — > CTF pwn 入门：栈溢出、格式化字符串、ret2libc。 触发词：pwn、栈溢出、格式化字符串、ret2libc、ROP、shellcode 注入
- `re-python` [atomic] — > Python 打包/混淆样本分析：PyInstaller/PyArmor/Nuitka/Cython 解包、pyc 版本识别与反编译。 触发词：Python打包、PyInstaller、PyArmor、pyc、pyt
- `re-ransomware` [atomic] — > 勒索软件分析：加密识别、勒索信、解密恢复思路。 触发词：勒索、ransomware、加密文件、勒索信、解密恢复
- `re-riscv` [atomic] — > RISC-V 架构逆向：RV32/RV64、压缩指令（RVC）、gp 相对寻址、ABI 与 ecall 系统调用约定、工具链指纹。 触发词：RISC-V、riscv、RV32、RV64、RVC、压缩指令、ecall、
- `re-rtos` [atomic] — RTOS 结构分析：FreeRTOS/ThreadX/Zephyr/RT-Thread/VxWorks/QNX/RTEMS/NuttX/eCos/µC-OS/SYS-BIOS/SAFERTOS/CMSIS-RTX5/T-
- `re-rust` [atomic] — Rust 二进制逆向：符号、monomorphization、所有权模式。触发词：Rust、rust、Rust二进制、cargo
- `re-sample-acquire` [atomic] — > 样本现场采集（从现象到可用样本）：目标没有独立进程、样本不落盘时，以「异常执行内存 + 到达该内存的执行上下文」为核心定位载体并运行时提取。 覆盖四种观测模型：Windows（VAD/线程/ETW）、Linux（VM
- `re-sandbox` [atomic] — > 沙箱环境搭建（动态分析强制前置）。 触发词：沙箱、隔离环境、firejail、VM快照、安全运行
- `re-sdr` [atomic] — > 射频逆向：信号采集、频谱分析、解调、帧同步与协议恢复、重放。 触发词：SDR、射频、信号分析、解调、RTL-SDR、HackRF、无线协议、遥测。
- `re-shellcode` [atomic] — > Shellcode 分析：提取、解码循环、模拟执行。 触发词：shellcode、shell code、位置无关、解码循环、恶意载荷
- `re-stego` [atomic] — > 隐写术检测与提取：文件尾附加、图片 LSB、音频与其他载体、提取验证。 触发词：隐写、stego、LSB、文件尾附加、隐写提取、图片隐写。
- `re-swift` [atomic] — > Swift 二进制逆向：mangling 解码、协议 witness table、闭包捕获、ObjC 互操作。 触发词：Swift逆向、swiftc、witness table、swift demangle、闭包捕获
- `re-tee` [atomic] — > TEE/TrustZone 逆向：OP-TEE 架构、可信应用（Trusted App）、secure storage、SMC 接口与设备密钥。 触发词：TEE、TrustZone、OP-TEE、可信应用、Trust
- `re-ti` [atomic] — > 威胁情报查询与关联：VT/Any.run/hybrid-analysis、MISP。 触发词：威胁情报、VirusTotal、Any.run、沙箱查询、MISP、样本关联
- `re-triage` [atomic] — > 文件初步勘察：file/哈希(sha256/md5)/熵/strings/架构识别。 触发词：先看看这文件、triage、初勘、这是什么文件、hash
- `re-uefi` [atomic] — > UEFI/BIOS 固件：SEC/PEI/DXE/BDS 阶段判定、DXE 驱动、UEFI 模块、bootkit。 触发词：UEFI、BIOS、DXE、PEI、SEC、PEIM、HOB、bootkit、Secure 
- `re-variant` [atomic] — > 二进制变体/补丁对比：函数匹配、N-day 补丁 diff、变体溯源与相似度分析。 触发词：二进制对比、补丁对比、N-day、变体分析、BinDiff、函数匹配、样本相似。
- `re-vuln` [gateway] — > 漏洞挖掘网关。编排：目标与输入面识别 → 覆盖率引导 fuzzing → 崩溃分析 → 逆向定位 → 报告。
- `re-whitebox` [atomic] — > 白盒加密分析：白盒实现识别、密钥提取。 触发词：白盒、whitebox、白盒加密、密钥隐藏
- `re-windbg` [atomic] — > WinDbg 调试（Windows 用户态+内核）。触发词：WinDbg、windbg、内核调试、kd、!analyze
- `re-x64dbg` [atomic] — > x64dbg 调试（Windows）：attach、断点、Scylla。 触发词：x64dbg、Windows调试、Scylla
- `re-z3` [atomic] — Z3 约束求解：建模、密钥/flag 推导。触发词：z3、约束求解、solver、SMT
- `re-zig` [atomic] — > Zig 编译产物逆向：产物识别、comptime 展开、panic/错误处理路径、C ABI 边界。 触发词：Zig逆向、zig、comptime、zig 产物、panic。

---

## C 级清单(存档无需读)

`re-harmonyos`