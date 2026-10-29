import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'legado_builtin_data.dart';
import 'legado_gbk.dart';

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

class LegadoDrop {
  const LegadoDrop({required this.name, required this.reason});

  final String name;
  final String reason;

  static const reasonMissingName = '无名';
  static const reasonMissingSearchUrl = '无搜索地址';
  static const reasonBadShape = '形状不支持';
}

class LegadoParseReport {
  const LegadoParseReport({required this.sources, required this.dropped});

  final List<LegadoSource> sources;
  final List<LegadoDrop> dropped;
}

void _collectLegadoItems(
  dynamic decoded,
  List<LegadoSource> sources,
  List<LegadoDrop> dropped,
) {
  if (decoded is List) {
    for (final item in decoded) {
      _collectLegadoItems(item, sources, dropped);
    }
    return;
  }
  if (decoded is Map<String, dynamic>) {
    for (final key in const ['sources', 'bookSources', 'data']) {
      final inner = decoded[key];
      if (inner is List) {
        for (final item in inner) {
          _collectLegadoItems(item, sources, dropped);
        }
        return;
      }
    }
    final source = LegadoSource.fromJson(decoded);
    if (source.name.isEmpty) {
      dropped.add(
        LegadoDrop(name: source.url, reason: LegadoDrop.reasonMissingName),
      );
    } else if (source.searchUrl.isEmpty) {
      dropped.add(
        LegadoDrop(
          name: source.name,
          reason: LegadoDrop.reasonMissingSearchUrl,
        ),
      );
    } else {
      sources.add(source);
    }
    return;
  }
  dropped.add(const LegadoDrop(name: '', reason: LegadoDrop.reasonBadShape));
}

LegadoParseReport _reportFromDecoded(dynamic decoded) {
  final sources = <LegadoSource>[];
  final dropped = <LegadoDrop>[];
  _collectLegadoItems(decoded, sources, dropped);
  return LegadoParseReport(sources: sources, dropped: dropped);
}

LegadoParseReport parseLegadoSourcesReport(String text) {
  var cleaned = text;
  while (cleaned.startsWith('\uFEFF')) {
    cleaned = cleaned.substring(1);
  }
  try {
    return _reportFromDecoded(jsonDecode(cleaned));
  } catch (_) {
    final sources = <LegadoSource>[];
    final dropped = <LegadoDrop>[];
    var anyLineOk = false;
    for (final line in cleaned.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final part = _reportFromDecoded(jsonDecode(trimmed));
        sources.addAll(part.sources);
        dropped.addAll(part.dropped);
        anyLineOk = true;
      } catch (_) {}
    }
    if (anyLineOk) {
      return LegadoParseReport(sources: sources, dropped: dropped);
    }
    rethrow;
  }
}

List<LegadoSource> parseLegadoSources(String text) {
  return parseLegadoSourcesReport(text).sources;
}

String decodeLegadoImportBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return decodeGbkBytes(bytes);
  }
}

String legadoCheckReasonText(Map<String, dynamic> check) {
  if (check['supported'] != false) return '';
  final fields = check['unsupportedFields'];
  if (fields is! List) return '';
  const fieldNames = {
    'bookList': '搜索列表',
    'name': '书名',
    'author': '作者',
    'coverUrl': '封面',
    'bookUrl': '书籍链接',
    'intro': '简介',
  };
  const reasonNames = {
    'xpath': 'XPath',
    'js': 'JS',
    'jsonpath': '高级 JSONPath',
    'nth': ':nth 选择器',
    'child': ':first-child/:last-child',
  };
  final parts = <String>[];
  for (final item in fields) {
    if (item is! Map<String, dynamic>) continue;
    final field = (item['field'] ?? '').toString();
    final reason = (item['reason'] ?? '').toString();
    final fieldName = fieldNames[field] ?? field;
    final reasonName = reasonNames[reason] ?? reason;
    if (fieldName.isEmpty && reasonName.isEmpty) continue;
    parts.add('$fieldName（$reasonName）');
  }
  return parts.join('、');
}

class LegadoStore {
  static const _key = 'legado_sources_v1';
  static const _seededKey = 'legado_builtin_seeded_v2';

  static Future<int> seedBuiltin() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededKey) == true) return 0;
    final before = await load();
    final parsed = parseLegadoSources(builtinLegadoRulesJson);
    final merged = await addAll(parsed);
    await prefs.setBool(_seededKey, true);
    return merged.length - before.length;
  }

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
