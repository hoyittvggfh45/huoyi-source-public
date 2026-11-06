import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<LocalStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  return LocalStore(await SharedPreferences.getInstance());
}

Future<void> _pumpSettings(
  WidgetTester tester,
  TargetPlatform platform,
  LocalStore store,
) async {
  tester.view.physicalSize = const Size(1080, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: SettingsScreen(repository: FixtureRepository(), store: store),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('毛玻璃布局（手机）设置里有 Telegram 登录入口', (tester) async {
    final store = await _store();
    await _pumpSettings(tester, TargetPlatform.android, store);
    expect(find.byKey(const ValueKey('tgdrama-login-entry')), findsOneWidget);
    expect(find.text('Telegram 登录'), findsOneWidget);
  });

  testWidgets('标准布局（桌面）设置里有 Telegram 登录入口', (tester) async {
    final store = await _store();
    await _pumpSettings(tester, TargetPlatform.windows, store);
    expect(find.byKey(const ValueKey('tgdrama-login-entry')), findsOneWidget);
    expect(find.text('Telegram 登录'), findsOneWidget);
  });
}
