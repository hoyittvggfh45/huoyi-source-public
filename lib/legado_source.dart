import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LegadoSource {
  const LegadoSource({
    required this.name,
    required this.url,
    required this.searchUrl,
    required this.rawJson,
  });

  final String name;
  final String url;
  final String searchUrl;
  final String rawJson;

  String get id => name.isNotEmpty ? name : url;

  factory LegadoSource.fromJson(Map<String, dynamic> json) {
    return LegadoSource(
      name: (json['bookSourceName'] ?? '').toString(),
      url: (json['bookSourceUrl'] ?? '').toString(),
      searchUrl: (json['searchUrl'] ?? '').toString(),
      rawJson: jsonEncode(json),
    );
  }
}

List<LegadoSource> parseLegadoSources(String text) {
  final decoded = jsonDecode(text);
  final items = <Map<String, dynamic>>[];
  if (decoded is List) {
    for (final item in decoded) {
      if (item is Map<String, dynamic>) items.add(item);
    }
  } else if (decoded is Map<String, dynamic>) {
    final inner = decoded['sources'];
    if (inner is List) {
      for (final item in inner) {
        if (item is Map<String, dynamic>) items.add(item);
      }
    } else {
      items.add(decoded);
    }
  }
  return items
      .map(LegadoSource.fromJson)
      .where((s) => s.name.isNotEmpty && s.searchUrl.isNotEmpty)
      .toList();
}

class LegadoStore {
  static const _key = 'legado_sources_v1';

  static Future<List<LegadoSource>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return parseLegadoSources(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<List<LegadoSource>> addAll(List<LegadoSource> sources) async {
    final existing = await load();
    final ids = existing.map((s) => s.id).toSet();
    for (final source in sources) {
      if (ids.add(source.id)) existing.add(source);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(existing.map((s) => jsonDecode(s.rawJson)).toList()),
    );
    return existing;
  }

  static Future<List<LegadoSource>> remove(LegadoSource source) async {
    final existing = await load();
    existing.removeWhere((s) => s.id == source.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(existing.map((s) => jsonDecode(s.rawJson)).toList()),
    );
    return existing;
  }
}
