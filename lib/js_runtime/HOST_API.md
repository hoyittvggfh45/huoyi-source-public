# Hiker 宿主 API 与页面路由骨架（Phase 1）

范围：只新增本目录下的骨架文件，不改树内任何现有文件。
星辰小程序资产尚未到手，本骨架不含任何小程序脚本内容，不虚构规则、字段与地址。

## 文件位置

- `lib/js_runtime/host_api.dart`：宿主 API 骨架
- `lib/js_runtime/miniapp_router.dart`：index／manage／parse 三类页面路由骨架
- `lib/js_runtime/HOST_API.md`：本清单

## 接口清单

| 项 | 类／方法 | 状态 | 说明 |
| --- | --- | --- | --- |
| http | `HostHttp.get`、`HostHttp.post` | 已实现 | Dart `HttpClient` 真实现；返回状态码、正文、原始字节、响应头；默认 30 秒超时；正文另保留原始字节，供 gbk 解码用 |
| crypto-js | `HostCrypto.md5Hex`、`sha1Hex`、`sha256Hex`、`sha512Hex`、`hmacSha1Hex`、`hmacSha256Hex` | 已实现 | 用树内已有 `crypto` 包实现，不新增依赖 |
| gbk 解码 | `HostGbk.decodeBytes`、`decodeWithCharset` | 已实现 | 只读引用树内已有 `lib/legado_gbk.dart` 的 `decodeGbkBytes`／`decodeLegadoBytes`，未改其文件；`gbk`／`gb2312`／`gb18030` 走同一解码路径，其余走 UTF-8 |
| gbk 编码 | `HostGbk.encode` | 占位待定 | 树内 legado_gbk 只有解码、没有编码能力；现抛 `UnimplementedError`，不等资产也能定性为待补，不静默返回错误结果 |
| local | `HostLocal.open`、`getString`／`setString`、`getInt`／`setInt`、`getBool`／`setBool`、`remove`、`keys` | 已实现 | `SharedPreferences` 键值存储；键前缀为 `hiker_host:<namespace>:`，与插件中心 `miniapp:<appId>:` 命名空间分开，避免互相串键 |
| assets | `HostAssets.loadString`、`loadBytes` | 已实现 | `rootBundle` 读应用资产；资产路径布局等资产到了再对 |
| cheerio | `HostCheerio.load`、`select` | 占位待资产 | 树里无 html 解析依赖，Phase 1 不改 `pubspec.yaml`、不新增依赖；现抛 `UnimplementedError`，不等资产不定选择器语义 |
| 聚合入口 | `HostApi.create`、`HostApi.dispose` | 已实现 | 一次组装六项；`dispose` 关闭 http 客户端 |
| 页面路由 | `MiniAppRoute`、`MiniAppRouter.onGenerateRoute`／`push`／`pushNamed`、`MiniAppPageShell`、`MiniAppWebPage` | 路由已实现，执行未接线 | 路由表：`/miniapp/index/<id>`、`/miniapp/manage/<id>`、`/miniapp/parse/<id>`；页面壳用 `webview_flutter`；只有显式传入 `initialUrl` 时才加载 WebView，否则显示“尚未接线”占位页，不实际执行任何小程序 |

## 占位项与原因

1. cheerio 占位：缺 html 解析依赖是事实原因；选型（手写最小解析、还是等接线期评估是否引入依赖）要等真实脚本里实际出现的选择器形态再定，现在写一个假解析只会让后续对账更难。
2. gbk 编码占位：复用对象本身不提供编码，补编码需要另写 GBK 编码表或引入编解码能力，两者都不属于 Phase 1 只新增骨架的范围。
3. QuickJS 接线占位：并行执行人正在写 `lib/js_runtime/js_engine.dart`，接口已固定为 `QuickJsEngine.open(String libPath)`／`eval(String code)`／`dispose()`；本骨架故意不 `import` 该文件，避免在对方文件落地前引入不存在的依赖。接线期再由接线方把 `HostApi` 实例的方法注册进 JS 上下文。

## 参考形态说明

`assets/miniapps/hello`（`manifest.json`＋`index.html`）只是树内插件中心样例：本路由借鉴的是它“清单含 id／name／entry、入口为相对路径”的形态，不把它当 Hiker 脚本、不把它当星辰资产写进骨架，路由里也没有写死该样例的 id。

## 等星辰小程序资产到了再对

- 脚本里真实用到的宿主调用名与返回形态：`fetch`／结果回传／`parseDom` 规则字段是否与本骨架的 `HostHttpResponse`／`HostGbk`／`HostCheerio` 接口一一对应，不对应则改骨架，不改脚本语义去凑。
- cheerio 选择器实际形态：`&&` 链、`@text`／`@href` 这类取字段写法、索引与过滤写法以脚本为准，届时再定最小解析器的覆盖面。
- gbk 编码是否真被脚本用到：用不到则编码占位可长期保留；用到再补。
- local 键命名空间：脚本若自带键名前缀约定，以脚本为准调整 `HostLocal` 的 namespace 入参，不动插件中心存储。
- assets 布局：脚本是放应用资产还是应用文档目录、相对路径基准是什么，以资产交付形态为准。
- 页面分工：index／manage／parse 三类页中哪些走 WebView 壳、哪些走 QuickJS 执行，以脚本结构为准。

## P1 后接线还差什么

1. 在应用路由里注册 `MiniAppRouter.onGenerateRoute`（需改现有入口文件，Phase 1 故意不动，等 KOTV P1 协调人落地后再接）。
2. QuickJS 引擎实例化：`libPath` 的来源与落盘位置、引擎 so 的打包方式由 QuickJS 执行人那侧定；本骨架不替它定路径。
3. 把 `HostApi` 的 http／crypto／gbk／local／assets／cheerio 注册进 JS 全局对象，并定好异步回调与错误透传方式（现骨架方法均为 Dart 侧同步或 Future，未做 JS 桥接）。
4. cheerio 落地：按资产对账结果实现最小解析或引入依赖（引入依赖需改 pubspec，走接线期决策，不在 Phase 1 偷改）。
5. 网络与权限策略：是否沿用插件中心“allowlist＋权限声明”的形态、allowlist 值以什么为准，接线期定；本骨架 http 层本身不做 allowlist。
6. 树侧 analyze 由 KOTV P1 协调人最后统一跑；本任务不跑 `flutter pub get`、不跑 `finish_task.py`、不发频道、不推云。
7. 我方鉴权、中转、源体系、详情 FongMiTV 模式均未动；对方品牌、站源、线路地址、解析器、引擎地址、配对码、密钥材料一律未进树。

## 接线状态（P1 落地后接线批）

- JS 全局注册：`lib/js_runtime/js_bridge.dart`（JsBridge）＋`host_js.dart`（JS 层宿主函数）。已注册：`_http`（缓存同步直返／未缓存走 Promise，`complete` 回调按 `{ok:false,status:500,url}` 失败形）、`windows` 对象（getItem／setItem／getPublicItem／setPublicItem 原始键直通＋`storage0` JSON 包装层）、`windows.http` 链式（fetch／post／request／postRequest／fetchCookie＋success／error／func／headers／start）、`pdfh／pdfa`（经 cheerio 层）、`setResult`（Dart 侧读取）、`getPath`（`hiker://assets/`／`hiker://files/`／`hiker://page/`／`hiker://empty`）、`downloadFile`（Promise＋Dart 落盘）、`_base64`、`fy_bridge_app`（fetch 走文件任务＋log）、`__freejsRequest`、`__lxRequest`、`__lxMd5`（JS 内 MD5）、`__lxRandom`、`__lxMeta`、`__lxAes`（经 CryptoJS bundle，CBC＋PKCS7，key／iv 为 UTF-8 字符串的约定待真实脚本验证）、`__lxRsa`（BigInt＋PKCS#1 v1.5，`(mode, data, nHex, eHex/dHex)` 约定待真实脚本验证）、`global／window／self` 别名。异步模型：规则包在 async 壳内执行，`fetch` 未缓存时返回 Promise，Dart 侧以 `JS_ExecutePendingJob`＋事件循环泵送排空，循环直到规则完成且待处理注册表为空；同步 `fetch` 只对解释器预取的页面生效，未缓存同步调用方拿到的是 Promise（见诚实缺口）。
- http JS 包装层：已实现（见上）。存储补公开区：`HostApi` 增加 `localPublic`（`HostLocal` 第二命名空间）。虚拟路径：`HostPaths`（`hiker://files/` 映射到调用方传入的 `filesDir`，应用侧由 path_provider 提供）。
- cheerio 落地：`assets/js_runtime/cheerio.min.js`（通用库文件）＋`lib/js_runtime/cheerio_js.dart`（CheerioJs.buildInstallScript：module 垫片求值＋`pdfh／pdfa` 规则层），覆盖 tag／#id／.class／后代、`:matches(`／`:not(`／`:contains(`、Text／Html／属性字段、`pdfa` 列表语义；位置伪类随 shipped 库覆盖。
- 海阔规则解释器：`lib/js_runtime/hiker_rule.dart`（规则模型＋归一化＋`fypage／fyclass／fyarea／fyyear／fysort／fyAll／{host}` 代入＋搜索关键词代入＋pages 子页面解析）＋`lib/js_runtime/rule_runner.dart`（preRule 前置执行、`js:` 规则执行框架、`;` 多段规则、items＋字段分类的 `&&` 链解释、搜索源过滤、详情兜底链 sdetail `*` 直通→卡片字段复用→https 外框→明示无详情、章节模型、代理分支）。`js:` 为主路径（111／115 列表规则），`&&` 链为次级路径。
- 卡片渲染：`lib/js_runtime/miniapp_cards.dart`（MovieGrid 三列／两列、TextList、IconGrid、movie_1 族 FongMi 模式详情布局：毛玻璃 hero＋头项＋简介＋选集区，无选集时不显示该区）。
- 模块加载：`%s` 代入与 `__jsEvalReturn` 约定未单独成模块——spider 式模块加载需真实脚本再对，现以规则执行框架＋`fy_bridge_app.fetch` 文件任务覆盖文件加载路径；ES 模块＋动态 `import()` 由引擎原生支持，Job 排空由桥接循环覆盖。
- WebView 本地服务：`lib/js_runtime/miniapp_local_service.dart`（loopback 服务，`/parse` 双 `%s` 代入真实实现＋自有最小解析壳页，`/action`／`/file…`／`/upload`／`/manage/*` 为 honest stub，返回 `{ok:false, error:'not implemented'}`，页面驱动待后续批）；路由已在 `main.dart` 应用入口注册 `MiniAppRouter.onGenerateRoute`，parse 页经本地服务加载。
- QuickJS 引擎实例化与 so 打包：`lib/js_runtime/engine_loader.dart`（Android 上 `DynamicLibrary.open('libquickjs.so')`）；`android/app/src/main/jniLibs/arm64-v8a/libquickjs.so` 已由 NDK 28.2.13676358 交叉编译（ELF 64-bit ARM aarch64）；`abiFilters` 本就只出 arm64-v8a，32 位不另做分支，`build.gradle.kts` 未动；iOS 静态库形态记为缺口（未做）。
- 资产注册：`pubspec.yaml` 增加 `assets/js_runtime/`（cheerio.min.js＋crypto-js.js）；`pubspec.lock` 未动。
- 小程序不带成人标记、不走午夜门禁（用户 02:33 纠正）：解释器与渲染器内无任何成人标记与门禁逻辑；成人标记分组在分析报告中只记结构计数。
