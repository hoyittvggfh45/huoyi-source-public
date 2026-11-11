import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_bridge.dart';
import 'models.dart';

class HongguoAccount {
  const HongguoAccount({
    required this.userId,
    required this.displayName,
    this.maskedPhone = '',
    required this.method,
  });

  final String userId;
  final String displayName;
  final String maskedPhone;
  final String method;

  bool get loggedIn => userId.isNotEmpty;

  String get methodLabel => switch (method) {
    'sms' => '短信登录',
    'qr' => '扫码登录',
    _ => method,
  };

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'maskedPhone': maskedPhone,
    'method': method,
  };

  factory HongguoAccount.fromJson(Map<String, dynamic> json) => HongguoAccount(
    userId: json['userId'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    maskedPhone: json['maskedPhone'] as String? ?? '',
    method: json['method'] as String? ?? '',
  );

  static String maskPhone(String phone) {
    if (phone.length != 11) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(7)}';
  }
}

const hongguoAccountStorageKey = 'hongguoAccount';
const hongguoAccountCredentialsKey = 'hongguoAccountCredentials';
const hongguoCloudHistoryKey = 'hongguoCloudHistory';
const hongguoCloudFavoritesKey = 'hongguoCloudFavorites';
const hongguoCloudReservationsKey = 'hongguoCloudReservations';
const hongguoCloudUploadQueueKey = 'hongguoCloudUploadQueue';
const hongguoFavoriteUpdateKey = 'hongguoFavoriteUpdate';

const hongguoCloudHistoryLimit = 50;
const hongguoReservationBatchLimit = 20;

final hongguoAccountNotifier = ValueNotifier<HongguoAccount?>(null);

bool _hongguoAccountLoaded = false;

Future<void> ensureHongguoAccountLoaded() async {
  if (_hongguoAccountLoaded) return;
  final preferences = await SharedPreferences.getInstance();
  final raw = preferences.getString(hongguoAccountStorageKey);
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        hongguoAccountNotifier.value = HongguoAccount.fromJson(decoded);
      }
    } catch (_) {}
  }
  _hongguoAccountLoaded = true;
}

Future<void> saveHongguoAccount(HongguoAccount account) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    hongguoAccountStorageKey,
    jsonEncode(account.toJson()),
  );
  hongguoAccountNotifier.value = account;
}

Future<void> clearHongguoAccount() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.remove(hongguoAccountStorageKey);
  hongguoAccountNotifier.value = null;
}

class HongguoAccountCredentials {
  const HongguoAccountCredentials({
    required this.cookie,
    this.deviceId = '',
    this.installId = '',
  });

  final String cookie;
  final String deviceId;
  final String installId;

  bool get valid => cookie.isNotEmpty;

  String get cookieHeader => cookie;

  Map<String, dynamic> toJson() => {
    'cookie': cookie,
    'deviceId': deviceId,
    'installId': installId,
  };

  factory HongguoAccountCredentials.fromJson(Map<String, dynamic> json) =>
      HongguoAccountCredentials(
        cookie: json['cookie'] as String? ?? '',
        deviceId: json['deviceId'] as String? ?? '',
        installId: json['installId'] as String? ?? '',
      );

  @override
  String toString() => 'HongguoAccountCredentials([redacted])';
}

Future<HongguoAccountCredentials?> loadHongguoAccountCredentials() async {
  final preferences = await SharedPreferences.getInstance();
  final raw = preferences.getString(hongguoAccountCredentialsKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      final credentials = HongguoAccountCredentials.fromJson(decoded);
      return credentials.valid ? credentials : null;
    }
  } catch (_) {}
  return null;
}

Future<void> saveHongguoAccountCredentials(
  HongguoAccountCredentials credentials,
) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    hongguoAccountCredentialsKey,
    jsonEncode(credentials.toJson()),
  );
}

Future<void> clearHongguoAccountCredentials() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.remove(hongguoAccountCredentialsKey);
}

class HongguoLoginFailure implements Exception {
  const HongguoLoginFailure(
    this.message, {
    this.errorCode,
    this.canRetryCode = false,
  });

  final String message;
  final int? errorCode;
  final bool canRetryCode;

  @override
  String toString() => message;
}

class HongguoAccountUnavailable implements Exception {
  const HongguoAccountUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class HongguoCountryCode {
  const HongguoCountryCode(this.code, this.label);

  final String code;
  final String label;
}

const hongguoCountryCodes = <HongguoCountryCode>[
  HongguoCountryCode('86', '中国大陆 +86'),
  HongguoCountryCode('852', '香港 +852'),
  HongguoCountryCode('853', '澳门 +853'),
  HongguoCountryCode('886', '台湾 +886'),
  HongguoCountryCode('81', '日本 +81'),
  HongguoCountryCode('82', '韩国 +82'),
  HongguoCountryCode('1', '美国/加拿大 +1'),
  HongguoCountryCode('44', '英国 +44'),
  HongguoCountryCode('61', '澳大利亚 +61'),
  HongguoCountryCode('65', '新加坡 +65'),
  HongguoCountryCode('60', '马来西亚 +60'),
];

String formatHongguoPhone(String countryCode, String number) {
  final cc = countryCode.replaceAll(RegExp(r'\D'), '');
  final digits = number
      .replaceAll(RegExp(r'\D'), '')
      .replaceFirst(RegExp(r'^0'), '');
  if (cc == '86') {
    if (!RegExp(r'^1\d{10}$').hasMatch(digits)) {
      throw const HongguoLoginFailure('大陆手机号是 1 开头的 11 位数字');
    }
    return digits;
  }
  if (!RegExp(r'^[1-9]\d{0,2}$').hasMatch(cc)) {
    throw const HongguoLoginFailure('区号是 1–3 位数字');
  }
  if (digits.length < 4 || cc.length + digits.length > 15) {
    throw const HongguoLoginFailure('号码长度不对：区号加号码最多 15 位');
  }
  return '+$cc $digits';
}

String parseHongguoPhone(String raw) {
  final text = raw.trim();
  if (!text.startsWith('+')) return formatHongguoPhone('86', text);
  final cc = text.substring(1).split(RegExp(r'\D')).first;
  final rest = text.substring(1 + cc.length);
  if (rest.isEmpty || (rest[0] != '-' && rest[0] != ' ')) {
    throw const HongguoLoginFailure('境外号码写成 +区号 号码，如 +886 0912345678');
  }
  return formatHongguoPhone(cc, rest);
}

class HongguoSmsSent {
  const HongguoSmsSent({required this.maskedMobile, required this.retrySeconds});

  final String maskedMobile;
  final int retrySeconds;
}

class HongguoSmsCountdown {
  HongguoSmsCountdown({required int retrySeconds})
    : remainingSeconds = retrySeconds < 0 ? 0 : retrySeconds;

  int remainingSeconds;

  bool get canResend => remainingSeconds <= 0;

  void tick() {
    if (remainingSeconds > 0) remainingSeconds--;
  }

  void reset(int retrySeconds) {
    remainingSeconds = retrySeconds < 0 ? 0 : retrySeconds;
  }
}

class HongguoQrCode {
  const HongguoQrCode({
    required this.imageBytes,
    required this.expiresInSeconds,
  });

  final List<int> imageBytes;
  final int expiresInSeconds;
}

enum HongguoQrPollResult { waiting, scanned, confirmed, expired }

class HongguoQrCountdown {
  HongguoQrCountdown({required int expiresInSeconds})
    : remainingSeconds = expiresInSeconds < 0 ? 0 : expiresInSeconds;

  int remainingSeconds;

  bool get expired => remainingSeconds <= 0;

  void tick() {
    if (remainingSeconds > 0) remainingSeconds--;
  }
}

class HongguoCloudProfile {
  const HongguoCloudProfile({required this.id, required this.nickname});

  final String id;
  final String nickname;

  factory HongguoCloudProfile.fromJson(Map<String, dynamic> json) =>
      HongguoCloudProfile(
        id: json['biz_user_id'] as String? ?? json['id'] as String? ?? '',
        nickname:
            json['user_name'] as String? ?? json['nickname'] as String? ?? '',
      );
}

int _hongguoMillis(dynamic value) {
  if (value is num) {
    final millis = value.toInt();
    if (millis > 0 && millis < 10000000000) return millis * 1000;
    return millis;
  }
  return 0;
}

String _hongguoString(dynamic value) => value is String ? value : '';

Drama _hongguoCloudDrama(
  Map<String, dynamic> json, {
  String badge = '',
  String description = '',
}) {
  return Drama(
    id:
        _hongguoString(json['series_id']).isNotEmpty
            ? _hongguoString(json['series_id'])
            : _hongguoString(json['book_id']),
    source: SourceSite.hongguo.id,
    title:
        _hongguoString(json['series_title']).isNotEmpty
            ? _hongguoString(json['series_title'])
            : _hongguoString(json['title']).isNotEmpty
            ? _hongguoString(json['title'])
            : _hongguoString(json['book_name']),
    description: description,
    cover:
        _hongguoString(json['series_cover_url']).isNotEmpty
            ? _hongguoString(json['series_cover_url'])
            : _hongguoString(json['cover']).isNotEmpty
            ? _hongguoString(json['cover'])
            : _hongguoString(json['thumb_url']),
    episodes: 0,
    releaseStatus: badge,
  );
}

class HongguoCloudProgress {
  const HongguoCloudProgress({
    required this.seriesId,
    this.seriesTitle = '',
    this.seriesCover = '',
    required this.episodeId,
    required this.episodeIndex,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.episodeCount = 0,
  });

  final String seriesId;
  final String seriesTitle;
  final String seriesCover;
  final String episodeId;
  final int episodeIndex;
  final int position;
  final int duration;
  final int updatedAt;
  final int episodeCount;

  Drama get drama => Drama(
    id: seriesId,
    source: SourceSite.hongguo.id,
    title: seriesTitle,
    cover: seriesCover,
    episodes: episodeCount,
  );

  Map<String, dynamic> toJson() => {
    'seriesId': seriesId,
    'seriesTitle': seriesTitle,
    'seriesCover': seriesCover,
    'episodeId': episodeId,
    'episodeIndex': episodeIndex,
    'position': position,
    'duration': duration,
    'updatedAt': updatedAt,
    'episodeCount': episodeCount,
  };

  factory HongguoCloudProgress.fromJson(Map<String, dynamic> json) {
    final rawSeriesId = json['seriesId'];
    final rawEpisodeId = json['episodeId'];
    if (rawSeriesId is String && rawEpisodeId is String) {
      return HongguoCloudProgress(
        seriesId: rawSeriesId,
        seriesTitle: json['seriesTitle'] as String? ?? '',
        seriesCover: json['seriesCover'] as String? ?? '',
        episodeId: rawEpisodeId,
        episodeIndex: (json['episodeIndex'] as num?)?.toInt() ?? 0,
        position: (json['position'] as num?)?.toInt() ?? 0,
        duration: (json['duration'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
        episodeCount: (json['episodeCount'] as num?)?.toInt() ?? 0,
      );
    }
    final seriesId =
        _hongguoString(json['series_id']).isNotEmpty
            ? _hongguoString(json['series_id'])
            : _hongguoString(json['book_id']);
    final episodeId = _hongguoString(json['vid']);
    if (!RegExp(r'^[0-9]{1,30}$').hasMatch(seriesId) ||
        !RegExp(r'^[0-9]{1,30}$').hasMatch(episodeId)) {
      throw const FormatException('云端历史条目缺少剧集或分集编号');
    }
    return HongguoCloudProgress(
      seriesId: seriesId,
      seriesTitle:
          _hongguoString(json['title']).isNotEmpty
              ? _hongguoString(json['title'])
              : '剧集 $seriesId',
      seriesCover: _hongguoString(json['thumb_url']),
      episodeId: episodeId,
      episodeIndex:
          ((json['vid_index'] as num?)?.toInt() ?? 1) - 1 < 0
              ? 0
              : ((json['vid_index'] as num?)?.toInt() ?? 1) - 1,
      position: (json['current_play_time'] as num?)?.toInt() ?? 0,
      duration: (json['current_total_time'] as num?)?.toInt() ?? 0,
      updatedAt: _hongguoMillis(json['last_watch_time']),
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
    );
  }

  static List<HongguoCloudProgress> parseList(dynamic raw) {
    final rows = raw is List ? raw : const [];
    final result = <HongguoCloudProgress>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        try {
          result.add(HongguoCloudProgress.fromJson(row));
        } catch (_) {}
      } else if (row is Map) {
        try {
          result.add(
            HongguoCloudProgress.fromJson(row.cast<String, dynamic>()),
          );
        } catch (_) {}
      }
    }
    final seen = <String>{};
    result.retainWhere((item) => seen.add(item.seriesId));
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result.take(hongguoCloudHistoryLimit).toList();
  }
}

class HongguoCloudFavorite {
  const HongguoCloudFavorite({required this.drama, required this.collectedAt});

  final Drama drama;
  final int collectedAt;

  Map<String, dynamic> toJson() => {
    'seriesId': drama.id,
    'title': drama.title,
    'cover': drama.cover,
    'description': drama.description,
    'badge': drama.releaseStatus,
    'collectedAt': collectedAt,
  };

  factory HongguoCloudFavorite.fromJson(Map<String, dynamic> json) {
    if (json['seriesId'] is String) {
      return HongguoCloudFavorite(
        drama: Drama(
          id: json['seriesId'] as String,
          source: SourceSite.hongguo.id,
          title: json['title'] as String? ?? '',
          description: json['description'] as String? ?? '',
          cover: json['cover'] as String? ?? '',
          releaseStatus: json['badge'] as String? ?? '',
        ),
        collectedAt: (json['collectedAt'] as num?)?.toInt() ?? 0,
      );
    }
    final video =
        json['video_data'] is Map<String, dynamic>
            ? json['video_data'] as Map<String, dynamic>
            : json;
    final drama = _hongguoCloudDrama(
      {...json, ...video},
      badge:
          (video['episode_cnt'] as num?) != null &&
                  (video['episode_cnt'] as num) > 0
              ? '全 ${video['episode_cnt']} 集'
              : '',
      description:
          _hongguoString(json['series_intro']).isNotEmpty
              ? _hongguoString(json['series_intro'])
              : _hongguoString(video['video_desc']),
    );
    if (drama.id.isEmpty || drama.title.isEmpty) {
      throw const FormatException('账户收藏条目缺少剧集编号或标题');
    }
    return HongguoCloudFavorite(
      drama: drama,
      collectedAt: _hongguoMillis(json['collect_time']),
    );
  }

  static List<HongguoCloudFavorite> parseList(dynamic raw) {
    final rows = raw is List ? raw : const [];
    final result = <HongguoCloudFavorite>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        try {
          result.add(HongguoCloudFavorite.fromJson(row));
        } catch (_) {}
      } else if (row is Map) {
        try {
          result.add(
            HongguoCloudFavorite.fromJson(row.cast<String, dynamic>()),
          );
        } catch (_) {}
      }
    }
    final seen = <String>{};
    result.retainWhere((item) => seen.add(item.drama.id));
    result.sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
    return result;
  }
}

class HongguoCloudReservation {
  const HongguoCloudReservation({
    required this.drama,
    required this.online,
    required this.publishAt,
    this.publishText = '',
  });

  final Drama drama;
  final bool online;
  final int publishAt;
  final String publishText;

  Map<String, dynamic> toJson() => {
    'seriesId': drama.id,
    'title': drama.title,
    'cover': drama.cover,
    'description': drama.description,
    'badge': drama.releaseStatus,
    'online': online,
    'publishAt': publishAt,
    'publishText': publishText,
  };

  factory HongguoCloudReservation.fromJson(Map<String, dynamic> json) {
    if (json['seriesId'] is String) {
      return HongguoCloudReservation(
        drama: Drama(
          id: json['seriesId'] as String,
          source: SourceSite.hongguo.id,
          title: json['title'] as String? ?? '',
          description: json['description'] as String? ?? '',
          cover: json['cover'] as String? ?? '',
          releaseStatus: json['badge'] as String? ?? '',
        ),
        online: json['online'] as bool? ?? false,
        publishAt: (json['publishAt'] as num?)?.toInt() ?? 0,
        publishText: json['publishText'] as String? ?? '',
      );
    }
    final online = json['online'] as bool? ?? true;
    final video =
        json['subscribe_data'] is Map<String, dynamic>
            ? json['subscribe_data'] as Map<String, dynamic>
            : json['video_data'] is Map<String, dynamic>
            ? json['video_data'] as Map<String, dynamic>
            : json;
    var seriesId = _hongguoString(video['series_id']);
    if (seriesId.isEmpty) seriesId = _hongguoString(json['series_id']);
    if (seriesId.isEmpty) seriesId = _hongguoString(json['book_id']);
    if (seriesId.isEmpty &&
        !online &&
        identical(video, json) &&
        RegExp(r'^[0-9]{1,30}$').hasMatch(_hongguoString(json['item_id']))) {
      seriesId = 'reservation:${json['item_id']}';
    }
    final title =
        _hongguoString(json['series_title']).isNotEmpty
            ? _hongguoString(json['series_title'])
            : _hongguoString(video['title']).isNotEmpty
            ? _hongguoString(video['title'])
            : _hongguoString(video['book_name']).isNotEmpty
            ? _hongguoString(video['book_name'])
            : _hongguoString(json['name']);
    if (seriesId.isEmpty || title.isEmpty) {
      throw const FormatException('预约条目缺少剧集编号或标题');
    }
    final drama = _hongguoCloudDrama(
      {...video, 'series_id': seriesId},
      badge:
          _hongguoString(json['episode_badge']).isNotEmpty
              ? _hongguoString(json['episode_badge'])
              : (online ? '已上线' : '待上线'),
      description:
          _hongguoString(video['video_desc']).isNotEmpty
              ? _hongguoString(video['video_desc'])
              : _hongguoString(json['abstract']),
    );
    return HongguoCloudReservation(
      drama: drama,
      online: online,
      publishAt: _hongguoMillis(json['schedule_publish_time']),
      publishText: _hongguoString(json['expected_rec_text']),
    );
  }

  static List<HongguoCloudReservation> parseList(dynamic raw, bool online) {
    final rows = raw is List ? raw : const [];
    final result = <HongguoCloudReservation>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        try {
          final item = HongguoCloudReservation.fromJson({
            ...row,
            'online': row['is_online'] as bool? ?? online,
          });
          if (item.online == online) result.add(item);
        } catch (_) {}
      } else if (row is Map) {
        try {
          final item = HongguoCloudReservation.fromJson({
            ...row.cast<String, dynamic>(),
            'online': online,
          });
          if (item.online == online) result.add(item);
        } catch (_) {}
      }
    }
    final seen = <String>{};
    result.retainWhere((item) => seen.add(item.drama.id));
    return result.take(hongguoReservationBatchLimit).toList();
  }
}

class HongguoLocalProgress {
  const HongguoLocalProgress({
    required this.seriesId,
    required this.episodeId,
    required this.episodeIndex,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final String seriesId;
  final String episodeId;
  final int episodeIndex;
  final int position;
  final int duration;
  final int updatedAt;
}

class HongguoResumeTarget {
  const HongguoResumeTarget({required this.index, required this.position});

  final int index;
  final int position;
}

class HongguoResumePlayback {
  static HongguoLocalProgress? progress({
    required String seriesId,
    required List<String> episodeIds,
    HongguoLocalProgress? local,
    HongguoCloudProgress? cloud,
    bool preferCloud = false,
  }) {
    final device =
        local != null && local.seriesId == seriesId ? local : null;
    HongguoLocalProgress? remote;
    if (cloud != null && cloud.seriesId == seriesId) {
      final index = episodeIds.indexOf(cloud.episodeId);
      final resolvedIndex =
          index >= 0
              ? index
              : cloud.episodeIndex >= 0 &&
                      cloud.episodeIndex < episodeIds.length
                  ? cloud.episodeIndex
                  : -1;
      if (resolvedIndex >= 0) {
        remote = HongguoLocalProgress(
          seriesId: seriesId,
          episodeId: episodeIds[resolvedIndex],
          episodeIndex: resolvedIndex,
          position: cloud.position < 0 ? 0 : cloud.position,
          duration: cloud.duration < 0 ? 0 : cloud.duration,
          updatedAt: cloud.updatedAt,
        );
      }
    }
    if (preferCloud && remote != null) return remote;
    if (remote != null &&
        (device == null || remote.updatedAt > device.updatedAt)) {
      return remote;
    }
    return device;
  }

  static HongguoResumeTarget target({
    required List<String> episodeIds,
    required String? episodeId,
    required int position,
    required bool completed,
  }) {
    final index = episodeId == null ? -1 : episodeIds.indexOf(episodeId);
    if (index < 0) return const HongguoResumeTarget(index: 0, position: 0);
    if (completed) {
      return HongguoResumeTarget(
        index:
            index + 1 > episodeIds.length - 1
                ? episodeIds.length - 1
                : index + 1,
        position: 0,
      );
    }
    return HongguoResumeTarget(
      index: index,
      position: position < 0 ? 0 : position,
    );
  }
}

class HongguoFavoriteUpdate {
  const HongguoFavoriteUpdate({
    required this.total,
    required this.seen,
    required this.checkedAt,
  });

  final int total;
  final int seen;
  final int checkedAt;

  int get added => total - seen < 0 ? 0 : total - seen;

  HongguoFavoriteUpdate observe(int count, int now, {bool acknowledge = false}) {
    if (count <= 0 || now < checkedAt) return this;
    return HongguoFavoriteUpdate(
      total: count,
      seen: acknowledge ? (seen > count ? seen : count) : seen,
      checkedAt: now,
    );
  }

  Map<String, dynamic> toJson() => {
    'total': total,
    'seen': seen,
    'checkedAt': checkedAt,
  };

  factory HongguoFavoriteUpdate.first(int count, int now) {
    if (count <= 0) throw ArgumentError('count must be positive');
    return HongguoFavoriteUpdate(total: count, seen: count, checkedAt: now);
  }

  static HongguoFavoriteUpdate? decode(Map<String, dynamic>? json) {
    if (json == null) return null;
    final total = (json['total'] as num?)?.toInt();
    final seen = (json['seen'] as num?)?.toInt();
    final checkedAt = (json['checkedAt'] as num?)?.toInt();
    if (total == null ||
        seen == null ||
        checkedAt == null ||
        total <= 0 ||
        seen <= 0 ||
        checkedAt < 0) {
      return null;
    }
    return HongguoFavoriteUpdate(
      total: total,
      seen: seen,
      checkedAt: checkedAt,
    );
  }
}

abstract class HongguoAccountTransport {
  const HongguoAccountTransport();

  static const HongguoAccountTransport unavailable =
      _HongguoUnavailableTransport();

  Future<HongguoSmsSent> sendSmsCode(String mobile);
  Future<HongguoAccountCredentials> verifySmsCode({
    required String mobile,
    required String code,
  });
  Future<HongguoQrCode> fetchQrCode();
  Future<HongguoQrPollResult> pollQrCode();
  Future<HongguoAccountCredentials> confirmQrCode();
  Future<HongguoCloudProfile> fetchProfile(
    HongguoAccountCredentials credentials,
  );
  Future<List<HongguoCloudFavorite>> fetchCloudFavorites(
    HongguoAccountCredentials credentials,
  );
  Future<void> setCloudFavorite(
    HongguoAccountCredentials credentials, {
    required String seriesId,
    required bool add,
  });
  Future<List<HongguoCloudProgress>> fetchCloudHistory(
    HongguoAccountCredentials credentials,
  );
  Future<void> uploadCloudProgress(
    HongguoAccountCredentials credentials, {
    required HongguoCloudProgress progress,
  });
  Future<List<HongguoCloudReservation>> fetchReservations(
    HongguoAccountCredentials credentials, {
    required bool online,
  });
  Future<void> reserveWork(
    HongguoAccountCredentials credentials, {
    required String seriesId,
  });
}

class _HongguoUnavailableTransport extends HongguoAccountTransport {
  const _HongguoUnavailableTransport();

  static const _message = '红果账号接口尚未接线：Go 核没有对应的账号动作';

  @override
  Future<HongguoSmsSent> sendSmsCode(String mobile) async =>
      throw const HongguoAccountUnavailable(_message);

  @override
  Future<HongguoAccountCredentials> verifySmsCode({
    required String mobile,
    required String code,
  }) async => throw const HongguoAccountUnavailable(_message);

  @override
  Future<HongguoQrCode> fetchQrCode() async =>
      throw const HongguoAccountUnavailable(_message);

  @override
  Future<HongguoQrPollResult> pollQrCode() async =>
      throw const HongguoAccountUnavailable(_message);

  @override
  Future<HongguoAccountCredentials> confirmQrCode() async =>
      throw const HongguoAccountUnavailable(_message);

  @override
  Future<HongguoCloudProfile> fetchProfile(
    HongguoAccountCredentials credentials,
  ) async => throw const HongguoAccountUnavailable(_message);

  @override
  Future<List<HongguoCloudFavorite>> fetchCloudFavorites(
    HongguoAccountCredentials credentials,
  ) async => throw const HongguoAccountUnavailable(_message);

  @override
  Future<void> setCloudFavorite(
    HongguoAccountCredentials credentials, {
    required String seriesId,
    required bool add,
  }) async => throw const HongguoAccountUnavailable(_message);

  @override
  Future<List<HongguoCloudProgress>> fetchCloudHistory(
    HongguoAccountCredentials credentials,
  ) async => throw const HongguoAccountUnavailable(_message);

  @override
  Future<void> uploadCloudProgress(
    HongguoAccountCredentials credentials, {
    required HongguoCloudProgress progress,
  }) async => throw const HongguoAccountUnavailable(_message);

  @override
  Future<List<HongguoCloudReservation>> fetchReservations(
    HongguoAccountCredentials credentials, {
    required bool online,
  }) async => throw const HongguoAccountUnavailable(_message);

  @override
  Future<void> reserveWork(
    HongguoAccountCredentials credentials, {
    required String seriesId,
  }) async => throw const HongguoAccountUnavailable(_message);
}

class GoHongguoAccountTransport extends HongguoAccountTransport {
  GoHongguoAccountTransport(this._repository);

  final AppRepository _repository;

  @override
  Future<HongguoSmsSent> sendSmsCode(String mobile) async {
    try {
      final result = await _repository.hongguoAccountSendSms(mobile);
      return HongguoSmsSent(
        maskedMobile: result['maskedMobile'] as String? ?? mobile,
        retrySeconds: (result['retrySeconds'] as num?)?.toInt() ?? 60,
      );
    } on AppFailure catch (error) {
      if (error.message.contains('错误码 7')) {
        throw const HongguoLoginFailure(
          '平台限流：请求太频繁，请等 60 秒后再试（错误码 7）',
          errorCode: 7,
        );
      }
      rethrow;
    }
  }

  @override
  Future<HongguoAccountCredentials> verifySmsCode({
    required String mobile,
    required String code,
  }) async {
    try {
      final result = await _repository.hongguoAccountVerifySms(mobile, code);
      return HongguoAccountCredentials(
        cookie: result['cookie'] as String? ?? '',
        deviceId: result['deviceId'] as String? ?? '',
        installId: result['installId'] as String? ?? '',
      );
    } on AppFailure catch (error) {
      if (error.message.contains('错误码 1102')) {
        throw HongguoLoginFailure(
          error.message,
          errorCode: 1102,
          canRetryCode: true,
        );
      }
      rethrow;
    }
  }

  @override
  Future<HongguoQrCode> fetchQrCode() async {
    final result = await _repository.hongguoAccountQrCode();
    return HongguoQrCode(
      imageBytes: base64Decode(result['imageBase64'] as String? ?? ''),
      expiresInSeconds: (result['expiresInSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<HongguoQrPollResult> pollQrCode() async {
    final result = await _repository.hongguoAccountQrPoll();
    return switch (result['result'] as String?) {
      'scanned' => HongguoQrPollResult.scanned,
      'confirmed' => HongguoQrPollResult.confirmed,
      'expired' => HongguoQrPollResult.expired,
      _ => HongguoQrPollResult.waiting,
    };
  }

  @override
  Future<HongguoAccountCredentials> confirmQrCode() async {
    final result = await _repository.hongguoAccountQrConfirm();
    return HongguoAccountCredentials(
      cookie: result['cookie'] as String? ?? '',
      deviceId: result['deviceId'] as String? ?? '',
      installId: result['installId'] as String? ?? '',
    );
  }

  @override
  Future<HongguoCloudProfile> fetchProfile(
    HongguoAccountCredentials credentials,
  ) async {
    final result = await _repository.hongguoAccountProfile(
      credentials.cookie,
    );
    final raw = result['profile'];
    if (raw is! Map<String, dynamic>) {
      throw const HongguoLoginFailure('账号资料为空');
    }
    return HongguoCloudProfile.fromJson(raw);
  }

  @override
  Future<List<HongguoCloudFavorite>> fetchCloudFavorites(
    HongguoAccountCredentials credentials,
  ) async {
    final result = await _repository.hongguoAccountFavorites(
      credentials.cookie,
    );
    return HongguoCloudFavorite.parseList(result['rows']);
  }

  @override
  Future<void> setCloudFavorite(
    HongguoAccountCredentials credentials, {
    required String seriesId,
    required bool add,
  }) async {
    await _repository.hongguoAccountSetFavorite(
      credentials.cookie,
      seriesId,
      add,
    );
  }

  @override
  Future<List<HongguoCloudProgress>> fetchCloudHistory(
    HongguoAccountCredentials credentials,
  ) async {
    final result = await _repository.hongguoAccountHistory(
      credentials.cookie,
    );
    return HongguoCloudProgress.parseList(result['rows']);
  }

  @override
  Future<void> uploadCloudProgress(
    HongguoAccountCredentials credentials, {
    required HongguoCloudProgress progress,
  }) async {
    await _repository.hongguoAccountUploadProgress(
      credentials.cookie,
      progress.toJson(),
    );
  }

  @override
  Future<List<HongguoCloudReservation>> fetchReservations(
    HongguoAccountCredentials credentials, {
    required bool online,
  }) async {
    final result = await _repository.hongguoAccountReservations(
      credentials.cookie,
      online,
    );
    return HongguoCloudReservation.parseList(result['rows'], online);
  }

  @override
  Future<void> reserveWork(
    HongguoAccountCredentials credentials, {
    required String seriesId,
  }) async {
    await _repository.hongguoAccountReserve(credentials.cookie, seriesId);
  }
}

class HongguoAccountController extends ChangeNotifier {
  HongguoAccountController({
    this._transport = HongguoAccountTransport.unavailable,
  });

  HongguoAccountController.withTransport(this._transport);

  final HongguoAccountTransport _transport;

  HongguoAccountCredentials? _credentials;
  List<HongguoCloudFavorite> _cloudFavorites = const [];
  List<HongguoCloudProgress> _cloudHistory = const [];
  List<HongguoCloudReservation> _onlineReservations = const [];
  List<HongguoCloudReservation> _upcomingReservations = const [];
  List<HongguoCloudProgress> _uploadQueue = const [];
  HongguoFavoriteUpdate? _favoriteUpdate;
  bool _uploading = false;

  bool get loggedIn =>
      hongguoAccountNotifier.value?.loggedIn == true &&
      _credentials?.valid == true;

  List<HongguoCloudFavorite> get cloudFavorites =>
      List.unmodifiable(_cloudFavorites);
  List<HongguoCloudProgress> get cloudHistory =>
      List.unmodifiable(_cloudHistory);
  List<HongguoCloudReservation> get onlineReservations =>
      List.unmodifiable(_onlineReservations);
  List<HongguoCloudReservation> get upcomingReservations =>
      List.unmodifiable(_upcomingReservations);
  List<HongguoCloudProgress> get pendingUploads =>
      List.unmodifiable(_uploadQueue);
  HongguoFavoriteUpdate? get favoriteUpdate => _favoriteUpdate;

  Set<String> get cloudFavoriteIds =>
      _cloudFavorites.map((item) => item.drama.id).toSet();

  bool isCloudFavorite(String seriesId) =>
      _cloudFavorites.any((item) => item.drama.id == seriesId);

  HongguoCloudProgress? cloudProgress(String seriesId) {
    for (final item in _cloudHistory) {
      if (item.seriesId == seriesId) return item;
    }
    return null;
  }

  bool isReserved(String seriesId) =>
      _onlineReservations.any((item) => item.drama.id == seriesId) ||
      _upcomingReservations.any((item) => item.drama.id == seriesId);

  Future<void> load() async {
    await ensureHongguoAccountLoaded();
    _credentials = await loadHongguoAccountCredentials();
    final preferences = await SharedPreferences.getInstance();
    _cloudHistory = _decodeHistory(
      preferences.getString(hongguoCloudHistoryKey),
    );
    _cloudFavorites = _decodeFavorites(
      preferences.getString(hongguoCloudFavoritesKey),
    );
    final reservations = _decodeReservations(
      preferences.getString(hongguoCloudReservationsKey),
    );
    _onlineReservations =
        reservations.where((item) => item.online).toList();
    _upcomingReservations =
        reservations.where((item) => !item.online).toList();
    _uploadQueue = _decodeHistory(
      preferences.getString(hongguoCloudUploadQueueKey),
    );
    final updateRaw = preferences.getString(hongguoFavoriteUpdateKey);
    if (updateRaw != null && updateRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(updateRaw);
        if (decoded is Map<String, dynamic>) {
          _favoriteUpdate = HongguoFavoriteUpdate.decode(decoded);
        }
      } catch (_) {}
    }
    if (hongguoAccountNotifier.value?.loggedIn != true ||
        _credentials?.valid != true) {
      _cloudHistory = const [];
      _cloudFavorites = const [];
      _onlineReservations = const [];
      _upcomingReservations = const [];
    }
    notifyListeners();
  }

  Future<HongguoSmsSent> transportSendSmsCode(String mobile) =>
      _transport.sendSmsCode(mobile);

  Future<HongguoQrCode> transportFetchQrCode() => _transport.fetchQrCode();

  Future<HongguoQrPollResult> transportPollQrCode() =>
      _transport.pollQrCode();

  Future<HongguoAccount> loginWithSms({
    required String mobile,
    required String code,
  }) async {
    final credentials = await _transport.verifySmsCode(
      mobile: mobile,
      code: code,
    );
    return _acceptCredentials(credentials, method: 'sms', mobile: mobile);
  }

  Future<HongguoAccount> loginWithQr() async {
    final credentials = await _transport.confirmQrCode();
    return _acceptCredentials(credentials, method: 'qr', mobile: '');
  }

  Future<HongguoAccount> _acceptCredentials(
    HongguoAccountCredentials credentials, {
    required String method,
    required String mobile,
  }) async {
    final profile = await _transport.fetchProfile(credentials);
    if (profile.id.isEmpty) {
      throw const HongguoLoginFailure(
        '该手机号还没有红果账号资料，请先用官方红果 App 登录一次再回来试',
      );
    }
    _credentials = credentials;
    await saveHongguoAccountCredentials(credentials);
    final account = HongguoAccount(
      userId: profile.id,
      displayName:
          profile.nickname.isNotEmpty ? profile.nickname : '红果用户',
      maskedPhone:
          mobile.isEmpty
              ? ''
              : mobile.length == 11
              ? HongguoAccount.maskPhone(mobile)
              : mobile,
      method: method,
    );
    await saveHongguoAccount(account);
    await refreshCloudData();
    notifyListeners();
    return account;
  }

  Future<void> logout() async {
    _credentials = null;
    _cloudFavorites = const [];
    _cloudHistory = const [];
    _onlineReservations = const [];
    _upcomingReservations = const [];
    _favoriteUpdate = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(hongguoCloudHistoryKey);
    await preferences.remove(hongguoCloudFavoritesKey);
    await preferences.remove(hongguoCloudReservationsKey);
    await preferences.remove(hongguoFavoriteUpdateKey);
    await clearHongguoAccountCredentials();
    await clearHongguoAccount();
    notifyListeners();
  }

  Future<void> refreshCloudData() async {
    await refreshCloudHistory();
    await refreshCloudFavorites();
    await refreshReservations(online: true);
    await refreshReservations(online: false);
  }

  Future<void> refreshCloudHistory() async {
    final credentials = _credentials;
    if (credentials == null || !credentials.valid) return;
    final history = await _transport.fetchCloudHistory(credentials);
    _cloudHistory = history;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      hongguoCloudHistoryKey,
      jsonEncode(history.map((item) => item.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> refreshCloudFavorites() async {
    final credentials = _credentials;
    if (credentials == null || !credentials.valid) return;
    final favorites = await _transport.fetchCloudFavorites(credentials);
    _cloudFavorites = favorites;
    final now = DateTime.now().millisecondsSinceEpoch;
    _favoriteUpdate =
        _favoriteUpdate == null
            ? HongguoFavoriteUpdate.first(favorites.length, now)
            : _favoriteUpdate!.observe(favorites.length, now);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      hongguoCloudFavoritesKey,
      jsonEncode(favorites.map((item) => item.toJson()).toList()),
    );
    if (_favoriteUpdate != null) {
      await preferences.setString(
        hongguoFavoriteUpdateKey,
        jsonEncode(_favoriteUpdate!.toJson()),
      );
    }
    notifyListeners();
  }

  Future<void> acknowledgeFavoriteUpdate() async {
    final update = _favoriteUpdate;
    if (update == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _favoriteUpdate = update.observe(update.total, now, acknowledge: true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      hongguoFavoriteUpdateKey,
      jsonEncode(_favoriteUpdate!.toJson()),
    );
    notifyListeners();
  }

  Future<void> changeCloudFavorite(Drama drama, bool add) async {
    final credentials = _credentials;
    if (credentials == null || !credentials.valid) {
      throw const HongguoLoginFailure('请先登录红果账号');
    }
    if (!RegExp(r'^[0-9]{1,30}$').hasMatch(drama.id)) {
      throw const HongguoLoginFailure('剧集编号无效');
    }
    await _transport.setCloudFavorite(
      credentials,
      seriesId: drama.id,
      add: add,
    );
    await refreshCloudFavorites();
  }

  Future<void> refreshReservations({required bool online}) async {
    final credentials = _credentials;
    if (credentials == null || !credentials.valid) return;
    final rows = await _transport.fetchReservations(
      credentials,
      online: online,
    );
    if (online) {
      _onlineReservations = rows;
    } else {
      _upcomingReservations = rows;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      hongguoCloudReservationsKey,
      jsonEncode([
        ..._onlineReservations.map((item) => item.toJson()),
        ..._upcomingReservations.map((item) => item.toJson()),
      ]),
    );
    notifyListeners();
  }

  Future<void> reserveSeries(String seriesId) async {
    final credentials = _credentials;
    if (credentials == null || !credentials.valid) {
      throw const HongguoLoginFailure('请先登录红果账号');
    }
    if (!RegExp(r'^[0-9]{1,19}$').hasMatch(seriesId)) {
      throw const HongguoLoginFailure('预约编号无效');
    }
    await _transport.reserveWork(credentials, seriesId: seriesId);
    await refreshReservations(online: false);
  }

  Future<void> recordPlayback(HongguoCloudProgress progress) async {
    _uploadQueue = [..._uploadQueue, progress];
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      hongguoCloudUploadQueueKey,
      jsonEncode(_uploadQueue.map((item) => item.toJson()).toList()),
    );
    notifyListeners();
    await drainUploads();
  }

  Future<void> drainUploads() async {
    final credentials = _credentials;
    if (_uploading ||
        credentials == null ||
        !credentials.valid ||
        _uploadQueue.isEmpty) {
      return;
    }
    _uploading = true;
    try {
      final remaining = [..._uploadQueue];
      for (final item in List.of(remaining)) {
        try {
          await _transport.uploadCloudProgress(
            credentials,
            progress: item,
          );
          remaining.remove(item);
        } catch (_) {
          break;
        }
      }
      _uploadQueue = remaining;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        hongguoCloudUploadQueueKey,
        jsonEncode(remaining.map((item) => item.toJson()).toList()),
      );
      notifyListeners();
    } finally {
      _uploading = false;
    }
  }

  static List<HongguoCloudProgress> _decodeHistory(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return HongguoCloudProgress.parseList(decoded);
    } catch (_) {}
    return const [];
  }

  static List<HongguoCloudFavorite> _decodeFavorites(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return HongguoCloudFavorite.parseList(decoded);
    } catch (_) {}
    return const [];
  }

  static List<HongguoCloudReservation> _decodeReservations(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final rows = <HongguoCloudReservation>[];
        for (final row in decoded) {
          if (row is Map<String, dynamic>) {
            try {
              rows.add(HongguoCloudReservation.fromJson(row));
            } catch (_) {}
          }
        }
        return rows;
      }
    } catch (_) {}
    return const [];
  }
}
