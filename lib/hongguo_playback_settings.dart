import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HongguoFrameMode {
  fit('完整画面', BoxFit.contain),
  zoom('等比铺满', BoxFit.cover),
  fill('拉伸铺满', BoxFit.fill);

  const HongguoFrameMode(this.label, this.boxFit);
  final String label;
  final BoxFit boxFit;

  static HongguoFrameMode fromStored(String? value) =>
      HongguoFrameMode.values.asNameMap()[value] ?? HongguoFrameMode.fit;
}

class HongguoPlaybackSettings {
  const HongguoPlaybackSettings({
    this.frameMode = HongguoFrameMode.fit,
    this.rotationQuarters = 0,
    this.alwaysShowProgress = false,
    this.seasonAutoplay = false,
  });

  final HongguoFrameMode frameMode;
  final int rotationQuarters;
  final bool alwaysShowProgress;
  final bool seasonAutoplay;

  static const storageKey = 'hongguoPlaybackSettings';

  HongguoPlaybackSettings copyWith({
    HongguoFrameMode? frameMode,
    int? rotationQuarters,
    bool? alwaysShowProgress,
    bool? seasonAutoplay,
  }) => HongguoPlaybackSettings(
    frameMode: frameMode ?? this.frameMode,
    rotationQuarters: rotationQuarters ?? this.rotationQuarters,
    alwaysShowProgress: alwaysShowProgress ?? this.alwaysShowProgress,
    seasonAutoplay: seasonAutoplay ?? this.seasonAutoplay,
  );

  Map<String, dynamic> toJson() => {
    'frameMode': frameMode.name,
    'rotationQuarters': rotationQuarters,
    'alwaysShowProgress': alwaysShowProgress,
    'seasonAutoplay': seasonAutoplay,
  };

  factory HongguoPlaybackSettings.fromJson(Map<String, dynamic> value) {
    final rotation = value['rotationQuarters'];
    final quarters = rotation is int
        ? rotation % 4
        : rotation is num
        ? rotation.toInt() % 4
        : 0;
    return HongguoPlaybackSettings(
      frameMode: HongguoFrameMode.fromStored(value['frameMode'] as String?),
      rotationQuarters: quarters < 0 ? quarters + 4 : quarters,
      alwaysShowProgress: value['alwaysShowProgress'] is bool
          ? value['alwaysShowProgress'] as bool
          : false,
      seasonAutoplay: value['seasonAutoplay'] is bool
          ? value['seasonAutoplay'] as bool
          : false,
    );
  }

  static HongguoPlaybackSettings load(SharedPreferences preferences) {
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return const HongguoPlaybackSettings();
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        return HongguoPlaybackSettings.fromJson(parsed);
      }
    } catch (_) {}
    return const HongguoPlaybackSettings();
  }

  Future<void> save(SharedPreferences preferences) =>
      preferences.setString(storageKey, jsonEncode(toJson()));
}
