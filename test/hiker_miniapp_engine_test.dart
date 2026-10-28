import 'dart:convert';

import 'package:duanju_app/hiker_miniapp/hiker_miniapp_engine.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_rule.dart';
import 'package:flutter_test/flutter_test.dart';

HikerMiniappRule _rule({
  String findRule = 'js: setResult([]);',
  String searchFind = 'js: setResult([]);',
  String detailFindRule = 'js: setResult([]);',
  String className = '最新&热门',
  String classUrl = '/latest/fypage&/hot/fypage',
}) {
  return HikerMiniappRule.fromJson({
    'title': '桩规则',
    'type': '2',
    'url': 'https://example.invalid',
    'col_type': 'movie_3',
    'class_name': className,
    'class_url': classUrl,
    'find_rule': findRule,
    'searchFind': searchFind,
    'search_url': 'hiker://empty',
    'detail_col_type': 'movie_1_vertical_pic_blur',
    'detail_find_rule': detailFindRule,
    'ua': '',
    'preRule': '',
  });
}

List<Map<String, dynamic>> _detailItems() {
  return [
    {
      'title': '测试剧名',
      'col_type': 'movie_1_vertical_pic_blur',
      'url': 'https://example.invalid/detail/1',
      'pic_url': 'https://example.invalid/poster.jpg',
      'actor': '演员甲',
    },
    {'title': '剧情简介', 'col_type': 'text_1', 'desc': '这是一段简介正文。'},
    {'title': '标签：剧情·爱情', 'col_type': 'text_1'},
    {
      'title': '播放线路：在线播放',
      'col_type': 'text_center_1',
      'extra': {'lineVisible': false},
    },
    {
      'title': '第1集',
      'col_type': 'text_1',
      'url': 'https://example.invalid/play/1.m3u8',
    },
    {
      'title': '第2集',
      'col_type': 'text_1',
      'url': 'https://example.invalid/play/2.m3u8',
    },
    {
      'title': '第3集',
      'col_type': 'text_1',
      'url': 'hiker://empty',
      'desc': '需 py 源（正片）',
    },
    {
      'title': '本片剧照',
      'col_type': 'text_center_1',
      'extra': {'lineVisible': false},
    },
    {
      'title': '剧照1',
      'col_type': 'pic_1',
      'pic_url': 'https://example.invalid/still1.jpg',
      'url': 'hiker://empty',
    },
    {
      'title': '剧照2',
      'col_type': 'pic_1',
      'pic_url': 'https://example.invalid/still2.jpg',
      'url': 'hiker://empty',
    },
  ];
}

void main() {
  test('home maps list results to cards with key aliases', () async {
    final calls = <List<String>>[];
    final engine = HikerMiniappEngine(
      rule: _rule(),
      run: (ruleJson, action, input) async {
        calls.add([action, input]);
        return [
          {
            'title': '卡一',
            'href': 'https://example.invalid/1',
            'img': 'https://example.invalid/1.jpg',
            'note': '共 10 集',
            'category': '真人剧',
          },
        ];
      },
    );
    final home = await engine.home();
    expect(home.cards.length, 1);
    expect(home.cards.first.title, '卡一');
    expect(home.cards.first.url, 'https://example.invalid/1');
    expect(home.cards.first.pic, 'https://example.invalid/1.jpg');
    expect(home.cards.first.desc, '共 10 集');
    expect(home.cards.first.tag, '真人剧');
    expect(home.navs, isEmpty);
    expect(calls.first[0], 'list');
    expect(calls.first[1], 'https://example.invalid/latest/1');
  });

  test('home resolves root relative card links against rule url', () async {
    final engine = HikerMiniappEngine(
      rule: _rule(),
      run: (ruleJson, action, input) async {
        return [
          {'title': '相对卡', 'href': '/detail/9', 'img': '/covers/9.jpg'},
        ];
      },
    );
    final home = await engine.home();
    expect(home.cards.first.url, 'https://example.invalid/detail/9');
    expect(home.cards.first.pic, 'https://example.invalid/covers/9.jpg');
  });

  test('home second category and page substitute into the input url', () async {
    String? seen;
    final engine = HikerMiniappEngine(
      rule: _rule(),
      run: (ruleJson, action, input) async {
        seen = input;
        return [];
      },
    );
    await engine.home(categoryIndex: 1, page: 4);
    expect(seen, 'https://example.invalid/hot/4');
  });

  test('home normalizes map data lists and raw json strings', () async {
    final mapEngine = HikerMiniappEngine(
      rule: _rule(),
      run: (ruleJson, action, input) async {
        return {
          'data': [
            {'title': '卡A', 'url': 'https://example.invalid/a'},
          ],
        };
      },
    );
    expect((await mapEngine.home()).cards.first.title, '卡A');
    final stringEngine = HikerMiniappEngine(
      rule: _rule(),
      run: (ruleJson, action, input) async {
        return jsonEncode([
          {'title': '卡B', 'url': 'https://example.invalid/b'},
        ]);
      },
    );
    expect((await stringEngine.home()).cards.first.title, '卡B');
  });

  test('search passes the keyword through as input', () async {
    String? seenAction;
    String? seenInput;
    final engine = HikerMiniappEngine(
      rule: _rule(),
      run: (ruleJson, action, input) async {
        seenAction = action;
        seenInput = input;
        return [
          {'title': '搜到卡', 'url': 'https://example.invalid/s'},
        ];
      },
    );
    final cards = await engine.search('测试关键词');
    expect(seenAction, 'search');
    expect(seenInput, '测试关键词');
    expect(cards.first.title, '搜到卡');
  });

  test(
    'detail maps fongmitv items to header, synopsis, lines and stills',
    () async {
      final engine = HikerMiniappEngine(
        rule: _rule(),
        run: (ruleJson, action, input) async => _detailItems(),
      );
      final detail = await engine.detail('https://example.invalid/detail/1');
      expect(detail.title, '测试剧名');
      expect(detail.poster, 'https://example.invalid/poster.jpg');
      expect(detail.actress, '演员甲');
      expect(detail.synopsis, '这是一段简介正文。');
      expect(detail.tags, ['剧情', '爱情']);
      expect(detail.lines.length, 1);
      expect(detail.lines.first.name, '在线播放');
      expect(detail.lines.first.episodes.length, 2);
      expect(detail.lines.first.episodes[0].title, '第1集');
      expect(detail.lines.first.episodes[0].playable, isTrue);
      expect(detail.unavailable.length, 1);
      expect(detail.unavailable.first.title, '第3集');
      expect(detail.unavailable.first.playable, isFalse);
      expect(detail.stills.length, 2);
      expect(detail.stills.first, 'https://example.invalid/still1.jpg');
    },
  );

  test('detail resolves relative episode links into playable lines', () async {
    final engine = HikerMiniappEngine(
      rule: _rule(),
      run: (ruleJson, action, input) async {
        return [
          {
            'title': '相对剧',
            'col_type': 'movie_1_vertical_pic_blur',
            'url': 'https://example.invalid/detail/1',
            'pic_url': '/poster.jpg',
          },
          {'title': '播放线路：在线播放', 'col_type': 'text_center_1'},
          {'title': '第1集', 'col_type': 'text_1', 'url': '/play/1.m3u8'},
          {
            'title': '第2集',
            'col_type': 'text_1',
            'url': 'https://example.invalid/play/2.m3u8',
          },
          {
            'title': '剧照',
            'col_type': 'pic_1',
            'pic_url': '/still.jpg',
            'url': 'hiker://empty',
          },
        ];
      },
    );
    final detail = await engine.detail('/detail/1');
    expect(detail.poster, 'https://example.invalid/poster.jpg');
    expect(detail.lines.length, 1);
    expect(detail.lines.first.episodes.length, 2);
    expect(
      detail.lines.first.episodes.first.url,
      'https://example.invalid/play/1.m3u8',
    );
    expect(detail.unavailable, isEmpty);
    expect(detail.stills, ['https://example.invalid/still.jpg']);
  });

  test('resolvePlayUrl returns raw url without last chapter rule', () async {
    final engine = HikerMiniappEngine(
      rule: _rule(),
      run: (ruleJson, action, input) async => 'https://example.invalid/x',
    );
    expect(
      await engine.resolvePlayUrl('https://example.invalid/play/1'),
      'https://example.invalid/play/1',
    );
  });

  test(
    'resolvePlayUrl uses engine play result and falls back on error',
    () async {
      final lazyRule = HikerMiniappRule.fromJson({
        'title': '懒规则',
        'type': '2',
        'url': 'https://example.invalid',
        'col_type': 'movie_3',
        'find_rule': 'js: setResult([]);',
        'searchFind': 'js: setResult([]);',
        'detail_find_rule': 'js: setResult([]);',
        'last_chapter_rule':
            'js: setResult("https://example.invalid/real.m3u8");',
      });
      var calls = 0;
      final okEngine = HikerMiniappEngine(
        rule: lazyRule,
        run: (ruleJson, action, input) async {
          calls++;
          expect(action, 'play');
          expect(input, 'https://example.invalid/play/1');
          final decoded = jsonDecode(ruleJson) as Map<String, dynamic>;
          expect(decoded['last_chapter_rule'], contains('setResult'));
          return 'https://example.invalid/real.m3u8';
        },
      );
      expect(
        await okEngine.resolvePlayUrl('https://example.invalid/play/1'),
        'https://example.invalid/real.m3u8',
      );
      expect(calls, 1);
      final failingEngine = HikerMiniappEngine(
        rule: lazyRule,
        run: (ruleJson, action, input) async {
          throw StateError('engine down');
        },
      );
      expect(
        await failingEngine.resolvePlayUrl('https://example.invalid/play/1'),
        'https://example.invalid/play/1',
      );
    },
  );

  test('detail accepts map shaped results with episodes and stills', () async {
    final engine = HikerMiniappEngine(
      rule: _rule(),
      run: (ruleJson, action, input) async {
        return {
          'title': '单对象剧',
          'pic_url': 'https://example.invalid/p.jpg',
          'actor': '演员乙',
          'desc': '单对象简介',
          'episodes': [
            {'title': '第1集', 'url': 'https://example.invalid/e1'},
          ],
          'stills': ['https://example.invalid/s1.jpg'],
        };
      },
    );
    final detail = await engine.detail('https://example.invalid/d');
    expect(detail.title, '单对象剧');
    expect(detail.poster, 'https://example.invalid/p.jpg');
    expect(detail.lines.first.episodes.first.title, '第1集');
    expect(detail.stills, ['https://example.invalid/s1.jpg']);
  });

  test('empty find, search and detail scripts throw failure', () async {
    final engine = HikerMiniappEngine(
      rule: _rule(findRule: '', searchFind: '', detailFindRule: ''),
      run: (ruleJson, action, input) async => [],
    );
    expect(engine.home(), throwsA(isA<HikerMiniappFailure>()));
    expect(engine.search('x'), throwsA(isA<HikerMiniappFailure>()));
    expect(engine.detail('x'), throwsA(isA<HikerMiniappFailure>()));
  });

  test('run function errors are wrapped as failures', () async {
    final engine = HikerMiniappEngine(
      rule: _rule(),
      run: (ruleJson, action, input) async {
        throw StateError('go engine down');
      },
    );
    expect(engine.home(), throwsA(isA<HikerMiniappFailure>()));
  });
}
