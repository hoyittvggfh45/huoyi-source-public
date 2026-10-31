import 'dart:convert';

import 'package:duanju_app/content_audio.dart';
import 'package:duanju_app/content_audio_history.dart';
import 'package:duanju_app/content_audio_player.dart';
import 'package:duanju_app/content_cms.dart';
import 'package:duanju_app/legado_builtin_data.dart';
import 'package:duanju_app/legado_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _categoryIndex = '''
<a href="/book/kongbuxuanyi/" data-cid="12"  title="恐怖悬疑">恐怖悬疑</a>
<a href="/book/dushiyanqing/" data-cid="13"  title="都市言情">都市言情</a>
<a href="/book/junshilishi/" data-cid="16"  title="军事历史">军事历史</a>
<a href="/book/junshilishi/" data-cid="16"  title="军事历史">军事历史</a>
''';

const _catalogPage = '''
<ul class="m-book-list">
<li>
<a href="/book/QiongGuiDeShangXiaLiangQianNian/" class="full-link" title="穷鬼的上下两千年"></a>
<div class="cover">
<a href="/book/QiongGuiDeShangXiaLiangQianNian/">
<img src="https://www.tingshuwang.cc/d/file/cover/yt/14503/14503.webp" alt="穷鬼的上下两千年">
<em>穷鬼的上下两千年 第469集 豆饭（完结）</em>
</a>
</div>
<div class="info">
<span class="t"><h5><a href="/book/QiongGuiDeShangXiaLiangQianNian/">穷鬼的上下两千年</a><em class="finished">已完结</em></h5></span>
<span class="f">
<em class="click"><i class="iconfont icon-listen"></i>1万</em>
<em class="author"><i class="iconfont icon-voice"></i><a href="/announcer/%E5%85%A8%E5%8B%87/" title="全勇播讲的有声小说" target="_self">全勇</a></em>
</span>
<p class="intro">《穷鬼的上下两千年》有声小说是非玩家角色所着的权谋治癒系历史小说</p>
</div>
</li>
</ul>
<a href="index_2.html">下一页</a>
''';

const _detailPage = '''
<title>大国相有声小说全集-主播：-作者：余人-听书网</title>
<img src="https://www.tingshuwang.cc/d/file/cover/21687/efa0565a4409ff5fb964243843a846ea.gif" alt="大国相">
<a href="/book/DaGuoXiang/25537.html" target="_self" title="大国相 第1350集_贺寿">第1350集_贺寿</a>
<a href="/book/DaGuoXiang/25536.html" target="_self" title="大国相 第1349集_青山下">第1349集_青山下</a>
<a href="/book/DaGuoXiang/21787.html" target="_self" title="大国相 第001集_寒门书生">第001集_寒门书生</a>
''';

const _chapterPage = '''
videourl:'https://www.tingshuwang.cc/d/file/21687/0001.m4a', videotype:'m4a',
''';

void main() {
  group('听书网解析', () {
    test('分类去重', () {
      final categories = parseTingshuwangCategories(_categoryIndex);
      expect(categories.map((c) => c.id), [
        'kongbuxuanyi',
        'dushiyanqing',
        'junshilishi',
      ]);
      expect(categories.last.name, '军事历史');
    });

    test('分类列表卡片与翻页', () {
      final page = parseTingshuwangCatalog(_catalogPage, 1);
      expect(page.items, hasLength(1));
      final book = page.items.first;
      expect(book.id, 'QiongGuiDeShangXiaLiangQianNian');
      expect(book.title, '穷鬼的上下两千年');
      expect(book.cover, contains('d/file/cover'));
      expect(book.author, '全勇');
      expect(book.remarks, contains('已完结'));
      expect(book.intro, contains('权谋'));
      expect(page.hasMore, isTrue);
      expect(parseTingshuwangCatalog(_catalogPage, 2).hasMore, isFalse);
    });

    test('详情章节倒序回正序', () {
      final detail = parseTingshuwangDetail(_detailPage, 'DaGuoXiang');
      expect(detail.book.title, '大国相');
      expect(detail.book.author, '余人');
      expect(detail.book.cover, contains('d/file/cover'));
      expect(detail.chapters, hasLength(3));
      expect(detail.chapters.first.title, '第001集_寒门书生');
      expect(detail.chapters.first.id, endsWith('/21787.html'));
      expect(detail.chapters.last.title, '第1350集_贺寿');
    });

    test('章节音频地址', () {
      expect(
        parseTingshuwangAudioUrl(_chapterPage),
        'https://www.tingshuwang.cc/d/file/21687/0001.m4a',
      );
      expect(
        () => parseTingshuwangAudioUrl('<html></html>'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('听书搜索多页与翻页判定', () {
    const searchPage1 = '''
<ul class="m-book-list">
<li>
<a href="/book/DaGuoXiang/" class="full-link" title="大国相"></a>
<img src="https://www.tingshuwang.cc/d/file/cover/21687/x.gif">
</li>
</ul>
<div class="mpages"><span class="page-info">当前: 1/2</span>
<a href="index_2.html" class="next" title="下一页">下一页</a></div>
''';
    const searchPage2 = '''
<ul class="m-book-list">
<li>
<a href="/book/OtherBook/" class="full-link" title="他书"></a>
<img src="https://www.tingshuwang.cc/d/file/cover/1/x.gif">
</li>
</ul>
<div class="mpages"><span class="page-info">当前: 2/2</span></div>
''';

    test('搜索第 1 页有下一页，第 2 页无下一页', () {
      expect(parseTingshuwangSearch(searchPage1, 1).hasMore, isTrue);
      expect(parseTingshuwangSearch(searchPage2, 2).hasMore, isFalse);
      expect(parseTingshuwangSearch(searchPage2, 2).items.first.id, 'OtherBook');
    });

    test('仅页码信息也可判定翻页', () {
      expect(tingshuwangHasMore('<span>当前: 1/3</span>', 1), isTrue);
      expect(tingshuwangHasMore('<span>当前: 3/3</span>', 3), isFalse);
      expect(tingshuwangHasMore('<div>无分页信息</div>', 1), isFalse);
    });
  });

  group('MacCMS 多线路', () {
    test('全线路解析并以播放源名作 meta，去重同地址', () {
      final chapters = parseMacCmsEpisodesAllLines({
        'vod_play_from': '线路A\$\$\$线路B',
        'vod_play_url':
            '第1集\$https://a.example/1.mp3#第2集\$https://a.example/2.mp4'
            '\$\$\$第1集\$https://b.example/1.mp3#第1集\$https://a.example/1.mp3',
      }, onlyAudio: true);
      expect(chapters.map((c) => c.id), [
        'https://a.example/1.mp3',
        'https://b.example/1.mp3',
      ]);
      expect(chapters.first.meta, '线路A');
      expect(chapters.last.meta, '线路B');
      expect(
        parseMacCmsEpisodes({
          'vod_play_url':
              '第1集\$https://a.example/1.mp3\$\$\$第1集\$https://b.example/1.mp3',
        }, onlyAudio: true),
        hasLength(1),
      );
    });
  });

  group('网页抓取引擎解析', () {
    test('分类与卡片与章节与音频地址均由命名组承载', () {
      final categories = parseWebScrapeCategories(
        '<a href="/c/1">玄幻</a><a href="/c/2">都市</a>',
        RegExp(r'href="/c/(?<id>[^"]+)">(?<name>[^<]+)</a>'),
      );
      expect(categories.map((c) => c.id), ['1', '2']);
      final cards = parseWebScrapeCards(
        '<a href="/b/9" title="书名"><img src="c.jpg"></a>',
        RegExp(
          r'href="/b/(?<id>[^"]+)" title="(?<title>[^"]+)">'
          r'<img src="(?<cover>[^"]+)">',
        ),
      );
      expect(cards.single.title, '书名');
      expect(cards.single.cover, 'c.jpg');
      final chapters = parseWebScrapeChapters(
        '<a href="/p/1">第1集</a><a href="/p/2">第2集</a>',
        RegExp(r'href="(?<id>[^"]+)">(?<title>[^<]+)</a>'),
      );
      expect(chapters.map((c) => c.title), ['第1集', '第2集']);
      expect(
        parseWebScrapeAudioUrl(
          "audio:'https://a.example/1.mp3'",
          RegExp(r"audio:'(?<url>[^']+)'"),
        ),
        'https://a.example/1.mp3',
      );
      expect(
        () => parseWebScrapeAudioUrl(
          '<html></html>',
          RegExp(r"audio:'(?<url>[^']+)'"),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('听书进度与历史纯函数', () {
    test('历史合并去重置顶并截断', () {
      final old = [
        for (var i = 0; i < 3; i++)
          AudioHistoryEntry(
            sourceId: 's',
            bookId: 'b$i',
            title: '书$i',
            updatedAtMs: i,
          ),
      ];
      final merged = mergeAudioHistory(
        old,
        const AudioHistoryEntry(
          sourceId: 's',
          bookId: 'b1',
          title: '书1',
          updatedAtMs: 9,
        ),
        max: 3,
      );
      expect(merged.map((e) => e.bookId), ['b1', 'b0', 'b2']);
      expect(merged.first.updatedAtMs, 9);
    });

    test('断点与历史条目 JSON 往返', () {
      const resume = AudioResume(
        chapterIndex: 3,
        positionMs: 12345,
        updatedAtMs: 99,
      );
      expect(AudioResume.fromJson(resume.toJson()), isNotNull);
      expect(AudioResume.fromJson(resume.toJson())!.positionMs, 12345);
      expect(AudioResume.fromJson({'chapterIndex': 'x'}), isNull);
      const entry = AudioHistoryEntry(
        sourceId: 's',
        bookId: 'b',
        title: '书',
        chapterIndex: 2,
        chapterTitle: '第3集',
        positionMs: 5000,
        updatedAtMs: 7,
      );
      final restored = AudioHistoryEntry.fromJson(entry.toJson())!;
      expect(restored.key, 's::b');
      expect(restored.chapterTitle, '第3集');
      expect(audioResumeKey('s', 'b'), 'audio_resume_s_b');
    });
  });

  group('内置规则书源种子', () {
    test('216 条全带名，搜索地址缺失者仅限猫果且带发现地址', () {
      final sources = parseLegadoSources(builtinLegadoRulesJson);
      expect(sources, hasLength(216));
      for (final source in sources) {
        expect(source.name, isNotEmpty);
        if (source.searchUrl.isEmpty) {
          expect(source.name, '猫果');
          expect(source.exploreUrl, isNotEmpty);
        }
      }
    });

    test('成人分组现状：🔞 分组仅 2 条旧补，新增 5 条以 R18 分组标记', () {
      final decoded = jsonDecode(builtinLegadoRulesJson);
      expect(decoded, isA<List>());
      final flagged = <String>[];
      final r18 = <String>[];
      for (final item in decoded as List) {
        final map = item as Map;
        final name = '${map['bookSourceName']}';
        final group = '${map['bookSourceGroup'] ?? ''}';
        if (group.contains('🔞')) flagged.add(name);
        if (group.contains('R18')) r18.add(name);
      }
      expect(flagged, ['啵乐屋🔞', '🔞 夜色韩漫']);
      expect(r18, [
        'XiuRenBox 秀人网写真',
        '美人图 写真美图',
        'MMRGB 魅色MM',
        '漫小肆韓漫',
        '4KHD 高清写真',
      ]);
    });
  });

  group('听书进度落盘与续播', () {
    test('断点保存读取与清除，零进度不落盘', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AudioProgressStore();
      expect(await store.loadResume('s', 'b'), isNull);
      await store.saveResume('s', 'b', 2, 0);
      expect(await store.loadResume('s', 'b'), isNull);
      await store.saveResume('s', 'b', 2, 65432);
      final resume = await store.loadResume('s', 'b');
      expect(resume, isNotNull);
      expect(resume!.chapterIndex, 2);
      expect(resume.positionMs, 65432);
      await store.clearResume('s', 'b');
      expect(await store.loadResume('s', 'b'), isNull);
    });

    test('损坏的断点与历史数据不抛错且读回空', () async {
      SharedPreferences.setMockInitialValues({
        'audio_resume_s_b': 'not-json',
        'audio_history': 'not-json',
      });
      final store = AudioProgressStore();
      expect(await store.loadResume('s', 'b'), isNull);
      expect(await store.loadHistory(), isEmpty);
    });

    test('历史记录落盘去重置顶并截断', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AudioProgressStore();
      for (var i = 0; i < 3; i++) {
        await store.recordHistory(
          AudioHistoryEntry(
            sourceId: 's',
            bookId: 'b$i',
            title: '书$i',
            updatedAtMs: i,
          ),
        );
      }
      await store.recordHistory(
        const AudioHistoryEntry(
          sourceId: 's',
          bookId: 'b1',
          title: '书1',
          updatedAtMs: 9,
        ),
      );
      final history = await store.loadHistory();
      expect(history.map((e) => e.bookId), ['b1', 'b2', 'b0']);
      expect(history.first.updatedAtMs, 9);
    });

    test('收藏与播放模式落盘往返', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AudioProgressStore();
      expect(await store.isFavorite('s::b'), isFalse);
      await store.setFavorite('s::b', true);
      expect(await store.isFavorite('s::b'), isTrue);
      await store.setFavorite('s::b', false);
      expect(await store.isFavorite('s::b'), isFalse);
      await store.savePlayMode('shuffle');
      expect(await store.loadPlayMode(), 'shuffle');
    });
  });

  group('听书播放模式', () {
    test('四种模式存储值往返，未知值回落顺序播放', () {
      for (final mode in AudioPlayMode.values) {
        expect(
          AudioPlayModeValue.fromStorage(mode.storageValue),
          mode,
        );
      }
      expect(AudioPlayModeValue.fromStorage('nope'), AudioPlayMode.sequence);
      expect(AudioPlayModeValue.fromStorage(null), AudioPlayMode.sequence);
      expect(
        AudioPlayMode.values.map((m) => m.storageValue).toSet(),
        hasLength(4),
      );
    });

    test('循环与随机下一集分支', () {
      expect(
        audioNextIndex(AudioPlayMode.sequence, 0, 3, () => 2),
        1,
      );
      expect(audioNextIndex(AudioPlayMode.sequence, 2, 3, () => 0), isNull);
      expect(audioNextIndex(AudioPlayMode.loopAll, 2, 3, () => 0), 0);
      expect(audioNextIndex(AudioPlayMode.loopOne, 1, 3, () => 0), 1);
      expect(audioNextIndex(AudioPlayMode.shuffle, 1, 3, () => 2), 2);
      expect(audioNextIndex(AudioPlayMode.sequence, 0, 1, () => 0), isNull);
      expect(audioNextIndex(AudioPlayMode.sequence, 5, 3, () => 0), isNull);
      expect(audioNextIndex(AudioPlayMode.sequence, 0, 0, () => 0), isNull);
    });

    test('上一集分支，循环全部在首集回末集', () {
      expect(audioPrevIndex(AudioPlayMode.sequence, 2, 3, () => 0), 1);
      expect(audioPrevIndex(AudioPlayMode.sequence, 0, 3, () => 0), isNull);
      expect(audioPrevIndex(AudioPlayMode.loopAll, 0, 3, () => 0), 2);
      expect(audioPrevIndex(AudioPlayMode.loopOne, 1, 3, () => 0), 0);
      expect(audioPrevIndex(AudioPlayMode.shuffle, 0, 3, () => 2), 2);
    });
  });
}
