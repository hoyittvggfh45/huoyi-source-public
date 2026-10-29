import 'package:duanju_app/models.dart';
import 'package:duanju_app/rfw_theme/rfw_theme_data.dart';
import 'package:duanju_app/rfw_theme/rfw_theme_events.dart';
import 'package:duanju_app/rfw_theme/rfw_theme_host.dart';
import 'package:duanju_app/rfw_theme/rfw_theme_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const hostTheme = '''
import core.widgets;
import peek.home;

widget root = PeekStickyGrid(
  heroHeight: 0.0,
  pinnedHeight: 40.0,
  sectionHeight: 0.0,
  crossAxisCount: 1,
  childAspectRatio: 2.0,
  horizontalPadding: 12.0,
  bottomPadding: 24.0,
  pinnedHeader: Container(
    color: 0xFFFAF6EE,
    child: Text(text: "theme header"),
  ),
  children: [
    GestureDetector(
      onTap: event "openItem" { index: 0 },
      child: Text(text: "first item"),
    ),
    PeekCarousel(
      height: 120.0,
      autoPlay: false,
      interval: 6.0,
      showIndicators: false,
      children: [
        Text(text: "slide one"),
      ],
    ),
  ],
);
''';

Map<String, Object?> hostData() {
  return buildRfwHomeData(
    const RfwHomeDataInput(
      categories: [CatalogCategory('', '全部')],
      category: '',
      items: [Drama(id: 'd1', source: 'hongguo', title: '第一部')],
      recommend: [],
      filters: [],
      selectedFilters: {},
    ),
  );
}

void main() {
  testWidgets('host renders theme and forwards tap events', (tester) async {
    final actions = <RfwThemeAction>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RfwThemeHost(
            themeText: hostTheme,
            homeData: hostData(),
            onAction: actions.add,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('theme header'), findsOneWidget);
    expect(find.text('first item'), findsOneWidget);
    await tester.tap(find.text('first item'));
    await tester.pump();
    expect(actions.length, 1);
    expect(actions.first.kind, RfwThemeActionKind.openItem);
    expect(actions.first.index, 0);
  });

  testWidgets('host shows an error instead of a broken theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RfwThemeHost(
            themeText: 'import core.widgets;\nwidget root = ',
            homeData: hostData(),
            onAction: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('first item'), findsNothing);
    expect(find.text('theme header'), findsNothing);
  });

  testWidgets('built-in theme assets parse and validate', (tester) async {
    for (final entry in builtinRfwThemes) {
      final asset = entry.asset;
      expect(asset, isNotNull);
      final text = await rootBundle.loadString(asset!);
      final result = validateRfwThemeText(text);
      expect(result.ok, true, reason: '${entry.id}: ${result.reason}');
      expect(text, isNot(contains('127.0.0.1')));
    }
  });
}
