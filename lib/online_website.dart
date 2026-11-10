import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const String onlineWebsiteSourceId = 'online_website';

const String onlineWebsiteNoMediaMessage = '没有嗅探到可播放的视频地址，该站可能用了加密播放或需要登录';

class OnlineWebsite {
  const OnlineWebsite({
    required this.id,
    required this.name,
    required this.url,
    this.autoMode = true,
    this.pureMode = true,
  });

  final String id;
  final String name;
  final String url;
  final bool autoMode;
  final bool pureMode;

  factory OnlineWebsite.fromJson(Map<String, dynamic> json) => OnlineWebsite(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
    autoMode: json['autoMode'] as bool? ?? true,
    pureMode: json['pureMode'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'autoMode': autoMode,
    'pureMode': pureMode,
  };

  OnlineWebsite copyWith({
    String? name,
    String? url,
    bool? autoMode,
    bool? pureMode,
  }) => OnlineWebsite(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    autoMode: autoMode ?? this.autoMode,
    pureMode: pureMode ?? this.pureMode,
  );

  String get displayName => name.isEmpty ? hostLabel : name;

  String get hostLabel {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? url : host;
  }
}

class OnlineWebsiteStore {
  static const _key = 'online_websites';

  static String newId() => DateTime.now().millisecondsSinceEpoch.toString();

  static Future<List<OnlineWebsite>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final rows = jsonDecode(raw) as List;
      return [
        for (final row in rows)
          if (row is Map)
            OnlineWebsite.fromJson(Map<String, dynamic>.from(row)),
      ].where((item) => item.id.isNotEmpty && item.url.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<OnlineWebsite> items) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }
}

class OnlineWebsiteCard {
  const OnlineWebsiteCard({
    required this.title,
    required this.url,
    this.cover = '',
  });

  final String title;
  final String url;
  final String cover;

  factory OnlineWebsiteCard.fromJson(Map<String, dynamic> json) =>
      OnlineWebsiteCard(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'title': title, 'url': url, 'cover': cover};
}

class OnlineWebsiteEpisode {
  const OnlineWebsiteEpisode({required this.title, required this.url});

  final String title;
  final String url;

  factory OnlineWebsiteEpisode.fromJson(Map<String, dynamic> json) =>
      OnlineWebsiteEpisode(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'title': title, 'url': url};
}

class OnlineWebsiteDetailInfo {
  const OnlineWebsiteDetailInfo({
    this.title = '',
    this.cover = '',
    this.director = '',
    this.actors = '',
    this.description = '',
  });

  final String title;
  final String cover;
  final String director;
  final String actors;
  final String description;

  factory OnlineWebsiteDetailInfo.fromJson(Map<String, dynamic> json) =>
      OnlineWebsiteDetailInfo(
        title: json['title'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
        director: json['director'] as String? ?? '',
        actors: json['actors'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

DramaDetail onlineWebsiteDetail({
  required OnlineWebsite site,
  required String pageUrl,
  required String title,
  required String cover,
  required List<OnlineWebsiteEpisode> episodes,
}) {
  final drama = Drama(
    id: '$onlineWebsiteSourceId:${site.id}:${_stableHash(pageUrl).toRadixString(16)}',
    source: onlineWebsiteSourceId,
    sourceId: site.id,
    title: title.isEmpty ? site.displayName : title,
    cover: cover,
    episodes: episodes.length,
  );
  return DramaDetail(drama, [
    for (var i = 0; i < episodes.length; i++)
      Episode(<String, dynamic>{
        'id': 'ep${i + 1}',
        'title': episodes[i].title,
        'currentEpisode': i + 1,
        'url': episodes[i].url,
      }, i + 1),
  ]);
}
