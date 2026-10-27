# CF-Ares 过盾术 · tvbox-dev 技能整合包

> 道友须知：此乃「CF-Ares」Cloudflare 对抗框架学习整合包 —— 两阶段过盾范式（curl_cffi 指纹直试 → 懒加载浏览器引擎解 5秒盾/CAPTCHA/Turnstile），整合进 tvbox-dev 技能流水线，供未来遭遇 CF 盾宝穴时启用。

## 一、整合到 tvbox-dev 技能（三步）

### 1. 放置子技能目录
把本包 `cf-ares技能/` 整体拷入 tvbox-dev 技能根下：

```bash
cp -r "cf-ares技能" <技能根>/.skills/tvbox-dev/skills/cf-ares
```

### 2. 放置过盾桥接器
把 `桥接脚本/cf_ares_bridge.py` 拷入 tvbox-dev 的 scripts 目录：

```bash
cp 桥接脚本/cf_ares_bridge.py <技能根>/.skills/tvbox-dev/scripts/
```

### 3. 放置自包含库（可选，推荐）
把 `cf_ares库/` 整个拷到桥接脚本旁（`scripts/cf_ares/`），实现免 pip 自包含：
桥接器自动优先加载本地库目录，未装环境也能跑。

## 二、SKILL.md 追加（铁律 32 · CF-Ares 过盾通道）

```markdown
32. **CF-Ares过盾通道铁律（2026-10-21新增，铁律级·CF挑战站自动启用）**：遭遇Cloudflare 5秒盾/CAPTCHA/Turnstile/JS质询拦截时，铁律23五通道全部失败后（或Turnstile过盾失败），**必须自动启用CF-Ares过盾通道**（`scripts/cf_ares_bridge.py`，两阶段范式：curl_cffi指纹直试→懒加载浏览器引擎解盾→固化cf_clearance Cookie）。**关键设计（两段式）**：开发端过盾→Cookie固化导出→TVBox壳内Spider直接带Cookie访问（chaquo手机端无浏览器，禁止在Spider内跑浏览器引擎）。**使用流程**：①`python3 scripts/cf_ares_bridge.py solve "https://目标站" -o cf_cookies.json`（开发端过盾，自动存Cookie）②Spider `__init__` 或 `init()` 中 `from cf_ares_bridge import cookie_header_for; self.cf_header={"Cookie": cookie_header_for(self.rawSite)}` ③所有请求带 `self.cf_header`（失败回退直连）。**AresClient全自动**：`from cf_ares_bridge import cf_get; r=cf_get(url)` 自动 curl→浏览器→重试。**判定标准**：CF挑战站必须试此通道，Cookie固化后列表/详情/播放全链路可访问，禁止直接判定失败跳过。
```

## 三、四壳 Spider 集成示例（过盾 Cookie 固化）

```python
try:
    from cf_ares_bridge import cookie_header_for, load_cookies
    _CF_HEADER = {"Cookie": cookie_header_for("https://目标站.com")}
except Exception:
    _CF_HEADER = {}

def _get(self, url):
    r = requests.get(url, headers={**self._ua(), **_CF_HEADER}, timeout=25)
    if r.status_code != 200 and _CF_HEADER:
        # Cookie 失效 → 重试过盾
        try:
            from cf_ares_bridge import cf_solve
            cf_solve(url)
            return requests.get(url, headers=self._ua(), timeout=25)
        except Exception:
            return r
    return r
```

## 四、本包结构

```
CF-Ares过盾整合包/
├── 集成说明.md               # 本文档
├── cf-ares技能/              # 子技能（SKILL.md + scripts + references）
│   ├── SKILL.md
│   ├── scripts/detect_cf.py      # CF 挑战检测
│   ├── scripts/test_engine.py    # 引擎自测
│   └── references/               # api / troubleshooting
├── cf_ares库/                # 自包含源码库（免 pip）
│   ├── client.py                 # AresClient（get/solve_challenge/session）
│   ├── engines/                  # curl / selenium / undetected / base
│   └── utils/                    # session / fingerprint
├── 桥接脚本/
│   └── cf_ares_bridge.py         # TVBox 过盾桥接器（solve/get/header 三命令 + 库模式）
└── 示例/
    ├── basic_usage.py            # 基础过盾 GET
    ├── advanced_usage.py         # 引擎/指纹/代理配置
    └── session_management.py     # 会话保存/加载
```

## 五、实测结果（2026-10-21 · Python 3.12）

| 项目 | 结果 |
|------|------|
| pip 安装 | ✅（`pip install .`，依赖：seleniumbase / undetected-chromedriver / curl_cffi） |
| 源码自包含加载 | ✅（`PYTHONPATH=cf_ares库` 免安装导入） |
| curl 引擎过盾（CF 站 javcode.net） | ✅ HTTP 200（零浏览器开销） |
| solve_challenge 显式过盾 | ⚠️ 需 Chrome（无头/有头）；沙箱无直连 Chrome 时提示 WebDriver 失败——用户环境装 Chrome 即可 |
| Cookie 固化复用 | ✅（save/load json，Spider 带 Cookie 头直连） |

## 六、限制与建议

- **浏览器引擎需 Chrome/Chromedriver**：开发端过盾必须装 Chrome；TVBox 壳内（chaquo）**禁止跑浏览器**，一律用固化 Cookie。
- **Cookie 有效期**：cf_clearance 通常 15 分钟~数小时（视站点），Spider 内置失效重过盾逻辑（见第三节示例）。
- **会话管理**：`save_session/load_session`（AresClient 原生）可跨请求复用已验证会话，降低过盾频率。
- **合规**：仅限个人技术研究与自有站点授权测试；遵守目标站 ToS，禁止商用、大规模爬取。

---
⚔️ 技术升级：CF-Ares 两阶段过盾 · 浏览器引擎懒加载 · Cookie 固化两段式 · 免pip自包含
💎 核心价值观：铁律如山 · 质量为魂 · 进化不止 · 道友为尊
📜 免责声明：仅供参考学习，严禁商用贩卖
