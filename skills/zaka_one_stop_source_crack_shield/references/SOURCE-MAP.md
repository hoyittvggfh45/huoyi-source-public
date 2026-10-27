# 来源映射 · 三包如何融成一条龙

本技能由用户 2026-10-21 上传的三份材料整合而成，原始上传件保留在 `~/workspace/user/files/`。

## 1. zaka-write-source（写源主干）

- 来源 zip: `zaka-_____-_____1__2_xkdg.zip` 内 `zaka-write-source/`
- 落位: `SKILL.md` 五步流水线并入本技能主文件；`tools/` 五件原样；`技法/` 八张卡 → `references/cards/`；`坑总表.md` → `references/pitfalls.md`；`索引/` → `references/index/`；`java/`、`evidence/` 原样保留
- 实测（2026-10-21，本机）: `zaka_crack_kit.py --selftest` 29/29 通过，`gate_probe.py --selftest` 全绿（zero / differentiated / unreachable 三档判定正确）

## 2. 逆向技能包全部合集（判据与深挖库）

- 来源 md: `_____-_______0_2r9t.md`（286 个 md 合并，34,688 行）→ `references/rev-full-collection.md`
- 其中 122 个 library 技能同时以独立文件落在 `references/rev-library/`（276 个文件），原 `SKILL.md` 改名为 `SKILL.ref.md`，避免被误注册成 122 个独立技能，内容未改

## 3. CF-Ares 过盾整合包（破盾通道）

- 来源 zip: `CF-Ares________1_atvf.zip` 内 `CF-Ares过盾整合包/`
- 落位: `cf_ares库/` → `scripts/cf_ares/`（自包含，免 pip 优先加载）；`桥接脚本/cf_ares_bridge.py` → `scripts/cf_ares_bridge.py`；检测/自测脚本 → `scripts/detect_cf.py`、`scripts/test_engine.py`；`示例/` → `scripts/examples/`；`cf-ares技能/references/` + `集成说明.md` → `references/cf-ares/`
- 已知限制: 浏览器引擎需要本机 Chrome/ChromeDriver；`curl_cffi` 未装时 `detect_cf.py` 无法运行，curl 引擎需 `pip install curl_cffi`（或用自包含库路径）；原文实测记录（2026-10-21）为 curl 引擎对 CF 站返回 HTTP 200、Cookie 固化复用可用，本机本次未联网复测目标站
- 融合点: 原集成说明要求接进 tvbox-dev 的「铁律32」，在本技能中改为流水线正式一环——判型命中盾 → CF-Ares 两段式（开发端过盾 + Cookie 固化）→ Spider 只带 Cookie，不在壳内跑浏览器

## 融合口径

判得准 → 能取数就别解算法 → 盾走 CF-Ares 固化通道 → 解完必须真拉一次 → 没到 AUDIT_OK 不算交付；破不开走撤退交付四件套。
