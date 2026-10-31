import 'dart:io';

import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/miniapp/plugin_center_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('market tab lists builtin items without any remote load', (
    tester,
  ) async {
    final tempDir = Directory('/tmp/huoyi_market_builtin_test');
    if (!tempDir.existsSync()) tempDir.createSync(recursive: true);
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => tempDir.path);
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(home: PluginCenterScreen(store: store)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('市场'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('LogVar 弹幕服务'), findsOneWidget);
    for (var i = 0; i < 20 && find.text('影视库').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('影视库'), findsOneWidget);
    for (var i = 0; i < 20 && find.text('咪咕直播').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('咪咕直播'), findsOneWidget);
    expect(find.text('暂无市场条目'), findsNothing);
    store.dispose();
    tempDir.deleteSync(recursive: true);
  });
}
