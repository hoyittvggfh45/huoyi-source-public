import 'package:duanju_app/app_drawer.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('redesigned drawer renders grouped cards', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.platformLight,
        home: Scaffold(
          key: scaffoldKey,
          drawer: AppDrawer(
            zone: HomeZone.drama,
            midnightActivated: false,
            currentVersion: '1.0.4+46',
            onZoneSelected: (_) {},
            onWatchRoom: () {},
            onTool: (_) {},
            onMinorProtectionChanged: (_) {},
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('红蚁TV'), findsOneWidget);
    expect(find.text('当前版本 1.0.4+46'), findsNWidgets(2));
    expect(find.text('影视模块'), findsOneWidget);
    expect(find.text('选择一项配置或进入模块'), findsOneWidget);
    expect(find.text('应用工具'), findsOneWidget);
    expect(find.text('通用配置与管理'), findsOneWidget);
    for (final label in [
      '短剧',
      '点播',
      '直播',
      '听书',
      '阅读',
      '一起看房间',
      '站源管理',
      '内容源管理',
      '播放设置',
      '播放器选择',
      '电视直播',
      '影视下载',
      '外观主题',
      '代理内核',
      '解析接口',
      '站点验证',
      '设备互联',
      '导入中心',
      '蜘蛛规则编辑器',
      '设置',
      '软件更新',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('午夜'), findsNothing);
    expect(find.text('未成年保护'), findsNothing);
    expect(find.text('© 2026 红蚁TV'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
  });
}
