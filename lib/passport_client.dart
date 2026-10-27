import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'hongguo_account.dart';

class PassportException implements Exception {
  PassportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class QrTicket {
  const QrTicket({required this.ticket, required this.imageUrl});

  final String ticket;
  final String imageUrl;
}

class PassportClient {
  PassportClient({HttpClient? client}) : _client = client ?? HttpClient();

  static const _host = 'passport.snssdk.com';

  final HttpClient _client;

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> fields,
  ) async {
    final request = await _client.postUrl(Uri.https(_host, path));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.headers.set('user-agent', 'Huoyi/1.0 (Flutter)');
    request.write(Uri(queryParameters: fields).query);
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw PassportException('登录服务返回异常，请稍后重试');
    }
    return decoded;
  }

  Map<String, dynamic> _payload(Map<String, dynamic> response) {
    final errorCode = response['error_code'] ?? response['code'];
    if (errorCode is int && errorCode != 0) {
      throw PassportException(
        _stringField(response, ['message', 'error', 'msg']) ?? '登录失败，请稍后重试',
      );
    }
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    return response;
  }

  String? _stringField(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> requestSmsCode(String phone) async {
    final response = await _post('/passport/mobile/send_code/', {
      'mobile': phone,
      'type': 'login',
    });
    _payload(response);
  }

  Future<HongguoAccount> verifySmsCode(String phone, String code) async {
    final response = await _post('/passport/mobile/login/', {
      'mobile': phone,
      'code': code,
    });
    final data = _payload(response);
    return _accountFrom(data, method: 'sms', maskedPhone: phone);
  }

  Future<QrTicket> createQrTicket() async {
    final response = await _post('/passport/qrcode/create/', {});
    final data = _payload(response);
    final ticket = _stringField(data, ['ticket', 'qrcode_ticket', 'token']);
    final imageUrl =
        _stringField(data, ['qrcode_url', 'image_url', 'url']) ?? '';
    if (ticket == null || ticket.isEmpty) {
      throw PassportException('获取登录二维码失败，请稍后重试');
    }
    return QrTicket(ticket: ticket, imageUrl: imageUrl);
  }

  Future<HongguoAccount?> pollQrTicket(String ticket) async {
    final response = await _post('/passport/qrcode/scan_status/', {
      'ticket': ticket,
    });
    final data = _payload(response);
    final status = _stringField(data, ['status', 'state']) ?? '';
    if (status == 'success' || status == 'authorized' || status == 'login') {
      return _accountFrom(data, method: 'qr');
    }
    if (status == 'expired' || status == 'cancelled' || status == 'canceled') {
      throw PassportException('二维码已失效，请重新获取');
    }
    return null;
  }

  HongguoAccount _accountFrom(
    Map<String, dynamic> data, {
    required String method,
    String maskedPhone = '',
  }) {
    final userId =
        _stringField(data, ['user_id', 'uid', 'id', 'open_id']) ?? '';
    if (userId.isEmpty) {
      throw PassportException('登录返回中缺少账号信息，请稍后重试');
    }
    final name =
        _stringField(data, ['nickname', 'name', 'screen_name']) ?? '已登录账号';
    return HongguoAccount(
      userId: userId,
      displayName: name,
      maskedPhone: maskedPhone.isEmpty
          ? ''
          : HongguoAccount.maskPhone(maskedPhone),
      method: method,
    );
  }
}
