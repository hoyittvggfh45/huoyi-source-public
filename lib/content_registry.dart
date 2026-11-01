import 'content_audio.dart';
import 'content_http.dart';
import 'content_models.dart';
import 'content_py.dart';

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
    ),
  ];

  static List<ContentSource> sourcesFor(ContentSection section) => [
    for (final source in _sources)
      if (source.section == section) source,
  ];

  static List<ContentSource> get allSources => List.unmodifiable(_sources);

  static bool isKnownId(String id) => _sources.any((source) => source.id == id);
}
