import 'dart:convert';

class MiniAppCard {
  const MiniAppCard({
    required this.title,
    required this.url,
    this.picUrl = '',
    this.desc = '',
    this.colType = '',
    this.extra = const <String, String>{},
  });

  final String title;
  final String url;
  final String picUrl;
  final String desc;
  final String colType;
  final Map<String, String> extra;

  MiniAppCard withColType(String colType) {
    return MiniAppCard(
      title: title,
      url: url,
      picUrl: picUrl,
      desc: desc,
      colType: colType,
      extra: extra,
    );
  }
}

class MiniAppChapter {
  const MiniAppChapter({required this.title, required this.url});

  final String title;
  final String url;
}

class MiniAppDetail {
  const MiniAppDetail({
    required this.title,
    required this.picUrl,
    required this.desc,
    required this.colType,
    this.playUrl = '',
    this.frameUrl = '',
    this.episodes = const <String>[],
    this.chapters = const <MiniAppChapter>[],
    this.hasDetail = true,
    this.proxy,
  });

  final String title;
  final String picUrl;
  final String desc;
  final String colType;
  final String playUrl;
  final String frameUrl;
  final List<String> episodes;
  final List<MiniAppChapter> chapters;
  final bool hasDetail;
  final String? proxy;

  factory MiniAppDetail.none() {
    return const MiniAppDetail(
      title: '',
      picUrl: '',
      desc: '',
      colType: '',
      hasDetail: false,
    );
  }

  factory MiniAppDetail.fromCard(MiniAppCard card) {
    return MiniAppDetail(
      title: card.title,
      picUrl: card.picUrl,
      desc: card.desc,
      colType: card.colType,
      playUrl: card.url,
    );
  }
}

class MiniAppSubPage {
  const MiniAppSubPage({
    required this.name,
    required this.path,
    required this.rule,
    required this.colType,
  });

  final String name;
  final String path;
  final String rule;
  final String colType;
}

class HikerRule {
  const HikerRule({
    required this.title,
    required this.url,
    required this.colType,
    required this.className,
    required this.classUrl,
    required this.areaName,
    required this.areaUrl,
    required this.sortName,
    required this.sortUrl,
    required this.yearName,
    required this.yearUrl,
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
    required this.pages,
    required this.type,
    required this.firstHeader,
    required this.lastChapterRule,
    required this.proxy,
    required this.icon,
    required this.author,
    required this.version,
  });

  final String title;
  final String url;
  final String colType;
  final String className;
  final String classUrl;
  final String areaName;
  final String areaUrl;
  final String sortName;
  final String sortUrl;
  final String yearName;
  final String yearUrl;
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
  final String pages;
  final String type;
  final String firstHeader;
  final String lastChapterRule;
  final String proxy;
  final String icon;
  final String author;
  final String version;

  factory HikerRule.fromJson(Map<String, dynamic> json) {
    String str(String key) {
      final value = json[key];
      if (value == null) return '';
      return value.toString();
    }

    return HikerRule(
      title: str('title'),
      url: str('url'),
      colType: str('col_type'),
      className: str('class_name'),
      classUrl: str('class_url'),
      areaName: str('area_name'),
      areaUrl: str('area_url'),
      sortName: str('sort_name'),
      sortUrl: str('sort_url'),
      yearName: str('year_name'),
      yearUrl: str('year_url'),
      findRule: str('find_rule'),
      searchFind: str('searchFind'),
      searchUrl: str('search_url'),
      group: str('group'),
      detailColType: str('detail_col_type'),
      detailFindRule: str('detail_find_rule'),
      sdetailColType: str('sdetail_col_type'),
      sdetailFindRule: str('sdetail_find_rule'),
      ua: str('ua'),
      preRule: str('preRule'),
      pages: str('pages'),
      type: str('type'),
      firstHeader: str('firstHeader'),
      lastChapterRule: str('last_chapter_rule'),
      proxy: str('proxy'),
      icon: str('icon'),
      author: str('author'),
      version: str('version'),
    );
  }

  bool get hasSearch => searchFind.isNotEmpty && searchUrl.isNotEmpty;

  bool get hasDetail => detailFindRule.isNotEmpty;

  bool get hasSdetail => sdetailFindRule.isNotEmpty;

  bool get hasChapters => lastChapterRule.isNotEmpty;

  bool get hasProxy => proxy.isNotEmpty;

  bool get isJsList => findRule.startsWith('js:');

  bool get isJsSearch => searchFind.startsWith('js:');

  bool get isJsDetail => detailFindRule.startsWith('js:');

  List<String> get classNames => _splitFilter(className);

  List<String> get areaNames => _splitFilter(areaName);

  List<String> get sortNames => _splitFilter(sortName);

  List<String> get yearNames => _splitFilter(yearName);

  List<MiniAppSubPage> get subPages {
    if (pages.isEmpty) return const <MiniAppSubPage>[];
    try {
      final decoded = jsonDecode(pages);
      if (decoded is! List) return const <MiniAppSubPage>[];
      final out = <MiniAppSubPage>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        String str(String key) {
          final value = item[key];
          if (value == null) return '';
          return value.toString();
        }

        out.add(
          MiniAppSubPage(
            name: str('name'),
            path: str('path'),
            rule: str('rule'),
            colType: str('col_type'),
          ),
        );
      }
      return out;
    } catch (_) {
      return const <MiniAppSubPage>[];
    }
  }

  String buildListUrl({
    int page = 1,
    String? cls,
    String? area,
    String? sort,
    String? year,
    String host = '',
  }) {
    var out = url;
    out = out.replaceAll('{host}', host);
    out = out.replaceAll('fypage', page.toString());
    out = out.replaceAll('fyclass', cls ?? '');
    out = out.replaceAll('fyarea', area ?? '');
    out = out.replaceAll('fyyear', year ?? '');
    out = out.replaceAll('fysort', sort ?? '');
    out = out.replaceAll('fyAll', cls ?? '');
    return out;
  }

  String buildSearchUrl(
    String keyword, {
    int page = 1,
    String host = '',
  }) {
    var out = searchUrl;
    out = out.replaceAll('{host}', host);
    out = out.replaceAll('fypage', page.toString());
    final encoded = Uri.encodeComponent(keyword);
    var replaced = false;
    if (out.contains('{wd}') || out.contains('{keyword}')) {
      out = out.replaceAll('{wd}', encoded).replaceAll('{keyword}', encoded);
      replaced = true;
    }
    if (out.contains('keyword')) {
      out = out.replaceAllMapped(
        RegExp(r'\bkeyword\b'),
        (_) => encoded,
      );
      replaced = true;
    }
    if (!replaced && out.contains('wd=')) {
      final index = out.indexOf('wd=');
      final after = out.indexOf('&', index);
      if (after < 0) {
        out = out.substring(0, index + 3) + encoded;
      } else {
        out = out.substring(0, index + 3) + encoded + out.substring(after);
      }
      replaced = true;
    }
    return out;
  }

  static List<String> _splitFilter(String value) {
    if (value.isEmpty) return const <String>[];
    return value
        .split('&')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}

List<MiniAppCard> cardsFromSetResult(dynamic value, String colType) {
  final items = _flattenToList(value);
  final cards = <MiniAppCard>[];
  for (final item in items) {
    if (item is String) {
      cards.add(MiniAppCard(title: item, url: '', colType: colType));
      continue;
    }
    if (item is! Map) continue;
    String str(String key) {
      final v = item[key];
      if (v == null) return '';
      return v.toString();
    }

    final title = str('title').isNotEmpty
        ? str('title')
        : (str('name').isNotEmpty ? str('name') : '');
    var url = str('url');
    if (url.isEmpty) url = str('link');
    var pic = str('pic_url');
    if (pic.isEmpty) pic = str('pic');
    if (pic.isEmpty) pic = str('img');
    if (pic.isEmpty) pic = str('cover');
    var desc = str('desc');
    if (desc.isEmpty) desc = str('description');
    final extra = <String, String>{};
    item.forEach((key, val) {
      final k = key.toString();
      if (k == 'title' ||
          k == 'name' ||
          k == 'url' ||
          k == 'link' ||
          k == 'pic_url' ||
          k == 'pic' ||
          k == 'img' ||
          k == 'cover' ||
          k == 'desc' ||
          k == 'description' ||
          k == 'col_type') {
        return;
      }
      extra[k] = val == null ? '' : val.toString();
    });
    cards.add(
      MiniAppCard(
        title: title,
        url: url,
        picUrl: pic,
        desc: desc,
        colType: str('col_type').isNotEmpty ? str('col_type') : colType,
        extra: extra,
      ),
    );
  }
  return cards;
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
