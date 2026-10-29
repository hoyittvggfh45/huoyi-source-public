import 'package:flutter/material.dart';

import '../playback_parse.dart';
import '../playback_preferences.dart';
import '../player_core.dart';
import 'kotv_theme.dart';

enum KotvAspectRatio { fit }

enum KotvPlayerAutoSwitch { automatic, off }

String kotvDecoderLabel(TelevisionDecoder decoder) => switch (decoder) {
  TelevisionDecoder.optimized => '自动优化',
  TelevisionDecoder.hardware => '硬件解码',
  TelevisionDecoder.software => '软件解码',
};

Future<KotvAspectRatio?> showKotvAspectRatioDialog({
  required BuildContext context,
  required KotvAspectRatio current,
}) => showKotvOptionDialog<KotvAspectRatio>(
  context: context,
  title: '画面比例',
  options: KotvAspectRatio.values,
  current: current,
  label: (_) => '适应',
);

Future<KotvPlayerAutoSwitch?> showKotvPlayerAutoSwitchDialog({
  required BuildContext context,
  required KotvPlayerAutoSwitch current,
}) => showKotvOptionDialog<KotvPlayerAutoSwitch>(
  context: context,
  title: '自动切换播放器',
  options: KotvPlayerAutoSwitch.values,
  current: current,
  label: (value) => switch (value) {
    KotvPlayerAutoSwitch.automatic => '自动',
    KotvPlayerAutoSwitch.off => '关闭',
  },
);

Future<PlayerCore?> showKotvRenderBackendDialog({
  required BuildContext context,
  required PlayerCore current,
  required bool exoAvailable,
}) => showKotvOptionDialog<PlayerCore>(
  context: context,
  title: '渲染方式',
  options: [
    for (final core in PlayerCore.values)
      if (core != PlayerCore.exo || exoAvailable) core,
  ],
  current: current,
  label: (core) => core.dialogTitle,
);

Future<TelevisionDecoder?> showKotvDecoderDialog({
  required BuildContext context,
  required TelevisionDecoder current,
}) => showKotvOptionDialog<TelevisionDecoder>(
  context: context,
  title: '解码方式',
  options: TelevisionDecoder.values,
  current: current,
  label: kotvDecoderLabel,
);

Future<String?> showKotvDefaultParserDialog({
  required BuildContext context,
  required List<ParseInterface> interfaces,
  required String selectedId,
}) {
  final names = {for (final item in interfaces) item.id: item.name};
  return showKotvOptionDialog<String>(
    context: context,
    title: '默认解析器',
    options: ['', for (final item in interfaces) item.id],
    current: selectedId,
    label: (id) => id.isEmpty ? '不使用解析' : (names[id] ?? id),
  );
}
