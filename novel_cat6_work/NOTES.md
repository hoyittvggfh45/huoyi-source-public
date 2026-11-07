# 6 小说源分类 + 封面 + 18+ 标签审计（2026-11-07）

## 实测结论
- 宿主 categories 动作：6 源修前全部已返回非空分类（nnhanman 3、jywx2 11、55comics 4、kmh001 3、csmanhua 20、kxmanhua 6）。
  唯一手机侧可见缺陷：kmh001 的“最新”type_id 为空串，content_py.dart 会跳过空 id，手机上只剩 2 个分类。
  已修：type_id 改为 all，categoryContent 内 all 映射回空 status 调接口。
- 现网出卡（本机出口实测）：nnhanman 全部/已完结各 18 卡、jywx2 两分类各 20 卡、55comics 韩漫/日漫各 20 卡、kxmanhua 全部/韩漫各 24 卡。
  kmh001 / csmanhua 本机出口 TCP 不通（curl 超时），蜘蛛级出卡未验；kmh001 的 API 与首页经另一路现取证实存活且接口结构与蜘蛛解析一致，
  csmanhua 首页 81 天前缓存证实站存在、分类页现取回 520，未能证实当前可达。
- 封面：kxmanhua 修前列表与详情封面恒为空，站上有 data-setbg 封面，已改取封面并现网复验通过；jywx2 站上确实无封面
  （列表行无 img、详情页唯一 img 是广告图），不硬编假图；其余 4 源代码本就取封面，nnhanman/55comics 现网验过，kmh001 按真实接口结构离线验过解析，csmanhua 未验。
- 18+ 标签：6 源全成人，无待定；登记名修前已全带 🔞（未动）；蜘蛛 getName 修前全缺，修后全补 🔞 前缀。

## 改动文件（只改 6 个 py，未动 Dart、未推仓、未构建、未升版）
- assets/novel_spiders/kxmanhua.py：列表取 data-setbg 封面；详情取 anime__details__pic 封面；getName 加 🔞。
- assets/novel_spiders/kmh001.py：最新分类 id '' 改 all 并映射回空 status；getName 加 🔞。
- assets/novel_spiders/nnhanman.py、jywx2.py、55comics.py、csmanhua.py：仅 getName 加 🔞。

## 验证
- novel_cat6_work/verify_cat6.py：21 项全过（分类、🔞 名、开心看漫画离线真页 24 卡全带封面 + 详情封面、K漫画离线真接口结构解析 + all 映射）。
- 现网复验：kxmanhua 列表与详情封面均为真（probe_live.log 末尾）。
- Flutter 单测：content_registry / novel_zone / builtin_py_sites / content_zone_binding 共 53 过 2 败；
  2 败均为 content_registry_test.dart 里“听书”期望未跟上另一人做的“飞卢听书”改名（与本批无关，本批未动 Dart；小说区成人隐藏测试通过）。
- flutter analyze：本批未改 Dart 文件，按任务口径不跑。
