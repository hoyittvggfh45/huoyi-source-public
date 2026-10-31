import 'content_http.dart';
import 'content_models.dart';
import 'core_bridge.dart';

/// 听书通用引擎：MacCMS（苹果CMS）JSON 采集接口与网页抓取引擎。
///
/// MacCMS 按 provide 口径实现（ac=list/detail、class 分类、vod_play_url
/// 分集），任何提供该接口的听书站填 base 即可成源。网页抓取引擎为
/// 调用方供正则的通用抓取（分类/卡片/章节/音频地址均由正则组承载），
/// 不写死任何站点结构。ZBlog 引擎未落：字符串层无可确定的标准
/// 列表/章节/音频契约，见批次报告。两引擎均无实站验证：注册表默认
/// 不挂实例，解析逻辑由离线单测覆盖。
class MacCmsAudioSource extends ContentSource {
  MacCmsAudioSource(
    this._http, {
    required this.sourceId,
    required this.sourceName,
    required this.base,
    this.onlyAudio = true,
  });

  final ContentHttp _http;
  final String sourceId;
  final String sourceName;

  /// 站点根地址（不带尾斜杠），接口在其下 /api.php/provide/vod/。
  final String base;

  /// true 时详情只保留音频后缀的播放地址。
  final bool onlyAudio;

  @override
  String get id => sourceId;
  @override
  String get name => sourceName;
  @override
  ContentSection get section => ContentSection.audio;
  @override
  String get note => '通用引擎实例，未做实站验证';

  String get _api => '$base/api.php/provide/vod/';

  static const _audioExts = ['.mp3', '.m4a', '.aac', '.ogg', '.wav', '.flac'];

  @override
  Future<List<ContentCategory>> categories() async {
    final json = contentJsonObject(await _http.get('$_api?ac=list&pg=1'));
    return parseMacCmsCategories(json);
  }

  @override
  Future<ContentPage> catalog(String categoryId, int page) async {
    final t = categoryId == 'all' ? '' : '&t=$categoryId';
    final json = contentJsonObject(await _http.get('$_api?ac=list$t&pg=$page'));
    return parseMacCmsListPage(json, page);
  }

  @override
  Future<ContentPage> search(String keyword, int page) async {
    final wd = Uri.encodeQueryComponent(keyword);
    final json = contentJsonObject(
      await _http.get('$_api?ac=list&wd=$wd&pg=$page'),
    );
    return parseMacCmsListPage(json, page);
  }

  @override
  Future<ContentBookDetail> detail(String bookId) async {
    final json = contentJsonObject(
      await _http.get('$_api?ac=detail&ids=$bookId'),
    );
    final rows = json['list'];
    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      throw AppFailure('CMS 源未返回详情');
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    final book = macCmsBook(row);
    return ContentBookDetail(
      book: book,
      chapters: parseMacCmsEpisodesAllLines(row, onlyAudio: onlyAudio),
    );
  }

  @override
  Future<ContentAudioTrack> audioTrack(
    String bookId,
    ContentChapter chapter,
  ) async {
    if (chapter.id.isEmpty) throw AppFailure('CMS 源章节缺少播放地址');
    return ContentAudioTrack(url: chapter.id);
  }

  static bool isAudioUrl(String url) {
    final lower = url.toLowerCase();
    return _audioExts.any((ext) => lower.split('?').first.endsWith(ext));
  }
}

ContentBook macCmsBook(Map<String, dynamic> row) => ContentBook(
  id: '${row['vod_id'] ?? ''}',
  title: '${row['vod_name'] ?? ''}',
  cover: '${row['vod_pic'] ?? ''}',
  author: '${row['vod_actor'] ?? ''}',
  remarks: '${row['vod_remarks'] ?? ''}',
  intro: '${row['vod_content'] ?? ''}',
);

List<ContentCategory> parseMacCmsCategories(Map<String, dynamic> json) {
  final rows = json['class'];
  return [
    const ContentCategory(id: 'all', name: '全部'),
    if (rows is List)
      for (final row in rows)
        if (row is Map && row['type_id'] != null)
          ContentCategory(
            id: '${row['type_id']}',
            name: '${row['type_name'] ?? ''}',
          ),
  ];
}

ContentPage parseMacCmsListPage(Map<String, dynamic> json, int page) {
  final rows = json['list'];
  final pageCount = json['pagecount'] is num
      ? (json['pagecount'] as num).toInt()
      : page;
  final total = json['total'] is num ? (json['total'] as num).toInt() : 0;
  return ContentPage(
    items: [
      if (rows is List)
        for (final row in rows)
          if (row is Map) macCmsBook(Map<String, dynamic>.from(row)),
    ],
    hasMore: page < pageCount,
    total: total,
  );
}

/// vod_play_url 口径：多线路以 $$$ 分隔取第一条，集以 # 分隔，
/// 每集为「标题$地址」（无 $ 时整段即地址）。
List<ContentChapter> parseMacCmsEpisodes(
  Map<String, dynamic> row, {
  bool onlyAudio = false,
}) {
  final raw = '${row['vod_play_url'] ?? ''}';
  if (raw.trim().isEmpty) return const [];
  final firstLine = raw.split('\$\$\$').first;
  return _parseMacCmsLine(firstLine, '', onlyAudio: onlyAudio);
}

List<ContentChapter> _parseMacCmsLine(
  String line,
  String lineName, {
  bool onlyAudio = false,
}) {
  final chapters = <ContentChapter>[];
  for (final part in line.split('#')) {
    final seg = part.trim();
    if (seg.isEmpty) continue;
    final at = seg.indexOf('\$');
    final title = at > 0 ? seg.substring(0, at) : '第${chapters.length + 1}集';
    final url = at >= 0 ? seg.substring(at + 1) : seg;
    if (url.isEmpty) continue;
    if (onlyAudio && !MacCmsAudioSource.isAudioUrl(url)) continue;
    chapters.add(ContentChapter(id: url, title: title, meta: lineName));
  }
  return chapters;
}

List<ContentChapter> parseMacCmsEpisodesAllLines(
  Map<String, dynamic> row, {
  bool onlyAudio = false,
}) {
  final raw = '${row['vod_play_url'] ?? ''}';
  if (raw.trim().isEmpty) return const [];
  final lines = raw.split('\$\$\$');
  final names = '${row['vod_play_from'] ?? ''}'.split('\$\$\$');
  final chapters = <ContentChapter>[];
  final seen = <String>{};
  for (var i = 0; i < lines.length; i++) {
    final lineName = i < names.length ? names[i].trim() : '';
    for (final chapter in _parseMacCmsLine(
      lines[i],
      lineName,
      onlyAudio: onlyAudio,
    )) {
      if (!seen.add(chapter.id)) continue;
      chapters.add(chapter);
    }
  }
  return chapters;
}

List<ContentCategory> parseWebScrapeCategories(
  String html,
  RegExp pattern,
) {
  final categories = <ContentCategory>[];
  final seen = <String>{};
  for (final match in pattern.allMatches(html)) {
    final id = match.namedGroup('id')?.trim() ?? '';
    final name = match.namedGroup('name')?.trim() ?? '';
    if (id.isEmpty || name.isEmpty || !seen.add(id)) continue;
    categories.add(ContentCategory(id: id, name: name));
  }
  return categories;
}

String _optionalGroup(RegExpMatch match, String name) {
  try {
    return match.namedGroup(name)?.trim() ?? '';
  } catch (_) {
    return '';
  }
}

List<ContentBook> parseWebScrapeCards(String html, RegExp pattern) {
  final books = <ContentBook>[];
  final seen = <String>{};
  for (final match in pattern.allMatches(html)) {
    final id = match.namedGroup('id')?.trim() ?? '';
    final title = match.namedGroup('title')?.trim() ?? '';
    if (id.isEmpty || title.isEmpty || !seen.add(id)) continue;
    books.add(
      ContentBook(
        id: id,
        title: title,
        cover: _optionalGroup(match, 'cover'),
        author: _optionalGroup(match, 'author'),
        remarks: _optionalGroup(match, 'remarks'),
        intro: _optionalGroup(match, 'intro'),
      ),
    );
  }
  return books;
}

List<ContentChapter> parseWebScrapeChapters(String html, RegExp pattern) {
  final chapters = <ContentChapter>[];
  final seen = <String>{};
  for (final match in pattern.allMatches(html)) {
    final id = match.namedGroup('id')?.trim() ?? '';
    final title = match.namedGroup('title')?.trim() ?? '';
    if (id.isEmpty || title.isEmpty || !seen.add(id)) continue;
    chapters.add(ContentChapter(id: id, title: title));
  }
  return chapters;
}

String parseWebScrapeAudioUrl(String html, RegExp pattern) {
  final match = pattern.firstMatch(html);
  final url = match?.namedGroup('url')?.trim() ?? '';
  if (url.isEmpty) throw AppFailure('该章节未找到音频地址');
  return url;
}

class WebScrapeAudioSource extends ContentSource {
  WebScrapeAudioSource(
    this._http, {
    required this.sourceId,
    required this.sourceName,
    required this.categoriesUrl,
    required this.catalogUrl,
    required this.searchUrl,
    required this.detailUrl,
    required this.categoryPattern,
    required this.cardPattern,
    required this.chapterPattern,
    required this.audioPattern,
    this.nextPageMarker,
    this.audioHeaders = const {},
  });

  final ContentHttp _http;
  final String sourceId;
  final String sourceName;
  final String categoriesUrl;
  final String Function(String category, int page) catalogUrl;
  final String Function(String keyword, int page) searchUrl;
  final String Function(String book) detailUrl;
  final RegExp categoryPattern;
  final RegExp cardPattern;
  final RegExp chapterPattern;
  final RegExp audioPattern;
  final String Function(int page)? nextPageMarker;
  final Map<String, String> audioHeaders;

  @override
  String get id => sourceId;
  @override
  String get name => sourceName;
  @override
  ContentSection get section => ContentSection.audio;
  @override
  String get note => '网页抓取引擎实例，未做实站验证';

  bool _hasMore(String html, int page) {
    final marker = nextPageMarker;
    if (marker == null) return false;
    return html.contains(marker(page + 1));
  }

  @override
  Future<List<ContentCategory>> categories() async {
    final html = await _http.get(categoriesUrl);
    return parseWebScrapeCategories(html, categoryPattern);
  }

  @override
  Future<ContentPage> catalog(String categoryId, int page) async {
    final html = await _http.get(catalogUrl(categoryId, page));
    final items = parseWebScrapeCards(html, cardPattern);
    return ContentPage(
      items: items,
      hasMore: items.isNotEmpty && _hasMore(html, page),
      total: items.length,
    );
  }

  @override
  Future<ContentPage> search(String keyword, int page) async {
    final html = await _http.get(searchUrl(keyword, page));
    final items = parseWebScrapeCards(html, cardPattern);
    return ContentPage(
      items: items,
      hasMore: items.isNotEmpty && _hasMore(html, page),
      total: items.length,
    );
  }

  @override
  Future<ContentBookDetail> detail(String bookId) async {
    final html = await _http.get(detailUrl(bookId));
    final books = parseWebScrapeCards(html, cardPattern);
    final chapters = parseWebScrapeChapters(html, chapterPattern);
    if (chapters.isEmpty) throw AppFailure('该书暂无章节');
    return ContentBookDetail(
      book: books.isEmpty
          ? ContentBook(id: bookId, title: '')
          : books.first,
      chapters: chapters,
    );
  }

  @override
  Future<ContentAudioTrack> audioTrack(
    String bookId,
    ContentChapter chapter,
  ) async {
    final html = await _http.get(chapter.id);
    return ContentAudioTrack(
      url: parseWebScrapeAudioUrl(html, audioPattern),
      headers: audioHeaders,
    );
  }
}
