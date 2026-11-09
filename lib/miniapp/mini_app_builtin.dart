import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mini_app_manifest.dart';
import 'mini_app_store.dart';

class MiniAppBuiltinFailure {
  const MiniAppBuiltinFailure({required this.appId, required this.reason});

  final String appId;
  final String reason;
}

class MiniAppBuiltinResult {
  const MiniAppBuiltinResult({
    required this.installed,
    required this.skipped,
    required this.failed,
  });

  final List<String> installed;
  final List<String> skipped;
  final List<MiniAppBuiltinFailure> failed;

  bool get hasFailures => failed.isNotEmpty;
}

class MiniAppBuiltin {
  static const String marketAsset = 'assets/miniapps/builtin/market.json';
  static const String seededKey = 'huoyi_miniapp_builtin_seeded_v1';

  static Future<MiniAppBuiltinResult> ensureSeeded(
    MiniAppStore store, {
    SharedPreferences? prefs,
    Future<ByteData> Function(String asset)? loadAsset,
  }) async {
    final preferences = prefs ?? await SharedPreferences.getInstance();
    final load = loadAsset ?? rootBundle.load;
    List<MiniAppMarketItem> items;
    try {
      final raw = await load(marketAsset);
      items = parseMiniAppMarketJson(
        utf8.decode(raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes)),
      );
    } catch (_) {
      return const MiniAppBuiltinResult(
        installed: [],
        skipped: [],
        failed: [],
      );
    }
    if (preferences.getBool(seededKey) == true) {
      return MiniAppBuiltinResult(
        installed: const [],
        skipped: items.map((item) => item.appId).toList(),
        failed: const [],
      );
    }
    final installed = <String>[];
    final skipped = <String>[];
    final failed = <MiniAppBuiltinFailure>[];
    for (final item in items) {
      final existing = await store.installedDir(item.appId);
      if (existing != null) {
        skipped.add(item.appId);
        continue;
      }
      try {
        if (item.url.endsWith('.json')) {
          final raw = await load(
            'assets/miniapps/builtin/${item.appId}.manifest.json',
          );
          final manifest = await store.installFromManifestJson(
            utf8.decode(
              raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
            ),
          );
          installed.add(manifest.appId);
        } else {
          final raw = await load('assets/miniapps/builtin/${item.appId}.zip');
          final manifest = await store.installFromZipBytes(
            raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
            expectedMd5: item.md5,
          );
          installed.add(manifest.appId);
        }
      } catch (error) {
        failed.add(
          MiniAppBuiltinFailure(appId: item.appId, reason: error.toString()),
        );
      }
    }
    if (items.isNotEmpty && failed.isEmpty) {
      await preferences.setBool(seededKey, true);
    }
    return MiniAppBuiltinResult(
      installed: installed,
      skipped: skipped,
      failed: failed,
    );
  }
}
