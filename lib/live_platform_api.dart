import 'dart:convert';

import 'live_models.dart';

const _bilibiliCategories = <LivePlatform>[
  LivePlatform(id: 'rec', name: '热门推荐'),
];

const _huyaCategories = <LivePlatform>[
  LivePlatform(id: '0', name: '全部'),
  LivePlatform(id: '2336', name: '王者荣耀'),
  LivePlatform(id: '1', name: '英雄联盟'),
  LivePlatform(id: '1663', name: '星秀'),
  LivePlatform(id: '3203', name: '和平精英'),
  LivePlatform(id: '2165', name: '户外'),
  LivePlatform(id: '1732', name: '我的世界'),
  LivePlatform(id: '100029', name: '暗区突围'),
  LivePlatform(id: '2633', name: '二次元'),
  LivePlatform(id: '1964', name: '主机游戏'),
  LivePlatform(id: '2793', name: '天天吃鸡'),
  LivePlatform(id: '4', name: '穿越火线'),
  LivePlatform(id: '8', name: '魔兽世界'),
  LivePlatform(id: '2', name: '地下城与勇士'),
  LivePlatform(id: '7', name: 'DOTA2'),
];

List<LivePlatform> livePlatformCategories(String sourceId) =>
    switch (sourceId) {
      'bilibili' => _bilibiliCategories,
      'huya' => _huyaCategories,
      _ => const [],
    };

int liveRoomsPagesPerFetch(String sourceId) => sourceId == 'bilibili' ? 3 : 1;

String liveRoomsUrl(
  String sourceId,
  String platformId,
  int page,
) => switch (sourceId) {
  'bilibili' =>
    'https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getMoreRecList'
        '?platform=web&page=$page',
  'huya' =>
    'https://www.huya.com/cache.php?m=LiveList&do=getLiveListByPage'
        '&tagAll=0&page=$page'
        '${platformId == '0' ? '' : '&gameId=$platformId'}',
  _ => '',
};

List<LiveChannel> liveParseRooms(
  String sourceId,
  LivePlatform platform,
  String body, {
  int firstNumber = 1,
}) => switch (sourceId) {
  'bilibili' => _bilibiliRooms(sourceId, platform, body, firstNumber),
  'huya' => _huyaRooms(sourceId, platform, body, firstNumber),
  _ => const [],
};

String livePlaybackRequestUrl(String sourceId, LiveChannel channel) =>
    switch (sourceId) {
      'bilibili' =>
        'https://api.live.bilibili.com/room/v1/Room/playUrl'
            '?cid=${channel.token}&qn=10000&platform=web',
      'huya' => 'https://www.huya.com/${channel.token}',
      _ => '',
    };

List<String> liveParsePlaybackUrls(String sourceId, String body) =>
    switch (sourceId) {
      'bilibili' => _bilibiliPlaybackUrls(body),
      'huya' => _huyaPlaybackUrls(body),
      _ => const [],
    };

String _text(Object? value) => '${value ?? ''}'.trim();

List<LiveChannel> _bilibiliRooms(
  String sourceId,
  LivePlatform platform,
  String body,
  int firstNumber,
) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  final data = decoded is Map ? decoded['data'] : null;
  final rows = data is Map ? data['recommend_room_list'] : null;
  if (rows is! List) return const [];
  final channels = <LiveChannel>[];
  for (final row in rows.whereType<Map>()) {
    final roomId = _text(row['roomid']);
    if (roomId.isEmpty) continue;
    final uname = _text(row['uname']);
    final title = _text(row['title']);
    final area = [
      _text(row['area_v2_parent_name']),
      _text(row['area_v2_name']),
    ].where((value) => value.isNotEmpty).join('/');
    final online = row['online'];
    final subtitle = [
      if (uname.isNotEmpty) uname,
      if (area.isNotEmpty) area,
      if (online is num && online > 0) '$online 人气',
    ].join(' · ');
    channels.add(
      LiveChannel(
        key: LiveChannel.makeKey(sourceId, platform.name, roomId),
        name: title.isEmpty ? (uname.isEmpty ? '直播间 $roomId' : uname) : title,
        urls: ['https://live.bilibili.com/$roomId'],
        number: (firstNumber + channels.length).toString().padLeft(3, '0'),
        logo: _text(row['cover']).isNotEmpty
            ? _text(row['cover'])
            : _text(row['keyframe']),
        group: platform.name,
        source: sourceId,
        token: roomId,
        subtitle: subtitle,
      ),
    );
  }
  return channels;
}

List<LiveChannel> _huyaRooms(
  String sourceId,
  LivePlatform platform,
  String body,
  int firstNumber,
) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  final data = decoded is Map ? decoded['data'] : null;
  final rows = data is Map ? data['datas'] : null;
  if (rows is! List) return const [];
  final channels = <LiveChannel>[];
  for (final row in rows.whereType<Map>()) {
    final room = _text(row['profileRoom']);
    if (room.isEmpty || room == '0') continue;
    final nick = _text(row['nick']);
    final title = _text(row['introduction']).isNotEmpty
        ? _text(row['introduction'])
        : _text(row['roomName']);
    final game = _text(row['gameFullName']);
    final subtitle = [
      if (nick.isNotEmpty) nick,
      if (game.isNotEmpty) game,
    ].join(' · ');
    channels.add(
      LiveChannel(
        key: LiveChannel.makeKey(sourceId, platform.name, room),
        name: title.isEmpty ? (nick.isEmpty ? '直播间 $room' : nick) : title,
        urls: ['https://www.huya.com/$room'],
        number: (firstNumber + channels.length).toString().padLeft(3, '0'),
        logo: _text(row['screenshot']),
        group: platform.name,
        source: sourceId,
        token: room,
        subtitle: subtitle,
      ),
    );
  }
  return channels;
}

List<String> _bilibiliPlaybackUrls(String body) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  final data = decoded is Map ? decoded['data'] : null;
  final rows = data is Map ? data['durl'] : null;
  if (rows is! List) return const [];
  return [
    for (final row in rows.whereType<Map>())
      if (_text(row['url']).isNotEmpty && isPlayableLiveUrl(_text(row['url'])))
        _text(row['url']),
  ];
}

int _jsonValueEnd(String text, int start) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ']' || ch == '}') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return -1;
}

List<String> _huyaPlaybackUrls(String body) {
  final at = body.indexOf('"gameStreamInfoList"');
  if (at < 0) return const [];
  final start = body.indexOf('[', at);
  if (start < 0) return const [];
  final end = _jsonValueEnd(body, start);
  if (end < 0) return const [];
  final dynamic decoded;
  try {
    decoded = jsonDecode(body.substring(start, end));
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final entries = decoded.whereType<Map>().toList()
    ..sort(
      (a, b) => ((b['iPCPriorityRate'] as num?) ?? 0).compareTo(
        (a['iPCPriorityRate'] as num?) ?? 0,
      ),
    );
  String build(Map entry, String urlKey, String suffixKey, String codeKey) {
    final base = _text(entry[urlKey]);
    final name = _text(entry['sStreamName']);
    final suffix = _text(entry[suffixKey]);
    final code = _text(entry[codeKey]);
    if (base.isEmpty || name.isEmpty || suffix.isEmpty) return '';
    return code.isEmpty ? '$base/$name.$suffix' : '$base/$name.$suffix?$code';
  }

  final urls = <String>[];
  for (final entry in entries) {
    final hls = build(entry, 'sHlsUrl', 'sHlsUrlSuffix', 'sHlsAntiCode');
    if (hls.isNotEmpty && !urls.contains(hls)) urls.add(hls);
  }
  for (final entry in entries) {
    final flv = build(entry, 'sFlvUrl', 'sFlvUrlSuffix', 'sFlvAntiCode');
    if (flv.isNotEmpty && !urls.contains(flv)) urls.add(flv);
  }
  return urls.where(isPlayableLiveUrl).toList();
}
