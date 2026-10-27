import 'package:duanju_app/hiker_miniapp/hiker_category_shell.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_engine.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_home.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_rule.dart';
import 'package:duanju_app/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

HikerMiniappRule _rule() {
  return HikerMiniappRule.fromJson({
    'title': '桩规则',
    'type': '2',
    'url': 'https://example.invalid',
    'col_type': 'movie_3',
    'class_name': '分类A&分类B',
    'class_url': '/a/fypage&/b/fypage',
    'find_rule': 'js: setResult([]);',
    'searchFind': 'js: setResult([]);',
    'search_url': 'hiker://empty',
    'detail_col_type': 'movie_1_vertical_pic_blur',
    'detail_find_rule': 'js: setResult([]);',
    'ua': '',
    'preRule': '',
  });
}

Future<dynamic> _stubRun(
  List<List<String>> calls,
  String ruleJson,
  String action,
  String input,
) async {
  calls.add([action, input]);
  if (action == 'list') {
    return [
      {'title': '列表卡一', 'url': 'https://example.invalid/1'},
      {'title': '列表卡二', 'url': 'https://example.invalid/2'},
    ];
  }
  if (action == 'search') {
    return [
      {'title': '搜索卡', 'url': 'https://example.invalid/s'},
    ];
  }
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
      {'title': '本片剧照', 'col_type': 'text_center_1'},
      {
        'title': '剧照1',
        'col_type': 'pic_1',
        'pic_url': 'https://example.invalid/still1.jpg',
        'url': 'hiker://empty',
      },
    ];
  }
  return [];
}

void main() {
  testWidgets(
    'home renders cards, switches category, searches and opens detail',
    (tester) async {
      final calls = <List<String>>[];
      final played = <List<Object>>[];
      final engine = HikerMiniappEngine(
        rule: _rule(),
        run: (ruleJson, action, input) =>
            _stubRun(calls, ruleJson, action, input),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HikerMiniappHomeScreen(
            engine: engine,
            onPlay: (title, episodes, index) {
              played.add([title, episodes, index]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('列表卡一'), findsOneWidget);
      expect(find.text('列表卡二'), findsOneWidget);

      await tester.tap(find.text('分类B'));
      await tester.pumpAndSettle();
      expect(calls.last, ['list', '/b/1']);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '关键词');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('搜索卡'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('列表卡一'), findsOneWidget);

      await tester.tap(find.text('列表卡一'));
      await tester.pumpAndSettle();
      expect(find.text('详情剧名'), findsOneWidget);
      expect(find.text('剧情简介'), findsOneWidget);
      expect(find.text('简介正文。'), findsOneWidget);
      expect(find.text('播放线路：在线播放'), findsOneWidget);
      expect(find.text('本片剧照'), findsOneWidget);
      expect(find.text('演员甲'), findsOneWidget);

      await tester.tap(find.text('第1集'));
      await tester.pumpAndSettle();
      expect(played.length, 1);
      expect(played.first[0], '详情剧名');
      expect(played.first[2], 0);

      await tester.tap(find.text('第3集'));
      await tester.pumpAndSettle();
      expect(played.length, 1);
    },
  );

  testWidgets('shell shows hiker tab rules and empty state without ant tab', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore(prefs);
    final calls = <List<String>>[];
    Future<dynamic> engineRun(String ruleJson, String action, String input) {
      return _stubRun(calls, ruleJson, action, input);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: HikerCategoryShell(
          store: store,
          hikerRun: engineRun,
          hikerRules: [_rule()],
          initialTab: HikerMiniappTab.hiker,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('蚂蚁'), findsOneWidget);
    expect(find.text('海阔'), findsOneWidget);
    expect(find.text('桩规则'), findsOneWidget);

    await tester.tap(find.text('桩规则'));
    await tester.pumpAndSettle();
    expect(find.text('列表卡一'), findsOneWidget);
  });

  testWidgets('shell shows empty placeholder when no hiker rules exist', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore(prefs);
    await tester.pumpWidget(
      MaterialApp(
        home: HikerCategoryShell(
          store: store,
          hikerRun: (ruleJson, action, input) async => [],
          hikerRules: const [],
          initialTab: HikerMiniappTab.hiker,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无海阔规则'), findsOneWidget);
  });
}
