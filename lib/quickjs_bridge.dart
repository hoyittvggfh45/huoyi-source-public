import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class QuickJSResult {
  const QuickJSResult({required this.ok, this.result, this.error = ''});

  final bool ok;
  final dynamic result;
  final String error;

  factory QuickJSResult.fromJson(Map<String, dynamic> json) => QuickJSResult(
        ok: json['ok'] == true,
        result: json['result'],
        error: json['error'] as String? ?? '',
      );
}

class QuickJSBridge {
  QuickJSBridge._();

  static const _channel = MethodChannel('huoyi/quickjs');

  static Future<QuickJSResult> eval(
    String script, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final raw = await _channel.invokeMethod<String>('eval', {
      'script': script,
      'timeoutMs': timeout.inMilliseconds,
    });
    if (raw == null || raw.isEmpty) {
      return const QuickJSResult(ok: false, error: 'QuickJS 无返回');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const QuickJSResult(ok: false, error: 'QuickJS 返回格式不对');
    }
    return QuickJSResult.fromJson(decoded);
  }

  static Future<bool> get available async {
    try {
      final raw = await _channel.invokeMethod<String>('status');
      if (raw == null) return false;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> && decoded['available'] == true;
    } catch (_) {
      return false;
    }
  }
}
