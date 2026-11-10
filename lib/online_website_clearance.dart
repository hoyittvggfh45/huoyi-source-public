import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OnlineWebsiteClearance {
  const OnlineWebsiteClearance({
    required this.host,
    required this.clearance,
    required this.userAgent,
    required this.updatedAt,
  });

  final String host;
  final String clearance;
  final String userAgent;
  final DateTime updatedAt;

  bool get isStale =>
      DateTime.now().difference(updatedAt) > const Duration(minutes: 30);

  factory OnlineWebsiteClearance.fromJson(Map<String, dynamic> json) =>
      OnlineWebsiteClearance(
        host: json['host'] as String? ?? '',
        clearance: json['clearance'] as String? ?? '',
        userAgent: json['userAgent'] as String? ?? '',
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
    'host': host,
    'clearance': clearance,
    'userAgent': userAgent,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class OnlineWebsiteClearanceStore {
  static const _key = 'online_website_clearances';

  static Future<Map<String, OnlineWebsiteClearance>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, OnlineWebsiteClearance>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map) {
          final clearance = OnlineWebsiteClearance.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (clearance.host.isNotEmpty && clearance.clearance.isNotEmpty) {
            result[clearance.host] = clearance;
          }
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<OnlineWebsiteClearance?> loadForHost(String host) async {
    final all = await loadAll();
    var candidate = host.toLowerCase();
    while (true) {
      final found = all[candidate];
      if (found != null) return found;
      final dot = candidate.indexOf('.');
      if (dot < 0) return null;
      candidate = candidate.substring(dot + 1);
      if (!candidate.contains('.')) return all[candidate];
    }
  }

  static Future<void> save(OnlineWebsiteClearance clearance) async {
    final all = await loadAll();
    all[clearance.host] = clearance;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode({
        for (final entry in all.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  static Future<void> removeForHost(String host) async {
    final all = await loadAll();
    if (all.remove(host.toLowerCase()) == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode({
        for (final entry in all.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}
