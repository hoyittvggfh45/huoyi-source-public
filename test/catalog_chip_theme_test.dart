import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duanju_app/catalog_filters.dart';
import 'package:duanju_app/models.dart';

void main() {
  const container = Color(0xFF123456);
  const selected = Color(0xFFC8E6C9);
  ThemeData theme() => ThemeData(
    colorScheme: const ColorScheme.light(surfaceContainerHighest: container),
  );

  testWidgets('catalog chips use theme container color, not white', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme(),
        home: Scaffold(
          body: CatalogFilterRows(
            groups: const [
              CatalogFilterGroup('tag', '标签', [
                CatalogFilterOption('daily', '日常'),
              ]),
            ],
            selected: const {'tag': ''},
            onSelected: (_, _) {},
          ),
        ),
      ),
    );
    final all = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '全部'),
    );
    final daily = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '日常'),
    );
    expect(all.selected, isTrue);
    expect(all.selectedColor, selected);
    expect(all.selectedColor, isNot(Colors.white));
    expect(all.labelStyle?.color, theme().colorScheme.onSurface);
    expect(all.labelStyle?.color, isNot(Colors.white));
    expect(daily.backgroundColor, container);
    expect(daily.backgroundColor, isNot(Colors.white));
    expect(daily.backgroundColor, isNot(daily.selectedColor));
    expect(daily.labelStyle?.fontSize, 12);
  });

  testWidgets('category chips use theme container color, not white', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme(),
        home: Scaffold(
          body: CatalogFilters(
            categories: const [
              CatalogCategory('', '全部'),
              CatalogCategory('real', '真人剧'),
            ],
            category: '',
            onCategory: (_) {},
            onRetry: () {},
          ),
        ),
      ),
    );
    final other = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '真人剧'),
    );
    expect(other.backgroundColor, container);
    expect(other.backgroundColor, isNot(Colors.white));
    expect(other.selectedColor, selected);
    expect(other.selectedColor, isNot(other.backgroundColor));
    expect(other.labelStyle?.fontSize, 12);
  });
}
