import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyPassResult {
  const DailyPassResult({required this.ok, this.message = ''});
  final bool ok;
  final String message;
}

class DailyPass {
  static const _url = 'https://zsub.97471201.workers.dev/api/gate/check';
  static const _key = 'zkgate1-7f3a9c2e5b8d1046';

  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('daily_pass_device');
    if (id == null || id.isEmpty) {
      final random = Random.secure();
      id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await prefs.setString('daily_pass_device', id);
    }
    return id;
  }

  static Future<DailyPassResult> verify(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const DailyPassResult(ok: false, message: '请输入今日密码');
    }
    try {
      final t = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final f = await _deviceId();
      final sig = Hmac(
        sha256,
        utf8.encode(_key),
      ).convert(utf8.encode('1|$trimmed|$f|$t')).toString();
      final uri = Uri.parse(_url).replace(
        queryParameters: {
          'k': 'jianshang',
          'c': trimmed,
          'f': f,
          't': '$t',
          's': sig,
          'm': 'day',
        },
      );
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.getUrl(uri);
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
        if (response.statusCode != 200) {
          return const DailyPassResult(ok: false, message: '网络错误，请重试');
        }
        final data = jsonDecode(await utf8.decoder.bind(response).join());
        if (data is Map && data['ok'] == 1) {
          return const DailyPassResult(ok: true);
        }
        final gateCode = data is Map ? data['code']?.toString() ?? '' : '';
        if (gateCode == 'LOCK') {
          return const DailyPassResult(ok: false, message: '试错次数太多，已锁定，请稍后再试');
        }
        return const DailyPassResult(ok: false, message: '密码错误，今日密码见皇帝影院频道');
      } finally {
        client.close();
      }
    } catch (_) {
      return const DailyPassResult(ok: false, message: '网络错误，请重试');
    }
  }
}
