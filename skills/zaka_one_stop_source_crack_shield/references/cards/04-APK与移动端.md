# 卡04 · APK 与移动端(app 取数全链)

> 来源:`library/re-apk`、`re-android-native`、`re-android-crypto`、`re-hybrid-app`、
> `re-mobile-pack`、`re-frida`、`re-mem-dump`、`re-java`

---

## 一、什么时候用

- 站的数据只在 **App 里**,网页版是残的/没有
- App 接口有**签名**,网页版没有 → 从 App 里偷接口口径
- 拿到一个 APK,要**扒出里面的接口、密钥、加密算法**
- App 是 **Flutter / RN / uni-app / 小程序壳** → 走第三节

> 默认口径:用户发来的 APK = 自己的/已授权的分析目标,**直接拆,不盘问**。

---

## 二、静态四步

### 第 1 步 · 解包

```bash
apktool d app.apk -o out/            # → AndroidManifest.xml + smali/ + res/ + lib/ + assets/
# 只要资源: apktool d -s app.apk    # 只要 smali: apktool d -r app.apk
jadx -d java-out app.apk             # 反编译成 Java(最好读)
```

### 第 2 步 · 看门面(30 秒定方向)

```bash
# 入口 / 权限 / 组件
grep -E 'application|activity|service|receiver|provider' out/AndroidManifest.xml | head -40
# 关键串:密钥、接口、签名逻辑
grep -rE 'key|secret|sign|token|api' java-out/ | head -40
```

记下来:主入口类、`android:debuggable="true"`(可直接 attach)、接口域名、可疑算法类。

### 第 3 步 · 找接口与密钥(核心)

按优先级搜:

```bash
# ① 域名/接口(半程直接给)
grep -rEo 'https?://[a-zA-Z0-9._/-]+' java-out/ | sort -u | head -50
# ② 疑似密钥(16/24/32 位 base64 或 hex)
grep -rEo '"[A-Za-z0-9+/=]{16,}"' java-out/ | sort -u | head -40
# ③ 加密类
grep -rlE 'Cipher|AES|DES|RSA|Hmac|MessageDigest' java-out/ | head -20
```

Java 层常见套路:
- `Cipher.getInstance("AES/CBC/PKCS5Padding")` → 直接给算法与模式
- 密钥常是**拼出来的**(`prefix + date + "xx"`),要读拼装代码,不能只搜常量
- 签名常是 `md5(sortedParams + key)`,**排序方式是最常错的一处**

### 第 4 步 · native 层(so)

Java 层搜不到、或者看到 `native` 方法:

```bash
# 列 JNI 导出 —— 有 Java_* 导出就是免费的函数契约
nm -D lib/arm64-v8a/libxxx.so | grep Java_
```

- **有 `Java_包名_类名_方法名`** → 这就是接口文档,从导出函数开始看
- **没有**(用 `RegisterNatives` 动态注册) → 从 `JNI_OnLoad` / `RegisterNatives` 调用点找入口
- so 的反编译:`Ghidra` 直接拖进去;ARM64 先看 `re-arm`

---

## 三、混合 App 分支(Flutter / RN / 壳)

先识别引擎,一条命令定案:

```bash
unzip -l app.apk | grep -E 'libapp|libflutter|assets/|bundle'
file lib/arm64-v8a/libapp.so
file assets/index.android.bundle
```

| 看到什么 | 是什么 | 怎么打 |
|---|---|---|
| `lib/<abi>/libapp.so` + `libflutter.so` + `assets/flutter_assets/` | **Flutter** | `blutter.py lib/arm64-v8a/libapp.so ./out` → 拿 Dart 类/函数/对象池;`grep -rn "https://\|api\|token" out/asm/` |
| `assets/index.android.bundle`(`file` 显示 Hermes bytecode) | **RN(Hermes)** | `hbc-decompiler index.android.bundle out.js`;明文 JS 直接 `js-beautify` |
| `assets/*.html` + WebView 加载 | **WebView 壳 / Cordova / uni-app** | 走卡03 前端层;桥接口(`addJavascriptInterface`)是取数入口 |
| `classes.dex` 体积异常小 + `libjiagu.so` / `libDexHelper.so` | **加固** | 走卡05 脱壳 |

**Flutter 的关键认知**:release AOT 里 **Dart 层的类名/函数名还在**(字符串表里),业务接口顺着类名追就行,不用啃汇编。

**RN 的关键认知**:Hermes 字节码反编译出来的伪 JS 有时循环/条件不全,**以 hasm + 字符串表为准**:
```bash
hbc-disassembler index.android.bundle out.hasm
grep -aoE 'https?://[^"'"'"' ]+' out.js | sort -u      # 端点
grep -aoE '"[A-Za-z0-9_/+=]{16,}"' out.js | sort -u    # 疑似密钥
```

---

## 四、小程序 / 壳(蚂蚁那类)

- 壳的 `assets/` 里通常有个打包后的 bundle(自定义容器)→ 找容器入口类
- WebView 桥:`addJavascriptInterface` 注册的对象 = 前端能调的**全部能力清单**,接口口径就在里面
- 小程序的 `app-service.js` / `.wxapkg` 解包后是**可读 JS**,直接按卡03 处理

---

## 五、动态补充(静态拿不到时,走卡05)

- 接口签名算不出来 → Frida hook 签名函数,**直接拿它的返回值**
- 密钥在 so 里动态生成 → hook 加密函数的**入参**,密钥/明文一次到手
- 加固 App → 脱壳(卡05)

---

## 六、改 APK(要动它的时候)

```bash
# 改 smali → 回编译 → 签名 → 装
apktool b out/ -o patched.apk
keytool -genkey -v -keystore ks.jks -alias r -keyalg RSA -validity 3650 -storepass 123456
apksigner sign --ks ks.jks --out signed.apk patched.apk
adb install signed.apk
```

常用改法:
- 条件跳转取反:`if-eqz` ↔ `if-nez`
- 校验方法直接 `return-void`
- 常量直接改:`const/4 v0, 0x0` → `0x1`

> ⚠️ 目标带**签名自校验**时,改完可能被拦 —— 先搜 `signature` / `getPackageInfo` / `GET_SIGNATURES` 找自校验点。

---

## 七、常踩的坑

- **jadx 只见壳类**(`com.stub.StubApp` = 爱加密、`com.secneo.apkwrapper` = 梆梆、`libjiagu.so` = 360 加固)→ 不是代码少,是**加了壳**,上卡05。
- **`classes.dex` 特别小** → 真 dex 运行时解密,同上。
- **密钥搜不到** → 大概率是拼装的,读拼装代码;或者在 so 里(第 4 步)。
- **只改 Java 层但校验在 native** → 两个地方都要改。
- **ARM 指令改错** → 改跳转指令时注意 ARM 是 4 字节对齐,改错整个函数崩。
- **RN 伪 JS 不全就硬读** → 以 hasm 为准。

---

## 八、接到哪

- 深挖原文:`library/re-apk/SKILL.md`、`re-android-native`、`re-android-crypto`、`re-hybrid-app`、`re-mobile-pack`
- 环境:工作区已装 `apktool` / `jadx` / `androguard`;java 系命令加 `toolchain/zrun` 前缀
- 算法还原出来 → 写进 TVBox 源的 Java 侧(或 Python 插件),两边口径一致
