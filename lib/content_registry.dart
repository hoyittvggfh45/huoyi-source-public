import 'content_audio.dart';
import 'content_http.dart';
import 'content_lrts.dart';
import 'content_models.dart';
import 'content_py.dart';
import 'midnight_zone.dart';

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
  ];

  static final List<ContentSource> _novelImports = [];

  static void setNovelImports(List<ContentSource> sources) {
    _novelImports
      ..clear()
      ..addAll(sources);
  }

  static List<ContentSource> _baseFor(ContentSection section) {
    return section == ContentSection.novel
        ? [..._novelBuiltins, ..._novelImports]
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
