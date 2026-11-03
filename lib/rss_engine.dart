import 'dart:convert';

import 'package:enough_convert/gbk.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'rss_model.dart';

const _rssUserAgent =
    'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 '
    'Chrome/120.0 Mobile Safari/537.36';

class RssListResult {
  const RssListResult({
    required this.items,
    required this.nextPageUrl,
  });

  final List<RssItem> items;
  final String? nextPageUrl;
}

class RssArticleResult {
  const RssArticleResult({
    required this.blocks,
    required this.originalLink,
  });

  final List<RssContentBlock> blocks;
  final String originalLink;
}

abstract class RssEngineApi {
  Future<RssListResult> fetchItems(RssSource source, {int page = 1});

  Future<RssListResult> fetchPageUrl(RssSource source, String pageUrl);

  Future<RssArticleResult> fetchArticle(RssSource source, RssItem item);
}

class _Step {
  const _Step.tag(this.name, {this.cls = ''})
    : kind = _StepKind.tag,
      index = 0;

  const _Step.cls(this.name)
    : kind = _StepKind.cls,
      cls = '',
      index = 0;

  const _Step.id(this.name)
    : kind = _StepKind.id,
      cls = '',
      index = 0;

  const _Step.index(this.index)
    : kind = _StepKind.at,
      name = '',
      cls = '';

  const _Step.children()
    : kind = _StepKind.children,
      name = '',
      cls = '',
      index = 0;

  final _StepKind kind;
  final String name;
  final String cls;
  final int index;
}

enum _StepKind { tag, cls, id, at, children }

const _extractions = {'text', 'textNodes', 'html', 'href', 'src', 'alt'};

bool _isIndexToken(String token) => RegExp(r'^-?\d+$').hasMatch(token);

List<_Step> _parseSteps(String token) {
  if (token == 'children') return const [_Step.children()];
  List<_Step> withRest(
    _Step Function(String) first,
    List<String> rest,
  ) {
    final steps = <_Step>[first(rest.first)];
    for (final part in rest.skip(1)) {
      if (_isIndexToken(part)) {
        steps.add(_Step.index(int.parse(part)));
      } else if (steps.length == 1 && steps.first.kind == _StepKind.tag) {
        steps[0] = _Step.tag(steps.first.name, cls: part);
      } else {
        steps.add(_Step.cls(part));
      }
    }
    return steps;
  }

  if (token.startsWith('tag.')) {
    return withRest((name) => _Step.tag(name), token.substring(4).split('.'));
  }
  if (token.startsWith('class.')) {
    return withRest((name) => _Step.cls(name), token.substring(6).split('.'));
  }
  if (token.startsWith('id.')) {
    return withRest((name) => _Step.id(name), token.substring(3).split('.'));
  }
  if (token.startsWith('.')) {
    final parts = token.substring(1).split('.');
    final steps = <_Step>[];
    if (parts.first.isNotEmpty && !_isIndexToken(parts.first)) {
      steps.add(_Step.cls(parts.first));
    }
    for (final part in parts.skip(1)) {
      if (_isIndexToken(part)) {
        steps.add(_Step.index(int.parse(part)));
      } else {
        steps.add(_Step.cls(part));
      }
    }
    if (parts.first.isNotEmpty && _isIndexToken(parts.first)) {
      steps.add(_Step.index(int.parse(parts.first)));
    }
    return steps;
  }
  if (_isIndexToken(token)) return [_Step.index(int.parse(token))];
  return withRest((name) => _Step.tag(name), token.split('.'));
}

bool _isExtractionToken(String token) {
  if (_extractions.contains(token)) return true;
  if (token.contains('-') || token.contains('_') || token.contains(':')) {
    return true;
  }
  return false;
}

List<Element> _applySteps(List<Element> current, List<_Step> steps) {
  var set = current;
  for (final step in steps) {
    switch (step.kind) {
      case _StepKind.tag:
        final selector = step.cls.isEmpty
            ? step.name
            : '${step.name}.${step.cls}';
        final found = <Element>[];
        final seen = <Element>{};
        for (final element in set) {
          for (final match in element.querySelectorAll(selector)) {
            if (seen.add(match)) found.add(match);
          }
        }
        set = found;
      case _StepKind.cls:
        final found = <Element>[];
        final seen = <Element>{};
        for (final element in set) {
          for (final match in element.querySelectorAll('.${step.name}')) {
            if (seen.add(match)) found.add(match);
          }
        }
        set = found;
      case _StepKind.id:
        final found = <Element>[];
        for (final element in set) {
          final match = element.querySelector('#${step.name}');
          if (match != null) found.add(match);
        }
        set = found;
      case _StepKind.at:
        if (set.isEmpty) {
          set = const [];
        } else {
          final at = step.index >= 0 ? step.index : set.length + step.index;
          set = at >= 0 && at < set.length ? [set[at]] : const [];
        }
      case _StepKind.children:
        set = [for (final element in set) ...element.children];
    }
    if (set.isEmpty) break;
  }
  return set;
}

String _extract(Element element, String extraction) {
  switch (extraction) {
    case 'text':
      return element.text.trim();
    case 'textNodes':
      final buffer = StringBuffer();
      for (final node in element.nodes) {
        if (node is Text) buffer.write(node.text);
      }
      return buffer.toString().trim();
    case 'html':
      return element.innerHtml.trim();
    case 'href':
    case 'src':
    case 'alt':
      return element.attributes[extraction]?.trim() ?? '';
    default:
      return element.attributes[extraction]?.trim() ?? '';
  }
}

List<String> _splitAlternatives(String rule) {
  final parts = <String>[];
  var depth = 0;
  final current = StringBuffer();
  for (var i = 0; i < rule.length; i++) {
    final char = rule[i];
    if (char == '{' && i + 1 < rule.length && rule[i + 1] == '{') {
      depth++;
    }
    if (char == '}' && i + 1 < rule.length && rule[i + 1] == '}') {
      depth--;
    }
    if (depth == 0 &&
        char == '|' &&
        i + 1 < rule.length &&
        rule[i + 1] == '|') {
      parts.add(current.toString());
      current.clear();
      i++;
      continue;
    }
    current.write(char);
  }
  parts.add(current.toString());
  return parts;
}

dynamic _evalJsonPath(dynamic root, String path) {
  var current = root;
  var rest = path;
  if (rest.startsWith(r'$..')) {
    final key = rest.substring(3).split('.').first;
    return _jsonDeepFind(root, key);
  }
  if (rest.startsWith(r'$.')) {
    rest = rest.substring(2);
  } else if (rest == r'$') {
    return root;
  } else if (rest.startsWith(r'$')) {
    rest = rest.substring(1);
    if (rest.startsWith('.')) rest = rest.substring(1);
  }
  if (rest.isEmpty) return current;
  final segments = <String>[];
  final buffer = StringBuffer();
  for (var i = 0; i < rest.length; i++) {
    final char = rest[i];
    if (char == '.') {
      if (buffer.isNotEmpty) {
        segments.add(buffer.toString());
        buffer.clear();
      }
    } else if (char == '[') {
      if (buffer.isNotEmpty) {
        segments.add(buffer.toString());
        buffer.clear();
      }
      final close = rest.indexOf(']', i);
      if (close < 0) break;
      segments.add(rest.substring(i + 1, close));
      i = close;
    } else {
      buffer.write(char);
    }
  }
  if (buffer.isNotEmpty) segments.add(buffer.toString());
  for (final segment in segments) {
    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) {
        return null;
      }
      current = current[index];
    } else {
      return null;
    }
    if (current == null) return null;
  }
  return current;
}

dynamic _jsonDeepFind(dynamic node, String key) {
  if (node is Map) {
    if (node.containsKey(key)) return node[key];
    for (final value in node.values) {
      final found = _jsonDeepFind(value, key);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final value in node) {
      final found = _jsonDeepFind(value, key);
      if (found != null) return found;
    }
  }
  return null;
}

String _jsonScalar(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is num || value is bool) return value.toString();
  return jsonEncode(value);
}

List<String> _jsonStrings(dynamic value) {
  if (value == null) return const [];
  if (value is List) {
    return [
      for (final item in value)
        if (_jsonScalar(item).isNotEmpty) _jsonScalar(item),
    ];
  }
  final single = _jsonScalar(value);
  return single.isEmpty ? const [] : [single];
}

dynamic _parseJsLiteral(String body) {
  final text = body.trim();
  if (text.isEmpty) return null;
  if ((text.startsWith('"') && text.endsWith('"')) ||
      (text.startsWith("'") && text.endsWith("'"))) {
    return text.substring(1, text.length - 1);
  }
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

bool _looksLikeScript(String rule) {
  final text = rule.trim();
  return text.contains('<js>') || text.startsWith('@js:');
}

dynamic _evalJsLiteralRule(String rule) {
  final text = rule.trim();
  if (text.startsWith('@js:')) {
    final body = text.substring(4).trim();
    final parsed = _parseJsLiteral(body);
    if (parsed != null) return parsed;
    throw const RssFailure('该源用了脚本规则，当前版本暂不支持', scriptUnsupported: true);
  }
  if (text.contains('<js>')) {
    throw const RssFailure('该源用了脚本规则，当前版本暂不支持', scriptUnsupported: true);
  }
  return null;
}

class RssEngine implements RssEngineApi {
  const RssEngine({http.Client? client}) : _client = client;

  final http.Client? _client;

  String decodeBody(List<int> bytes) {
    var body = bytes;
    if (body.length >= 3 &&
        body[0] == 0xEF &&
        body[1] == 0xBB &&
        body[2] == 0xBF) {
      body = body.sublist(3);
    }
    try {
      return utf8.decode(body);
    } on FormatException {
      return gbk.decode(body);
    }
  }

  Future<String> fetchText(String url) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': _rssUserAgent,
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw RssFailure('源站返回 ${response.statusCode}');
      }
      return decodeBody(response.bodyBytes);
    } on RssFailure {
      rethrow;
    } catch (error) {
      throw RssFailure('抓取失败：$error');
    } finally {
      if (_client == null) client.close();
    }
  }

  List<String> evalStrings(
    String rule,
    dynamic context,
    String pageUrl,
  ) {
    final text = rule.trim();
    if (text.isEmpty) return const [];
    if (_looksLikeScript(text)) {
      final literal = _evalJsLiteralRule(text);
      if (literal == null) return const [];
      return _jsonStrings(literal);
    }
    if (text.contains('{{')) {
      return [_expandTemplate(text, context, pageUrl)];
    }
    if (text.contains('&&')) {
      final out = <String>[];
      for (final part in text.split('&&')) {
        out.addAll(evalStrings(part, context, pageUrl));
      }
      return out;
    }
    for (final alternative in _splitAlternatives(text)) {
      final result = _evalSingle(alternative.trim(), context, pageUrl);
      if (result.isNotEmpty) return result;
    }
    return const [];
  }

  String evalFirstString(String rule, dynamic context, String pageUrl) {
    final values = evalStrings(rule, context, pageUrl);
    return values.isEmpty ? '' : values.first;
  }

  String _expandTemplate(String template, dynamic context, String pageUrl) {
    final buffer = StringBuffer();
    var rest = template;
    while (true) {
      final start = rest.indexOf('{{');
      if (start < 0) {
        buffer.write(rest);
        break;
      }
      final end = rest.indexOf('}}', start + 2);
      if (end < 0) {
        buffer.write(rest);
        break;
      }
      buffer.write(rest.substring(0, start));
      var inner = rest.substring(start + 2, end).trim();
      if (inner == 'baseUrl') {
        buffer.write(pageUrl);
      } else {
        if (inner.startsWith('@') && !inner.startsWith('@@')) {
          inner = inner.substring(1);
        }
        buffer.write(evalFirstString(inner, context, pageUrl));
      }
      rest = rest.substring(end + 2);
    }
    return buffer.toString();
  }

  List<String> _evalSingle(String rule, dynamic context, String pageUrl) {
    if (rule.isEmpty) return const [];
    if (rule.contains('##')) {
      final parts = rule.split('##');
      final base = evalFirstString(parts.first, context, pageUrl);
      if (parts.length < 2) return [base];
      final pattern = parts[1];
      final replacement = parts.length > 2 ? parts.sublist(2).join('##') : '';
      try {
        return [base.replaceAll(RegExp(pattern), replacement)];
      } catch (_) {
        return [base.replaceAll(pattern, replacement)];
      }
    }
    if (context is Map || context is List) {
      if (!rule.startsWith(r'$')) return const [];
      return _jsonStrings(_evalJsonPath(context, rule));
    }
    if (context is Element || context is Document) {
      final root = context is Document
          ? context.documentElement
          : context as Element;
      if (root == null) return const [];
      final tokens = rule.split('@');
      String extraction = 'text';
      var chainTokens = tokens;
      if (tokens.length > 1 && _isExtractionToken(tokens.last)) {
        extraction = tokens.last;
        chainTokens = tokens.sublist(0, tokens.length - 1);
      }
      final steps = <_Step>[];
      for (final token in chainTokens) {
        if (token.isEmpty) continue;
        steps.addAll(_parseSteps(token));
      }
      final elements = _applySteps([root], steps);
      return [
        for (final element in elements)
          if (_extract(element, extraction).isNotEmpty)
            _extract(element, extraction),
      ];
    }
    return const [];
  }

  List<dynamic> evalArticles(String rule, dynamic page, String pageUrl) {
    final text = rule.trim();
    if (text.isEmpty) return const [];
    if (_looksLikeScript(text)) {
      final literal = _evalJsLiteralRule(text);
      if (literal is List) return literal;
      throw const RssFailure('条目规则返回的不是列表');
    }
    if (text.contains('&&')) {
      final out = <dynamic>[];
      for (final part in text.split('&&')) {
        out.addAll(evalArticles(part, page, pageUrl));
      }
      return out;
    }
    for (final alternative in _splitAlternatives(text)) {
      final result = _evalArticlesSingle(alternative.trim(), page, pageUrl);
      if (result.isNotEmpty) return result;
    }
    return const [];
  }

  List<dynamic> _evalArticlesSingle(String rule, dynamic page, String pageUrl) {
    if (page is Map || page is List) {
      if (!rule.startsWith(r'$')) return const [];
      final value = _evalJsonPath(page, rule);
      if (value is List) return value;
      return const [];
    }
    if (page is Document) {
      final root = page.documentElement;
      if (root == null) return const [];
      final tokens = rule.split('@');
      final steps = <_Step>[];
      for (final token in tokens) {
        if (token.isEmpty) continue;
        steps.addAll(_parseSteps(token));
      }
      return _applySteps([root], steps);
    }
    return const [];
  }

  String _resolveUrl(String raw, String pageUrl) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return trimmed;
    return Uri.parse(pageUrl).resolve(trimmed).toString();
  }

  String applyPageTemplate(String url, int page) {
    var out = url;
    out = out.replaceAllMapped(
      RegExp(r'\{\{\s*\(page-1\)\s*\*\s*(\d+)\s*\}\}'),
      (match) => ((page - 1) * int.parse(match.group(1)!)).toString(),
    );
    out = out.replaceAll(RegExp(r'\{\{\s*page\s*\}\}'), page.toString());
    if (out.contains('{{')) {
      throw const RssFailure('分页地址模板暂不支持');
    }
    return out;
  }

  RssListResult parseListPage(
    RssSource source,
    String body,
    String pageUrl,
    int page,
  ) {
    final trimmed = body.trimLeft();
    final isJson = trimmed.startsWith('{') || trimmed.startsWith('[');
    dynamic pageData;
    if (isJson) {
      try {
        pageData = jsonDecode(body);
      } catch (_) {
        throw const RssFailure('订阅源返回的不是合法数据');
      }
    } else {
      pageData = html_parser.parse(body);
    }
    final articles = evalArticles(source.ruleArticles, pageData, pageUrl);
    final items = <RssItem>[];
    for (final article in articles) {
      final title = evalFirstString(source.ruleTitle, article, pageUrl);
      final rawLink = evalFirstString(source.ruleLink, article, pageUrl);
      final link = _resolveUrl(rawLink, pageUrl);
      final date = evalFirstString(source.rulePubDate, article, pageUrl);
      final rawImage = source.ruleImage.isEmpty
          ? ''
          : evalFirstString(source.ruleImage, article, pageUrl);
      final image = rawImage.isEmpty ? '' : _resolveUrl(rawImage, pageUrl);
      if (title.isEmpty && link.isEmpty && image.isEmpty) continue;
      items.add(RssItem(title: title, link: link, date: date, imageUrl: image));
    }
    if (items.isEmpty) {
      throw const RssFailure('该源没有解析出条目，可能已失效或规则不匹配');
    }
    final nextPageUrl = resolveNextPage(source, pageData, pageUrl, page);
    return RssListResult(items: items, nextPageUrl: nextPageUrl);
  }

  String? resolveNextPage(
    RssSource source,
    dynamic pageData,
    String pageUrl,
    int page,
  ) {
    final rule = source.ruleNextPage.trim();
    if (rule.isEmpty) return null;
    if (rule == 'page') {
      if (!source.sourceUrl.contains('{{')) return null;
      return applyPageTemplate(source.sourceUrl, page + 1);
    }
    if (_looksLikeScript(rule)) {
      throw const RssFailure(
        '该源的翻页用了脚本规则，当前版本暂不支持',
        scriptUnsupported: true,
      );
    }
    if (rule.contains('{{')) {
      final expanded = _expandTemplate(rule, pageData, pageUrl);
      if (expanded.trim().isEmpty || expanded == pageUrl) return null;
      return _resolveUrl(expanded, pageUrl);
    }
    final values = evalStrings(rule, pageData, pageUrl);
    if (values.isEmpty) return null;
    return _resolveUrl(values.first, pageUrl);
  }

  @override
  Future<RssListResult> fetchItems(RssSource source, {int page = 1}) async {
    final url = applyPageTemplate(source.sourceUrl, page);
    final body = await fetchText(url);
    return parseListPage(source, body, url, page);
  }

  @override
  Future<RssListResult> fetchPageUrl(RssSource source, String pageUrl) async {
    final body = await fetchText(pageUrl);
    return parseListPage(source, body, pageUrl, 1);
  }

  RssArticleResult parseArticlePage(
    RssSource source,
    RssItem item,
    String body,
  ) {
    if (source.ruleContent.trim().isEmpty) {
      return RssArticleResult(blocks: const [], originalLink: item.link);
    }
    final trimmed = body.trimLeft();
    dynamic pageData;
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        pageData = jsonDecode(body);
      } catch (_) {
        throw const RssFailure('正文页返回的不是合法数据');
      }
    } else {
      pageData = html_parser.parse(body);
    }
    String content = '';
    if (pageData is Document) {
      final values = evalStrings(source.ruleContent, pageData, item.link);
      content = values.join('\n');
      if (content.isEmpty) {
        final tokens = source.ruleContent.split('@');
        if (!_isExtractionToken(tokens.last)) {
          final steps = <_Step>[];
          for (final token in tokens) {
            if (token.isEmpty) continue;
            steps.addAll(_parseSteps(token));
          }
          final root = pageData.documentElement;
          if (root != null) {
            final elements = _applySteps([root], steps);
            content = elements.map((e) => e.outerHtml).join('\n');
          }
        }
      }
    } else {
      content = evalFirstString(source.ruleContent, pageData, item.link);
    }
    return RssArticleResult(
      blocks: contentBlocks(content, item.link),
      originalLink: item.link,
    );
  }

  @override
  Future<RssArticleResult> fetchArticle(
    RssSource source,
    RssItem item,
  ) async {
    if (source.ruleContent.trim().isEmpty) {
      return RssArticleResult(blocks: const [], originalLink: item.link);
    }
    final body = await fetchText(item.link);
    return parseArticlePage(source, item, body);
  }

  List<RssContentBlock> contentBlocks(String content, String pageUrl) {
    final text = content.trim();
    if (text.isEmpty) return const [];
    if (!text.contains('<')) {
      return [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty) RssContentBlock.text(line.trim()),
      ];
    }
    final document = html_parser.parse(text);
    final body = document.body;
    if (body == null) return const [];
    final blocks = <RssContentBlock>[];
    void walk(Element element) {
      if (element.localName == 'img') {
        final src = element.attributes['src'] ?? '';
        if (src.isNotEmpty) {
          blocks.add(RssContentBlock.image(_resolveUrl(src, pageUrl)));
        }
        return;
      }
      if ({
        'p',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
        'li',
        'blockquote',
        'pre',
      }.contains(element.localName)) {
        final value = element.text.trim();
        if (value.isNotEmpty) blocks.add(RssContentBlock.text(value));
        for (final child in element.children) {
          if (child.localName == 'img') walk(child);
        }
        return;
      }
      for (final child in element.children) {
        walk(child);
      }
    }

    for (final child in body.children) {
      walk(child);
    }
    if (blocks.isEmpty) {
      final value = body.text.trim();
      if (value.isNotEmpty) return [RssContentBlock.text(value)];
    }
    return blocks;
  }
}
