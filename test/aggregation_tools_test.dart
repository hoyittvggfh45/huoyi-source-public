import 'package:duanju_app/aggregation_prefs.dart';
import 'package:duanju_app/aggregation_settings_screen.dart';
import 'package:duanju_app/experiment_zone_screen.dart';
import 'package:duanju_app/floating_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('悬浮窗通道方法透传', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('huoyi/floating_window'),
          (call) async {
            calls.add(call.method);
            return switch (call.method) {
              'isPermissionGranted' => true,
              'isShowing' => true,
              _ => null,
            };
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('huoyi/floating_window'),
            null,
          ),
    );
    expect(await FloatingWindow.isPermissionGranted(), isTrue);
    expect(await FloatingWindow.isShowing(), isTrue);
    await FloatingWindow.show();
    await FloatingWindow.hide();
    await FloatingWindow.requestPermission();
    expect(calls, [
      'isPermissionGranted',
      'isShowing',
      'show',
      'hide',
      'requestPermission',
    ]);
  });

  testWidgets('聚合设置页渲染与实验开关落盘', (tester) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('huoyi/floating_window'),
          (call) async => switch (call.method) {
            'isPermissionGranted' => true,
            'isShowing' => false,
            _ => null,
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('huoyi/floating_window'),
            null,
          ),
    );
    var ai = 0;
    var lz = 0;
    var experiment = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AggregationSettingsScreen(
          onOpenAi: () => ai++,
          onOpenLz: () => lz++,
          onOpenExperiment: () => experiment++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('聚合设置'), findsOneWidget);
    expect(find.text('悬浮窗开关'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('aggregation-setting-ai')),
    );
    await tester.tap(
      find.byKey(const ValueKey('aggregation-setting-lz')),
    );
    await tester.tap(
      find.byKey(const ValueKey('aggregation-setting-experiment-entry')),
    );
    await tester.pumpAndSettle();
    expect(ai, 1);
    expect(lz, 1);
    expect(experiment, 1);
    await tester.tap(
      find.byKey(const ValueKey('aggregation-setting-experiment')),
    );
    await tester.pumpAndSettle();
    expect(await AggregationPrefs.experimentEnabled(), isFalse);
  });

  testWidgets('实验区开与关两种态', (tester) async {
    var enabled = true;
    var floating = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ExperimentZoneScreen(
          enabled: enabled,
          onEnabledChanged: (value) => enabled = value,
          onOpenFloatingSettings: () => floating++,
          onOpenAi: () {},
          onOpenLz: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TV 版式'), findsOneWidget);
    expect(find.text('暂缓'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('experiment-floating')));
    await tester.pumpAndSettle();
    expect(floating, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: ExperimentZoneScreen(
          enabled: false,
          onEnabledChanged: (value) => enabled = value,
          onOpenFloatingSettings: () => floating++,
          onOpenAi: () {},
          onOpenLz: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TV 版式'), findsNothing);
    expect(find.text('实验区已关闭，打开开关后可看实验项。'), findsOneWidget);
  });
}
