# 案例 · AvBox 聚合壳(2026-10)

## 结论一句话
Flutter(Dart AOT)聚合壳,32 站 / 93 路由 / 23 网关节点,全部挂在自己写的私有网关后面;
签名逻辑编译进 Dart 机器码,网关对未过签请求零区分度。**这条路在当前环境不成立**,已按撤退交付。

## 这次真正学到的三条(已固化进技法卡 08)
1. 先判壳:`libapp.so` + `libflutter.so` + 空 dex = Flutter AOT,dex 上耗时间是白费。
2. 先判反馈:23 台节点对任何错请求回同一条 `{"code":400,"msg":"违规请求"}` → 零区分度 → 460 种拼法全是无信息量重复。工具:`tools/gate_probe.py`。
3. 先判值不值:绕开网关后,明文里唯一直连的真源站只有 missav / javdb;missav 三家域都不给内容、javdb 只给磁力 → **破了也没有 TVBox 可播源**。

## 交付物(本目录)
- `avbox_逆向档案.txt`  包体结构 / 模块 / 路由 / 网关节点 / 签名形态 / 已排除方向 / 下一步
- `avbox_probe.py`      网关探测器(签名函数 `make_sign()` 可插拔)
- `routes.json`         93 条路由全集
- `mods.json`           32 个模块名

## 下一步(要真拿下的唯一路径)
找一台内存 ≥8G 的机器跑 blutter:
`python3 blutter.py lib/arm64-v8a ./out` → `grep -r "_generateSign" out/asm/`
把函数体 asm 拿出来,翻译成 Python,填进 `make_sign()`。
