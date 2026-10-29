import 'dart:convert';

enum ClipboardMatchKind { antPackageLink }

class ClipboardRuleMatch {
  const ClipboardRuleMatch({required this.kind, required this.payload});

  final ClipboardMatchKind kind;
  final String payload;
}

ClipboardRuleMatch? matchClipboardRule(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('https://')) {
    final path = trimmed.split(RegExp(r'[?#]')).first;
    if (path.toLowerCase().endsWith('.zip')) {
      return ClipboardRuleMatch(
        kind: ClipboardMatchKind.antPackageLink,
        payload: trimmed,
      );
    }
  }
  return null;
}

String clipboardPromptHash(String text) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in utf8.encode(text)) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
