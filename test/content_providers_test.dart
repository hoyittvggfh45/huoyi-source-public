import 'dart:convert';

import 'package:duanju_app/content_baozimh.dart';
import 'package:duanju_app/content_cms.dart';
import 'package:duanju_app/content_copymanga.dart';
import 'package:duanju_app/content_dongmanla.dart';
import 'package:duanju_app/content_mangadex.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MacCMS 通用引擎解析', () {
    test('分类与列表', () {
      final cats = parseMacCmsCategories(
        jsonDecode(
              '{"class":[{"type_id":1,"type_name":"有声小说"}],'
              '"pagecount":3,"total":42,'
              '"list":[{"vod_id":9,"vod_name":"书","vod_pic":"p.jpg",'
              '"vod_remarks":"更新至10集"}]}',
            )
            as Map<String, dynamic>,
      );
      expect(cats, hasLength(2));
      expect(cats.last.name, '有声小说');
      final page = parseMacCmsListPage(
        jsonDecode(
              '{"pagecount":3,"total":42,"list":[{"vod_id":9,'
              '"vod_name":"书","vod_pic":"p.jpg","vod_remarks":"更新至10集"}]}',
            )
            as Map<String, dynamic>,
        1,
      );
      expect(page.items.first.title, '书');
      expect(page.hasMore, isTrue);
    });

    test('分集解析与音频过滤', () {
      final chapters = parseMacCmsEpisodes({
        'vod_play_url':
            '第1集\$https://a.example/1.mp3#第2集\$https://a.example/2.mp4'
            '\$\$\$第1集\$https://b.example/1.mp3',
      }, onlyAudio: true);
      expect(chapters, hasLength(1));
      expect(chapters.first.title, '第1集');
      expect(chapters.first.id, 'https://a.example/1.mp3');
      expect(MacCmsAudioSource.isAudioUrl('https://a/1.MP3?x=1'), isTrue);
      expect(MacCmsAudioSource.isAudioUrl('https://a/1.mp4'), isFalse);
    });
  });

  group('MangaDex 解析（公开 API 结构样本）', () {
    test('列表与封面拼装', () {
      final json =
          jsonDecode(
                '{"data":[{"id":"m1","type":"manga",'
                '"attributes":{"title":{"en":"Test Manga"},"status":"ongoing",'
                '"year":2024,"description":{"zh":"简介"}},'
                '"relationships":[{"type":"cover_art","attributes":'
                '{"fileName":"c.jpg"}},{"type":"author","attributes":'
                '{"name":"作者"}}]}],"limit":20,"offset":0,"total":21}',
              )
              as Map<String, dynamic>;
      final page = parseMangaDexListPage(json, 1);
      expect(page.items.first.title, 'Test Manga');
      expect(
        page.items.first.cover,
        'https://uploads.mangadex.org/covers/m1/c.jpg.256.jpg',
      );
      expect(page.items.first.intro, '简介');
      expect(page.hasMore, isTrue);
    });

    test('章节与页图', () {
      final chapter = mangaDexChapter({
        'id': 'ch1',
        'attributes': {'chapter': '3', 'title': '开始', 'pages': 18},
      });
      expect(chapter?.title, '第3话 开始');
      expect(chapter?.meta, '18 页');
      final external = mangaDexChapter({
        'id': 'ch2',
        'attributes': {'chapter': '4', 'pages': 10, 'externalUrl': 'https://x'},
      });
      expect(external, isNull);
      final pages = parseMangaDexPages(
        jsonDecode(
              '{"baseUrl":"https://up.example","chapter":'
              '{"hash":"h1","data":["a.jpg","b.jpg"],"dataSaver":[]}}',
            )
            as Map<String, dynamic>,
      );
      expect(pages, [
        'https://up.example/data/h1/a.jpg',
        'https://up.example/data/h1/b.jpg',
      ]);
    });
  });

  group('动漫啦 解析', () {
    test('卡片列表', () {
      const html =
          '<ul><li><a href="/manhua/detail/42/">'
          '<img data-cover src="https://img.dongman.la/uploads/42.jpg"></a>'
          '<a href="/manhua/detail/42/">某漫画</a>'
          '状态：<span class="c">连载中</span>作者：佚名'
          '最新：<a href="/manhua/chapter/42/7/">第7话</a></li></ul>';
      final books = parseDongmanlaCards(html);
      expect(books, hasLength(1));
      expect(books.first.title, '某漫画');
      expect(books.first.remarks, contains('连载中'));
      expect(books.first.remarks, contains('第7话'));
    });

    test('详情章节排序与章图', () {
      const html =
          '<html><head>'
          '<meta property="og:title" content="某漫画漫画在线阅读"></head>'
          '<body><div class="detail-description"><p>简介文字</p></div>'
          '<a href="/manhua/chapter/42/9/">第2话</a>'
          '<a href="/manhua/chapter/42/7/">第1话</a>'
          '<img src="https://img.dongman.la/h/42/7/1.jpg">'
          '<img src="https://img.dongman.la/h/42/7/2.jpg"></body></html>';
      final detail = parseDongmanlaDetail(html, '42');
      expect(detail.book.title, '某漫画');
      expect(detail.book.intro, '简介文字');
      expect(detail.chapters.map((c) => c.title), ['第1话', '第2话']);
      expect(detail.chapters.first.id, '42/7');
      expect(parseDongmanlaChapterImages(html), hasLength(2));
    });
  });

  group('拷贝漫画解析（结构与 2026-10-24 实拉响应一致）', () {
    test('列表卡片取 slug/封面/作者', () {
      final page = parseCopymangaList({
        'results': {
          'list': [
            {
              'path_word': 'haizeiwang',
              'name': '海贼王',
              'cover': 'https://cdn.example/cover.jpg',
              'author': [
                {'name': '尾田荣一郎'},
              ],
            },
          ],
          'total': 50,
        },
      }, 1);
      expect(page.items.single.id, 'haizeiwang');
      expect(page.items.single.author, '尾田荣一郎');
      expect(page.hasMore, isTrue);
    });

    test('详情书籍与章节行解析（保留接口顺序）', () {
      final book = copymangaBook({
        'name': '测试漫画',
        'cover': '',
        'author': [],
        'status': {'display': '连载中'},
        'brief': '简介',
      }, 'slug1');
      expect(book.title, '测试漫画');
      final chapters = [
        for (final row in [
          {'uuid': 'u2', 'name': '第10話'},
          {'uuid': 'u1', 'name': '第2話'},
        ])
          copymangaChapter(row)!,
      ];
      expect(chapters.map((c) => c.id), ['u2', 'u1']);
    });

    test('章节页图直链解析', () {
      final pages = parseCopymangaPages({
        'results': {
          'chapter': {
            'contents': [
              {'url': 'https://img.example/1.jpg'},
              {'url': 'https://img.example/2.jpg'},
            ],
          },
        },
      });
      expect(pages, hasLength(2));
    });
  });

  group('包子漫画解析（结构与 2026-10-24 实拉响应一致）', () {
    test('SSR 卡片解析', () {
      const html = '''
<a href="/manga/fanrenxiuxianzhuan" class="cardlink"><img class="card" src="https://img.example/c.jpg" alt="凡人修仙传"><h3 class="cardtitle">凡人修仙传</h3></a>''';
      final books = parseBaozimhCards(html);
      expect(books.single.id, 'fanrenxiuxianzhuan');
      expect(books.single.title, '凡人修仙传');
    });

    test('详情 API 解析并跳过广告章', () {
      final detail = parseBaozimhDetail(
        {
          'data': {
            'title': '凡人',
            'slug': 'fanren',
            'cover': 'https://img.example/c.jpg',
            'desc': '简介',
            'status': '连载中',
            'chapters': [
              {
                'id': 11,
                'attributes': {'title': '第1话', 'isAd': 0},
              },
              {
                'id': 12,
                'attributes': {'title': '广告', 'isAd': 1},
              },
            ],
          },
        },
        'fanren',
        '1001',
        '',
      );
      expect(detail.chapters, hasLength(1));
      // 章节 id 为 mid:cid 复合（章节页接口需要 mid）
      expect(detail.chapters.single.id, '1001:11');
    });
  });
}
