import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AudioResume {
  const AudioResume({
    required this.chapterIndex,
    required this.positionMs,
    required this.updatedAtMs,
  });

  final int chapterIndex;
  final int positionMs;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
    'chapterIndex': chapterIndex,
    'positionMs': positionMs,
    'updatedAtMs': updatedAtMs,
  };

  static AudioResume? fromJson(dynamic value) {
    if (value is! Map) return null;
    final chapterIndex = value['chapterIndex'];
    final positionMs = value['positionMs'];
    final updatedAtMs = value['updatedAtMs'];
    if (chapterIndex is! num || positionMs is! num || updatedAtMs is! num) {
      return null;
    }
    return AudioResume(
      chapterIndex: chapterIndex.toInt(),
      positionMs: positionMs.toInt(),
      updatedAtMs: updatedAtMs.toInt(),
    );
  }
}

class AudioHistoryEntry {
  const AudioHistoryEntry({
    required this.sourceId,
    required this.bookId,
    required this.title,
    this.cover = '',
    this.chapterIndex = 0,
    this.chapterTitle = '',
    this.positionMs = 0,
    required this.updatedAtMs,
  });

  final String sourceId;
  final String bookId;
  final String title;
  final String cover;
  final int chapterIndex;
  final String chapterTitle;
  final int positionMs;
  final int updatedAtMs;

  String get key => '$sourceId::$bookId';

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'bookId': bookId,
    'title': title,
    'cover': cover,
    'chapterIndex': chapterIndex,
    'chapterTitle': chapterTitle,
    'positionMs': positionMs,
    'updatedAtMs': updatedAtMs,
  };

  static AudioHistoryEntry? fromJson(dynamic value) {
    if (value is! Map) return null;
    final sourceId = value['sourceId'];
    final bookId = value['bookId'];
    final title = value['title'];
    if (sourceId is! String || bookId is! String || title is! String) {
      return null;
    }
    int asInt(dynamic v) => v is num ? v.toInt() : 0;
    String asString(dynamic v) => v is String ? v : '';
    return AudioHistoryEntry(
      sourceId: sourceId,
      bookId: bookId,
      title: title,
      cover: asString(value['cover']),
      chapterIndex: asInt(value['chapterIndex']),
      chapterTitle: asString(value['chapterTitle']),
      positionMs: asInt(value['positionMs']),
      updatedAtMs: asInt(value['updatedAtMs']),
    );
  }
}

List<AudioHistoryEntry> mergeAudioHistory(
  List<AudioHistoryEntry> existing,
  AudioHistoryEntry entry, {
  int max = 30,
}) {
  final next = [
    entry,
    for (final item in existing)
      if (item.key != entry.key) item,
  ];
  if (next.length <= max) return next;
  return next.sublist(0, max);
}

String audioResumeKey(String sourceId, String bookId) =>
    'audio_resume_${sourceId}_$bookId';

class AudioProgressStore {
  static const _historyKey = 'audio_history';
  static const _favoritesKey = 'audio_favorites';
  static const _playModeKey = 'audio_play_mode';

  Future<AudioResume?> loadResume(String sourceId, String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(audioResumeKey(sourceId, bookId));
    if (raw == null) return null;
    try {
      return AudioResume.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveResume(
    String sourceId,
    String bookId,
    int chapterIndex,
    int positionMs,
  ) async {
    if (positionMs <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      audioResumeKey(sourceId, bookId),
      jsonEncode(
        AudioResume(
          chapterIndex: chapterIndex,
          positionMs: positionMs,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ).toJson(),
      ),
    );
  }

  Future<void> clearResume(String sourceId, String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(audioResumeKey(sourceId, bookId));
  }

  Future<List<AudioHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (AudioHistoryEntry.fromJson(item) != null)
            AudioHistoryEntry.fromJson(item)!,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> recordHistory(AudioHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final merged = mergeAudioHistory(await loadHistory(), entry);
    await prefs.setString(
      _historyKey,
      jsonEncode([for (final item in merged) item.toJson()]),
    );
  }

  Future<Set<String>> loadFavoriteKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoritesKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<bool> isFavorite(String key) async {
    return (await loadFavoriteKeys()).contains(key);
  }

  Future<void> setFavorite(String key, bool favorite) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await loadFavoriteKeys();
    if (favorite) {
      keys.add(key);
    } else {
      keys.remove(key);
    }
    await prefs.setString(_favoritesKey, jsonEncode(keys.toList()));
  }

  Future<String?> loadPlayMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_playModeKey);
  }

  Future<void> savePlayMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playModeKey, mode);
  }
}
