import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/drama_theater_screen.dart';
import 'package:duanju_app/models.dart';

class _FakeRepository implements AppRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _dramas = [
  Drama(
    id: '',
    source: 's',
    title: '剧A',
    category: '真人剧',
    tags: ['穿越'],
    episodes: 78,
    description: '简介A',
    heat: '4439万热度',
  ),
  Drama(
    id: '',
    source: 's',
    title: '剧B',
    category: '漫剧',
    tags: ['系统'],
    episodes: 102,
    description: '简介B',
    views: '100万播放',
  ),
  Drama(
    id: '',
    source: 's',
    title: '剧C',
    category: 'AI漫剧',
    tags: ['系统'],
    episodes: 66,
  ),
  Drama(id: '', source: 's', title: '文件夹剧', kind: 'folder'),
];

void main() {
  test('segment matching follows category and tag text', () {
    const real = Drama(
      id: 'a',
      source: 's',
      title: 'A',
      category: '真人剧',
    );
    const comic = Drama(id: 'a', source: 's', title: 'A', category: '漫剧');
    const aiComic = Drama(
      id: 'a',
      source: 's',
      title: 'A',
      category: 'AI漫剧',
    );
    const folder = Drama(
      id: 'a',
      source: 's',
      title: 'A',
      category: '真人剧',
      kind: 'folder',
    );
    expect(theaterSegmentMatches(real, '真人剧'), isTrue);
    expect(theaterSegmentMatches(real, '漫剧'), isFalse);
    expect(theaterSegmentMatches(comic, '漫剧'), isTrue);
    expect(theaterSegmentMatches(aiComic, '漫剧'), isFalse);
    expect(theaterSegmentMatches(aiComic, 'AI剧'), isTrue);
    expect(theaterSegmentMatches(real, '视频'), isTrue);
    expect(theaterSegmentMatches(folder, '视频'), isFalse);
  });

  test('filtering combines segment category tag and query', () {
    expect(
      theaterFilterDramas(_dramas, segment: '真人剧').map((d) => d.title),
      ['剧A'],
    );
    expect(
      theaterFilterDramas(_dramas, segment: '视频').map((d) => d.title),
      ['剧A', '剧B', '剧C'],
    );
    expect(
      theaterFilterDramas(
        _dramas,
        segment: '视频',
        tag: '系统',
      ).map((d) => d.title),
      ['剧B', '剧C'],
    );
    expect(
      theaterFilterDramas(
        _dramas,
        segment: '视频',
        query: '剧B',
      ).map((d) => d.title),
      ['剧B'],
    );
    expect(
      theaterFilterDramas(
        _dramas,
        segment: '视频',
        category: '漫剧',
      ).map((d) => d.title),
      ['剧B'],
    );
  });

  test('distinct tags dedupe in first seen order', () {
    expect(theaterDistinctTags(_dramas), ['穿越', '系统']);
  });

  test('genre categories drop generic segment names', () {
    expect(
      theaterGenreCategories(const [
        CatalogCategory.all,
        CatalogCategory('xj', '玄幻'),
        CatalogCategory('zr', '真人剧'),
        CatalogCategory('ds', '都市'),
      ]).map((c) => c.name),
      ['玄幻', '都市'],
    );
  });

  testWidgets('theater screen shows title segments filters grid and nav', (
    tester,
  ) async {
    Drama? opened;
    var feedTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DramaTheaterScreen(
          dramas: _dramas,
          repository: _FakeRepository(),
          categories: const [
            CatalogCategory.all,
            CatalogCategory('xj', '玄幻'),
          ],
          onOpenDrama: (drama) => opened = drama,
          onOpenFeed: () => feedTaps++,
          onSearchSubmitted: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('剧场'), findsNWidgets(2));
    expect(find.text('真人剧'), findsOneWidget);
    expect(find.text('漫剧'), findsOneWidget);
    expect(find.text('AI剧'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('玄幻'), findsOneWidget);
    expect(find.text('穿越'), findsOneWidget);
    expect(find.text('剧A'), findsOneWidget);
    expect(find.text('全78集'), findsOneWidget);
    expect(find.text('简介A'), findsOneWidget);
    expect(find.text('4439万热度'), findsOneWidget);
    expect(find.text('剧B'), findsNothing);
    expect(find.text('文件夹剧'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
    await tester.tap(find.text('漫剧'));
    await tester.pump();
    expect(find.text('剧B'), findsOneWidget);
    expect(find.text('剧A'), findsNothing);
    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(feedTaps, 1);
    await tester.ensureVisible(find.text('剧B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('剧B'));
    await tester.pump();
    expect(opened?.title, '剧B');
  });

  testWidgets('theater screen shows empty state without videos', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DramaTheaterScreen(
          dramas: const [],
          repository: _FakeRepository(),
          onOpenDrama: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('暂无可播短剧'), findsOneWidget);
  });
}
