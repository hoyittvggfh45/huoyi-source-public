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

Future<dynamic> _stubRun(String ruleJson, String action, String input) async {
  if (action == 'detail') {
    return [
      {
        'title': '详情剧名',
        'col_type': 'movie_1_vertical_pic_blur',
        'url': 'https://example.invalid/detail/1',
        'pic_url': '',
        'actor': '演员甲',
      },
      {'title': '剧情简介', 'col_type': 'text_1', 'desc': '简介正文。'},
      {'title': '播放线路：在线播放', 'col_type': 'text_center_1'},
      {
        'title': '第1集',
        'col_type': 'text_1',
        'url': 'https://example.invalid/play/1.m3u8',
      },
      {'title': '第3集', 'col_type': 'text_1', 'url': 'hiker://empty'},
    ];
  }
  return [];
}

void main() {
  testWidgets('detail shows line buttons and footprint bar', (tester) async {
    final played = <List<Object>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HikerMiniappDetailScreen(
          engine: HikerMiniappEngine(rule: _rule(), run: _stubRun),
          card: const HikerMiniappCard(
            title: '详情剧名',
            url: 'https://example.invalid/detail/1',
            pic: '',
            desc: '',
            tag: '',
          ),
          onPlay: (title, episodes, index) {
            played.add([title, episodes, index]);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('播放地址'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '在线播放'), findsOneWidget);
    expect(find.text('▶ 在线播放 · 第1集'), findsNothing);
    await tester.tap(find.text('第1集'));
    await tester.pumpAndSettle();
    expect(played.length, 1);
    expect(played.first[2], 0);
    expect(find.text('▶ 在线播放 · 第1集'), findsOneWidget);
    await tester.tap(find.text('▶ 在线播放 · 第1集'));
    await tester.pumpAndSettle();
    expect(played.length, 2);
    expect(played.last[2], 0);
    await tester.tap(find.widgetWithText(FilledButton, '在线播放'));
    await tester.pumpAndSettle();
    expect(played.length, 3);
    expect(played.last[2], 0);
  });
}
