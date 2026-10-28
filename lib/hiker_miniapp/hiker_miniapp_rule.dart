import 'dart:convert';

class HikerMiniappCategory {
  const HikerMiniappCategory({required this.name, required this.url});

  final String name;
  final String url;
}

class HikerMiniappFilter {
  const HikerMiniappFilter({required this.name, required this.url});

  final String name;
  final String url;
}

class HikerMiniappPage {
  const HikerMiniappPage({required this.path, required this.rule});

  final String path;
  final String rule;

  Map<String, dynamic> toJson() => {'path': path, 'rule': rule};
}

List<HikerMiniappPage> parseHikerMiniappPages(dynamic value) {
  dynamic decoded = value;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } catch (_) {
      return const [];
    }
  }
  if (decoded is! List) return const [];
  final out = <HikerMiniappPage>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final path = _asString(item['path']);
    if (path.isEmpty) continue;
    out.add(HikerMiniappPage(path: path, rule: _asString(item['rule'])));
  }
  return out;
}

class HikerMiniappRule {
  const HikerMiniappRule({
    required this.title,
    required this.author,
    required this.version,
    required this.type,
    required this.url,
    required this.colType,
    required this.classNames,
    required this.classUrls,
    required this.areaNames,
    required this.areaUrls,
    required this.sortNames,
    required this.yearNames,
    required this.sortUrls,
    required this.yearUrls,
    required this.findRule,
    required this.searchFind,
    required this.searchUrl,
    required this.group,
    required this.detailColType,
    required this.detailFindRule,
    required this.sdetailColType,
    required this.sdetailFindRule,
    required this.ua,
    required this.preRule,
    required this.lastChapterRule,
    this.pages = const [],
  });

  final String title;
  final String author;
  final String version;
  final String type;
  final String url;
  final String colType;
  final List<String> classNames;
  final List<String> classUrls;
  final List<String> areaNames;
  final List<String> areaUrls;
  final List<String> sortNames;
  final List<String> yearNames;
  final List<String> sortUrls;
  final List<String> yearUrls;
  final String findRule;
  final String searchFind;
  final String searchUrl;
  final String group;
  final String detailColType;
  final String detailFindRule;
  final String sdetailColType;
  final String sdetailFindRule;
  final String ua;
  final String preRule;
  final String lastChapterRule;
  final List<HikerMiniappPage> pages;

  factory HikerMiniappRule.fromJson(Map<String, dynamic> json) {
    final classNames = _splitAmp(_asString(json['class_name']));
    final areaNames = _splitAmp(_asString(json['area_name']));
    final sortNames = _splitAmp(_asString(json['sort_name']));
    final yearNames = _splitAmp(_asString(json['year_name']));
    return HikerMiniappRule(
      title: _asString(json['title']),
      author: _asString(json['author']),
      version: _asString(json['version']),
      type: _asString(json['type']),
      url: _asString(json['url']),
      colType: _asString(json['col_type']),
      classNames: classNames,
      classUrls: _splitUrlList(_asString(json['class_url']), classNames.length),
      areaNames: areaNames,
      areaUrls: _splitUrlList(_asString(json['area_url']), areaNames.length),
      sortNames: sortNames,
      yearNames: yearNames,
      sortUrls: _splitUrlList(_asString(json['sort_url']), sortNames.length),
      yearUrls: _splitUrlList(_asString(json['year_url']), yearNames.length),
      findRule: _asString(json['find_rule']),
      searchFind: _asString(json['searchFind']),
      searchUrl: _asString(json['search_url']),
      group: _asString(json['group']),
      detailColType: _asString(json['detail_col_type']),
      detailFindRule: _asString(json['detail_find_rule']),
      sdetailColType: _asString(json['sdetail_col_type']),
      sdetailFindRule: _asString(json['sdetail_find_rule']),
      ua: _asString(json['ua']),
      preRule: _asString(json['preRule']),
      lastChapterRule: _asString(json['last_chapter_rule']),
      pages: parseHikerMiniappPages(json['pages']),
    );
  }

  Map<String, dynamic> toEngineJson() => {
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
    'last_chapter_rule': lastChapterRule,
    'pages': [for (final page in pages) page.toJson()],
  };

  Map<String, dynamic> toJson() => {
    'title': title,
    'author': author,
    'version': version,
    'type': type,
    'url': url,
    'col_type': colType,
    'class_name': classNames.join('&'),
    'class_url': classUrls.join('&'),
    'area_name': areaNames.join('&'),
    'area_url': areaUrls.join('&'),
    'sort_name': sortNames.join('&'),
    'year_name': yearNames.join('&'),
    'sort_url': sortUrls.join('&'),
    'year_url': yearUrls.join('&'),
    'find_rule': findRule,
    'searchFind': searchFind,
    'search_url': searchUrl,
    'group': group,
    'detail_col_type': detailColType,
    'detail_find_rule': detailFindRule,
    'sdetail_col_type': sdetailColType,
    'sdetail_find_rule': sdetailFindRule,
    'ua': ua,
    'preRule': preRule,
    'last_chapter_rule': lastChapterRule,
    'pages': [for (final page in pages) page.toJson()],
  };

  String get id => title.isEmpty ? url : title;

  List<HikerMiniappCategory> get categories {
    final count = classNames.length < classUrls.length
        ? classNames.length
        : classUrls.length;
    return [
      for (var i = 0; i < count; i++)
        HikerMiniappCategory(name: classNames[i], url: classUrls[i]),
    ];
  }

  List<HikerMiniappFilter> get areaFilters => _pairFilters(areaNames, areaUrls);

  List<HikerMiniappFilter> get sortFilters => _pairFilters(sortNames, sortUrls);

  List<HikerMiniappFilter> get yearFilters => _pairFilters(yearNames, yearUrls);

  bool get hasFindRule => findRule.trim().isNotEmpty;

  bool get hasSearch => searchFind.trim().isNotEmpty;

  bool get hasDetail => detailFindRule.trim().isNotEmpty;

  static bool isJsScript(String script) => script.trim().startsWith('js:');
}

List<HikerMiniappRule> parseHikerMiniappRules(String text) {
  var cleaned = text.trim();
  if (cleaned.startsWith('\uFEFF')) cleaned = cleaned.substring(1);
  if (cleaned.startsWith('```')) {
    final lines = cleaned.split('\n');
    final body = lines.sublist(1).join('\n').trim();
    cleaned = body.endsWith('```')
        ? body.substring(0, body.length - 3).trim()
        : body;
  }
  final decoded = jsonDecode(cleaned);
  List<dynamic> rawItems;
  if (decoded is List) {
    rawItems = decoded;
  } else if (decoded is Map) {
    List<dynamic>? wrapped;
    for (final key in ['rules', 'data', 'records', 'items', 'list']) {
      final value = decoded[key];
      if (value is List) {
        wrapped = value;
        break;
      }
    }
    rawItems = wrapped ?? [decoded];
  } else {
    rawItems = <dynamic>[];
  }
  final out = <HikerMiniappRule>[];
  for (final item in rawItems) {
    if (item is Map<String, dynamic>) {
      final rule = HikerMiniappRule.fromJson(item);
      if (rule.title.isNotEmpty || rule.url.isNotEmpty) out.add(rule);
    } else if (item is Map) {
      final rule = HikerMiniappRule.fromJson(
        item.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (rule.title.isNotEmpty || rule.url.isNotEmpty) out.add(rule);
    }
  }
  return out;
}

String _asString(dynamic value) => value == null ? '' : value.toString();

List<String> _splitAmp(String value) {
  return [
    for (final part in value.split('&')) part.trim(),
  ].where((part) => part.isNotEmpty).toList();
}

List<String> _splitUrlList(String value, int expectedCount) {
  final plain = _splitAmp(value);
  if (expectedCount <= 0 || plain.length == expectedCount) return plain;
  final merged = <String>[];
  for (final part in value.split('&')) {
    final piece = part.trim();
    if (piece.isEmpty) continue;
    if (merged.isEmpty ||
        piece.startsWith('http://') ||
        piece.startsWith('https://') ||
        piece.startsWith('/')) {
      merged.add(piece);
    } else {
      merged[merged.length - 1] = '${merged.last}&$piece';
    }
  }
  return merged;
}

List<HikerMiniappFilter> _pairFilters(List<String> names, List<String> urls) {
  final count = names.length < urls.length ? names.length : urls.length;
  return [
    for (var i = 0; i < count; i++)
      HikerMiniappFilter(name: names[i], url: urls[i]),
  ];
}
