import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

class HongguoDecoderLessons {
  HongguoDecoderLessons([Set<String>? failed])
    : _failed = failed == null ? <String>{} : Set.of(failed);

  final Set<String> _failed;

  static String? key(String codec, int? quality) {
    final normalized = codec.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (quality == null || quality <= 0) return normalized;
    return '$normalized|$quality';
  }

  String? remember(String codec, int? quality) {
    final exact = key(codec, quality);
    if (exact == null) return null;
    _failed.add(exact);
    return exact;
  }

  bool fails(String codec, int? quality) {
    final normalized = codec.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (quality != null && quality > 0) {
      if (_failed.contains('$normalized|$quality')) return true;
    }
    return _failed.contains(normalized);
  }

  Set<String> keys() => Set.unmodifiable(_failed);

  void restore(Iterable<String> keys) {
    _failed.clear();
    _failed.addAll(keys);
  }

  void reset() => _failed.clear();

  int get size => _failed.length;
}

class HongguoCodecCapabilities {
  static const List<int> qualityOptions = [480, 720, 1080];
  static const String lessonsKey = 'hongguoDecoderLessons';
  static const String codec = 'h264';

  static int normalizeQuality(int value) =>
      qualityOptions.contains(value) ? value : 0;

  static bool looksLikeDecodeFailure(String message) {
    final lower = message.toLowerCase();
    return lower.contains('codec') ||
        lower.contains('decoder') ||
        lower.contains('decode') ||
        lower.contains('render') ||
        lower.contains('unsupported') ||
        lower.contains('hardware') ||
        lower.contains('解码');
  }

  static List<int> supportedQualities(
    List<int> available,
    HongguoDecoderLessons lessons,
  ) => [
    for (final quality in available)
      if (quality > 0 && !lessons.fails(codec, quality)) quality,
  ];

  static int effectiveQuality(
    int requested,
    List<int> available,
    HongguoDecoderLessons lessons,
  ) {
    final supported = supportedQualities(available, lessons);
    if (supported.isEmpty) return 0;
    if (requested > 0) {
      final atOrBelow = supported.where((value) => value <= requested);
      if (atOrBelow.isNotEmpty) {
        return atOrBelow.reduce(math.max);
      }
      return supported.reduce(math.min);
    }
    return supported.reduce(math.max);
  }

  static int lowEndCap(HongguoDecoderLessons lessons) =>
      lessons.fails(codec, 1080) ? 720 : 1080;

  static HongguoDecoderLessons loadLessons(SharedPreferences preferences) {
    final stored = preferences.getStringList(lessonsKey);
    return HongguoDecoderLessons(stored?.toSet());
  }

  static Future<void> saveLessons(
    SharedPreferences preferences,
    HongguoDecoderLessons lessons,
  ) => preferences.setStringList(lessonsKey, lessons.keys().toList());
}
