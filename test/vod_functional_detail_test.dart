import 'dart:convert';

import 'package:duanju_app/detail_screen.dart';
import 'package:duanju_app/immersive_detail_view.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_parse.dart';
import 'package:duanju_app/player_picker.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:duanju_app/ui_style.dart';
import 'package:duanju_app/vod_detail_route.dart';
import 'package:duanju_app/xigua/cross_source_search.dart';
import 'package:duanju_app/xigua/xigua_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  test('vod open action routes vod plain taps to functional detail', () {
    expect(vodOpenAction(isVodZone: true, resume: false), VodOpenAction.detail);
    expect(
      vodOpenAction(isVodZone: true, resume: true),
      VodOpenAction.directPlayback,
    );
    expect(
      vodOpenAction(isVodZone: false, resume: false),
      VodOpenAction.directPlayback,
    );
    expect(
      vodOpenAction(isVodZone: false, resume: true),
      VodOpenAction.directPlayback,
    );
  });

  test('parse interface apply replaces placeholder or appends', () {
    const api = ParseInterface(
      id: 'line1',
      name: '线路一',
      url: 'https://parse.test/?url={url}',
    );
    expect(
      api.apply('https://media.test/play.m3u8'),
      'https://parse.test/?url=https%3A%2F%2Fmedia.test%2Fplay.m3u8',
    );
    const appended = ParseInterface(
      id: 'line2',
      name: '线路二',
      url: 'https://parse.test/jx/',
    );
    expect(
      appended.apply('https://media.test/play.m3u8'),
      'https://parse.test/jx/https://media.test/play.m3u8',
    );
  });

  test(
    'parse interface store round trips enabled list and selection',
    () async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferences.getInstance();
      final apis = [
        const ParseInterface(id: 'a', name: '线路甲', url: 'https://a.test/'),
        const ParseInterface(
          id: 'b',
          name: '线路乙',
          url: 'https://b.test/',
          enabled: false,
        ),
      ];
      await ParseInterfaceStore.save(apis);
      await ParseInterfaceStore.saveSelectedId('a');
      final enabled = await ParseInterfaceStore.loadEnabled();
      expect(enabled.map((api) => api.id), ['a']);
      expect(await ParseInterfaceStore.loadSelectedId(), 'a');
      await ParseInterfaceStore.saveSelectedId('');
      expect(await ParseInterfaceStore.loadSelectedId(), '');
    },
  );

  Future<LocalStore> pumpVodDetail(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    final previous = vodDetailStyleNotifier.value;
    vodDetailStyleNotifier.value = VodDetailStyle.ant;
    addTearDown(() => vodDetailStyleNotifier.value = previous);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          drama: FixtureRepository.free,
          repository: FixtureRepository(),
          store: store,
          applyVodStyle: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> tapAction(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(ValueKey('immersive-action-$label')));
  }

  testWidgets('vod detail renders immersive view with style set to ant', (
    tester,
  ) async {
    await pumpVodDetail(tester);
    expect(find.byKey(const ValueKey('immersive-action-全屏')), findsOneWidget);
    expect(find.byKey(const ValueKey('immersive-action-解析')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('immersive-episode-grid')),
      findsOneWidget,
    );
  });

  testWidgets('immersive action buttons fire fullscreen and parse callbacks', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(_VodActionHarness(calls: calls));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('immersive-action-全屏')),
    );
    await tester.tap(find.byKey(const ValueKey('immersive-action-全屏')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('immersive-action-解析')),
    );
    await tester.tap(find.byKey(const ValueKey('immersive-action-解析')));
    await tester.pump();
    expect(calls, ['fullscreen', 'parse']);
  });

  testWidgets('player route carries startFullscreen into player widgets', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    final detail = await FixtureRepository().detail(FixtureRepository.free);
    const animation = AlwaysStoppedAnimation<double>(0);
    Widget buildRoute({bool fullscreen = false}) {
      final route = buildPlayerRoute<void>(
        captured,
        detail: detail,
        initialIndex: 0,
        repository: FixtureRepository(),
        store: store,
        startFullscreen: fullscreen,
      );
      return (route as PageRouteBuilder<void>).pageBuilder(
        captured,
        animation,
        animation,
      );
    }

    expect(
      (buildRoute(fullscreen: true) as PlayerScreen).startFullscreen,
      isTrue,
    );
    expect((buildRoute() as PlayerScreen).startFullscreen, isFalse);
    await setSelectedPlayer(store, AppPlayer.xigua);
    expect(
      (buildRoute(fullscreen: true) as XiguaPlayerScreen).startFullscreen,
      isTrue,
    );
  });

  testWidgets('reverse button flips episode grid order', (tester) async {
    await pumpVodDetail(tester);
    final firstBefore = tester.getTopLeft(
      find.byKey(const ValueKey('immersive-episode-1')),
    );
    final secondBefore = tester.getTopLeft(
      find.byKey(const ValueKey('immersive-episode-2')),
    );
    expect(firstBefore.dx, lessThan(secondBefore.dx));
    await tapAction(tester, '倒叙');
    await tester.pumpAndSettle();
    final firstAfter = tester.getTopLeft(
      find.byKey(const ValueKey('immersive-episode-1')),
    );
    final secondAfter = tester.getTopLeft(
      find.byKey(const ValueKey('immersive-episode-2')),
    );
    expect(secondAfter.dx, lessThan(firstAfter.dx));
  });

  testWidgets('favorite button toggles store following', (tester) async {
    final store = await pumpVodDetail(tester);
    expect(store.following(FixtureRepository.free.id), isNull);
    await tapAction(tester, '收藏');
    await tester.pumpAndSettle();
    expect(store.following(FixtureRepository.free.id), isNotNull);
  });

  testWidgets('source switch button with no peers shows snackbar', (
    tester,
  ) async {
    await pumpVodDetail(tester);
    await tapAction(tester, '换源');
    await tester.pump();
    expect(find.text('暂无其它来源'), findsOneWidget);
  });

  testWidgets('parse button with no interfaces shows empty state', (
    tester,
  ) async {
    await pumpVodDetail(tester);
    await tapAction(tester, '解析');
    await tester.pumpAndSettle();
    expect(find.text('暂无可用解析接口'), findsOneWidget);
    await tester.tap(find.text('去添加'));
    await tester.pumpAndSettle();
    expect(find.text('解析接口'), findsOneWidget);
  });

  testWidgets('parse button lists enabled lines and marks selection', (
    tester,
  ) async {
    await pumpVodDetail(
      tester,
      prefs: {
        'parse_interfaces': jsonEncode([
          {
            'id': 'line1',
            'name': '线路一',
            'url': 'https://parse1.test/?url={url}',
            'enabled': true,
          },
          {
            'id': 'line2',
            'name': '线路二',
            'url': 'https://parse2.test/',
            'enabled': true,
          },
          {
            'id': 'line3',
            'name': '停用线路',
            'url': 'https://parse3.test/',
            'enabled': false,
          },
        ]),
        'parse_interface_selected': 'line1',
      },
    );
    await tapAction(tester, '解析');
    await tester.pumpAndSettle();
    expect(find.text('解析线路'), findsOneWidget);
    expect(find.text('线路一'), findsOneWidget);
    expect(find.text('线路二'), findsOneWidget);
    expect(find.text('停用线路'), findsNothing);
    expect(find.text('不使用解析'), findsOneWidget);
    expect(find.text('管理解析接口'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('管理解析接口'));
    await tester.pumpAndSettle();
    expect(find.text('解析接口'), findsOneWidget);
  });

  testWidgets('search button opens cross source search flow', (tester) async {
    await pumpVodDetail(tester);
    await tapAction(tester, '搜索');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final sheet = find.byType(CrossSourceSearchSheet).evaluate().isNotEmpty;
    final notice = find.text('当前没有其他支持在线搜索的站源').evaluate().isNotEmpty;
    expect(sheet || notice, isTrue);
  });

  testWidgets('download button opens download picker', (tester) async {
    await pumpVodDetail(tester);
    await tapAction(tester, '下载');
    await tester.pumpAndSettle();
    expect(find.textContaining('加入下载'), findsWidgets);
  });
}

class _VodActionHarness extends StatefulWidget {
  const _VodActionHarness({required this.calls});

  final List<String> calls;

  @override
  State<_VodActionHarness> createState() => _VodActionHarnessState();
}

class _VodActionHarnessState extends State<_VodActionHarness> {
  final scroll = ScrollController();
  final sectionKey = GlobalKey();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final episodes = [
      for (var i = 1; i <= 2; i++) Episode({'currentEpisode': i}, i),
    ];
    return MaterialApp(
      home: Scaffold(
        body: ImmersiveDetailView(
          drama: FixtureRepository.free,
          displayEpisodes: episodes,
          visibleEpisodes: episodes,
          episodeStart: 0,
          episodePage: 0,
          currentNumber: 1,
          reversed: false,
          isFavorite: false,
          engineName: 'mpv',
          sourceName: '占位来源',
          peers: const [],
          poster: const SizedBox(),
          backdrop: const SizedBox(),
          scrollController: scroll,
          episodeSectionKey: sectionKey,
          expandedDescription: false,
          watchProgress: 0,
          onBack: () {},
          onPlayEpisode: (_) {},
          onPlayResume: () {},
          onToggleReverse: () {},
          onToggleFavorite: () {},
          onOpenSourcePanel: () {},
          onDownload: () {},
          onSearch: () {},
          onParse: () => widget.calls.add('parse'),
          onFullscreen: () => widget.calls.add('fullscreen'),
          onLocateEpisode: (_) {},
          onToggleDescription: () {},
        ),
      ),
    );
  }
}
