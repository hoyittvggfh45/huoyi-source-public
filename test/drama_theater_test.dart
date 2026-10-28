import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/drama_style_home.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/widgets.dart';

class _FakeRepository implements AppRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('theater meta line prefers heat, then views, then null', () {
    expect(
      theaterMetaLine(
        const Drama(id: 'a', source: 's', title: 'A', heat: '4439万热度'),
      ),
      '4439万热度',
    );
    expect(
      theaterMetaLine(
        const Drama(id: 'a', source: 's', title: 'A', views: '100万播放'),
      ),
      '100万播放',
    );
    expect(
      theaterMetaLine(const Drama(id: 'a', source: 's', title: 'A')),
      isNull,
    );
  });

  test('theater tag line joins tags', () {
    expect(
      theaterTagLine(
        const Drama(id: 'a', source: 's', title: 'A', tags: ['玄幻', '穿越']),
      ),
      '玄幻 · 穿越',
    );
    expect(
      theaterTagLine(const Drama(id: 'a', source: 's', title: 'A')),
      isEmpty,
    );
  });

  testWidgets('theater home shows search, tabs, filter chips and grid', (
    tester,
  ) async {
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    var filterTaps = 0;
    var rankingTaps = 0;
    var newTaps = 0;
    Drama? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DramaStyleHome(
            dramas: const [
              Drama(
                id: '',
                source: 's',
                title: '剧A',
                heat: '4439万热度',
                tags: ['玄幻', '穿越'],
              ),
              Drama(
                id: '',
                source: 's',
                title: '剧B',
                views: '100万播放',
                tags: ['系统'],
              ),
              Drama(id: '', source: 's', title: '文件夹剧', kind: 'folder'),
            ],
            repository: _FakeRepository(),
            onOpenDrama: (drama) => opened = drama,
            onOpenFeed: () {},
            onPickSource: () {},
            sourceLabel: '站源 (1)',
            feedEnabled: true,
            categories: const [
              CatalogCategory.all,
              CatalogCategory('xj', '玄幻'),
            ],
            selectedCategory: '',
            onCategorySelected: (_) {},
            searchController: searchController,
            searchHint: '搜索短剧',
            onSearchChanged: (_) {},
            onSearchSubmitted: (_) {},
            onFilterPressed: () => filterTaps++,
            onRankingsPressed: () => rankingTaps++,
            onNewPressed: () => newTaps++,
            filtersActive: false,
            newActive: false,
            onMenuPressed: () {},
            onAccountPressed: () {},
            badgeOf: (drama) => drama.title == '剧A' ? '追剧中' : null,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('玄幻'), findsOneWidget);
    expect(find.text('筛选'), findsOneWidget);
    expect(find.text('排行榜'), findsOneWidget);
    expect(find.text('新剧'), findsOneWidget);
    expect(find.text('预约'), findsNothing);
    expect(find.byType(DramaTile), findsNWidgets(2));
    expect(find.text('剧A'), findsOneWidget);
    expect(find.text('4439万热度'), findsOneWidget);
    expect(find.text('100万播放'), findsOneWidget);
    expect(find.text('玄幻 · 穿越'), findsOneWidget);
    expect(find.text('追剧中'), findsOneWidget);
    expect(find.text('文件夹剧'), findsNothing);
    await tester.tap(find.text('筛选'));
    await tester.pump();
    expect(filterTaps, 1);
    await tester.tap(find.text('排行榜'));
    await tester.pump();
    expect(rankingTaps, 1);
    await tester.tap(find.text('新剧'));
    await tester.pump();
    expect(newTaps, 1);
    await tester.tap(find.byType(DramaTile).at(1));
    await tester.pump();
    expect(opened?.title, '剧B');
  });

  testWidgets('theater home shows empty state without videos', (tester) async {
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DramaStyleHome(
            dramas: const [],
            repository: _FakeRepository(),
            onOpenDrama: (_) {},
            onOpenFeed: () {},
            onPickSource: () {},
            sourceLabel: '站源 (0)',
            feedEnabled: false,
            categories: const [CatalogCategory.all],
            selectedCategory: '',
            onCategorySelected: (_) {},
            searchController: searchController,
            searchHint: '搜索短剧',
            onSearchChanged: (_) {},
            onSearchSubmitted: (_) {},
            onFilterPressed: () {},
            onRankingsPressed: () {},
            onNewPressed: () {},
            filtersActive: false,
            newActive: false,
            onMenuPressed: () {},
            onAccountPressed: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('暂无可播短剧'), findsOneWidget);
    expect(find.byType(DramaTile), findsNothing);
  });
}
