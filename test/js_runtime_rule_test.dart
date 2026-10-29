import 'dart:io';

import 'package:duanju_app/js_runtime/cheerio_js.dart';
import 'package:duanju_app/js_runtime/hiker_rule.dart';
import 'package:duanju_app/js_runtime/host_api.dart';
import 'package:duanju_app/js_runtime/js_bridge.dart';
import 'package:duanju_app/js_runtime/js_engine.dart';
import 'package:duanju_app/js_runtime/rule_runner.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements BridgeKeyValue {
  final _map = <String, String>{};

  @override
  String? read(String key) => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  List<String> keys() => _map.keys.toList();
}

class _StubHttp implements BridgeHttpClient {
  _StubHttp(this._bodies);

  final Map<String, String> _bodies;

  @override
  Future<HostHttpResponse> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final body = _bodies[url];
    if (body == null) throw Exception('stub: no body for $url');
    return HostHttpResponse(
      statusCode: 200,
      body: body,
      bodyBytes: body.codeUnits,
      headers: const {},
    );
  }

  @override
  Future<HostHttpResponse> post(
    String url, {
    Map<String, String> headers = const {},
    Object? body,
    String? contentType,
  }) async {
    return get(url, headers: headers);
  }
}

Future<JsBridge> _openBridge({bool withCheerio = false}) async {
  final engine = QuickJsEngine.open('/tmp/libquickjs.so');
  addTearDown(engine.dispose);
  final bridge = JsBridge.test(
    engine: engine,
    http: _StubHttp(const {}),
    storage: _MemoryStorage(),
    storagePublic: _MemoryStorage(),
    paths: HostPaths(filesDir: '/tmp/js_rule_files'),
  );
  await bridge.install();
  if (withCheerio) {
    final cheerio =
        await File('assets/js_runtime/cheerio.min.js').readAsString();
    await bridge.evalExtra(CheerioJs.buildInstallScript(cheerio));
  }
  return bridge;
}

HikerRule _rule(Map<String, dynamic> fields) {
  return HikerRule.fromJson(<String, dynamic>{
    'title': 'synthetic',
    'url': 'http://x/list/fypage',
    'col_type': 'movie_3',
    'find_rule': '',
    'ua': '',
    ...fields,
  });
}

void main() {
  test('rule normalization and list url substitution', () {
    final rule = _rule(<String, dynamic>{
      'url': 'http://h/list/fypage/fyclass/fyarea/fyyear/fysort/{host}/fyAll',
      'class_name': 'a&b',
    });
    expect(rule.classNames, ['a', 'b']);
    expect(
      rule.buildListUrl(
        page: 3,
        cls: 'c1',
        area: 'a1',
        sort: 's1',
        year: '2024',
        host: 'hh',
      ),
      'http://h/list/3/c1/a1/2024/s1/hh/c1',
    );
  });

  test('search url keyword substitution', () {
    final rule = _rule(<String, dynamic>{
      'search_url': 'http://h/s?keyword/fypage',
      'searchFind': 'js: setResult([]);',
    });
    expect(
      rule.buildSearchUrl('a b', page: 2),
      'http://h/s?a%20b/2',
    );
    final wdRule = _rule(<String, dynamic>{
      'search_url': 'http://h/s?wd=',
      'searchFind': 'js: setResult([]);',
    });
    expect(wdRule.buildSearchUrl('kw'), 'http://h/s?wd=kw');
  });

  test('cards from setResult variants', () {
    final cards = cardsFromSetResult(<dynamic>[
      {'title': 't', 'url': 'u', 'pic_url': 'p', 'desc': 'd'},
      'plain',
      {'name': 'n', 'link': 'l', 'img': 'i'},
    ], 'movie_3');
    expect(cards.length, 3);
    expect(cards[0].title, 't');
    expect(cards[0].picUrl, 'p');
    expect(cards[1].title, 'plain');
    expect(cards[2].title, 'n');
    expect(cards[2].url, 'l');
    expect(cards[2].picUrl, 'i');
  });

  test('runList with js rule reading cached fetch', () async {
    final bridge = await _openBridge();
    const html = '<html><body>page</body></html>';
    final runner = RuleRunner(
      bridge: bridge,
      fetcher: (url, headers) async => html,
    );
    final rule = _rule(<String, dynamic>{
      'find_rule':
          'js: var h = fetch("http://x/list/1"); setResult([{title: "t1", url: "u1", pic_url: "p1"}]);',
      'url': 'http://x/list/fypage',
    });
    final cards = await runner.runList(rule, page: 1);
    expect(cards.length, 1);
    expect(cards[0].title, 't1');
    expect(cards[0].colType, 'movie_3');
  });

  test('runList with multi-segment selector rule', () async {
    final bridge = await _openBridge(withCheerio: true);
    const html =
        '<html><body>'
        '<div class="item"><a href="/a1"><img src="/p1.jpg"><span class="t">T1</span></a></div>'
        '<div class="item"><a href="/a2"><img src="/p2.jpg"><span class="t">T2</span></a></div>'
        '</body></html>';
    final runner = RuleRunner(
      bridge: bridge,
      fetcher: (url, headers) async => html,
    );
    final rule = _rule(<String, dynamic>{
      'find_rule': 'body&&div.item;a&&href;img&&src;.t&&Text',
      'url': 'http://x/list/fypage',
    });
    final cards = await runner.runList(rule, page: 1);
    expect(cards.length, 2);
    expect(cards[0].title, 'T1');
    expect(cards[0].url, '/a1');
    expect(cards[0].picUrl, '/p1.jpg');
    expect(cards[1].title, 'T2');
    expect(cards[1].url, '/a2');
  });

  test('preRule result injects into list rule', () async {
    final bridge = await _openBridge();
    final runner = RuleRunner(
      bridge: bridge,
      fetcher: (url, headers) async => '<html></html>',
    );
    final rule = _rule(<String, dynamic>{
      'preRule': 'js: setResult("PRE");',
      'find_rule':
          'js: setResult([{title: globalThis.__preResult, url: "u"}]);',
    });
    final cards = await runner.runList(rule);
    expect(cards.length, 1);
    expect(cards[0].title, 'PRE');
  });

  test('detail fallback chain', () async {
    final bridge = await _openBridge();
    var fetched = 0;
    final runner = RuleRunner(
      bridge: bridge,
      fetcher: (url, headers) async {
        fetched++;
        return '<html></html>';
      },
    );
    final bare = _rule(<String, dynamic>{});
    final card = const MiniAppCard(
      title: 't',
      url: 'u',
      picUrl: 'p',
      desc: 'd',
    );
    final reused = await runner.runDetail(bare, card);
    expect(reused.hasDetail, isTrue);
    expect(reused.playUrl, 'u');
    expect(fetched, 0);

    final httpsCard = const MiniAppCard(title: '', url: 'https://x/v');
    final framed = await runner.runDetail(bare, httpsCard);
    expect(framed.frameUrl, 'https://x/v');

    final emptyCard = const MiniAppCard(title: '', url: 'hiker://empty');
    final none = await runner.runDetail(bare, emptyCard);
    expect(none.hasDetail, isFalse);

    final proxyRule = _rule(<String, dynamic>{'proxy': 'proxy-cfg'});
    final proxied = await runner.runDetail(proxyRule, card);
    expect(proxied.proxy, 'proxy-cfg');
  });

  test('detail js rule with episodes', () async {
    final bridge = await _openBridge();
    final runner = RuleRunner(
      bridge: bridge,
      fetcher: (url, headers) async => '<html>detail</html>',
    );
    final rule = _rule(<String, dynamic>{
      'detail_find_rule':
          'js: setResult({title: "dt", pic_url: "dp", desc: "dd", episodes: ["e1", "e2"]});',
      'detail_col_type': 'movie_1',
    });
    final card = const MiniAppCard(title: 't', url: 'http://x/d/1');
    final detail = await runner.runDetail(rule, card);
    expect(detail.title, 'dt');
    expect(detail.episodes, ['e1', 'e2']);
    expect(detail.colType, 'movie_1');
  });

  test('sdetail star falls through to card reuse without fetch', () async {
    final bridge = await _openBridge();
    var fetched = 0;
    final runner = RuleRunner(
      bridge: bridge,
      fetcher: (url, headers) async {
        fetched++;
        return '<html></html>';
      },
    );
    final rule = _rule(<String, dynamic>{'sdetail_find_rule': '*'});
    final card = const MiniAppCard(
      title: 't',
      url: 'http://x/d/1',
      picUrl: 'p',
      desc: 'd',
    );
    final detail = await runner.runDetail(rule, card);
    expect(detail.title, 't');
    expect(fetched, 0);
  });

  test('searchable filter and chapter rule', () async {
    final bridge = await _openBridge();
    final runner = RuleRunner(
      bridge: bridge,
      fetcher: (url, headers) async => '<html></html>',
    );
    final withSearch = _rule(<String, dynamic>{
      'searchFind': 'js: setResult([]);',
      'search_url': 'http://x/s?keyword',
    });
    final withoutSearch = _rule(<String, dynamic>{});
    expect(
      RuleRunner.searchableRules([withSearch, withoutSearch]),
      [withSearch],
    );
    final chapterRule = _rule(<String, dynamic>{
      'last_chapter_rule':
          'js: setResult([{title: "c1", url: "cu1"}, {title: "c2", url: "cu2"}]);',
    });
    final card = const MiniAppCard(title: 't', url: 'http://x/book/1');
    final detail = await runner.runDetail(chapterRule, card);
    expect(detail.chapters.length, 2);
    expect(detail.chapters[0].title, 'c1');
    expect(detail.chapters[1].url, 'cu2');
  });

  test('subpage parsing and run', () async {
    final bridge = await _openBridge();
    final runner = RuleRunner(
      bridge: bridge,
      fetcher: (url, headers) async => '<html></html>',
    );
    final rule = _rule(<String, dynamic>{
      'pages':
          '[{"name": "sub", "path": "/sub", "rule": "js: setResult([{title: \\"st\\", url: \\"su\\"}]);", "col_type": "movie_2"}]',
    });
    expect(rule.subPages.length, 1);
    expect(rule.subPages[0].name, 'sub');
    final cards = await runner.runSubPage(
      rule,
      rule.subPages[0],
      host: 'http://x',
    );
    expect(cards.length, 1);
    expect(cards[0].title, 'st');
    expect(cards[0].colType, 'movie_2');
  });
}
