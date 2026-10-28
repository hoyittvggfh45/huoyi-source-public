import '../models.dart';

Map<String, Object?> miniappVodJson(Drama drama) {
  final heat = drama.heat;
  final views = drama.views;
  final year = _vodYear(drama.onlineDate);
  return {
    'vod_id': drama.id,
    'vod_name': drama.title,
    'vod_pic': drama.cover,
    'vod_remarks': heat.isNotEmpty ? heat : views,
    'vod_year': year,
    'vod_area': '',
    'vod_lang': '',
    'vod_type': drama.category,
    'vod_content': drama.description,
    'id': drama.id,
    'title': drama.title,
    'cover': drama.cover,
    'description': drama.description,
  };
}

String _vodYear(String onlineDate) {
  if (onlineDate.length >= 4) {
    final head = onlineDate.substring(0, 4);
    if (int.tryParse(head) != null) return head;
  }
  return onlineDate;
}

List<Map<String, Object?>> miniappPlayLines(List<Episode> episodes) {
  final order = <String>[];
  final grouped = <String, List<Map<String, Object?>>>{};
  for (final episode in episodes) {
    final raw = episode.raw;
    final name = _lineName(raw);
    grouped.putIfAbsent(name, () {
      order.add(name);
      return [];
    });
    grouped[name]!.add({'name': episode.title, 'id': episode.id});
  }
  if (order.isEmpty) return [];
  return [
    for (final name in order) {'name': name, 'episodes': grouped[name]!},
  ];
}

String _lineName(Map<String, dynamic> raw) {
  for (final key in ['flag', 'from', 'line']) {
    final value = raw[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return '线路1';
}

Map<String, Object?> miniappDetailJson(DramaDetail detail) {
  final drama = detail.drama;
  final lines = miniappPlayLines(detail.episodes);
  final froms = <String>[];
  final urls = <String>[];
  for (final line in lines) {
    froms.add(line['name'] as String);
    final episodes = line['episodes'] as List<Map<String, Object?>>;
    urls.add(
      [
        for (final episode in episodes) '${episode['name']}\$${episode['id']}',
      ].join('#'),
    );
  }
  final base = miniappVodJson(drama);
  return {
    ...base,
    'vod_actor': '',
    'vod_director': '',
    'vod_play_from': froms,
    'vod_play_url': urls,
    'episodes': [
      for (final episode in detail.episodes)
        {
          'id': episode.id,
          'title': episode.title,
          'number': episode.number,
          'vip': episode.vip,
        },
    ],
  };
}

int miniappPageCount(bool hasMore, int page) {
  return hasMore ? page + 1 : page;
}

bool miniappLooksLikeMedia(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  for (final suffix in [
    '.m3u8',
    '.mp4',
    '.flv',
    '.ts',
    '.mov',
    '.mkv',
    '.webm',
    '.avi',
    '.m4v',
  ]) {
    if (path.endsWith(suffix)) return true;
  }
  return false;
}
