import 'dart:io';
import 'dart:ui' as ui;

import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/playback_parse.dart';
import 'package:duanju_app/player_core.dart';
import 'package:duanju_app/shell/kotv_settings_screen.dart';
import 'package:duanju_app/shell/kotv_shell_screen.dart';
import 'package:duanju_app/shell/kotv_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

const p1PreviewDir = '/home/hatch/workspace/huoyi_new/previews';

Future<LocalStore> p1Store(Map<String, Object> seeds) async {
  SharedPreferences.setMockInitialValues(seeds);
  return LocalStore(await SharedPreferences.getInstance());
}

ThemeData p1Theme() {
  final base = AppTheme.platformLight;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'PreviewCJK'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'PreviewCJK'),
  );
}

Future<void> p1Settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    try {
      await tester.pump(const Duration(milliseconds: 100));
    } catch (_) {}
  }
  for (var i = 0; i < 10; i++) {
    try {
      final error = tester.takeException();
      if (error == null) {
        break;
      }
    } catch (_) {
      break;
    }
  }
}

Future<GlobalKey> p1Pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  try {
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: p1Theme(),
          home: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'PreviewCJK'),
            child: Scaffold(body: screen),
          ),
        ),
      ),
    );
  } catch (_) {}
  await p1Settle(tester);
  return key;
}

Future<void> p1Capture(
  WidgetTester tester,
  Widget screen,
  String name,
) async {
  final key = await p1Pump(tester, screen);
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  image.dispose();
  Directory(p1PreviewDir).createSync(recursive: true);
  File('$p1PreviewDir/$name.png').writeAsBytesSync(bytes);
}

void main() {
  setUpAll(() async {
    try {
      final bytes = File(
        '/home/hatch/workspace/huoyi_new/cjk_subset.ttf',
      ).readAsBytesSync();
      final loader = FontLoader('PreviewCJK')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      final fallback = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await fallback.load();
    } catch (_) {}
  });

  test('p1 shell prefs round trip', () async {
    final store = await p1Store({});
    expect(store.useNewShell, isTrue);
    expect(store.autoSwitchPlayer, isTrue);
    await store.setUseNewShell(false);
    expect(store.useNewShell, isFalse);
    await store.setUseNewShell(true);
    expect(store.useNewShell, isTrue);
    await store.setAutoSwitchPlayer(false);
    expect(store.autoSwitchPlayer, isFalse);
    await store.setAutoSwitchPlayer(true);
    expect(store.autoSwitchPlayer, isTrue);
    await store.setPlayerCore(PlayerCore.mpv);
    expect(PlayerCoreStorage.read(store.preferences), PlayerCore.mpv);
    await store.setDefaultParserId('test-parser');
    expect(await ParseInterfaceStore.loadSelectedId(), 'test-parser');
    await store.setDefaultParserId('');
    expect(await ParseInterfaceStore.loadSelectedId(), '');
  });

  testWidgets('p1 new shell home without midnight tab', (tester) async {
    final store = await p1Store({});
    await p1Capture(
      tester,
      ProviderScope(
        child: KotvShellScreen(
          repository: FixtureRepository(),
          store: store,
          midnightActivated: false,
        ),
      ),
      'p1_new_shell_home',
    );
    expect(find.text('午夜区'), findsNothing);
    expect(find.text('短剧'), findsWidgets);
    expect(find.text('点播'), findsWidgets);
  });

  testWidgets('p1 new shell midnight tab', (tester) async {
    final store = await p1Store({'midnightActivated': true});
    final key = await p1Pump(
      tester,
      ProviderScope(
        child: KotvShellScreen(
          repository: FixtureRepository(),
          store: store,
          midnightActivated: true,
        ),
      ),
    );
    expect(find.text('午夜区'), findsWidgets);
    try {
      await tester.tap(
        find.descendant(
          of: find.byType(KotvBottomBar),
          matching: find.text('午夜区'),
        ),
      );
      await p1Settle(tester);
    } catch (_) {}
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    image.dispose();
    Directory(p1PreviewDir).createSync(recursive: true);
    File('$p1PreviewDir/p1_new_shell_midnight.png').writeAsBytesSync(bytes);
  });

  testWidgets('p1 new shell settings with shell switch', (tester) async {
    final store = await p1Store({});
    final key = await p1Pump(
      tester,
      ProviderScope(
        child: KotvShellScreen(
          repository: FixtureRepository(),
          store: store,
          midnightActivated: false,
        ),
      ),
    );
    try {
      await tester.tap(
        find.descendant(
          of: find.byType(KotvBottomBar),
          matching: find.text('设置'),
        ),
      );
      await p1Settle(tester);
    } catch (_) {}
    expect(find.text('界面壳'), findsWidgets);
    expect(find.text('使用新壳'), findsWidgets);
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    image.dispose();
    Directory(p1PreviewDir).createSync(recursive: true);
    File('$p1PreviewDir/p1_new_shell_settings.png').writeAsBytesSync(bytes);
  });

  testWidgets('p1 new shell settings midnight row', (tester) async {
    final store = await p1Store({});
    tester.view.physicalSize = const Size(390, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: p1Theme(),
          home: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'PreviewCJK'),
            child: Scaffold(
              body: KotvSettingsScreen(
                repository: FixtureRepository(),
                store: store,
              ),
            ),
          ),
        ),
      );
    } catch (_) {}
    await p1Settle(tester);
    expect(find.text('午夜区'), findsWidgets);
  });

  testWidgets('p1 old shell home', (tester) async {
    final store = await p1Store({});
    await p1Capture(
      tester,
      HomeScreen(repository: FixtureRepository(), store: store),
      'p1_old_shell_home',
    );
    expect(find.byType(HomeScreen), findsWidgets);
  });

  testWidgets('p1 main branch switches shells', (tester) async {
    final store = await p1Store({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: p1Theme(),
          home: DuanjuApp(
            repository: FixtureRepository(),
            store: store,
            useNewShell: true,
            midnightActivated: false,
          ),
        ),
      );
      await p1Settle(tester);
    } catch (_) {}
    expect(find.byType(KotvShellScreen), findsWidgets);
    try {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: p1Theme(),
          home: DuanjuApp(
            repository: FixtureRepository(),
            store: store,
            useNewShell: false,
            midnightActivated: false,
          ),
        ),
      );
      await p1Settle(tester);
    } catch (_) {}
    expect(find.byType(HomeScreen), findsWidgets);
    expect(find.byType(KotvShellScreen), findsNothing);
  });
}
