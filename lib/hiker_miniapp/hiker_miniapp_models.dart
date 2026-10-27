import 'dart:convert';

import 'hiker_rule_chain.dart';

typedef HikerPlayCallback =
    void Function(String title, List<HikerMiniappEpisode> episodes, int index);

Map<String, dynamic> hikerAsMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return {};
}

String _mapString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null) {
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
  }
  return '';
}

class HikerMiniappCard {
  const HikerMiniappCard({
    required this.title,
    required this.url,
    required this.pic,
    required this.desc,
    required this.tag,
  });

  final String title;
  final String url;
  final String pic;
  final String desc;
  final String tag;

  factory HikerMiniappCard.fromMap(Map<String, dynamic> map) {
    return HikerMiniappCard(
      title: _mapString(map, ['title', 'name']),
      url: _mapString(map, ['url', 'href']),
      pic: _mapString(map, ['pic_url', 'pic', 'img', 'src', 'cover', 'image']),
      desc: _mapString(map, ['desc', 'description', 'note']),
      tag: _mapString(map, ['tag', 'category', 'type']),
    );
  }
}

class HikerDetailItem {
  const HikerDetailItem({
    required this.title,
    required this.colType,
    required this.url,
    required this.img,
    required this.picUrl,
    required this.desc,
    required this.actor,
  });

  final String title;
  final String colType;
  final String url;
  final String img;
  final String picUrl;
  final String desc;
  final String actor;

  String get image => picUrl.isNotEmpty ? picUrl : img;

  bool get isPlayable => isPlayableHikerUrl(url);

  bool get isLineMarker => title.startsWith('播放线路');

  bool get isStillsMarker => title == '本片剧照';

  bool get isTagMarker => title.startsWith('标签：');

  bool get isTextKind =>
      colType == 'text_1' ||
      colType == 'text_center_1' ||
      colType == 'long_text' ||
      colType == 'rich_text';

  factory HikerDetailItem.fromMap(Map<String, dynamic> map) {
    return HikerDetailItem(
      title: _mapString(map, ['title', 'name']),
      colType: _mapString(map, ['col_type']),
      url: _mapString(map, ['url', 'href']),
      img: _mapString(map, ['img']),
      picUrl: _mapString(map, ['pic_url', 'pic']),
      desc: _mapString(map, ['desc', 'description']),
      actor: _mapString(map, ['actor', 'actress']),
    );
  }
}

class HikerMiniappEpisode {
  const HikerMiniappEpisode({
    required this.title,
    required this.url,
    required this.desc,
    required this.img,
  });

  final String title;
  final String url;
  final String desc;
  final String img;

  bool get playable => isPlayableHikerUrl(url);

  factory HikerMiniappEpisode.fromItem(HikerDetailItem item) {
    return HikerMiniappEpisode(
      title: item.title,
      url: item.url,
      desc: item.desc,
      img: item.image,
    );
  }
}

class HikerPlayLine {
  const HikerPlayLine({required this.name, required this.episodes});

  final String name;
  final List<HikerMiniappEpisode> episodes;
}

class HikerMiniappDetail {
  const HikerMiniappDetail({
    required this.items,
    required this.title,
    required this.poster,
    required this.actress,
    required this.synopsis,
    required this.tags,
    required this.lines,
    required this.stills,
    required this.unavailable,
  });

  final List<HikerDetailItem> items;
  final String title;
  final String poster;
  final String actress;
  final String synopsis;
  final List<String> tags;
  final List<HikerPlayLine> lines;
  final List<String> stills;
  final List<HikerMiniappEpisode> unavailable;

  List<HikerMiniappEpisode> get allEpisodes => [
    for (final line in lines) ...line.episodes,
  ];

  List<HikerMiniappEpisode> get playableEpisodes =>
      allEpisodes.where((e) => e.playable).toList();

  factory HikerMiniappDetail.fromResult(
    dynamic result, {
    String fallbackTitle = '',
  }) {
    if (result is String) {
      try {
        return HikerMiniappDetail.fromResult(
          jsonDecode(result),
          fallbackTitle: fallbackTitle,
        );
      } catch (_) {
        return HikerMiniappDetail.empty(fallbackTitle);
      }
    }
    if (result is Map) {
      final map = hikerAsMap(result);
      final data = map['data'];
      if (data is List) {
        return HikerMiniappDetail.fromItems([
          for (final e in data) HikerDetailItem.fromMap(hikerAsMap(e)),
        ], fallbackTitle: fallbackTitle);
      }
      return HikerMiniappDetail.fromMap(map, fallbackTitle: fallbackTitle);
    }
    if (result is List) {
      return HikerMiniappDetail.fromItems([
        for (final e in result) HikerDetailItem.fromMap(hikerAsMap(e)),
      ], fallbackTitle: fallbackTitle);
    }
    return HikerMiniappDetail.empty(fallbackTitle);
  }

  factory HikerMiniappDetail.empty(String title) {
    return HikerMiniappDetail(
      items: [],
      title: title,
      poster: '',
      actress: '',
      synopsis: '',
      tags: [],
      lines: [],
      stills: [],
      unavailable: [],
    );
  }

  factory HikerMiniappDetail.fromMap(
    Map<String, dynamic> map, {
    String fallbackTitle = '',
  }) {
    final title = _mapString(map, ['title', 'name']);
    final poster = _mapString(map, ['pic_url', 'pic', 'img', 'cover', 'image']);
    final actress = _mapString(map, ['actor', 'actress']);
    final synopsis = _mapString(map, ['desc', 'description', 'synopsis']);
    final episodesRaw = map['episodes'];
    final lines = <HikerPlayLine>[];
    if (episodesRaw is List) {
      final eps = [
        for (final e in episodesRaw)
          HikerMiniappEpisode(
            title: _mapString(hikerAsMap(e), ['title', 'name']),
            url: _mapString(hikerAsMap(e), ['url', 'href']),
            desc: _mapString(hikerAsMap(e), ['desc']),
            img: _mapString(hikerAsMap(e), ['pic_url', 'pic', 'img']),
          ),
      ].where((e) => e.title.isNotEmpty && e.url.isNotEmpty).toList();
      if (eps.isNotEmpty) {
        lines.add(HikerPlayLine(name: '在线播放', episodes: eps));
      }
    }
    final stillsRaw = map['stills'];
    final stills = <String>[];
    if (stillsRaw is List) {
      for (final e in stillsRaw) {
        if (e is String && e.trim().isNotEmpty) {
          stills.add(e.trim());
        } else if (e is Map) {
          final image = _mapString(hikerAsMap(e), ['pic_url', 'pic', 'img']);
          if (image.isNotEmpty) stills.add(image);
        }
      }
    }
    return HikerMiniappDetail(
      items: [],
      title: title.isEmpty ? fallbackTitle : title,
      poster: poster,
      actress: actress,
      synopsis: synopsis,
      tags: [],
      lines: lines,
      stills: stills,
      unavailable: [],
    );
  }

  factory HikerMiniappDetail.fromItems(
    List<HikerDetailItem> items, {
    String fallbackTitle = '',
  }) {
    if (items.isEmpty) return HikerMiniappDetail.empty(fallbackTitle);
    var headerIndex = 0;
    for (var i = 0; i < items.length; i++) {
      if (items[i].colType == 'movie_1_vertical_pic_blur' ||
          items[i].image.isNotEmpty) {
        headerIndex = i;
        break;
      }
    }
    final header = items[headerIndex];
    final title = header.title.isEmpty ? fallbackTitle : header.title;
    final poster = header.image;
    final actress = header.actor;
    final synopsisParts = <String>[];
    final tags = <String>[];
    final stills = <String>[];
    final lines = <HikerPlayLine>[];
    final unavailable = <HikerMiniappEpisode>[];
    var lineName = '在线播放';
    var inLines = false;
    var current = <HikerMiniappEpisode>[];
    void flush() {
      if (current.isNotEmpty) {
        lines.add(HikerPlayLine(name: lineName, episodes: current));
        current = <HikerMiniappEpisode>[];
      }
    }

    void addEpisode(HikerDetailItem item) {
      final episode = HikerMiniappEpisode.fromItem(item);
      if (episode.playable) {
        current.add(episode);
      } else if (item.url.isNotEmpty) {
        unavailable.add(episode);
      }
    }

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.isStillsMarker) continue;
      if (item.isLineMarker) {
        flush();
        var name = item.title;
        if (name.startsWith('播放线路：')) {
          name = name.substring(5);
        } else if (name.startsWith('播放线路')) {
          name = name.substring(4);
        }
        lineName = name.trim().isEmpty ? '在线播放' : name.trim();
        inLines = true;
        continue;
      }
      if (item.colType == 'pic_1') {
        if (item.image.isNotEmpty) stills.add(item.image);
        continue;
      }
      if (item.isTagMarker) {
        final raw = item.title.substring(3);
        for (final part in raw.split('·')) {
          final tag = part.trim();
          if (tag.isNotEmpty) tags.add(tag);
        }
        continue;
      }
      if (item.isTextKind) {
        if (item.url.isNotEmpty && (inLines || item.isPlayable)) {
          if (item.title.isNotEmpty) addEpisode(item);
          continue;
        }
        final text = item.desc.isNotEmpty ? item.desc : item.title;
        if (text.isNotEmpty) synopsisParts.add(text);
        continue;
      }
      if (i == headerIndex) continue;
      if (item.title.isEmpty) continue;
      addEpisode(item);
    }
    flush();
    var synopsis = synopsisParts.join('\n');
    if (synopsis.isEmpty && header.desc.isNotEmpty) {
      synopsis = header.desc;
    }
    return HikerMiniappDetail(
      items: items,
      title: title,
      poster: poster,
      actress: actress,
      synopsis: synopsis,
      tags: tags,
      lines: lines,
      stills: stills,
      unavailable: unavailable,
    );
  }
}
