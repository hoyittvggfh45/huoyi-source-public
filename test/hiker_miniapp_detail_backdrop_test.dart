import 'package:duanju_app/hiker_miniapp/hiker_miniapp_detail.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_engine.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_models.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_rule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HikerMiniappRule _rule() {
  return HikerMiniappRule.fromJson({
    'title': '桩规则',
    'type': '2',
    'url': 'https://example.invalid',
    'col_type': 'movie_3',
    'class_name': '分类A',
    'class_url': '/a/fypage',
    'find_rule': 'js: setResult([]);',
    'searchFind': 'js: setResult([]);',
    'search_url': 'hiker://empty',
    'detail_col_type': 'movie_1_vertical_pic_blur',
    'detail_find_rule': 'js: setResult([]);',
    'ua': '',
    'preRule': '',
  });
}

HikerRunFn _stubRun(
  bool withStill, {
  String poster = 'https://example.invalid/poster.jpg',
}) {
  return (String ruleJson, String action, String input) async {
    if (action == 'detail') {
      return [
        {
          'title': '详情剧名',
          'col_type': 'movie_1_vertical_pic_blur',
          'url': 'https://example.invalid/detail/1',
          'pic_url': poster,
          'actor': '演员甲',
        },
        {'title': '剧情简介', 'col_type': 'text_1', 'desc': '简介正文。'},
        {'title': '播放线路：在线播放', 'col_type': 'text_center_1'},
        {
          'title': '第1集',
          'col_type': 'text_1',
          'url': 'https://example.invalid/play/1.m3u8',
        },
        if (withStill)
          {
            'title': '',
            'col_type': 'pic_1',
            'pic_url': 'https://example.invalid/still1.jpg',
          },
      ];
    }
    return [];
  };
}

Future<void> _pumpDetail(
  WidgetTester tester,
  bool withStill, {
  String poster = 'https://example.invalid/poster.jpg',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: HikerMiniappDetailScreen(
        engine: HikerMiniappEngine(
          rule: _rule(),
          run: _stubRun(withStill, poster: poster),
        ),
        card: const HikerMiniappCard(
          title: '详情剧名',
          url: 'https://example.invalid/detail/1',
          pic: '',
          desc: '',
          tag: '',
        ),
        onPlay: (title, episodes, index) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('detail shows full-page backdrop from stills', (tester) async {
    await _pumpDetail(tester, true);
    expect(find.byKey(const ValueKey('hiker-detail-backdrop')), findsOneWidget);
    expect(find.text('详情剧名'), findsWidgets);
    expect(find.text('本片剧照'), findsOneWidget);
  });

  testWidgets('detail falls back to poster backdrop without stills', (
    tester,
  ) async {
    await _pumpDetail(tester, false);
    expect(find.byKey(const ValueKey('hiker-detail-backdrop')), findsOneWidget);
    expect(find.text('详情剧名'), findsWidgets);
    expect(find.text('本片剧照'), findsNothing);
  });

  testWidgets('detail shows poster image in header', (tester) async {
    await _pumpDetail(tester, true);
    expect(find.byKey(const ValueKey('hiker-detail-poster')), findsOneWidget);
  });

  testWidgets('detail falls back to first still as poster', (tester) async {
    await _pumpDetail(tester, true, poster: '');
    expect(find.byKey(const ValueKey('hiker-detail-poster')), findsOneWidget);
    expect(find.text('本片剧照'), findsOneWidget);
  });

  testWidgets('detail shows no poster element without poster or stills', (
    tester,
  ) async {
    await _pumpDetail(tester, false, poster: '');
    expect(find.byKey(const ValueKey('hiker-detail-poster')), findsNothing);
  });
}
