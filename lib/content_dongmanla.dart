import 'content_crypto.dart';
import 'content_http.dart';
import 'content_models.dart';
import 'core_bridge.dart';

const dongmanlaHost = 'https://www.dongman.la';

const _categories = [
  ContentCategory(id: 'all', name: '全部'),
  ContentCategory(id: 'guochan', name: '国漫'),
  ContentCategory(id: 'japan', name: '日漫'),
  ContentCategory(id: 'hanguo', name: '韩漫'),
  ContentCategory(id: 'oumei', name: '欧美'),
  ContentCategory(id: 'hongkongtaiwan', name: '港台'),
  ContentCategory(id: 'finish', name: '完结'),
  ContentCategory(id: 'serial', name: '连载'),
];

String _stripTags(String s) =>
    htmlUnescape(s.replaceAll(RegExp(r'<[^>]+>'), '')).trim();

List<ContentBook> parseDongmanlaCards(String html) {
  final books = <ContentBook>[];
  final seen = <String>{};
  for (final block in html.split('<li')) {
    final idMatch = RegExp(r'href="/manhua/detail/(\d+)/"').firstMatch(block);
    if (idMatch == null) continue;
    final coverMatch = RegExp(
      r'<img data-cover src="([^"]+)"',
    ).firstMatch(block);
    if (coverMatch == null) continue;
    final id = idMatch.group(1)!;
    if (!seen.add(id)) continue;
    final titleMatch = RegExp(
      '<a href="/manhua/detail/$id/"[^>]*>([^<]+)</a>',
    ).firstMatch(block);
    var title = titleMatch?.group(1)?.trim() ?? '';
    if (title.isEmpty) {
      final alt = RegExp(r'title="([^"]+?)漫画"').firstMatch(block);
      title = alt?.group(1)?.trim() ?? '';
    }
    if (title.isEmpty) continue;
    final status = RegExp(r'状态：<span[^>]*>([^<]+)</span>').firstMatch(block);
    final author = RegExp(r'作者：([^<]+)').firstMatch(block);
    final latest = RegExp(
      '最新：<a href="/manhua/chapter/$id/\\d+/"[^>]*>([^<]*)</a>',
    ).firstMatch(block);
    books.add(
      ContentBook(
        id: id,
        title: title,
        cover: coverMatch.group(1)!,
        author: author?.group(1)?.trim() ?? '',
        remarks: [
          status?.group(1)?.trim() ?? '',
          latest?.group(1)?.trim() ?? '',
        ].where((x) => x.isNotEmpty).join(' · '),
      ),
    );
  }
  return books;
}

ContentBookDetail parseDongmanlaDetail(String html, String bookId) {
  final titleMatch = RegExp(
    r'property="og:title" content="([^"]+)"',
  ).firstMatch(html);
  var title = (titleMatch?.group(1) ?? '').replaceAll('漫画在线阅读', '').trim();
  if (title.isEmpty) {
    final t = RegExp(r'<title>([^<]+)').firstMatch(html);
    title = (t?.group(1) ?? '').split('漫画_').first.trim();
  }
  final coverMatch =
      RegExp(r'<img[^>]+data-cover[^>]+src="([^"]+)"').firstMatch(html) ??
      RegExp(
        r'<img[^>]+src="(https://img\.dongman\.la/uploads[^"]+)"',
      ).firstMatch(html);
  final introMatch = RegExp(
    r'<div class="detail-description">.*?<p[^>]*>(.*?)</p>',
    dotAll: true,
  ).firstMatch(html);
  final intro = introMatch == null ? '' : _stripTags(introMatch.group(1)!);
  final authorMatch = RegExp(r'作者：([^<]+)').firstMatch(html);
  final statusMatch = RegExp(r'状态：<span[^>]*>([^<]+)</span>').firstMatch(html);
  final raw = <(String, String)>[];
  final seenIds = <String>{};
  for (final m in RegExp(
    'href="/manhua/chapter/$bookId/(\\d+)/"[^>]*>([^<]*)</a>',
  ).allMatches(html)) {
    final cid = m.group(1)!;
    if (!seenIds.add(cid)) continue;
    raw.add((cid, m.group(2)!.trim()));
  }
  int numberOf(String t) {
    final m = RegExp(r'第\s*(\d+(?:\.\d+)?)\s*[话話卷]').firstMatch(t);
    return m == null ? -1 : (double.tryParse(m.group(1)!) ?? -1).round();
  }

  final minId = raw.isEmpty
      ? 0
      : raw.map((e) => int.parse(e.$1)).reduce((a, b) => a < b ? a : b);
  final chapters =
      [
        for (final e in raw)
          (
            id: e.$1,
            title: e.$2,
            num: numberOf(e.$2) >= 0
                ? numberOf(e.$2)
                : (int.parse(e.$1) == minId ? 1 : 1 << 30),
          ),
      ]..sort((a, b) {
        final byNum = a.num.compareTo(b.num);
        return byNum != 0 ? byNum : int.parse(a.id).compareTo(int.parse(b.id));
      });
  return ContentBookDetail(
    book: ContentBook(
      id: bookId,
      title: title,
      cover: coverMatch?.group(1) ?? '',
      author: authorMatch?.group(1)?.trim() ?? '',
      remarks: statusMatch?.group(1)?.trim() ?? '',
      intro: intro,
    ),
    chapters: [
      for (final c in chapters)
        ContentChapter(
          id: '$bookId/${c.id}',
          title: c.title.isEmpty
              ? '第${c.num}话'
              : c.title.startsWith('开始阅读')
              ? '第1话'
              : c.title,
        ),
    ],
  );
}

List<String> parseDongmanlaChapterImages(String html) {
  final out = <String>[];
  final seen = <String>{};
  for (final m in RegExp(
    r'<img[^>]+src="(https://img\.dongman\.la/h/[^"]+)"',
  ).allMatches(html)) {
    final url = m.group(1)!;
    if (seen.add(url)) out.add(url);
  }
  return out;
}

class DongmanlaSource extends ContentSource {
  DongmanlaSource({ContentHttp? http}) : _http = http ?? ContentHttp();

  final ContentHttp _http;

  @override
  String get id => 'dongmanla';

  @override
  String get name => '动漫啦';

  @override
  ContentSection get section => ContentSection.comic;

  Future<String> _html(String url) =>
      _http.get(url, headers: {'Referer': '$dongmanlaHost/'});

  @override
  Future<List<ContentCategory>> categories() async => _categories;

  @override
  Future<ContentPage> catalog(String categoryId, int page) async {
    final path = categoryId == 'all' ? '/manhua/' : '/manhua/$categoryId/';
    final html = await _html('$dongmanlaHost$path?page=$page');
    final items = parseDongmanlaCards(html);
    return ContentPage(items: items, hasMore: items.isNotEmpty);
  }

  @override
  Future<ContentPage> search(String keyword, int page) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const ContentPage(items: []);
    final encoded = Uri.encodeComponent(kw).toLowerCase();
    final html = await _html('$dongmanlaHost/manhua/so/$encoded/?page=$page');
    final items = parseDongmanlaCards(html);
    return ContentPage(items: items, hasMore: items.isNotEmpty);
  }

  @override
  Future<ContentBookDetail> detail(String bookId) async {
    final html = await _html('$dongmanlaHost/manhua/detail/$bookId/');
    final detail = parseDongmanlaDetail(html, bookId);
    if (detail.chapters.isEmpty) {
      throw AppFailure('动漫啦未返回章节列表');
    }
    return detail;
  }

  @override
  Future<List<String>> chapterPages(
    String bookId,
    ContentChapter chapter,
  ) async {
    final html = await _html(
      '$dongmanlaHost/manhua/chapter/${chapter.id}/all.html',
    );
    final images = parseDongmanlaChapterImages(html);
    if (images.isEmpty) throw AppFailure('动漫啦未返回章节图片');
    return images;
  }

  @override
  Map<String, String> get pageHeaders => {'Referer': '$dongmanlaHost/'};
}
