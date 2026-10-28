import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duanju_app/immersive_detail_view.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/ui_style.dart';

Drama _testDrama() => const Drama(
  id: 't1',
  source: 'test',
  title: '占位剧名',
  description: '占位简介占位简介占位简介',
);

List<Episode> _testEpisodes() => [
  for (var i = 1; i <= 5; i++) Episode({'currentEpisode': i}, i),
];

class _ImmersiveHarness extends StatefulWidget {
  const _ImmersiveHarness({
    required this.episodes,
    required this.onSourcePanel,
  });

  final List<Episode> episodes;
  final VoidCallback onSourcePanel;

  @override
  State<_ImmersiveHarness> createState() => _ImmersiveHarnessState();
}

class _ImmersiveHarnessState extends State<_ImmersiveHarness> {
  bool reversed = false;
  final scroll = ScrollController();
  final sectionKey = GlobalKey();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final display = reversed
        ? widget.episodes.reversed.toList()
        : widget.episodes;
    return MaterialApp(
      home: Scaffold(
        body: ImmersiveDetailView(
          drama: _testDrama(),
          displayEpisodes: display,
          visibleEpisodes: display,
          episodeStart: 0,
          episodePage: 0,
          currentNumber: 1,
          reversed: reversed,
          isFavorite: false,
          engineName: 'mpv',
          sourceName: '占位来源',
          peers: const [],
          poster: const SizedBox(),
          backdrop: const SizedBox(),
          scrollController: scroll,
          episodeSectionKey: sectionKey,
          expandedDescription: false,
          watchProgress: 0.2,
          onBack: () {},
          onPlayEpisode: (_) {},
          onPlayResume: () {},
          onToggleReverse: () => setState(() => reversed = !reversed),
          onToggleFavorite: () {},
          onOpenSourcePanel: widget.onSourcePanel,
          onDownload: () {},
          onSearch: () {},
          onParse: () {},
          onFullscreen: () {},
          onLocateEpisode: (_) {},
          onToggleDescription: () {},
        ),
      ),
    );
  }
}

void main() {
  group('VodDetailStyle', () {
    test('storage round trip', () {
      expect(VodDetailStyle.ant.storageValue, 'ant');
      expect(VodDetailStyle.immersive.storageValue, 'immersive');
      expect(VodDetailStyle.immersive.label, '沉浸');
      expect(
        VodDetailStyle.fromStorageValue('immersive'),
        VodDetailStyle.immersive,
      );
    });

    test('unknown storage value falls back to ant', () {
      expect(VodDetailStyle.fromStorageValue(null), VodDetailStyle.ant);
      expect(VodDetailStyle.fromStorageValue('bogus'), VodDetailStyle.ant);
    });
  });

  group('ImmersiveDetailView', () {
    testWidgets('sections appear in spec order', (tester) async {
      await tester.pumpWidget(
        _ImmersiveHarness(episodes: _testEpisodes(), onSourcePanel: () {}),
      );
      await tester.pumpAndSettle();
      final keys = [
        'immersive-top-bar',
        'immersive-player-card',
        'immersive-title',
        'immersive-meta',
        'immersive-director',
        'immersive-actor',
        'immersive-synopsis',
        'immersive-engine',
        'immersive-actions',
        'immersive-source',
        'immersive-episode-grid',
      ];
      var previous = -1.0;
      for (final key in keys) {
        final finder = find.byKey(ValueKey(key));
        expect(finder, findsOneWidget, reason: key);
        final top = tester.getTopLeft(finder).dy;
        expect(top, greaterThan(previous), reason: key);
        previous = top;
      }
    });

    testWidgets('meta placeholders, engine hint and seven actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _ImmersiveHarness(episodes: _testEpisodes(), onSourcePanel: () {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('更新：暂无 来源：占位来源 年份：暂无'), findsOneWidget);
      expect(find.text('导演：暂无'), findsOneWidget);
      expect(find.text('演员：暂无'), findsOneWidget);
      expect(find.text('内置 mpv 播放中'), findsOneWidget);
      for (final label in ['全屏', '搜索', '倒叙', '收藏', '换源', '解析', '下载']) {
        expect(
          find.byKey(ValueKey('immersive-action-$label')),
          findsOneWidget,
          reason: label,
        );
      }
    });

    testWidgets('three column grid with red selected cell', (tester) async {
      await tester.pumpWidget(
        _ImmersiveHarness(episodes: _testEpisodes(), onSourcePanel: () {}),
      );
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('immersive-episode-grid')),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3);
      final selected = find.byKey(const ValueKey('immersive-episode-1'));
      expect(selected, findsOneWidget);
      final container = tester.widget<Container>(
        find.descendant(of: selected, matching: find.byType(Container)),
      );
      final primary = Theme.of(tester.element(selected)).colorScheme.primary;
      expect((container.decoration as BoxDecoration?)?.color, primary);
    });

    testWidgets('reverse flips grid order', (tester) async {
      await tester.pumpWidget(
        _ImmersiveHarness(episodes: _testEpisodes(), onSourcePanel: () {}),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('第 1 集')).dy,
        lessThan(tester.getTopLeft(find.text('第 5 集')).dy),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('immersive-action-倒叙')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('immersive-action-倒叙')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('第 5 集')).dy,
        lessThan(tester.getTopLeft(find.text('第 1 集')).dy),
      );
      expect(find.byKey(const ValueKey('immersive-episode-1')), findsOneWidget);
    });

    testWidgets('source pill shows name and opens panel', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _ImmersiveHarness(
          episodes: _testEpisodes(),
          onSourcePanel: () => opened++,
        ),
      );
      await tester.pumpAndSettle();
      final pill = find.byKey(const ValueKey('immersive-source-pill'));
      expect(pill, findsOneWidget);
      expect(
        find.descendant(of: pill, matching: find.text('占位来源')),
        findsOneWidget,
      );
      await tester.ensureVisible(pill);
      await tester.pumpAndSettle();
      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });
}
