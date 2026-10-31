import 'content_audio.dart';
import 'content_http.dart';
import 'content_models.dart';

class ContentRegistry {
  ContentRegistry._();

  static final ContentHttp _http = ContentHttp();

  static final List<ContentSource> _sources = [TingshuwangSource(_http)];

  static List<ContentSource> sourcesFor(ContentSection section) => [
    for (final source in _sources)
      if (source.section == section) source,
  ];

  static List<ContentSource> get allSources => List.unmodifiable(_sources);

  static bool isKnownId(String id) => _sources.any((source) => source.id == id);
}
