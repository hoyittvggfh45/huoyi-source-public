import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/detail_inline_player.dart';
import 'package:duanju_app/detail_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

class FailingInlineRepository extends FixtureRepository {
  bool failResolve = true;

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    bool adBlock = true,
    int quality = 0,
    int route = 0,
  }) async {
    if (failResolve) {
      throw AppFailure('站源拒绝了这次解析');
    }
    return super.resolve(
      drama,
      episode,
      adBlock: adBlock,
      quality: quality,
      route: route,
    );
  }
}

class DetailTestRepository extends FixtureRepository {
  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';
}

void main() {
  Future<LocalStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<InlinePlayer> pumpInline(
    WidgetTester tester, {
    required FixtureRepository repository,
    required LocalStore store,
    required ScriptedPlayer player,
  }) async {
    final detail = await repository.detail(FixtureRepository.free);
    final widget = InlinePlayer(
      detail: detail,
      index: 0,
      repository: repository,
      store: store,
      playerFactory: () => Player(platformPlayer: player),
      videoBuilder: (controls) => controls,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: widget),
      ),
    );
    await tester.pumpAndSettle();
    return widget;
  }

  test('inline resume keeps the further of captured and saved position', () {
    const episode = 2;
    expect(
      inlineResumePosition(captured: 10, saved: null, episodeNumber: episode),
      10,
    );
    final ahead = WatchEntry(
      drama: FixtureRepository.free,
      episode: episode,
      position: 40,
      duration: 120,
      updatedAt: DateTime.now(),
    );
    expect(
      inlineResumePosition(captured: 10, saved: ahead, episodeNumber: episode),
      40,
    );
    final behind = WatchEntry(
      drama: FixtureRepository.free,
      episode: episode,
      position: 5,
      duration: 120,
      updatedAt: DateTime.now(),
    );
    expect(
      inlineResumePosition(captured: 10, saved: behind, episodeNumber: episode),
      10,
    );
    final other = WatchEntry(
      drama: FixtureRepository.free,
      episode: 1,
      position: 90,
      duration: 120,
      updatedAt: DateTime.now(),
    );
    expect(
      inlineResumePosition(captured: 10, saved: other, episodeNumber: episode),
      10,
    );
  });

  testWidgets('inline player opens the resolved plan in place', (tester) async {
    final store = await makeStore();
    final repository = FixtureRepository();
    final player = ScriptedPlayer();
    await pumpInline(
      tester,
      repository: repository,
      store: store,
      player: player,
    );
    expect(player.opened, hasLength(1));
    expect(player.opened.single.uri, 'https://example.test/synthetic.mp4');
    expect(find.text('第 1 集'), findsOneWidget);
    expect(find.byKey(const ValueKey('inline-fullscreen')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline player shows the failure reason with retry', (
    tester,
  ) async {
    final store = await makeStore();
    final repository = FailingInlineRepository();
    final player = ScriptedPlayer();
    await pumpInline(
      tester,
      repository: repository,
      store: store,
      player: player,
    );
    expect(find.text('站源拒绝了这次解析'), findsOneWidget);
    expect(find.byKey(const ValueKey('inline-retry')), findsOneWidget);
    repository.failResolve = false;
    await tester.tap(find.byKey(const ValueKey('inline-retry')));
    await tester.pumpAndSettle();
    expect(player.opened, hasLength(1));
    expect(find.text('第 1 集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inline player surfaces player errors instead of a static panel',
    (tester) async {
      final store = await makeStore();
      final repository = RouteRepository()..broken = true;
      final player = ScriptedPlayer();
      await pumpInline(
        tester,
        repository: repository,
        store: store,
        player: player,
      );
      expect(player.opened, hasLength(1));
      expect(player.opened.single.uri, contains('broken'));
      expect(find.text('synthetic decoder failure'), findsOneWidget);
      expect(find.byKey(const ValueKey('inline-retry')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail page plays inline instead of pushing a player route', (
    tester,
  ) async {
    final store = await makeStore();
    size(tester, const Size(390, 844));
    final repository = DetailTestRepository();
    final player = ScriptedPlayer();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: DetailScreen(
          drama: FixtureRepository.free,
          repository: repository,
          store: store,
          playerFactory: () => Player(platformPlayer: player),
          videoBuilder: (controls) => controls,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inline-play')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('inline-play')));
    await tester.pumpAndSettle();
    expect(find.byType(InlinePlayer), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(player.opened, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
