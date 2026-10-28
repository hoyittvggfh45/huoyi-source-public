import 'content_audio.dart';
import 'content_baozimh.dart';
import 'content_copymanga.dart';
import 'content_dongmanla.dart';
import 'content_http.dart';
import 'content_mangadex.dart';
import 'content_models.dart';

class ContentRegistry {
  ContentRegistry._();

  static final ContentHttp _http = ContentHttp();

  static final List<ContentSource> _sources = [
    DongmanlaSource(http: _http),
    MangaDexSource(_http),
    CopymangaSource(_http),
    BaozimhSource(_http),
    TingshuwangSource(_http),
  ];

  static List<ContentSource> sourcesFor(ContentSection section) => [
    for (final source in _sources)
      if (source.section == section) source,
  ];

  static List<ContentSource> get allSources => List.unmodifiable(_sources);

  static bool isKnownId(String id) => _sources.any((source) => source.id == id);
}
