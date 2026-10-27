import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:duanju_app/account_screen.dart';
import 'package:duanju_app/app_drawer.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_source_screen.dart';
import 'package:duanju_app/content_zone_screen.dart';
import 'package:duanju_app/detail_screen.dart';
import 'package:duanju_app/downloads_screen.dart';
import 'package:duanju_app/drama_style_home.dart';
import 'package:duanju_app/fullscreen_feed_screen.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/legado_screen.dart';
import 'package:duanju_app/live_playback.dart';
import 'package:duanju_app/live_player_screen.dart';
import 'package:duanju_app/live_repository.dart';
import 'package:duanju_app/live_screen.dart';
import 'package:duanju_app/live_sources.dart';
import 'package:duanju_app/live_store.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/login_screen.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:duanju_app/saved_library.dart';
import 'package:duanju_app/settings_screen.dart';
import 'package:duanju_app/tvbox_player_bridge.dart';
import 'package:duanju_app/ui_style.dart';
import 'package:duanju_app/watchroom/player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

const previewDir = '/home/hatch/workspace/huoyi_new/previews';

Future<LocalStore> previewStore(Map<String, Object> seeds) async {
  SharedPreferences.setMockInitialValues(seeds);
  return LocalStore(await SharedPreferences.getInstance());
}

ThemeData previewTheme() {
  final base = AppTheme.platformLight;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'PreviewCJK'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'PreviewCJK'),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(
        fontFamily: 'PreviewCJK',
      ),
      subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(
        fontFamily: 'PreviewCJK',
      ),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'PreviewCJK',
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      titleTextStyle: base.dialogTheme.titleTextStyle?.copyWith(
        fontFamily: 'PreviewCJK',
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStateProperty.resolveWith((states) {
          final style = base.filledButtonTheme.style?.textStyle?.resolve(
            states,
          );
          return style?.copyWith(fontFamily: 'PreviewCJK');
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        textStyle: WidgetStateProperty.resolveWith((states) {
          final style = base.textButtonTheme.style?.textStyle?.resolve(states);
          return style?.copyWith(fontFamily: 'PreviewCJK');
        }),
      ),
    ),
  );
}

Future<void> settlePreview(WidgetTester tester) async {
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

Future<GlobalKey> pumpPreview(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  print('preview stage: pumping');
  try {
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme(),
          home: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'PreviewCJK'),
            child: Scaffold(body: screen),
          ),
        ),
      ),
    );
  } catch (_) {}
  print('preview stage: pumped, settling');
  await settlePreview(tester);
  print('preview stage: settled');
  return key;
}

Future<void> capturePreview(
  WidgetTester tester,
  Widget screen,
  String name,
) async {
  final key = await pumpPreview(tester, screen);
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  Directory(previewDir).createSync(recursive: true);
  File('$previewDir/$name.png').writeAsBytesSync(bytes);
  print('preview landed: $name');
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

  testWidgets('preview detail', (tester) async {
    final store = await previewStore({});
    await capturePreview(
      tester,
      DetailScreen(
        drama: FixtureRepository.free,
        repository: FixtureRepository(),
        store: store,
      ),
      'preview_detail',
    );
  });

  testWidgets('preview drama ant', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    final store = await previewStore({});
    await capturePreview(
      tester,
      HomeScreen(repository: FixtureRepository(), store: store),
      'preview_drama_ant',
    );
  });

  testWidgets('preview drama vod', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    final store = await previewStore({});
    final key = await pumpPreview(
      tester,
      HomeScreen(repository: FixtureRepository(), store: store),
    );
    try {
      await tester.tap(find.byKey(const ValueKey('open-app-drawer')));
      await settlePreview(tester);
      await tester.tap(find.text('点播区'));
      await settlePreview(tester);
    } catch (_) {}
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    Directory(previewDir).createSync(recursive: true);
    File('$previewDir/preview_drama_vod.png').writeAsBytesSync(bytes);
    print('preview landed: preview_drama_vod');
  });

  testWidgets('preview drama midnight', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    final store = await previewStore({'midnightActivated': true});
    final key = await pumpPreview(
      tester,
      HomeScreen(repository: FixtureRepository(), store: store),
    );
    try {
      await tester.tap(find.byKey(const ValueKey('open-app-drawer')));
      await settlePreview(tester);
      await tester.tap(find.text('午夜区'));
      await settlePreview(tester);
    } catch (_) {}
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    Directory(previewDir).createSync(recursive: true);
    File('$previewDir/preview_drama_midnight.png').writeAsBytesSync(bytes);
    print('preview landed: preview_drama_midnight');
  });

  testWidgets('preview feed fullscreen', (tester) async {
    final store = await previewStore({});
    await capturePreview(
      tester,
      FullscreenFeedScreen(
        dramas: [FixtureRepository.free, FixtureRepository.vip],
        repository: FixtureRepository(),
        store: store,
      ),
      'preview_feed_fullscreen',
    );
  });

  testWidgets('preview feed settings', (tester) async {
    final store = await previewStore({});
    final key = await pumpPreview(
      tester,
      FullscreenFeedScreen(
        dramas: [FixtureRepository.free, FixtureRepository.vip],
        repository: FixtureRepository(),
        store: store,
      ),
    );
    try {
      await tester.tap(find.byTooltip('流内设置'));
      await settlePreview(tester);
    } catch (_) {}
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    Directory(previewDir).createSync(recursive: true);
    File('$previewDir/preview_feed_settings.png').writeAsBytesSync(bytes);
    print('preview landed: preview_feed_settings');
  });

  testWidgets('preview drama home', (tester) async {
    print('preview stage: home test entered');
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    await capturePreview(
      tester,
      DramaStyleHome(
        dramas: [FixtureRepository.free, FixtureRepository.vip],
        repository: FixtureRepository(),
        onOpenDrama: (_) {},
        onOpenFeed: () {},
        onPickSource: () {},
        sourceLabel: '合成数据',
        feedEnabled: true,
        categories: const [CatalogCategory.all, CatalogCategory('syn', '合成数据')],
        selectedCategory: '',
        onCategorySelected: (_) {},
        searchController: searchController,
        searchHint: '搜索短剧',
        onSearchChanged: (_) {},
        onSearchSubmitted: (_) {},
        onSectionSelected: (_) {},
        onMenuPressed: () {},
        onAccountPressed: () {},
        onSettingsPressed: () {},
      ),
      'preview_drama_home',
    );
  });

  testWidgets('preview live', (tester) async {
    final store = await previewStore({});
    final prefs = await SharedPreferences.getInstance();
    await capturePreview(
      tester,
      LiveScreen(
        repository: LiveRepository(),
        store: LiveStore(prefs, 'default'),
        appStore: store,
      ),
      'preview_live',
    );
  });

  testWidgets('preview novel', (tester) async {
    await capturePreview(
      tester,
      LegadoScreen(repository: FixtureRepository()),
      'preview_novel',
    );
  });

  testWidgets('preview comic', (tester) async {
    await capturePreview(
      tester,
      const ContentZoneScreen(section: ContentSection.comic),
      'preview_comic',
    );
  });

  testWidgets('preview player detail', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    final repository = RouteRepository();
    final platform = ScriptedPlayer();
    final detail = await repository.detail(FixtureRepository.free);
    await capturePreview(
      tester,
      PlayerScreen(
        detail: detail,
        initialIndex: 0,
        initialPosition: 7,
        repository: repository,
        store: store,
        playerFactory: () => Player(platformPlayer: platform),
        videoBuilder: (controls) => controls,
      ),
      'preview_player_detail',
    );
  });

  testWidgets('preview player room', (tester) async {
    await capturePreview(
      tester,
      RoomPlayerView(
        handle: RoomPlayerHandle(),
        viewType: TvboxPlayerController.viewType,
        onCompleted: () {},
        onError: (_) {},
        onRetry: () {},
        onFullscreen: () {},
      ),
      'preview_player_room',
    );
  });

  testWidgets('preview player live', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await capturePreview(
      tester,
      LivePlayerScreen(
        playback: LivePlaybackController(repository: LiveRepository()),
        source: const LiveSource(
          id: 'test',
          name: '测试直播源',
          description: '测试',
          protocol: LiveProtocol.list,
        ),
        store: LiveStore(prefs, 'default'),
        onExit: () {},
      ),
      'preview_player_live',
    );
  });

  testWidgets('preview settings ant', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    final store = await previewStore({});
    await capturePreview(
      tester,
      SettingsScreen(repository: FixtureRepository(), store: store),
      'preview_settings_ant',
    );
  });

  testWidgets('preview settings drama', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.drama;
    addTearDown(() {
      dramaUiStyleNotifier.value = DramaUiStyle.ant;
    });
    final store = await previewStore({});
    await capturePreview(
      tester,
      SettingsScreen(repository: FixtureRepository(), store: store),
      'preview_settings_drama',
    );
  });

  testWidgets('preview settings style', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    addTearDown(() {
      dramaUiStyleNotifier.value = DramaUiStyle.ant;
    });
    final store = await previewStore({});
    final key = await pumpPreview(
      tester,
      SettingsScreen(repository: FixtureRepository(), store: store),
    );
    try {
      final styleRow = find.text('短剧区风格').first;
      await tester.ensureVisible(styleRow);
      await settlePreview(tester);
      await tester.tap(styleRow);
      await settlePreview(tester);
    } catch (_) {}
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    Directory(previewDir).createSync(recursive: true);
    File('$previewDir/preview_settings_style.png').writeAsBytesSync(bytes);
    print('preview landed: preview_settings_style');
  });

  testWidgets('preview account', (tester) async {
    await capturePreview(tester, const AccountScreen(), 'preview_account');
  });

  testWidgets('preview login', (tester) async {
    await capturePreview(tester, LoginScreen(), 'preview_login');
  });

  testWidgets('preview downloads', (tester) async {
    final store = await previewStore({});
    await capturePreview(
      tester,
      DownloadsScreen(repository: FixtureRepository(), store: store),
      'preview_downloads',
    );
  });

  testWidgets('preview follow', (tester) async {
    final store = await previewStore({});
    await capturePreview(
      tester,
      SavedLibrary(
        repository: FixtureRepository(),
        store: store,
        history: false,
        onOpen: (_) {},
        onContinue: (_) {},
      ),
      'preview_follow',
    );
  });

  testWidgets('preview history', (tester) async {
    final store = await previewStore({});
    await capturePreview(
      tester,
      SavedLibrary(
        repository: FixtureRepository(),
        store: store,
        history: true,
        onOpen: (_) {},
        onContinue: (_) {},
      ),
      'preview_history',
    );
  });

  testWidgets('preview drawer', (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    final key = await pumpPreview(
      tester,
      Scaffold(
        key: scaffoldKey,
        drawer: AppDrawer(
          zone: HomeZone.drama,
          midnightActivated: true,
          currentVersion: '1.0.0',
          onZoneSelected: (_) {},
          onMiniApp: () {},
          onHikerMiniApp: () {},
          onWatchRoom: () {},
          onTool: (_) {},
          onMinorProtectionChanged: (_) {},
          onVersionDoubleTap: () {},
        ),
        body: const SizedBox.shrink(),
      ),
    );
    scaffoldKey.currentState!.openDrawer();
    await settlePreview(tester);
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    Directory(previewDir).createSync(recursive: true);
    File('$previewDir/preview_drawer.png').writeAsBytesSync(bytes);
    print('preview landed: preview_drawer');
  });

  testWidgets('preview drawer grouped real', (tester) async {
    tester.view.physicalSize = const Size(390, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scaffoldKey = GlobalKey<ScaffoldState>();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme(),
          home: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'PreviewCJK'),
            child: Scaffold(
              key: scaffoldKey,
              drawer: AppDrawer(
                zone: HomeZone.drama,
                midnightActivated: true,
                currentVersion: '1.0.0',
                onZoneSelected: (_) {},
                onMiniApp: () {},
                onHikerMiniApp: () {},
                onWatchRoom: () {},
                onTool: (_) {},
                onMinorProtectionChanged: (_) {},
                onVersionDoubleTap: () {},
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    scaffoldKey.currentState!.openDrawer();
    await settlePreview(tester);
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    Directory(previewDir).createSync(recursive: true);
    File('$previewDir/preview_drawer_grouped_real.png').writeAsBytesSync(bytes);
    print('preview landed: preview_drawer_grouped_real');
  });

  testWidgets('preview content sources', (tester) async {
    final store = await previewStore({});
    await capturePreview(
      tester,
      ContentSourceScreen(repository: FixtureRepository(), store: store),
      'preview_content_sources',
    );
  });
}
