import 'content_http.dart';
import 'content_models.dart';
import 'core_bridge.dart';

const copymangaHost = 'https://www.manga2025.com';
const _api = '$copymangaHost/api/v3';

/// 拷贝漫画（manga2025.com 镜像）——公开 API v3，无加密：
/// /api/v3/comics 列表、/api/v3/search/comic 搜索、
/// /api/v3/comic/{slug} 详情、group/default/chapters 章节、
/// chapter/{uuid} 的 contents 直出页图 URL。
/// 2026-10-24 本机全链实拉通过（列表 total 122918、章节 45 页图直链）。
class CopymangaSource extends ContentSource {
  CopymangaSource(this._http);
  final ContentHttp _http;

  @override
  String get id => 'copymanga';
  @override
  String get name => '拷贝漫画';
  @override
  ContentSection get section => ContentSection.comic;
  @override
  String get note => '公开API · 2026-10-24 全链实拉通过';

  static const _cats = [
    ContentCategory(id: 'update', name: '最新更新'),
    ContentCategory(id: 'popular', name: '人气最热'),
    ContentCategory(id: 'newest', name: '最新上架'),
  ];

  static const _ordering = {
    'update': '-datetime_updated',
    'popular': '-popular',
    'newest': '-datetime_created',
  };

  Future<Map<String, dynamic>> _apiGet(String path) async {
    final text = await _http.get(
      '$_api$path',
      headers: {'Accept': 'application/json', 'Referer': '$copymangaHost/'},
    );
    final json = contentJsonObject(text);
    if (json['code'] != 200) {
      throw AppFailure('拷贝漫画接口异常：${json['message'] ?? json['code']}');
    }
    return json;
  }

  @override
  Future<List<ContentCategory>> categories() async => _cats;

  @override
  Future<ContentPage> catalog(String categoryId, int page) async {
    final ordering = _ordering[categoryId] ?? '-datetime_updated';
    final offset = (page - 1) * 20;
    final json = await _apiGet(
      '/comics?ordering=$ordering&limit=20&offset=$offset&platform=3',
    );
    return parseCopymangaList(json, page);
  }

  @override
  Future<ContentPage> search(String keyword, int page) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const ContentPage(items: []);
    final offset = (page - 1) * 20;
    final json = await _apiGet(
      '/search/comic?q=${Uri.encodeQueryComponent(kw)}'
      '&limit=20&offset=$offset&q_type=',
    );
    return parseCopymangaList(json, page);
  }

  @override
  Future<ContentBookDetail> detail(String bookId) async {
    final json = await _apiGet('/comic/$bookId');
    final results = json['results'];
    if (results is! Map) throw AppFailure('拷贝漫画未返回详情');
    final comic = results['comic'];
    if (comic is! Map) throw AppFailure('拷贝漫画未返回详情');
    final book = copymangaBook(Map<String, dynamic>.from(comic), bookId);
    final chapters = <ContentChapter>[];
    var chaptersTruncated = false;
    for (var offset = 0; offset < 1000; offset += 100) {
      final cj = await _apiGet(
        '/comic/$bookId/group/default/chapters?limit=100&offset=$offset',
      );
      final cr = cj['results'];
      final rows = cr is Map ? cr['list'] : null;
      if (rows is! List || rows.isEmpty) break;
      for (final row in rows) {
        if (row is Map) {
          final ch = copymangaChapter(Map<String, dynamic>.from(row));
          if (ch != null) chapters.add(ch);
        }
      }
      if (rows.length < 100) break;
      if (offset + 100 >= 1000) chaptersTruncated = true;
    }
    // 接口按 ordered 升序返回，保留原序（按标题字符串排会把第10話排到第2話前）
    return ContentBookDetail(
      book: book,
      chapters: chapters,
      chaptersTruncated: chaptersTruncated,
    );
  }

  @override
  Future<List<String>> chapterPages(
    String bookId,
    ContentChapter chapter,
  ) async {
    final json = await _apiGet('/comic/$bookId/chapter/${chapter.id}');
    return parseCopymangaPages(json);
  }

  @override
  Map<String, String> get pageHeaders => {'Referer': '$copymangaHost/'};
}

ContentBook copymangaBook(Map<String, dynamic> row, String id) {
  var author = '';
  final authors = row['author'];
  if (authors is List) {
    author = [
      for (final a in authors)
        if (a is Map && '${a['name'] ?? ''}'.isNotEmpty) '${a['name']}',
    ].join('、');
  }
  final themes = <String>[];
  final theme = row['theme'];
  if (theme is List) {
    for (final t in theme) {
      if (t is Map && '${t['name'] ?? ''}'.isNotEmpty) {
        themes.add('${t['name']}');
      }
    }
  }
  var status = '';
  final st = row['status'];
  if (st is Map && '${st['display'] ?? ''}'.isNotEmpty) {
    status = '${st['display']}';
  }
  return ContentBook(
    id: id,
    title: '${row['name'] ?? ''}',
    cover: '${row['cover'] ?? ''}',
    author: author,
    remarks: [
      status,
      themes.take(3).join(' '),
    ].where((s) => s.isNotEmpty).join(' · '),
    intro: '${row['brief'] ?? ''}'.trim(),
  );
}

ContentPage parseCopymangaList(Map<String, dynamic> json, int page) {
  final results = json['results'];
  if (results is! Map) return const ContentPage(items: []);
  final rows = results['list'];
  final total = results['total'] is num ? (results['total'] as num).toInt() : 0;
  final items = <ContentBook>[];
  if (rows is List) {
    for (final row in rows) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final slug = '${map['path_word'] ?? ''}';
      if (slug.isEmpty) continue;
      items.add(copymangaBook(map, slug));
    }
  }
  return ContentPage(items: items, hasMore: page * 20 < total, total: total);
}

ContentChapter? copymangaChapter(Map<String, dynamic> row) {
  final uuid = '${row['uuid'] ?? ''}';
  if (uuid.isEmpty) return null;
  final name = '${row['name'] ?? ''}';
  final size = row['size'] is num ? (row['size'] as num).toInt() : 0;
  return ContentChapter(
    id: uuid,
    title: name.isEmpty ? '章节' : name,
    meta: size > 0 ? '$size 页' : '',
  );
}

List<String> parseCopymangaPages(Map<String, dynamic> json) {
  final results = json['results'];
  if (results is! Map) return const [];
  final chapter = results['chapter'];
  if (chapter is! Map) return const [];
  final contents = chapter['contents'];
  if (contents is! List) return const [];
  return [
    for (final c in contents)
      if (c is Map && '${c['url'] ?? ''}'.isNotEmpty) '${c['url']}',
  ];
}
