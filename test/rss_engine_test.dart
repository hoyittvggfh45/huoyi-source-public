import 'dart:io';

import 'package:duanju_app/rss_engine.dart';
import 'package:duanju_app/rss_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _banyuetan = RssSource(
  id: 'rss_banyuetan',
  name: '半月谈',
  sourceUrl: 'http://www.banyuetan.org/',
  ruleArticles: '.clearFix.1@li',
  ruleTitle: 'img@alt',
  ruleLink: 'a.0@href',
  rulePubDate: '{{@tag.span@text}}',
  ruleContent:
      '<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0">\n{{@tag.title@html}}\n{{@.detail_top@html}}',
  ruleImage: 'img@src',
  ruleNextPage: '.listnext@href',
);

const _yinrss = RssSource(
  id: 'rss_yinrss',
  name: '隐订阅',
  sourceUrl: 'https://api.yinrss.com/feed',
  ruleArticles: r'$.data',
  ruleTitle: r'$.title',
  ruleLink: r'/detail?id={{$.id}}',
  rulePubDate: r'🌐 {{$.source}} &nbsp; ⏱️ {{$.date##T|\.\d{3}[zZ]$## }}',
  ruleContent:
      '<meta name="viewport" content="width=device-width,initial-scale=1.0,minimum-scale=1.0,maximum-scale=1.0,user-scalable=no">\n<br>\n<h3>{{\$..title}}</h3>\n<h6>\n\t<a href="{{\$..url}}">{{\$..source}}</a>\n\t<i>{{\$..date}}</i>\n</h6>\n<p>{{\$..content}}</p>',
  ruleImage: r'$.img',
  ruleNextPage: '',
);

String _fixture(String name) =>
    File('test/rss_fixtures/$name').readAsStringSync();

void main() {
  const engine = RssEngine();

  test('banyuetan list parses real article links', () {
    final result = engine.parseListPage(
      _banyuetan,
      _fixture('banyuetan_list.html'),
      'http://www.banyuetan.org/',
      1,
    );
    expect(result.items.length, greaterThan(5));
    for (final item in result.items) {
      expect(item.link.startsWith('http'), isTrue);
    }
    expect(
      result.items.any((item) => item.link.contains('/yw/detail/')),
      isTrue,
    );
  });

  test('img alt extraction works when alt exists', () {
    const page =
        '<html><body><ul><li><img src="/a.png" alt="头条"></li></ul></body></html>';
    final result = engine.parseListPage(
      const RssSource(
        id: 'x',
        name: 'x',
        sourceUrl: 'http://example.com/',
        ruleArticles: 'li',
        ruleTitle: 'img@alt',
        ruleLink: 'img@src',
      ),
      page,
      'http://example.com/',
      1,
    );
    expect(result.items.single.title, '头条');
  });

  test('banyuetan article parses content blocks', () {
    final item = RssItem(
      title: 'test',
      link: 'http://www.banyuetan.org/dyp/detail/20261102/1.html',
    );
    final result = engine.parseArticlePage(
      _banyuetan,
      item,
      _fixture('banyuetan_article.html'),
    );
    expect(result.blocks, isNotEmpty);
    expect(
      result.blocks.where((block) => !block.isImage).length,
      greaterThan(0),
    );
  });

  test('yinrss feed parses items with resolved links', () {
    final result = engine.parseListPage(
      _yinrss,
      _fixture('yinrss_feed.json'),
      'https://api.yinrss.com/feed',
      1,
    );
    expect(result.items.length, greaterThan(5));
    final first = result.items.first;
    expect(first.title, isNotEmpty);
    expect(first.link.startsWith('https://api.yinrss.com/detail?id='), isTrue);
    expect(first.date.contains('36氪'), isTrue);
  });

  test('yinrss detail parses content blocks', () {
    final item = RssItem(
      title: 'test',
      link: 'https://api.yinrss.com/detail?id=5031540',
    );
    final result = engine.parseArticlePage(
      _yinrss,
      item,
      _fixture('yinrss_detail.json'),
    );
    expect(result.blocks, isNotEmpty);
    expect(
      result.blocks.any(
        (block) => !block.isImage && block.text.contains('智子光垣'),
      ),
      isTrue,
    );
  });

  test('selector chain class plus index plus extraction', () {
    const html =
        '<div class="wrap"><ul><li><a href="/a">一</a></li>'
        '<li><a href="/b">二</a></li></ul></div>';
    final doc = engine.parseListPage(
      const RssSource(
        id: 'x',
        name: 'x',
        sourceUrl: 'http://example.com/',
        ruleArticles: '.wrap@li',
        ruleTitle: 'a@text',
        ruleLink: 'a@href',
      ),
      '<html><body>$html</body></html>',
      'http://example.com/',
      1,
    );
    expect(doc.items.map((item) => item.title), ['一', '二']);
    expect(doc.items.first.link, 'http://example.com/a');
  });

  test('alternatives replace join and json path', () {
    const page =
        '<html><body><div class="a">甲</div><div class="b">乙</div></body></html>';
    final doc = engine.parseListPage(
      const RssSource(
        id: 'x',
        name: 'x',
        sourceUrl: 'http://example.com/',
        ruleArticles: '.a&&.b',
        ruleTitle: '@text',
        ruleLink: '',
      ),
      page,
      'http://example.com/',
      1,
    );
    expect(doc.items.map((item) => item.title), ['甲', '乙']);
    expect(
      engine.evalFirstString(r'$.data[1].name', {
        'data': [
          {'name': 'a'},
          {'name': 'b'},
        ],
      }, 'http://example.com/'),
      'b',
    );
    expect(
      engine.evalFirstString(r'$..name', {
        'outer': {
          'inner': {'name': 'deep'},
        },
      }, 'http://example.com/'),
      'deep',
    );
  });

  test('script rules fail clearly instead of empty', () {
    expect(
      () => engine.evalStrings(
        '<js>java.log("x")</js>',
        null,
        'http://example.com/',
      ),
      throwsA(
        isA<RssFailure>().having(
          (error) => error.scriptUnsupported,
          'scriptUnsupported',
          true,
        ),
      ),
    );
    expect(
      engine.evalStrings(
        "@js: 'http://example.com/logo.png'",
        null,
        'http://example.com/',
      ),
      ['http://example.com/logo.png'],
    );
  });

  test('validation rejects book sources and missing fields', () {
    expect(
      () => parseRssSource(
        '{"bookSourceUrl": "http://example.com", "searchUrl": "http://example.com/s"}',
      ),
      throwsA(isA<RssFailure>()),
    );
    expect(
      () => parseRssSource('{"sourceUrl": "http://example.com"}'),
      throwsA(isA<RssFailure>()),
    );
    expect(
      () => parseRssSource('not json'),
      throwsA(isA<RssFailure>()),
    );
    final source = parseRssSource(
      '{"sourceName": "t", "sourceUrl": "http://example.com/feed", '
      '"ruleArticles": ".item", "ruleTitle": "a@text", "ruleLink": "a@href"}',
    );
    expect(source.name, 't');
  });

  test('page templates and next page', () {
    expect(
      engine.applyPageTemplate('http://example.com/api?page={{page}}', 3),
      'http://example.com/api?page=3',
    );
    expect(
      engine.applyPageTemplate(
        'http://example.com/api?limit=30&offset={{(page-1)*30}}',
        2,
      ),
      'http://example.com/api?limit=30&offset=30',
    );
    const source = RssSource(
      id: 'x',
      name: 'x',
      sourceUrl: 'http://example.com/',
      ruleArticles: '.item',
      ruleTitle: 'a@text',
      ruleLink: 'a@href',
      ruleNextPage: 'page',
    );
    expect(
      engine.resolveNextPage(source, null, 'http://example.com/', 1),
      isNull,
    );
  });

  test('content blocks split text and images', () {
    final blocks = engine.contentBlocks(
      '<p>第一段</p><p><img src="/a.png"></p><p>第二段</p>',
      'http://example.com/n/1.html',
    );
    expect(blocks.length, 3);
    expect(blocks[0].text, '第一段');
    expect(blocks[1].imageUrl, 'http://example.com/a.png');
    expect(blocks[2].text, '第二段');
  });
}
