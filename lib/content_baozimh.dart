import 'content_crypto.dart';
import 'content_http.dart';
import 'content_models.dart';
import 'core_bridge.dart';

const baozimhHost = 'https://baozimh.org';
const _apiBase = 'https://v2.apikk.top';

/// 包子漫画（baozimh.org 新版，Astro 站）：
/// 列表/搜索是服务端渲染 HTML（/manga/page/N、/hots、/dayup、/s?q=）；
/// 详情页带 data-mid，章节走公开 API /api/manga/get?mid= 全量返回；
/// 章节页图走 /api/v2/chapter/getinfo 取回后还要经站方混淆 JS
/// 解码器（chapter-decoder.js 的 __cimg.r）解码 images 编码串——
/// 该解码器带浏览器环境指纹校验，本机 Node 执行到 r() 抛内部码
/// x0 未能移植，故 chapterPages 如实抛错（卡点见批次报告_fix1），
/// 其余链路 2026-10-24 本机实拉通过：目录卡片、搜索 13 卡、
/// 详情 API 32 章节。
class BaozimhSource extends ContentSource {
  BaozimhSource(this._http);
  final ContentHttp _http;

  @override
  String get id => 'baozimh';
  @override
  String get name => '包子漫画';
  @override
  ContentSection get section => ContentSection.comic;
  @override
  String get note => '目录/详情/章节实拉通过 · 页图待站点JS解码器移植';

  static const _cats = [
    ContentCategory(id: 'all', name: '全部漫画'),
    ContentCategory(id: 'hots', name: '热门'),
    ContentCategory(id: 'dayup', name: '每日更新'),
  ];

  Future<String> _html(String url) =>
      _http.get(url, headers: {'Referer': '$baozimhHost/'});

  @override
  Future<List<ContentCategory>> categories() async => _cats;

  @override
  Future<ContentPage> catalog(String categoryId, int page) async {
    final String url;
    if (categoryId == 'hots') {
      if (page > 1) return const ContentPage(items: []);
      url = '$baozimhHost/hots';
    } else if (categoryId == 'dayup') {
      if (page > 1) return const ContentPage(items: []);
      url = '$baozimhHost/dayup';
    } else {
      url = '$baozimhHost/manga/page/$page';
    }
    final items = parseBaozimhCards(await _html(url));
    return ContentPage(items: items, hasMore: items.isNotEmpty);
  }

  @override
  Future<ContentPage> search(String keyword, int page) async {
    final kw = keyword.trim();
    if (kw.isEmpty || page > 1) return const ContentPage(items: []);
    final items = parseBaozimhCards(
      await _html('$baozimhHost/s?q=${Uri.encodeQueryComponent(kw)}'),
    );
    return ContentPage(items: items);
  }

  @override
  Future<ContentBookDetail> detail(String bookId) async {
    final html = await _html('$baozimhHost/manga/$bookId');
    final mid = RegExp(r'data-mid="(\d+)"').firstMatch(html)?.group(1) ?? '';
    if (mid.isEmpty) throw AppFailure('包子漫画详情未找到 mid');
    final json = contentJsonObject(
      await _http.get(
        '$_apiBase/api/manga/get?mid=$mid',
        headers: {'Referer': '$baozimhHost/'},
      ),
    );
    return parseBaozimhDetail(json, bookId, mid, html);
  }

  @override
  Future<List<String>> chapterPages(
    String bookId,
    ContentChapter chapter,
  ) async {
    // getinfo 能取回，但 info.images.images 是经站方混淆解码器
    // 编码的串（图床路径表），解码器未移植前不编造页图。
    throw AppFailure('包子漫画页图需站点 JS 解码器（__cimg.r）解码，本版本暂未支持');
  }

  @override
  Map<String, String> get pageHeaders => {'Referer': '$baozimhHost/'};
}

List<ContentBook> parseBaozimhCards(String html) {
  final books = <ContentBook>[];
  final seen = <String>{};
  for (final m in RegExp(
    r'<a href="/manga/([A-Za-z0-9\-_]+)"[^>]*>([\s\S]*?)</a>',
  ).allMatches(html)) {
    final slug = m.group(1)!;
    if (!seen.add(slug)) continue;
    final block = m.group(2)!;
    final cover =
        RegExp(
          r'<img[^>]+class="card"[^>]+src="([^"]+)"',
        ).firstMatch(block)?.group(1) ??
        RegExp(r'<img[^>]+src="([^"]+)"').firstMatch(block)?.group(1) ??
        '';
    final title =
        RegExp(
          r'<h3 class="cardtitle"[^>]*>([\s\S]*?)</h3>',
        ).firstMatch(block)?.group(1) ??
        '';
    final cleanTitle = htmlUnescape(
      title.replaceAll(RegExp(r'<[^>]+>'), ''),
    ).trim();
    if (cleanTitle.isEmpty) continue;
    books.add(ContentBook(id: slug, title: cleanTitle, cover: cover));
  }
  return books;
}

ContentBookDetail parseBaozimhDetail(
  Map<String, dynamic> json,
  String bookId,
  String mid,
  String html,
) {
  final data = json['data'];
  if (data is! Map) throw AppFailure('包子漫画未返回详情数据');
  final map = Map<String, dynamic>.from(data);
  var title = '${map['title'] ?? ''}';
  if (title.isEmpty) {
    final og = RegExp(
      r'property="og:title" content="([^"]+)"',
    ).firstMatch(html);
    title = (og?.group(1) ?? '').replaceAll(' - 包子漫畫', '').trim();
  }
  var cover = '';
  final ogImg = RegExp(
    r'property="og:image" content="([^"]+)"',
  ).firstMatch(html);
  if (ogImg != null) cover = ogImg.group(1)!;
  final chapters = <ContentChapter>[];
  final rows = map['chapters'];
  if (rows is List) {
    final parsed = <(int, ContentChapter)>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final attrs = row['attributes'];
      if (attrs is! Map) continue;
      if (attrs['isAd'] == 1) continue;
      final cid = '${row['id'] ?? ''}';
      if (cid.isEmpty) continue;
      final order = attrs['order'] is num ? (attrs['order'] as num).toInt() : 0;
      parsed.add((
        order,
        ContentChapter(
          id: '$mid:$cid',
          title: '${attrs['title'] ?? ''}'.trim().isEmpty
              ? '第$order话'
              : '${attrs['title']}',
          meta: '${attrs['updatedAt'] ?? ''}'.split('T').first,
        ),
      ));
    }
    parsed.sort((a, b) => a.$1.compareTo(b.$1));
    chapters.addAll([for (final p in parsed) p.$2]);
  }
  return ContentBookDetail(
    book: ContentBook(
      id: bookId,
      title: title,
      cover: cover,
      intro: '${map['desc'] ?? ''}'.trim(),
      remarks: '${map['status'] ?? ''}',
    ),
    chapters: chapters,
  );
}
