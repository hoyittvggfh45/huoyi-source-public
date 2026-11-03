import 'content_audio.dart';
import 'content_http.dart';
import 'content_legado.dart';
import 'content_lrts.dart';
import 'content_models.dart';
import 'content_py.dart';
import 'midnight_zone.dart';
import 'novel_yckceo_builtins.dart';

class ContentRegistry {
  ContentRegistry._();

  static final ContentHttp _http = ContentHttp();

  static final List<ContentSource> _sources = [
    TingshuwangSource(_http),
    PyContentSource(
      id: 'ximalaya',
      name: '喜马拉雅',
      assetPath: 'assets/audio_spiders/ximalaya.py',
    ),
    PyContentSource(
      id: 'hongguo_audio',
      name: '红果听书',
      assetPath: 'assets/audio_spiders/hongguo.py',
      fixedCategoryId: 'audio',
      fixedCategoryName: '听书',
      filterKey: 'acat',
    ),
    LrtsSource(_http),
    PyContentSource(
      id: 'hsvoice31',
      name: '🔞黄色有声小说',
      assetPath: 'assets/audio_spiders/hsvoice31.py',
    ),
  ];

  static bool midnightActivated = false;

  static final List<ContentSource> _novelBuiltins = [
    PyContentSource(
      id: 'aabook',
      name: '🔞疯情书库',
      assetPath: 'assets/novel_spiders/aabook.py',
      section: ContentSection.novel,
    ),
    PyContentSource(
      id: 'ylxs',
      name: '🔞月亮小说',
      assetPath: 'assets/novel_spiders/ylxs.py',
      section: ContentSection.novel,
    ),
    PyContentSource(
      id: 'cheniyo',
      name: '🔞桃色书屋',
      assetPath: 'assets/novel_spiders/cheniyo.py',
      section: ContentSection.novel,
    ),
    PyContentSource(
      id: 'hwg4',
      name: '🔞黄文阁',
      assetPath: 'assets/novel_spiders/hwg4.py',
      section: ContentSection.novel,
    ),
    PyContentSource(
      id: 'lbwen',
      name: '🔞刘备文',
      assetPath: 'assets/novel_spiders/lbwen.py',
      section: ContentSection.novel,
    ),
    PyContentSource(
      id: 'cjg',
      name: '🔞藏精阁',
      assetPath: 'assets/novel_spiders/cjg.py',
      section: ContentSection.novel,
    ),
    PyContentSource(
      id: 'buliang',
      name: '🔞不良小说网',
      assetPath: 'assets/novel_spiders/buliang.py',
      section: ContentSection.novel,
    ),
    PyContentSource(
      id: 'yinse',
      name: '🔞淫色小说网',
      assetPath: 'assets/novel_spiders/yinse.py',
      section: ContentSection.novel,
    ),
    PyContentSource(
      id: 'ssxxs',
      name: '🔞涩涩小说',
      assetPath: 'assets/novel_spiders/ssxxs.py',
      section: ContentSection.novel,
    ),
    PyContentSource(
      id: 'mhbl',
      name: '🔞漫画部落',
      assetPath: 'assets/novel_spiders/mhbl.py',
      section: ContentSection.novel,
    ),
  ];

  static final List<ContentSource> _novelImports = [];

  static final List<ContentSource> _novelJsonBuiltins = [
    JsonContentSource(
      id: 'biquge7',
      name: '笔趣阁（遇知）',
      assetPath: 'assets/novel_json_sources/biquge7.json',
      section: ContentSection.novel,
    ),
    JsonContentSource(
      id: 'kk169',
      name: '穿越小说（优质）',
      assetPath: 'assets/novel_json_sources/kk169.json',
      section: ContentSection.novel,
    ),
    JsonContentSource(
      id: 'quanwenyuedu',
      name: '免费小说',
      assetPath: 'assets/novel_json_sources/quanwenyuedu.json',
      section: ContentSection.novel,
    ),
    JsonContentSource(
      id: 'rulianshi',
      name: '包容小说',
      assetPath: 'assets/novel_json_sources/rulianshi.json',
      section: ContentSection.novel,
    ),
    JsonContentSource(
      id: 'yueyouxs',
      name: '阅友小说',
      assetPath: 'assets/novel_json_sources/yueyouxs.json',
      section: ContentSection.novel,
    ),
    JsonContentSource(
      id: 'zhulang',
      name: '逐浪小说',
      assetPath: 'assets/novel_json_sources/zhulang.json',
      section: ContentSection.novel,
    ),
  ];

  static void setNovelImports(List<ContentSource> sources) {
    _novelImports
      ..clear()
      ..addAll(sources);
  }

  static List<ContentSource> _baseFor(ContentSection section) {
    return section == ContentSection.novel
        ? [
            ..._novelBuiltins,
            ..._novelJsonBuiltins,
            ...novelYckceoBuiltins,
            ..._novelImports,
          ]
        : [
            for (final source in _sources)
              if (source.section == section) source,
          ];
  }

  static List<ContentSource> sourcesFor(ContentSection section) {
    final base = _baseFor(section);
    if (midnightActivated) return List.unmodifiable(base);
    return List.unmodifiable([
      for (final source in base)
        if (!isAdultSourceName(source.name)) source,
    ]);
  }

  static bool hasHiddenAdultSources(ContentSection section) {
    if (midnightActivated) return false;
    return _baseFor(
      section,
    ).any((source) => isAdultSourceName(source.name));
  }

  static List<ContentSource> get allSources => List.unmodifiable(_sources);

  static bool isKnownId(String id) => _sources.any((source) => source.id == id);
}
