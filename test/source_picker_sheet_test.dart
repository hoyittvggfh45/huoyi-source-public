import 'package:duanju_app/source_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _groups = [
  SourcePickerGroup(
    title: '内置影视',
    entries: [
      SourcePickerEntry(id: 'a', name: 'A站'),
      SourcePickerEntry(id: 'b', name: 'B站'),
    ],
  ),
  SourcePickerGroup(
    title: '导入',
    entries: [SourcePickerEntry(id: 'c', name: 'C站')],
  ),
];

Widget _host(void Function(String?) onResult) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async {
            final picked = await showSourcePickerSheet(
              context,
              sectionName: '影视',
              currentName: 'B站',
              currentId: 'b',
              groups: _groups,
            );
            onResult(picked);
          },
          child: const Text('打开'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('渲染分组与副提示，当前源高亮', (tester) async {
    await tester.pumpWidget(_host((_) {}));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('切换影视源'), findsOneWidget);
    expect(find.text('当前：B站'), findsOneWidget);
    expect(find.text('点击站源立即切换'), findsOneWidget);
    expect(find.text('内置影视'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    expect(find.text('A站'), findsOneWidget);
    expect(find.text('C站'), findsNothing);

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(find.text('C站'), findsOneWidget);

    final current = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'B站'),
    );
    expect(current.selected, isTrue);
    final other = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'A站'),
    );
    expect(other.selected, isFalse);
  });

  testWidgets('点选源立即关闭弹窗并回调所选 id', (tester) async {
    String? result;
    var completed = false;
    await tester.pumpWidget(
      _host((picked) {
        result = picked;
        completed = true;
      }),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('C站'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, 'c');
    expect(find.text('切换影视源'), findsNothing);
  });

  testWidgets('关闭按钮不回调选择', (tester) async {
    String? result = 'unset';
    var completed = false;
    await tester.pumpWidget(
      _host((picked) {
        result = picked;
        completed = true;
      }),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('source-picker-close')));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, isNull);
    expect(find.text('切换影视源'), findsNothing);
  });

  testWidgets('搜索过滤站源，无匹配给提示', (tester) async {
    await tester.pumpWidget(_host((_) {}));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('source-picker-search')),
      'C站',
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'C站'), findsOneWidget);
    expect(find.text('A站'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('source-picker-search')),
      'ZZZ',
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的站源'), findsOneWidget);
  });
}
