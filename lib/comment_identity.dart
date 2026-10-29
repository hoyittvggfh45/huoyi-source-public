import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String commentUserIdKey = 'comment_user_id';
const String commentNicknameKey = 'comment_nickname';

String generateCommentUserId(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String defaultCommentNickname(String userId) {
  final tail = userId.length >= 4
      ? userId.substring(userId.length - 4)
      : userId;
  return '用户$tail';
}

bool validCommentNickname(String nickname) {
  final trimmed = nickname.trim();
  final runes = trimmed.runes.length;
  return trimmed.isNotEmpty && runes <= 20;
}

class CommentIdentity extends ChangeNotifier {
  CommentIdentity._();

  static final CommentIdentity instance = CommentIdentity._();

  String _userId = '';
  String _nickname = '';
  bool _ready = false;
  Future<void>? _pending;

  String get userId => _userId;

  String get nickname => _nickname;

  bool get ready => _ready;

  @visibleForTesting
  void debugReset() {
    _userId = '';
    _nickname = '';
    _ready = false;
    _pending = null;
  }

  Future<void> ensure() {
    if (_ready) return Future.value();
    return _pending ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(commentUserIdKey) ?? '';
      if (id.isEmpty) {
        id = generateCommentUserId(Random.secure());
        await prefs.setString(commentUserIdKey, id);
      }
      var nickname = prefs.getString(commentNicknameKey) ?? '';
      if (nickname.isEmpty) {
        nickname = defaultCommentNickname(id);
        await prefs.setString(commentNicknameKey, nickname);
      }
      _userId = id;
      _nickname = nickname;
    } catch (_) {
      if (_userId.isEmpty) {
        _userId = generateCommentUserId(Random.secure());
      }
      if (_nickname.isEmpty) {
        _nickname = defaultCommentNickname(_userId);
      }
    }
    _ready = true;
    _pending = null;
    notifyListeners();
  }

  Future<bool> rename(String nickname) async {
    final trimmed = nickname.trim();
    if (!validCommentNickname(trimmed)) return false;
    await ensure();
    _nickname = trimmed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(commentNicknameKey, trimmed);
    } catch (_) {}
    notifyListeners();
    return true;
  }
}
