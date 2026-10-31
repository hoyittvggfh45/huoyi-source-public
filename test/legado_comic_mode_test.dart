import 'package:duanju_app/legado_builtin_data.dart';
import 'package:duanju_app/legado_screen.dart';
import 'package:duanju_app/legado_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

class _LegadoImageRepository extends FixtureRepository {
  @override
  Future<dynamic> legadoRun(
    String sourceJson,
    String action,
    String input,
  ) async {
    switch (action) {
      case 'check':
        return {'supported': true};
      case 'search':
        return [
          {'title': '合成漫画', 'author': '', 'url': 'b1'},
        ];
      case 'toc':
        return [
          {'title': '第1话', 'url': 'c1'},
        ];
      case 'content':
        return {
          'content': '',
          'images': [
            {'url': 'https://example.test/p1.jpg'},
            {'url': 'https://example.test/p2.jpg'},
          ],
        };
      default:
        return [];
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('comic filter is type 2 only and holds the seven added rules', () {
    final sources = parseLegadoSources(builtinLegadoRulesJson);
    final comics = sources.where((s) => s.type == '2').toList();
    final novels = sources.where((s) => s.type == '0').toList();
    expect(sources, hasLength(216));
    expect(comics, hasLength(210));
    expect(novels, hasLength(6));
    expect(
      comics.map((s) => s.name).toSet(),
      containsAll([
        '啵乐屋🔞',
        '🔞 夜色韩漫',
        'XiuRenBox 秀人网写真',
        '美人图 写真美图',
        'MMRGB 魅色MM',
        '漫小肆韓漫',
        '4KHD 高清写真',
      ]),
    );
    expect(comics.any((s) => s.type == '0'), isFalse);
    expect(novels.any((s) => s.type == '2'), isFalse);
    for (final name in [
      '啵乐屋🔞',
      '🔞 夜色韩漫',
      'XiuRenBox 秀人网写真',
      '美人图 写真美图',
      'MMRGB 魅色MM',
      '漫小肆韓漫',
      '4KHD 高清写真',
    ]) {
      final found = comics.where((s) => s.name == name).toList();
      expect(found, hasLength(1));
      expect(found.first.searchUrl.isNotEmpty, isTrue);
    }
  });

  testWidgets('comic mode starts on comic rules only', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LegadoScreen(
            repository: FixtureRepository(),
            initialComic: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final comicChip = find.byWidgetPredicate(
      (widget) =>
          widget is ChoiceChip &&
          widget.label is Text &&
          (widget.label as Text).data == '漫画' &&
          widget.selected,
    );
    expect(comicChip, findsOneWidget);
    expect(find.text('稻草人书屋'), findsWidgets);
    expect(find.text('猫果'), findsNothing);
    expect(find.text('全部书源'), findsOneWidget);
  });

  testWidgets('default mode still starts on novel rules only', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LegadoScreen(repository: FixtureRepository())),
      ),
    );
    await tester.pumpAndSettle();
    final novelChip = find.byWidgetPredicate(
      (widget) =>
          widget is ChoiceChip &&
          widget.label is Text &&
          (widget.label as Text).data == '小说' &&
          widget.selected,
    );
    expect(novelChip, findsOneWidget);
    expect(find.text('顶果'), findsWidgets);
    expect(find.text('稻草人书屋'), findsNothing);
  });

  testWidgets('comic mode switches to all sources and back', (tester) async {    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LegadoScreen(
            repository: FixtureRepository(),
            initialComic: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部书源'));
    await tester.pumpAndSettle();
    final allChip = find.byWidgetPredicate(
      (widget) =>
          widget is ChoiceChip &&
          widget.label is Text &&
          (widget.label as Text).data == '全部书源' &&
          widget.selected,
    );
    expect(allChip, findsOneWidget);
    await tester.tap(find.text('漫画'));
    await tester.pumpAndSettle();
    expect(find.text('猫果'), findsNothing);
    expect(find.text('稻草人书屋'), findsWidgets);
  });

  testWidgets('legado comic chapter renders synthetic image pages', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LegadoScreen(
            repository: _LegadoImageRepository(),
            initialComic: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '合成');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('合成漫画'), findsOneWidget);
    await tester.tap(find.text('合成漫画'));
    await tester.pumpAndSettle();
    expect(find.text('第1话'), findsOneWidget);
    await tester.tap(find.text('第1话'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 2 张'), findsOneWidget);
  });
}
