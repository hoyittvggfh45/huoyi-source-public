import 'dart:convert';

import 'package:duanju_app/hiker_miniapp/hiker_category_shell.dart';
import 'package:duanju_app/hiker_rule.dart';
import 'package:duanju_app/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _ruleJson() => jsonEncode({
  'title': '剪切板规则',
  'type': '2',
  'url': 'https://example.invalid',
  'col_type': 'movie_3',
  'find_rule': 'x',
});

Future<dynamic> _stubRun(String ruleJson, String action, String input) async {
  return [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String? clipboardText;

  setUp(() async {
    clipboardText = null;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            final text = clipboardText;
            if (text == null) return null;
            return {'text': text};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HikerCategoryShell(
          store: store,
          hikerRun: _stubRun,
          hikerRules: const [],
          initialTab: HikerMiniappTab.hiker,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntilMessage(WidgetTester tester, String needle) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining(needle).evaluate().isNotEmpty) return;
    }
  }

  testWidgets('shell prompts clipboard rule text and imports on confirm', (
    tester,
  ) async {
    clipboardText = _ruleJson();
    await pumpShell(tester);
    expect(find.text('剪贴板检测到小程序规则，是否立即导入？'), findsOneWidget);
    await tester.tap(find.text('立即导入'));
    await pumpUntilMessage(tester, '导入 1 条规则');
    expect(find.textContaining('导入 1 条规则'), findsOneWidget);
    expect(find.text('剪切板规则'), findsOneWidget);
    final stored = await HikerStore.load();
    expect(stored.length, 1);
    expect(stored.first.title, '剪切板规则');
  });

  testWidgets('shell shows no dialog for irrelevant clipboard text', (
    tester,
  ) async {
    clipboardText = '今天天气不错，晚上去散步';
    await pumpShell(tester);
    expect(find.text('温馨提示'), findsNothing);
    expect(find.text('暂无海阔规则'), findsOneWidget);
  });

  testWidgets(
    'shell skips second prompt for same content but manual still prompts',
    (tester) async {
      clipboardText = _ruleJson();
      await pumpShell(tester);
      expect(find.text('温馨提示'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('温馨提示'), findsNothing);
      await pumpShell(tester);
      expect(find.text('温馨提示'), findsNothing);
      await tester.tap(find.text('检测剪贴板'));
      await tester.pumpAndSettle();
      expect(find.text('温馨提示'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('shell shows cloud code hint without import action', (
    tester,
  ) async {
    clipboardText = '云abc123/xyz789';
    await pumpShell(tester);
    expect(find.text('检测到云口令，暂不支持导入它家云口令'), findsOneWidget);
    expect(find.text('立即导入'), findsNothing);
    expect(find.text('关闭'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(await HikerStore.load(), isEmpty);
  });
}
