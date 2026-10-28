import 'package:duanju_app/source_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const groups = [
    SourcePickerGroup(
      title: '',
      entries: [SourcePickerEntry(id: 'all', name: '全部站源')],
    ),
    SourcePickerGroup(
      title: '分组A',
      entries: [
        SourcePickerEntry(id: 'a', name: '站A'),
        SourcePickerEntry(id: 'b', name: '站B'),
      ],
    ),
  ];

  testWidgets('centered picker returns the tapped site', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showCenteredSourcePickerDialog(
                  context,
                  sectionName: '短剧',
                  currentName: '站A',
                  currentId: 'a',
                  groups: groups,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('centered-source-picker')),
      findsOneWidget,
    );
    expect(find.text('切换短剧源'), findsOneWidget);
    expect(find.text('当前：站A'), findsOneWidget);
    expect(find.text('分组A（2）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('centered-source-b')));
    await tester.pumpAndSettle();
    expect(picked, 'b');
    expect(find.byKey(const ValueKey('centered-source-picker')), findsNothing);
  });

  testWidgets('centered picker close returns null', (tester) async {
    String? picked = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showCenteredSourcePickerDialog(
                  context,
                  sectionName: '点播',
                  currentName: '站A',
                  currentId: 'a',
                  groups: groups,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('centered-source-close')));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
