import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../legado_gbk.dart';

class HostHttpResponse {
  const HostHttpResponse({
    required this.statusCode,
    required this.body,
    required this.bodyBytes,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final List<int> bodyBytes;
  final Map<String, String> headers;
}

class HostHttp {
  HostHttp({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<HostHttpResponse> get(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final request = await _client.getUrl(Uri.parse(url));
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    return _read(response);
  }

  Future<HostHttpResponse> post(
    String url, {
    Map<String, String> headers = const {},
    Object? body,
    String? contentType,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final request = await _client.postUrl(Uri.parse(url));
    headers.forEach(request.headers.set);
    if (contentType != null) {
      request.headers.contentType = ContentType.parse(contentType);
    }
    if (body is String) {
      request.write(body);
    } else if (body is List<int>) {
      request.add(body);
    } else if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(timeout);
    return _read(response);
  }

  Future<HostHttpResponse> _read(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    return HostHttpResponse(
      statusCode: response.statusCode,
      body: utf8.decode(bytes, allowMalformed: true),
      bodyBytes: bytes,
      headers: headers,
    );
  }

  void dispose() {
    _client.close(force: true);
  }
}

class HostCrypto {
  String md5Hex(String input) => md5.convert(utf8.encode(input)).toString();

  String sha1Hex(String input) => sha1.convert(utf8.encode(input)).toString();

  String sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  String sha512Hex(String input) =>
      sha512.convert(utf8.encode(input)).toString();

  String hmacSha1Hex(String key, String data) =>
      Hmac(sha1, utf8.encode(key)).convert(utf8.encode(data)).toString();

  String hmacSha256Hex(String key, String data) =>
      Hmac(sha256, utf8.encode(key)).convert(utf8.encode(data)).toString();
}

class HostGbk {
  String decodeBytes(List<int> bytes) => decodeGbkBytes(bytes);

  String decodeWithCharset(List<int> bytes, String charset) =>
      decodeLegadoBytes(bytes, charset);

  Uint8List encode(String input) {
    throw UnimplementedError(
      'HostGbk.encode is pending: tree legado_gbk only provides decoding',
    );
  }
}

class HostLocal {
  HostLocal(this._prefs, {this.namespace = 'default'});

  final SharedPreferences _prefs;
  final String namespace;

  static Future<HostLocal> open({String namespace = 'default'}) async {
    final prefs = await SharedPreferences.getInstance();
    return HostLocal(prefs, namespace: namespace);
  }

  String _key(String key) => 'hiker_host:$namespace:$key';

  String? getString(String key) => _prefs.getString(_key(key));

  Future<bool> setString(String key, String value) =>
      _prefs.setString(_key(key), value);

  int? getInt(String key) => _prefs.getInt(_key(key));

  Future<bool> setInt(String key, int value) =>
      _prefs.setInt(_key(key), value);

  bool? getBool(String key) => _prefs.getBool(_key(key));

  Future<bool> setBool(String key, bool value) =>
      _prefs.setBool(_key(key), value);

  Future<bool> remove(String key) => _prefs.remove(_key(key));

  List<String> keys() {
    final prefix = 'hiker_host:$namespace:';
    return _prefs
        .getKeys()
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .toList();
  }
}

class HostAssets {
  Future<String> loadString(String assetPath) =>
      rootBundle.loadString(assetPath);

  Future<Uint8List> loadBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  }
}

class HostPaths {
  HostPaths({required this.filesDir});

  final String filesDir;

  String resolve(String virtualPath) {
    if (virtualPath.startsWith('hiker://assets/')) {
      return virtualPath.substring('hiker://assets/'.length);
    }
    if (virtualPath.startsWith('hiker://files/')) {
      final rest = virtualPath.substring('hiker://files/'.length);
      if (filesDir.isEmpty) return rest;
      return '$filesDir/$rest';
    }
    if (virtualPath.startsWith('hiker://page/')) return '';
    if (virtualPath == 'hiker://empty') return '';
    return virtualPath;
  }

  bool get isFilesMapped => filesDir.isNotEmpty;
}

class HostCheerio {
  Never load(String html) {
    throw UnimplementedError(
      'HostCheerio is pending: no html parser dependency in tree',
    );
  }

  Never select(String selector) {
    throw UnimplementedError(
      'HostCheerio is pending: no html parser dependency in tree',
    );
  }
}

class HostApi {
  const HostApi({
    required this.http,
    required this.crypto,
    required this.gbk,
    required this.local,
    required this.localPublic,
    required this.assets,
    required this.paths,
    required this.cheerio,
  });

  final HostHttp http;
  final HostCrypto crypto;
  final HostGbk gbk;
  final HostLocal local;
  final HostLocal localPublic;
  final HostAssets assets;
  final HostPaths paths;
  final HostCheerio cheerio;

  static Future<HostApi> create({
    String localNamespace = 'default',
    String publicNamespace = 'public',
    String filesDir = '',
  }) async {
    final local = await HostLocal.open(namespace: localNamespace);
    final localPublic = await HostLocal.open(namespace: publicNamespace);
    return HostApi(
      http: HostHttp(),
      crypto: HostCrypto(),
      gbk: HostGbk(),
      local: local,
      localPublic: localPublic,
      assets: HostAssets(),
      paths: HostPaths(filesDir: filesDir),
      cheerio: HostCheerio(),
    );
  }

  Future<String> downloadFile(
    String url,
    String virtualPath, {
    Map<String, String> headers = const {},
  }) async {
    final resolved = paths.resolve(virtualPath);
    final response = await http.get(url, headers: headers);
    final file = File(resolved);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(response.bodyBytes);
    return resolved;
  }

  void dispose() {
    http.dispose();
  }
}
