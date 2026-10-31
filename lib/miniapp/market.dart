import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MarketItem {
  const MarketItem({
    required this.appId,
    required this.name,
    required this.version,
    required this.versionCode,
    required this.url,
    required this.md5,
    required this.size,
    required this.author,
    required this.description,
  });

  final String appId;
  final String name;
  final String version;
  final int versionCode;
  final String url;
  final String md5;
  final int size;
  final String author;
  final String description;

  bool get isZip => url.toLowerCase().endsWith('.zip');

  factory MarketItem.fromJson(Map<String, Object?> json) {
    final appId = json['appId'] as String? ?? json['id'] as String? ?? '';
    final name = json['name'] as String? ?? '';
    final url = json['url'] as String? ?? '';
    if (appId.isEmpty || name.isEmpty || url.isEmpty) {
      throw const FormatException('market item requires appId, name and url');
    }
    final versionCode = json['versionCode'];
    final size = json['size'];
    return MarketItem(
      appId: appId,
      name: name,
      version: json['version'] as String? ?? '',
      versionCode: versionCode is int
          ? versionCode
          : versionCode is num
          ? versionCode.toInt()
          : 0,
      url: url,
      md5: json['md5'] as String? ?? '',
      size: size is int
          ? size
          : size is num
          ? size.toInt()
          : 0,
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

List<MarketItem> parseMarketJson(Object? decoded) {
  final List<Object?> rows;
  if (decoded is Map<String, Object?>) {
    final apps = decoded['apps'];
    if (apps is! List) {
      throw const FormatException('market json has no apps list');
    }
    rows = apps;
  } else if (decoded is List) {
    rows = decoded;
  } else {
    throw const FormatException('market json must be an object or a list');
  }
  final items = <MarketItem>[];
  for (final row in rows) {
    if (row is! Map<String, Object?>) continue;
    try {
      items.add(MarketItem.fromJson(row));
    } catch (_) {
      continue;
    }
  }
  return items;
}

class MarketClient {
  MarketClient({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<List<MarketItem>> fetchItems(String url) async {
    final text = await _fetchText(url);
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const FormatException('market json is not valid json');
    }
    return parseMarketJson(decoded);
  }

  Future<List<int>> downloadPackage(MarketItem item) async {
    final bytes = await _fetchBytes(item.url);
    if (item.md5.isNotEmpty) {
      final actual = md5.convert(bytes).toString().toLowerCase();
      if (actual != item.md5.toLowerCase()) {
        throw const FormatException('market package md5 mismatch');
      }
    }
    return bytes;
  }

  Future<String> fetchManifestText(MarketItem item) async {
    final bytes = await _fetchBytes(item.url);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<String> _fetchText(String url) async {
    final bytes = await _fetchBytes(url);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String? directFallbackUrl(String url) {
    const prefix = 'https://ghfast.top/https://';
    if (url.startsWith(prefix)) {
      return 'https://${url.substring(prefix.length)}';
    }
    return null;
  }

  Future<List<int>> _fetchBytes(String url) async {
    try {
      return await _fetchBytesOnce(url);
    } catch (_) {
      final fallback = directFallbackUrl(url);
      if (fallback == null) rethrow;
      return await _fetchBytesOnce(fallback);
    }
  }

  Future<List<int>> _fetchBytesOnce(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
      throw const FormatException('market url must be an https address');
    }
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.userAgentHeader, 'huoyi-miniapp/1.0');
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException('market request failed: ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 128 * 1024 * 1024) {
        throw const FormatException('market package is too large');
      }
    }
    return bytes;
  }
}

class MarketSettings {
  MarketSettings(this.preferences);

  static const defaultUrl =
      'https://raw.githubusercontent.com/ant-video/ant-video/refs/heads/main/mini-app/market/market.json';
  static const _key = 'miniapp.marketUrl';
  static const _installedMapKey = 'miniapp.marketInstalledMap';

  final SharedPreferences preferences;

  String get url => preferences.getString(_key) ?? defaultUrl;

  Future<void> setUrl(String value) => preferences.setString(_key, value);

  Map<String, String> get installedIdMap {
    final raw = preferences.getString(_installedMapKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> recordInstalled(String marketAppId, String manifestId) async {
    final map = installedIdMap;
    map[marketAppId] = manifestId;
    await preferences.setString(_installedMapKey, jsonEncode(map));
  }
}
