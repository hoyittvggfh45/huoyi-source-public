import 'dart:convert';

import 'hiker_miniapp_models.dart';
import 'hiker_miniapp_rule.dart';
import 'hiker_rule_chain.dart';

typedef HikerRunFn =
    Future<dynamic> Function(String ruleJson, String action, String input);

class HikerMiniappFailure implements Exception {
  const HikerMiniappFailure(this.message);

  final String message;

  @override
  String toString() => 'HikerMiniappFailure: $message';
}

class HikerMiniappEngine {
  const HikerMiniappEngine({required this.rule, required this.run});

  final HikerMiniappRule rule;
  final HikerRunFn run;

  Future<List<HikerMiniappCard>> home({
    int categoryIndex = 0,
    int page = 1,
  }) async {
    if (!rule.hasFindRule) throw const HikerMiniappFailure('empty rule');
    final categories = rule.categories;
    var target = rule.url;
    if (categories.isNotEmpty) {
      final index = categoryIndex.clamp(0, categories.length - 1);
      target = categories[index].url;
    }
    if (target.isEmpty) target = rule.url;
    final raw = await _call('list', hikerPageUrl(target, page));
    return _cards(raw);
  }

  Future<List<HikerMiniappCard>> search(String keyword) async {
    if (!rule.hasSearch) throw const HikerMiniappFailure('empty rule');
    final raw = await _call('search', keyword);
    return _cards(raw);
  }

  Future<HikerMiniappDetail> detail(String url) async {
    if (!rule.hasDetail) throw const HikerMiniappFailure('empty rule');
    final raw = await _call('detail', url);
    return HikerMiniappDetail.fromResult(raw, fallbackTitle: rule.title);
  }

  Future<dynamic> _call(String action, String input) async {
    try {
      return await run(jsonEncode(rule.toEngineJson()), action, input);
    } catch (e) {
      if (e is HikerMiniappFailure) rethrow;
      throw HikerMiniappFailure(e.toString());
    }
  }

  List<HikerMiniappCard> _cards(dynamic raw) {
    if (raw is String) {
      try {
        return _cards(jsonDecode(raw));
      } catch (_) {
        return [];
      }
    }
    if (raw is List) {
      return [
        for (final e in raw) HikerMiniappCard.fromMap(hikerAsMap(e)),
      ].where((c) => c.title.isNotEmpty || c.url.isNotEmpty).toList();
    }
    if (raw is Map) {
      final map = hikerAsMap(raw);
      final data = map['data'];
      if (data is List) return _cards(data);
      final card = HikerMiniappCard.fromMap(map);
      if (card.title.isNotEmpty || card.url.isNotEmpty) return [card];
      return [];
    }
    return [];
  }
}
