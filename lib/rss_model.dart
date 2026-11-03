import 'dart:convert';

class RssFailure implements Exception {
  const RssFailure(this.message, {this.scriptUnsupported = false});

  final String message;
  final bool scriptUnsupported;

  @override
  String toString() => message;
}

class RssContentBlock {
  const RssContentBlock.text(this.text) : imageUrl = '';

  const RssContentBlock.image(this.imageUrl) : text = '';

  final String text;
  final String imageUrl;

  bool get isImage => imageUrl.isNotEmpty;
}

class RssItem {
  const RssItem({
    required this.title,
    required this.link,
    this.date = '',
    this.imageUrl = '',
  });

  final String title;
  final String link;
  final String date;
  final String imageUrl;
}

class RssSource {
  const RssSource({
    required this.id,
    required this.name,
    required this.sourceUrl,
    required this.ruleArticles,
    required this.ruleTitle,
    required this.ruleLink,
    this.rulePubDate = '',
    this.ruleContent = '',
    this.ruleImage = '',
    this.ruleNextPage = '',
    this.rawJson = '',
  });

  final String id;
  final String name;
  final String sourceUrl;
  final String ruleArticles;
  final String ruleTitle;
  final String ruleLink;
  final String rulePubDate;
  final String ruleContent;
  final String ruleImage;
  final String ruleNextPage;
  final String rawJson;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sourceUrl': sourceUrl,
    'ruleArticles': ruleArticles,
    'ruleTitle': ruleTitle,
    'ruleLink': ruleLink,
    'rulePubDate': rulePubDate,
    'ruleContent': ruleContent,
    'ruleImage': ruleImage,
    'ruleNextPage': ruleNextPage,
  };
}

String rssSourceId(String sourceUrl) {
  final uri = Uri.tryParse(sourceUrl);
  final host = (uri?.host ?? sourceUrl).replaceAll(
    RegExp(r'[^a-zA-Z0-9]+'),
    '_',
  );
  var hash = 0;
  for (final unit in sourceUrl.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return 'rss_${host}_$hash';
}

RssSource parseRssSource(String jsonText) {
  dynamic decoded;
  try {
    decoded = jsonDecode(jsonText);
  } catch (_) {
    throw const RssFailure('不是合法的 JSON 文件');
  }
  if (decoded is! Map) {
    throw const RssFailure('不是合法的订阅源文件');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (map['bookSourceUrl'] != null && map['sourceUrl'] == null) {
    throw const RssFailure('这是书源，不是订阅源');
  }
  String stringField(String key) {
    final value = map[key];
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  final sourceUrl = stringField('sourceUrl').trim();
  final ruleArticles = stringField('ruleArticles').trim();
  final ruleTitle = stringField('ruleTitle').trim();
  final ruleLink = stringField('ruleLink').trim();
  if (sourceUrl.isEmpty) {
    throw const RssFailure('订阅源缺少订阅地址');
  }
  final uri = Uri.tryParse(sourceUrl);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    throw const RssFailure('订阅地址不是合法网址');
  }
  if (ruleArticles.isEmpty) {
    throw const RssFailure('订阅源缺少条目列表规则');
  }
  if (ruleTitle.isEmpty) {
    throw const RssFailure('订阅源缺少标题规则');
  }
  if (ruleLink.isEmpty) {
    throw const RssFailure('订阅源缺少链接规则');
  }
  var name = stringField('sourceName').trim();
  if (name.isEmpty) name = uri.host;
  return RssSource(
    id: rssSourceId(sourceUrl),
    name: name,
    sourceUrl: sourceUrl,
    ruleArticles: ruleArticles,
    ruleTitle: ruleTitle,
    ruleLink: ruleLink,
    rulePubDate: stringField('rulePubDate').trim(),
    ruleContent: stringField('ruleContent').trim(),
    ruleImage: stringField('ruleImage').trim(),
    ruleNextPage: stringField('ruleNextPage').trim(),
    rawJson: jsonText,
  );
}
