import 'dart:convert';

import '../hiker_miniapp/hiker_miniapp_rule.dart';

enum ClipboardMatchKind { hikerRuleText, remoteRule, antPackageLink, cloudCode }

class ClipboardRuleMatch {
  const ClipboardRuleMatch({required this.kind, required this.payload});

  final ClipboardMatchKind kind;
  final String payload;
}

const _passwordIdentifiers = {
  'home_rule',
  'home_rule_v2',
  'home_rule_url',
  'home_sub',
};

ClipboardRuleMatch? matchClipboardRule(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.contains('￥')) {
    final parts = trimmed.split('￥');
    if (parts.length >= 3) {
      final identifier = parts[1].trim();
      if (_passwordIdentifiers.contains(identifier)) {
        final payload = parts.sublist(2).join('￥').trim();
        switch (identifier) {
          case 'home_rule':
            return ClipboardRuleMatch(
              kind: ClipboardMatchKind.hikerRuleText,
              payload: payload,
            );
          case 'home_rule_v2':
            final decoded = decodeHomeRuleV2(payload);
            if (decoded == null) return null;
            return ClipboardRuleMatch(
              kind: ClipboardMatchKind.hikerRuleText,
              payload: decoded,
            );
          case 'home_rule_url':
          case 'home_sub':
            return ClipboardRuleMatch(
              kind: ClipboardMatchKind.remoteRule,
              payload: payload,
            );
        }
      }
    }
  }
  if (isCloudCodeShape(trimmed)) {
    return ClipboardRuleMatch(
      kind: ClipboardMatchKind.cloudCode,
      payload: trimmed,
    );
  }
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      if (parseHikerMiniappRules(trimmed).isNotEmpty) {
        return ClipboardRuleMatch(
          kind: ClipboardMatchKind.hikerRuleText,
          payload: trimmed,
        );
      }
    } catch (_) {
      return null;
    }
  }
  if (trimmed.startsWith('https://')) {
    final path = trimmed.split(RegExp(r'[?#]')).first;
    if (path.toLowerCase().endsWith('.zip')) {
      return ClipboardRuleMatch(
        kind: ClipboardMatchKind.antPackageLink,
        payload: trimmed,
      );
    }
    return ClipboardRuleMatch(
      kind: ClipboardMatchKind.remoteRule,
      payload: trimmed,
    );
  }
  return null;
}

bool isCloudCodeShape(String text) {
  if (text.length > 200) return false;
  if (!text.startsWith('云')) return false;
  if (!text.contains('/')) return false;
  if (text.contains(' ') ||
      text.contains('\n') ||
      text.contains('\r') ||
      text.contains('\t')) {
    return false;
  }
  return true;
}

String? decodeHomeRuleV2(String payload) {
  var rest = payload;
  if (rest.startsWith('base64://')) {
    rest = rest.substring('base64://'.length);
  }
  final at = rest.lastIndexOf('@');
  if (at < 0) return null;
  final encoded = rest.substring(at + 1).trim();
  if (encoded.isEmpty) return null;
  try {
    return utf8.decode(base64Decode(encoded));
  } catch (_) {
    return null;
  }
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
