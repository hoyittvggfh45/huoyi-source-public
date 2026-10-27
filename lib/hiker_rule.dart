import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HikerRule {
  const HikerRule({
    required this.title,
    required this.type,
    required this.url,
    required this.colType,
    required this.findRule,
    required this.searchFind,
    required this.detailFindRule,
    required this.searchUrl,
    required this.ua,
    this.preRule = '',
  });

  final String title;
  final String type;
  final String url;
  final String colType;
  final String findRule;
  final String searchFind;
  final String detailFindRule;
  final String searchUrl;
  final String ua;
  final String preRule;

  factory HikerRule.fromJson(Map<String, dynamic> json) => HikerRule(
    title: json['title'] as String? ?? '',
    type: json['type'] as String? ?? '',
    url: json['url'] as String? ?? '',
    colType: json['col_type'] as String? ?? '',
    findRule: json['find_rule'] as String? ?? '',
    searchFind: json['searchFind'] as String? ?? '',
    detailFindRule: json['detail_find_rule'] as String? ?? '',
    searchUrl: json['search_url'] as String? ?? '',
    ua: json['ua'] as String? ?? '',
    preRule: json['preRule'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'type': type,
    'url': url,
    'col_type': colType,
    'find_rule': findRule,
    'searchFind': searchFind,
    'detail_find_rule': detailFindRule,
    'search_url': searchUrl,
    'ua': ua,
    'preRule': preRule,
  };

  String get id => title.isEmpty ? url : title;
}

({String identifier, String payload})? parseHikerPassword(String text) {
  final trimmed = text.trim();
  if (!trimmed.contains('￥')) return null;
  final parts = trimmed.split('￥');
  if (parts.length < 3 || !parts[0].contains('海阔视界')) return null;
  return (
    identifier: parts[1].trim(),
    payload: parts.sublist(2).join('￥').trim(),
  );
}

List<HikerRule> parseHikerRules(String text) {
  final decoded = jsonDecode(text);
  final items = decoded is List
      ? decoded
      : decoded is Map
      ? [decoded]
      : <dynamic>[];
  final out = <HikerRule>[];
  for (final item in items) {
    if (item is Map<String, dynamic>) {
      final rule = HikerRule.fromJson(item);
      if (rule.title.isNotEmpty || rule.url.isNotEmpty) out.add(rule);
    } else if (item is Map) {
      final rule = HikerRule.fromJson(
        item.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (rule.title.isNotEmpty || rule.url.isNotEmpty) out.add(rule);
    }
  }
  return out;
}

class HikerStore {
  static const _key = 'hiker_rules_v1';

  static Future<List<HikerRule>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return parseHikerRules(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<List<HikerRule>> addAll(List<HikerRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await load();
    final merged = [...existing];
    for (final rule in rules) {
      final index = merged.indexWhere((r) => r.id == rule.id);
      if (index >= 0) {
        merged[index] = rule;
      } else {
        merged.add(rule);
      }
    }
    await prefs.setString(
      _key,
      jsonEncode([for (final r in merged) r.toJson()]),
    );
    return merged;
  }

  static Future<List<HikerRule>> remove(HikerRule rule) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await load();
    final kept = [
      for (final r in existing)
        if (r.id != rule.id) r,
    ];
    await prefs.setString(_key, jsonEncode([for (final r in kept) r.toJson()]));
    return kept;
  }
}
