import 'package:shared_preferences/shared_preferences.dart';

import 'comment_api.dart';
import 'comment_identity.dart';
import 'comment_models.dart';
import 'danmaku_models.dart';

const int commentMaxChars = 200;
const Duration commentSendInterval = Duration(seconds: 5);
const String commentBlockedSendersKey = 'comment_blocked_senders';
const int commentCacheCap = 1000;

class CommentRateLimited implements Exception {
  const CommentRateLimited();
}

class CommentService {
  CommentService._({
    CommentApi? api,
    SharedPreferences? prefs,
    DateTime Function()? now,
  }) : _api = api ?? CommentApiClient(),
       _prefsOverride = prefs,
       _now = now ?? DateTime.now;

  static final CommentService instance = CommentService._();

  factory CommentService.forTest({
    required CommentApi api,
    required SharedPreferences prefs,
    DateTime Function()? now,
  }) => CommentService._(api: api, prefs: prefs, now: now);

  final CommentApi _api;
  final SharedPreferences? _prefsOverride;
  final DateTime Function() _now;
  SharedPreferences? _prefs;
  Future<void>? _prefsPending;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  String _cachedKey = '';
  bool _cachedLoaded = false;
  List<VideoComment> _cached = const [];
  final _blockedMemory = <String>{};

  Future<SharedPreferences?> _ensurePrefs() async {
    if (_prefsOverride != null) return _prefsOverride;
    if (_prefs != null) return _prefs;
    if (_prefsPending != null) {
      await _prefsPending;
      return _prefs;
    }
    final pending = SharedPreferences.getInstance()
        .then<void>((value) {
          _prefs = value;
        })
        .catchError((Object _) {});
    _prefsPending = pending;
    await pending;
    _prefsPending = null;
    return _prefs;
  }

  Future<Set<String>> blockedSenders() async {
    final prefs = await _ensurePrefs();
    if (prefs == null) return Set.of(_blockedMemory);
    return prefs.getStringList(commentBlockedSendersKey)?.toSet() ?? {};
  }

  Future<void> block(String senderId) async {
    if (senderId.isEmpty) return;
    final prefs = await _ensurePrefs();
    if (prefs != null) {
      final blocked = await blockedSenders();
      blocked.add(senderId);
      await prefs.setStringList(commentBlockedSendersKey, blocked.toList());
    } else {
      _blockedMemory.add(senderId);
    }
  }

  Future<void> unblock(String senderId) async {
    if (senderId.isEmpty) return;
    final prefs = await _ensurePrefs();
    if (prefs != null) {
      final blocked = await blockedSenders();
      blocked.remove(senderId);
      await prefs.setStringList(commentBlockedSendersKey, blocked.toList());
    } else {
      _blockedMemory.remove(senderId);
    }
  }

  Future<List<VideoComment>> fetchAll(String videoKey) async {
    if (_cachedLoaded && _cachedKey == videoKey) return _cached;
    final collected = <VideoComment>[];
    String? before;
    while (collected.length < commentCacheCap) {
      final page = await _api.fetch(
        videoKey: videoKey,
        limit: 200,
        before: before,
      );
      collected.addAll(page.items);
      before = page.nextBefore;
      if (before == null) break;
    }
    collected.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    _cachedKey = videoKey;
    _cached = List.unmodifiable(collected);
    _cachedLoaded = true;
    return _cached;
  }

  Future<List<DanmakuItem>> window(
    String videoKey,
    int startMs,
    int endMs,
  ) async {
    final all = await fetchAll(videoKey);
    final blocked = await blockedSenders();
    final items = <DanmakuItem>[];
    for (final comment in all) {
      if (comment.timeMs < startMs ||
          comment.timeMs >= endMs ||
          blocked.contains(comment.senderId)) {
        continue;
      }
      final text = comment.nickname.isNotEmpty
          ? '${comment.nickname}：${comment.text}'
          : comment.text;
      items.add(
        DanmakuItem(id: comment.id, text: text, timeMs: comment.timeMs),
      );
    }
    items.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return items;
  }

  Future<VideoComment> send({
    required String videoKey,
    required String text,
    required int timeMs,
  }) async {
    final trimmed = trimDanmakuText(text.trim(), commentMaxChars);
    if (trimmed.isEmpty) {
      throw const CommentApiException('评论不能为空');
    }
    final now = _now();
    if (now.difference(_lastSent) < commentSendInterval) {
      throw const CommentRateLimited();
    }
    await CommentIdentity.instance.ensure();
    final identity = CommentIdentity.instance;
    final posted = await _api.post(
      videoKey: videoKey,
      text: trimmed,
      timeMs: timeMs < 0 ? 0 : timeMs,
      senderId: identity.userId,
      nickname: identity.nickname,
    );
    _lastSent = _now();
    if (_cachedLoaded && _cachedKey == videoKey) {
      final next = [..._cached, posted]
        ..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
      _cached = List.unmodifiable(
        next.length > commentCacheCap
            ? next.sublist(next.length - commentCacheCap)
            : next,
      );
    }
    return posted;
  }
}
