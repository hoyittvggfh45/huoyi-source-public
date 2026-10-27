import 'content_http.dart';
import 'content_models.dart';
import 'core_bridge.dart';

/// 听书通用引擎之一：MacCMS（苹果CMS）JSON 采集接口。
///
/// 绿果鉴听书模块以 CMS/ZBlog/网页三通用引擎兜底长尾站；本引擎按
/// MacCMS provide 口径实现（ac=list/detail、class 分类、vod_play_url
/// 分集），任何提供该接口的听书站填 base 即可成源。ZBlog 与网页
/// 抓取引擎未落（见批次报告）。本机无实站验证：注册表默认不挂实例，
/// 解析逻辑由离线单测覆盖。
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
      chapters: parseMacCmsEpisodes(row, onlyAudio: onlyAudio),
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
  final chapters = <ContentChapter>[];
  for (final part in firstLine.split('#')) {
    final seg = part.trim();
    if (seg.isEmpty) continue;
    final at = seg.indexOf('\$');
    final title = at > 0 ? seg.substring(0, at) : '第${chapters.length + 1}集';
    final url = at >= 0 ? seg.substring(at + 1) : seg;
    if (url.isEmpty) continue;
    if (onlyAudio && !MacCmsAudioSource.isAudioUrl(url)) continue;
    chapters.add(ContentChapter(id: url, title: title));
  }
  return chapters;
}
