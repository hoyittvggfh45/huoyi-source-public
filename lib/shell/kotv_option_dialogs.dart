import 'package:flutter/material.dart';

import '../playback_parse.dart';
import '../playback_preferences.dart';
import 'kotv_theme.dart';

enum KotvAspectRatio { fit }

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
