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

class HikerMiniappNav {
  const HikerMiniappNav({required this.title, required this.sid});

  final String title;
  final String sid;
}

class HikerMiniappHomeResult {
  const HikerMiniappHomeResult({required this.cards, required this.navs});

  final List<HikerMiniappCard> cards;
  final List<HikerMiniappNav> navs;
}

const _homeChromeColTypes = {
  'scroll_button',
  'input',
  'text_icon',
  'text_center_1',
  'line_blank',
  'line',
  'blank_block',
  'rich_text',
};

class HikerMiniappEngine {
  const HikerMiniappEngine({required this.rule, required this.run});

  final HikerMiniappRule rule;
  final HikerRunFn run;

  Future<HikerMiniappHomeResult> home({
    int categoryIndex = 0,
    int page = 1,
    String? categorySid,
  }) async {
    if (!rule.hasFindRule) throw const HikerMiniappFailure('empty rule');
    final categories = rule.categories;
    if (categories.isNotEmpty) {
      final index = categoryIndex.clamp(0, categories.length - 1);
      var target = categories[index].url;
      if (target.isEmpty) target = rule.url;
      final raw = await _call(
        'list',
        hikerPageUrl(resolveHikerUrl(rule.url, target), page),
      );
      return HikerMiniappHomeResult(cards: _cards(raw), navs: const []);
    }
    var input = rule.url.isEmpty ? 'hiker://empty' : rule.url;
    final query = <String, String>{};
    if (categorySid != null && categorySid.isNotEmpty) {
      query['sd_cls'] = categorySid;
    }
    if (page > 1) query['sd_page'] = '$page';
    if (query.isNotEmpty) {
      final separator = input.contains('?') ? '&' : '?';
      final encoded = query.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&');
      input = '$input$separator$encoded';
    }
    final raw = await _call('list', input);
    return _splitHome(raw);
  }

  Future<List<HikerMiniappCard>> search(String keyword) async {
    if (!rule.hasSearch) throw const HikerMiniappFailure('empty rule');
    final raw = await _call('search', keyword);
    return _cards(raw);
  }

  Future<HikerMiniappDetail> detail(String url) async {
    if (!rule.hasDetail) throw const HikerMiniappFailure('empty rule');
    final resolvedUrl = resolveHikerUrl(rule.url, url);
    final raw = await _call('detail', resolvedUrl);
    final base = resolvedUrl.startsWith('http') ? resolvedUrl : rule.url;
    return HikerMiniappDetail.fromResult(
      resolveHikerResultUrls(raw, base),
      fallbackTitle: rule.title,
    );
  }

  Future<String> resolvePlayUrl(String episodeUrl) async {
    if (rule.lastChapterRule.trim().isEmpty) return episodeUrl;
    try {
      final raw = await _call('play', episodeUrl);
      final resolved = raw?.toString().trim() ?? '';
      if (resolved.isEmpty) return episodeUrl;
      return resolved;
    } catch (_) {
      return episodeUrl;
    }
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
      final out = <HikerMiniappCard>[];
      for (final e in raw) {
        final map = hikerAsMap(resolveHikerResultUrls(e, rule.url));
        if (_homeChromeColTypes.contains(map['col_type']?.toString() ?? '')) {
          continue;
        }
        final card = HikerMiniappCard.fromMap(map);
        if (card.title.isNotEmpty || card.url.isNotEmpty) out.add(card);
      }
      return out;
    }
    if (raw is Map) {
      final map = hikerAsMap(resolveHikerResultUrls(raw, rule.url));
      final data = map['data'];
      if (data is List) return _cards(data);
      if (_homeChromeColTypes.contains(map['col_type']?.toString() ?? '')) {
        return [];
      }
      final card = HikerMiniappCard.fromMap(map);
      if (card.title.isNotEmpty || card.url.isNotEmpty) return [card];
      return [];
    }
    return [];
  }

  HikerMiniappHomeResult _splitHome(dynamic raw) {
    final navs = <HikerMiniappNav>[];
    for (final item in _homeItems(raw)) {
      final map = hikerAsMap(resolveHikerResultUrls(item, rule.url));
      final colType = map['col_type']?.toString() ?? '';
      final url = map['url']?.toString() ?? map['href']?.toString() ?? '';
      if (colType == 'scroll_button' && url == 'hiker://empty') break;
      final card = HikerMiniappCard.fromMap(map);
      if (card.title.isEmpty && card.url.isEmpty) continue;
      if (_homeChromeColTypes.contains(colType)) {
        if (colType == 'scroll_button' && url.startsWith('hiker://lazy?')) {
          navs.add(_navFromLazy(map, url));
        }
        continue;
      }
      break;
    }
    return HikerMiniappHomeResult(cards: _cards(raw), navs: navs);
  }

  HikerMiniappNav _navFromLazy(Map<String, dynamic> map, String url) {
    var title = map['title']?.toString() ?? map['name']?.toString() ?? '';
    title = title.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    title = title.replaceAll(RegExp(r'^✓\s*'), '');
    var sid = '';
    try {
      final args = Uri.parse(url).queryParameters['args'];
      if (args != null) {
        final decoded = jsonDecode(args);
        if (decoded is List && decoded.isNotEmpty) {
          sid = decoded.first.toString();
        }
      }
    } catch (_) {}
    return HikerMiniappNav(title: title, sid: sid);
  }

  List<dynamic> _homeItems(dynamic raw) {
    if (raw is String) {
      try {
        return _homeItems(jsonDecode(raw));
      } catch (_) {
        return const [];
      }
    }
    if (raw is List) return raw;
    if (raw is Map) {
      final map = hikerAsMap(raw);
      final data = map['data'];
      if (data is List) return data;
      return [raw];
    }
    return const [];
  }
}
