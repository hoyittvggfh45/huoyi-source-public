import 'dart:io';

import 'package:flutter/services.dart';

import 'import_file_store.dart';
import 'jar_bridge.dart';
import 'models.dart';
import 'py_bridge.dart';
import 'py_contract.dart';

class JarYoutubeTakeover {
  JarYoutubeTakeover._();

  static const className = 'com.github.catvod.spider.ZakaYouTubeAmns';

  static const assetPath = 'assets/py_spiders/youtube.py';

  static String? _spiderPath;

  static bool isJarYoutubeSite(JarSiteSpec spec) =>
      spec.className == className;

  static bool isUsablePlan(PlaybackPlan plan) {
    if (plan.url.isEmpty || plan.needsParse) return false;
    if (plan.url.startsWith('proxy://') || plan.url.startsWith('proxy:')) {
      return false;
    }
    return plan.url.startsWith('http://') || plan.url.startsWith('https://');
  }

  static Future<String> _materializeSpider() async {
    final cached = _spiderPath;
    if (cached != null && await File(cached).exists()) return cached;
    final bytes = await rootBundle.load(assetPath);
    final fileName = await ImportFileStore.save(
      'builtin_jar_youtube',
      'py',
      bytes.buffer.asUint8List(),
    );
    final resolved = await ImportFileStore.pathOf(fileName);
    _spiderPath = resolved;
    return resolved;
  }

  static Future<PlaybackPlan?> tryResolve(
    JarSiteSpec spec,
    Drama drama,
    Episode episode,
  ) async {
    try {
      if (!isJarYoutubeSite(spec)) return null;
      if (!JarBridge.supported) return null;
      final status = await PyBridge.status();
      if (!status.available) return null;
      final flag = episode.raw['flag'] as String? ?? '';
      final playId = episode.raw['playId'] as String? ?? episode.id;
      if (playId.isEmpty) return null;
      final spiderPath = await _materializeSpider();
      final result = await PyBridge.call(spiderPath, {
        'action': 'resolve',
        'flag': flag,
        'playId': playId,
        'extend': spec.ext,
      });
      final plan = PyContract.planFromResult(result);
      if (!isUsablePlan(plan)) return null;
      return plan;
    } catch (_) {
      return null;
    }
  }
}
