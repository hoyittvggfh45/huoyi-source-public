import 'package:duanju_app/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDrawer(
    WidgetTester tester, {
    bool midnightActivated = false,
    required List<HomeZone> zones,
    required List<AppDrawerTool> tools,
    required VoidCallback onWatchRoom,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDrawer(
            zone: HomeZone.drama,
            midnightActivated: midnightActivated,
            currentVersion: '1.0.1',
            onZoneSelected: zones.add,
            onWatchRoom: onWatchRoom,
            onTool: tools.add,
            onMinorProtectionChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('drawer zone tabs map to their zones', (tester) async {
    final zones = <HomeZone>[];
    var room = 0;
    await pumpDrawer(
      tester,
      midnightActivated: true,
      zones: zones,
      tools: [],
      onWatchRoom: () => room++,
    );
    await tester.tap(find.text('点播'));
    expect(zones, [HomeZone.vod]);
    await tester.tap(find.text('午夜'));
    expect(zones, [HomeZone.vod, HomeZone.midnight]);
    await tester.tap(find.text('直播'));
    expect(zones, [HomeZone.vod, HomeZone.midnight, HomeZone.live]);
    await tester.ensureVisible(find.text('听书'));
    await tester.tap(find.text('听书'));
    expect(zones.last, HomeZone.audio);
    await tester.ensureVisible(find.text('阅读'));
    await tester.tap(find.text('阅读'));
    expect(zones.last, HomeZone.novel);
    await tester.tap(find.text('一起看房间'));
    expect(room, 1);
  });

  testWidgets('drawer tool tiles map to their tools', (tester) async {
    final tools = <AppDrawerTool>[];
    await pumpDrawer(tester, zones: [], tools: tools, onWatchRoom: () {});
    const expected = {
      '站源管理': AppDrawerTool.sources,
      '内容源管理': AppDrawerTool.contentSources,
      '播放设置': AppDrawerTool.playbackSettings,
      '播放器选择': AppDrawerTool.player,
      '影视下载': AppDrawerTool.downloads,
      '外观主题': AppDrawerTool.theme,
      '设置': AppDrawerTool.settings,
      '软件更新': AppDrawerTool.appUpdate,
      '导入中心': AppDrawerTool.importCenter,
      '解析接口': AppDrawerTool.parse,
      '站点验证': AppDrawerTool.clearance,
      '代理内核': AppDrawerTool.proxyKernel,
      '设备互联': AppDrawerTool.lanSync,
      '蜘蛛规则编辑器': AppDrawerTool.ruleEditor,
    };
    for (final entry in expected.entries) {
      await tester.ensureVisible(find.text(entry.key));
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(tools.last, entry.value);
    }
  });

  testWidgets('drawer tv live row switches to the live zone', (
    tester,
  ) async {
    final zones = <HomeZone>[];
    await pumpDrawer(tester, zones: zones, tools: [], onWatchRoom: () {});
    await tester.ensureVisible(find.text('电视直播'));
    await tester.tap(find.text('电视直播'));
    expect(zones, [HomeZone.live]);
  });

  testWidgets('drawer sections are all expanded at once', (tester) async {
    await pumpDrawer(
      tester,
      midnightActivated: true,
      zones: [],
      tools: [],
      onWatchRoom: () {},
    );
    expect(find.text('影视模块'), findsOneWidget);
    expect(find.text('应用工具'), findsOneWidget);
    expect(find.text('选择一项配置或进入模块'), findsOneWidget);
    expect(find.text('通用配置与管理'), findsOneWidget);
    expect(find.text('© 2026 红蚁TV'), findsOneWidget);
    for (final label in [
      '短剧',
      '点播',
      '午夜',
      '直播',
      '一起看房间',
      '听书',
      '站源管理',
      '播放设置',
      '影视下载',
      '软件更新',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('site source box keeps its key and tap callback', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SiteSourceBox(
            key: const ValueKey('drawer-site-box'),
            label: '测试站 (2)',
            onTap: () => tapped++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试站 (2)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drawer-site-box')));
    expect(tapped, 1);
  });

  testWidgets('drawer header no longer shows the site box', (tester) async {
    await pumpDrawer(tester, zones: [], tools: [], onWatchRoom: () {});
    expect(find.text('红蚁TV'), findsOneWidget);
    expect(find.text('当前版本 1.0.1'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('drawer-site-box')), findsNothing);
  });

  testWidgets('midnight tab follows activation', (tester) async {
    await pumpDrawer(
      tester,
      midnightActivated: false,
      zones: [],
      tools: [],
      onWatchRoom: () {},
    );
    expect(find.text('午夜'), findsNothing);
    expect(find.text('未成年保护'), findsNothing);

    final zones = <HomeZone>[];
    await pumpDrawer(
      tester,
      midnightActivated: true,
      zones: zones,
      tools: [],
      onWatchRoom: () {},
    );
    expect(find.text('午夜'), findsOneWidget);
    expect(find.text('未成年保护'), findsOneWidget);
    await tester.tap(find.text('午夜'));
    expect(zones, [HomeZone.midnight]);
  });
}
