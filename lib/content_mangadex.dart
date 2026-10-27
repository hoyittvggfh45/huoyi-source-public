import 'content_http.dart';
import 'content_models.dart';
import 'core_bridge.dart';

const _api = 'https://api.mangadex.org';
const _uploads = 'https://uploads.mangadex.org';

/// MangaDex（绿果鉴漫画原生 provider 之一，全公开 API）。
/// 按其公开 API 文档实现：/manga 列表与搜索、/manga/{id}/feed 章节、
/// /at-home/server/{chapterId} 取页图。
/// 2026-10-24 本机全链实拉通过（列表 total 73311、feed、at-home、
/// 首页图真 JPEG）。注意语言码：API 校验 ^[a-z]{2}(-[a-z]{2})?$，
/// 简体中文是 zh、繁体 zh-tw，写 zh-hans 会 400（旧实现踩过）。
class MangaDexSource extends ContentSource {
  MangaDexSource(this._http);
  final ContentHttp _http;

  @override
  String get id => 'mangadex';
  @override
  String get name => 'MangaDex';
  @override
  ContentSection get section => ContentSection.comic;
  @override
  String get note => '公开API · 2026-10-24 全链实拉通过';

  @override
  Future<List<ContentCategory>> categories() async => const [
    ContentCategory(id: 'popular', name: '热门'),
    ContentCategory(id: 'latest', name: '最新更新'),
  ];

  String _listUrl({required int page, String order = '', String title = ''}) {
    final offset = (page - 1) * 20;
    final buf = StringBuffer('$_api/manga?limit=20&offset=$offset');
    buf.write('&includes%5B%5D=cover_art&includes%5B%5D=author');
    buf.write('&contentRating%5B%5D=safe&contentRating%5B%5D=suggestive');
    if (order.isNotEmpty) buf.write('&order$order');
    if (title.isNotEmpty) {
      buf.write('&title=${Uri.encodeQueryComponent(title)}');
    }
    return buf.toString();
  }

  @override
  Future<ContentPage> catalog(String categoryId, int page) async {
    final order = categoryId == 'latest'
        ? '%5BupdatedAt%5D=desc'
        : '%5BfollowedCount%5D=desc';
    final json = contentJsonObject(
      await _http.get(_listUrl(page: page, order: order)),
    );
    return parseMangaDexListPage(json, page);
  }

  @override
  Future<ContentPage> search(String keyword, int page) async {
    final json = contentJsonObject(
      await _http.get(_listUrl(page: page, title: keyword)),
    );
    return parseMangaDexListPage(json, page);
  }

  @override
  Future<ContentBookDetail> detail(String bookId) async {
    final json = contentJsonObject(
      await _http.get(
        '$_api/manga/$bookId?includes%5B%5D=cover_art&includes%5B%5D=author',
      ),
    );
    final data = json['data'];
    if (data is! Map) throw AppFailure('MangaDex 未返回详情');
    final book = mangaDexBook(Map<String, dynamic>.from(data));
    final chapters = <ContentChapter>[];
    for (var offset = 0; offset < 1000; offset += 100) {
      final feed = contentJsonObject(
        await _http.get(
          '$_api/manga/$bookId/feed?limit=100&offset=$offset'
          '&translatedLanguage%5B%5D=zh'
          '&translatedLanguage%5B%5D=zh-tw'
          '&translatedLanguage%5B%5D=en'
          '&order%5Bchapter%5D=asc',
        ),
      );
      final rows = feed['data'];
      if (rows is! List || rows.isEmpty) break;
      for (final row in rows) {
        if (row is Map) {
          final chapter = mangaDexChapter(Map<String, dynamic>.from(row));
          if (chapter != null) chapters.add(chapter);
        }
      }
      if (rows.length < 100) break;
    }
    return ContentBookDetail(book: book, chapters: chapters);
  }

  @override
  Future<List<String>> chapterPages(
    String bookId,
    ContentChapter chapter,
  ) async {
    final json = contentJsonObject(
      await _http.get('$_api/at-home/server/${chapter.id}'),
    );
    return parseMangaDexPages(json);
  }
}

String _pickLocalized(Map<dynamic, dynamic> map) {
  for (final key in ['zh-hans', 'zh', 'en', 'ja']) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
  }
  for (final value in map.values) {
    if (value is String && value.isNotEmpty) return value;
  }
  return '';
}

ContentBook mangaDexBook(Map<String, dynamic> row) {
  final attrs = row['attributes'];
  final attrMap = attrs is Map ? attrs : const {};
  final titleRaw = attrMap['title'];
  final descRaw = attrMap['description'];
  var cover = '';
  var author = '';
  final rels = row['relationships'];
  if (rels is List) {
    for (final rel in rels) {
      if (rel is! Map) continue;
      final relAttrs = rel['attributes'];
      if (rel['type'] == 'cover_art' && relAttrs is Map) {
        final file = relAttrs['fileName'];
        if (file is String && file.isNotEmpty) {
          cover = '$_uploads/covers/${row['id']}/$file.256.jpg';
        }
      }
      if (rel['type'] == 'author' && relAttrs is Map && author.isEmpty) {
        author = '${relAttrs['name'] ?? ''}';
      }
    }
  }
  final status = switch ('${attrMap['status'] ?? ''}') {
    'completed' => '已完结',
    'ongoing' => '连载中',
    _ => '',
  };
  final year = attrMap['year']?.toString() ?? '';
  return ContentBook(
    id: '${row['id'] ?? ''}',
    title: titleRaw is Map ? _pickLocalized(titleRaw) : '${titleRaw ?? ''}',
    cover: cover,
    author: author,
    remarks: [status, year].where((s) => s.isNotEmpty).join(' · '),
    intro: descRaw is Map ? _pickLocalized(descRaw) : '${descRaw ?? ''}',
  );
}

ContentPage parseMangaDexListPage(Map<String, dynamic> json, int page) {
  final rows = json['data'];
  final total = json['total'] is num ? (json['total'] as num).toInt() : 0;
  final offset = json['offset'] is num ? (json['offset'] as num).toInt() : 0;
  final limit = json['limit'] is num ? (json['limit'] as num).toInt() : 20;
  return ContentPage(
    items: [
      if (rows is List)
        for (final row in rows)
          if (row is Map) mangaDexBook(Map<String, dynamic>.from(row)),
    ],
    hasMore: offset + limit < total,
    total: total,
  );
}

ContentChapter? mangaDexChapter(Map<String, dynamic> row) {
  final attrs = row['attributes'];
  if (attrs is! Map) return null;
  if (attrs['externalUrl'] != null) return null;
  if (attrs['isUnavailable'] == true) return null; // at-home 会 404
  final pages = attrs['pages'] is num ? (attrs['pages'] as num).toInt() : 0;
  if (pages <= 0) return null;
  final numText = '${attrs['chapter'] ?? ''}';
  final title = '${attrs['title'] ?? ''}';
  final label = [
    if (numText.isNotEmpty && numText != 'null') '第$numText话',
    if (title.isNotEmpty && title != 'null') title,
  ].join(' ');
  return ContentChapter(
    id: '${row['id'] ?? ''}',
    title: label.isEmpty ? '单话' : label,
    meta: '$pages 页',
  );
}

List<String> parseMangaDexPages(Map<String, dynamic> json) {
  final base = json['baseUrl'];
  final chapter = json['chapter'];
  if (base is! String || chapter is! Map) return const [];
  final hash = chapter['hash'];
  final files = chapter['data'];
  if (hash is! String || files is! List) return const [];
  return [
    for (final file in files)
      if (file is String && file.isNotEmpty) '$base/data/$hash/$file',
  ];
}
