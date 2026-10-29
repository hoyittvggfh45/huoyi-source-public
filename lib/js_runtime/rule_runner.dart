import 'dart:convert';

import 'hiker_rule.dart';
import 'js_bridge.dart';

typedef RuleFetcher = Future<String> Function(
  String url,
  Map<String, String> headers,
);

class RuleException implements Exception {
  RuleException(this.message);

  final String message;

  @override
  String toString() => 'RuleException: $message';
}

class _ItemFields {
  String? title;
  String? picUrl;
  String? url;
  String? desc;
}

class RuleRunner {
  RuleRunner({required this.bridge, required this.fetcher});

  final JsBridge bridge;
  final RuleFetcher fetcher;

  static List<HikerRule> searchableRules(Iterable<HikerRule> rules) {
    return rules.where((rule) => rule.hasSearch).toList();
  }

  Map<String, String> _headers(HikerRule rule) {
    if (rule.ua.isEmpty) return const <String, String>{};
    return <String, String>{'User-Agent': rule.ua};
  }

  Future<List<MiniAppCard>> runList(
    HikerRule rule, {
    int page = 1,
    Map<String, String> filters = const <String, String>{},
    String host = '',
  }) async {
    final url = rule.buildListUrl(
      page: page,
      cls: filters['class'],
      area: filters['area'],
      sort: filters['sort'],
      year: filters['year'],
      host: host,
    );
    final html = await fetcher(url, _headers(rule));
    final preResult = await _runPreRule(rule, html, url);
    await bridge.setPageCache(<String, String>{url: html});
    await bridge.setContext(preResult: preResult, pageHtml: html);
    final cards = await _runRuleCode(rule.findRule, html, url);
    return cards
        .map(
          (card) => card.colType.isEmpty
              ? card.withColType(rule.colType)
              : card,
        )
        .toList();
  }

  Future<List<MiniAppCard>> runSearch(
    HikerRule rule,
    String keyword, {
    int page = 1,
    String host = '',
  }) async {
    if (!rule.hasSearch) {
      throw RuleException('rule has no search');
    }
    final url = rule.buildSearchUrl(keyword, page: page, host: host);
    final html = await fetcher(url, _headers(rule));
    final preResult = await _runPreRule(rule, html, url);
    await bridge.setPageCache(<String, String>{url: html});
    await bridge.setContext(preResult: preResult, pageHtml: html);
    final cards = await _runRuleCode(rule.searchFind, html, url);
    return cards
        .map(
          (card) => card.colType.isEmpty
              ? card.withColType(rule.colType)
              : card,
        )
        .toList();
  }

  Future<MiniAppDetail> runDetail(
    HikerRule rule,
    MiniAppCard card, {
    String host = '',
  }) async {
    final detailColType =
        rule.detailColType.isNotEmpty ? rule.detailColType : card.colType;
    if (rule.hasProxy) {
      return MiniAppDetail(
        title: card.title,
        picUrl: card.picUrl,
        desc: card.desc,
        colType: detailColType,
        playUrl: card.url,
        proxy: rule.proxy,
      );
    }
    if (card.url.isEmpty) return MiniAppDetail.none();
    final headers = _headers(rule);
    if (rule.hasChapters) {
      final html = await fetcher(card.url, headers);
      await bridge.setPageCache(<String, String>{card.url: html});
      await bridge.setContext(pageHtml: html);
      final chapters = await _runChapterCode(rule.lastChapterRule, html);
      return MiniAppDetail(
        title: card.title,
        picUrl: card.picUrl,
        desc: card.desc,
        colType: detailColType,
        playUrl: card.url,
        chapters: chapters,
      );
    }
    if (rule.hasDetail) {
      final html = await fetcher(card.url, headers);
      await bridge.setPageCache(<String, String>{card.url: html});
      await bridge.setContext(pageHtml: html);
      return _detailFromCode(rule.detailFindRule, html, card, rule);
    }
    if (rule.hasSdetail) {
      final sdetail = rule.sdetailFindRule;
      if (sdetail.startsWith('js:')) {
        final html = await fetcher(card.url, headers);
        await bridge.setPageCache(<String, String>{card.url: html});
        await bridge.setContext(pageHtml: html);
        return _detailFromCode(sdetail, html, card, rule);
      }
    }
    if (card.title.isNotEmpty ||
        card.picUrl.isNotEmpty ||
        card.desc.isNotEmpty) {
      return MiniAppDetail.fromCard(card);
    }
    if (card.url.startsWith('https://') || card.url.startsWith('http://')) {
      return MiniAppDetail(
        title: card.title,
        picUrl: card.picUrl,
        desc: card.desc,
        colType: detailColType,
        frameUrl: card.url,
      );
    }
    return MiniAppDetail.none();
  }

  Future<List<MiniAppCard>> runSubPage(
    HikerRule rule,
    MiniAppSubPage sub, {
    int page = 1,
    String host = '',
  }) async {
    var url = sub.path;
    if (!url.startsWith('http://') &&
        !url.startsWith('https://') &&
        !url.startsWith('hiker://')) {
      if (host.isNotEmpty) {
        url = host + (url.startsWith('/') ? url : '/$url');
      }
    }
    url = url.replaceAll('fypage', page.toString());
    final html = await fetcher(url, _headers(rule));
    await bridge.setPageCache(<String, String>{url: html});
    await bridge.setContext(pageHtml: html);
    final cards = await _runRuleCode(sub.rule, html, url);
    final fallbackColType =
        sub.colType.isNotEmpty ? sub.colType : rule.colType;
    return cards
        .map(
          (card) => card.colType.isEmpty
              ? card.withColType(fallbackColType)
              : card,
        )
        .toList();
  }

  Future<dynamic> _runPreRule(
    HikerRule rule,
    String html,
    String pageUrl,
  ) async {
    final pre = rule.preRule;
    if (pre.isEmpty) return null;
    await bridge.setPageCache(<String, String>{pageUrl: html});
    await bridge.setContext(pageHtml: html);
    if (pre.startsWith('js:')) {
      final outcome = await bridge.runJsCode(pre.substring(3));
      if (!outcome.ok) {
        throw RuleException('preRule failed: ${outcome.error}');
      }
      return outcome.setResult;
    }
    final collected = <String>[];
    for (final segment in pre.split(';')) {
      final seg = segment.trim();
      if (seg.isEmpty) continue;
      if (seg.contains('&&')) {
        collected.addAll(await bridge.pdfaList(html, seg));
      } else if (seg.startsWith('js:')) {
        final outcome = await bridge.runJsCode(seg.substring(3));
        if (outcome.setResult != null) {
          collected.add(outcome.setResult.toString());
        }
      }
    }
    return collected.isEmpty ? null : collected;
  }

  Future<List<MiniAppCard>> _runRuleCode(
    String code,
    String html,
    String pageUrl,
  ) async {
    if (code.startsWith('js:')) {
      final outcome = await bridge.runJsCode(code.substring(3));
      if (!outcome.ok) {
        throw RuleException('js rule failed: ${outcome.error}');
      }
      return cardsFromSetResult(outcome.setResult, '');
    }
    final segments = code
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (segments.isEmpty) return const <MiniAppCard>[];
    if (segments.length == 1) {
      final items = await bridge.pdfaList(html, segments[0]);
      return items
          .map(
            (item) => MiniAppCard(title: '', url: '', desc: item),
          )
          .toList();
    }
    final items = await bridge.pdfaList(html, segments[0]);
    final cards = <MiniAppCard>[];
    for (final item in items) {
      final fields = await _evalItemSegments(segments.sublist(1), item);
      if (fields.title == null &&
          fields.picUrl == null &&
          fields.url == null &&
          fields.desc == null) {
        continue;
      }
      cards.add(
        MiniAppCard(
          title: fields.title ?? '',
          url: fields.url ?? '',
          picUrl: fields.picUrl ?? '',
          desc: fields.desc ?? '',
        ),
      );
    }
    return cards;
  }

  Future<_ItemFields> _evalItemSegments(
    List<String> segments,
    String itemHtml,
  ) async {
    final fields = _ItemFields();
    for (final segment in segments) {
      final value = await _evalSegment(segment, itemHtml);
      if (value.isEmpty) continue;
      final tail = _segmentTail(segment);
      if (tail == 'href') {
        fields.url ??= value;
      } else if (tail == 'src' ||
          tail == 'data-original' ||
          tail == 'data-src' ||
          tail.contains('style')) {
        fields.picUrl ??= value;
      } else if (tail == 'Text' ||
          tail == 'title' ||
          tail == 'Title' ||
          tail == 'alt') {
        if (fields.title == null) {
          fields.title = value;
        } else {
          fields.desc ??= value;
        }
      } else if (tail == 'Html') {
        fields.desc ??= value;
      }
    }
    return fields;
  }

  Future<String> _evalSegment(String segment, String itemHtml) async {
    final jsIndex = segment.indexOf('js:');
    if (jsIndex < 0) {
      return bridge.pdfhValue(itemHtml, segment);
    }
    final base = segment.substring(0, jsIndex);
    final jsCode = segment.substring(jsIndex + 3);
    String baseResult;
    if (base.isEmpty) {
      baseResult = itemHtml;
    } else if (base.contains('&&')) {
      baseResult = await bridge.pdfhValue(itemHtml, base);
    } else {
      baseResult = base;
    }
    try {
      return bridge.engine.eval(
        'var input = ${jsonEncode(baseResult)}; $jsCode',
      );
    } catch (e) {
      throw RuleException('segment js failed: $e');
    }
  }

  String _segmentTail(String segment) {
    var seg = segment;
    final jsIndex = seg.indexOf('js:');
    if (jsIndex >= 0) seg = seg.substring(0, jsIndex);
    if (seg.contains('&&')) {
      return seg.substring(seg.lastIndexOf('&&') + 2).trim();
    }
    return seg.trim();
  }

  Future<MiniAppDetail> _detailFromCode(
    String code,
    String html,
    MiniAppCard card,
    HikerRule rule,
  ) async {
    final detailColType =
        rule.detailColType.isNotEmpty ? rule.detailColType : card.colType;
    if (code.startsWith('js:')) {
      final outcome = await bridge.runJsCode(code.substring(3));
      if (!outcome.ok) {
        throw RuleException('detail rule failed: ${outcome.error}');
      }
      return _detailFromSetResult(outcome.setResult, card, detailColType);
    }
    final segments = code
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final fields = await _evalItemSegments(segments, html);
    return MiniAppDetail(
      title: fields.title ?? card.title,
      picUrl: fields.picUrl ?? card.picUrl,
      desc: fields.desc ?? card.desc,
      colType: detailColType,
      playUrl: fields.url ?? card.url,
    );
  }

  MiniAppDetail _detailFromSetResult(
    dynamic value,
    MiniAppCard card,
    String detailColType,
  ) {
    if (value is Map) {
      String str(String key) {
        final v = value[key];
        if (v == null) return '';
        return v.toString();
      }

      final title = str('title').isNotEmpty ? str('title') : card.title;
      var pic = str('pic_url');
      if (pic.isEmpty) pic = str('pic');
      if (pic.isEmpty) pic = card.picUrl;
      var desc = str('desc');
      if (desc.isEmpty) desc = str('description');
      if (desc.isEmpty) desc = card.desc;
      final episodes = <String>[];
      final ep = value['episodes'] ?? value['list'] ?? value['chapters'];
      if (ep is List) {
        for (final e in ep) {
          if (e is String) {
            episodes.add(e);
          } else if (e is Map) {
            final t = e['title']?.toString() ??
                e['name']?.toString() ??
                '';
            if (t.isNotEmpty) episodes.add(t);
          }
        }
      }
      var play = str('url');
      if (play.isEmpty) play = str('playUrl');
      if (play.isEmpty) play = card.url;
      return MiniAppDetail(
        title: title,
        picUrl: pic,
        desc: desc,
        colType: detailColType,
        playUrl: play,
        episodes: episodes,
      );
    }
    if (value is List) {
      final episodes = value.map((e) => e.toString()).toList();
      return MiniAppDetail(
        title: card.title,
        picUrl: card.picUrl,
        desc: card.desc,
        colType: detailColType,
        playUrl: card.url,
        episodes: episodes,
      );
    }
    return MiniAppDetail.fromCard(card);
  }

  Future<List<MiniAppChapter>> _runChapterCode(
    String code,
    String html,
  ) async {
    if (code.startsWith('js:')) {
      final outcome = await bridge.runJsCode(code.substring(3));
      if (!outcome.ok) {
        throw RuleException('chapter rule failed: ${outcome.error}');
      }
      final items = _flattenToList(outcome.setResult);
      final chapters = <MiniAppChapter>[];
      for (final item in items) {
        if (item is String) {
          chapters.add(MiniAppChapter(title: item, url: ''));
        } else if (item is Map) {
          final title = item['title']?.toString() ??
              item['name']?.toString() ??
              '';
          final url = item['url']?.toString() ??
              item['link']?.toString() ??
              '';
          if (title.isNotEmpty || url.isNotEmpty) {
            chapters.add(MiniAppChapter(title: title, url: url));
          }
        }
      }
      return chapters;
    }
    final segments = code
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (segments.isEmpty) return const <MiniAppChapter>[];
    final items = await bridge.pdfaList(html, segments[0]);
    final chapters = <MiniAppChapter>[];
    for (final item in items) {
      final fields = await _evalItemSegments(segments.sublist(1), item);
      if (fields.title == null && fields.url == null) continue;
      chapters.add(
        MiniAppChapter(
          title: fields.title ?? '',
          url: fields.url ?? '',
        ),
      );
    }
    return chapters;
  }
}

List<dynamic> _flattenToList(dynamic value) {
  if (value == null) return const <dynamic>[];
  if (value is List) return value;
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.value is List) return entry.value as List;
    }
    return <dynamic>[value];
  }
  return <dynamic>[value];
}
