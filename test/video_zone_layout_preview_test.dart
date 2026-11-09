import 'dart:io';
import 'dart:ui' as ui;

import 'package:duanju_app/main.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/ui_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

const _outDir = '/home/hatch/workspace/huoyi_new/miniapp_fix_preview';

Future<LocalStore> _previewStore() async {
  SharedPreferences.setMockInitialValues({});
  return LocalStore(await SharedPreferences.getInstance());
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    try {
      await tester.pump(const Duration(milliseconds: 100));
    } catch (_) {}
  }
  for (var i = 0; i < 10; i++) {
    try {
      if (tester.takeException() == null) break;
    } catch (_) {
      break;
    }
  }
}

Future<GlobalKey> _pumpApp(
  WidgetTester tester,
  LocalStore store,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: DuanjuApp(repository: FixtureRepository(), store: store),
    ),
  );
  await _settle(tester);
  return key;
}

Future<void> _openTheater(WidgetTester tester) async {
  await tester.tap(find.text('剧场'));
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  Directory(_outDir).createSync(recursive: true);
  File('$_outDir/$name.png').writeAsBytesSync(bytes);
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

  testWidgets('preview video zone ant layout', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    final store = await _previewStore();
    final key = await _pumpApp(tester, store);
    await _openTheater(tester);
    await tester.tap(find.byKey(const ValueKey('theater-menu')));
    await _settle(tester);
    await tester.tap(find.text('点播'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('open-history')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-favorites')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-rankings')), findsNothing);
    expect(find.text('排行榜'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    await _capture(tester, key, 'video_zone_layout');
  });

  testWidgets('preview drama zone ant layout', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    final store = await _previewStore();
    final key = await _pumpApp(tester, store);
    await _openTheater(tester);
    expect(find.byKey(const ValueKey('theater-history')), findsOneWidget);
    expect(find.byKey(const ValueKey('theater-favorites')), findsOneWidget);
    expect(find.byKey(const ValueKey('theater-search')), findsOneWidget);
    expect(find.text('排行榜'), findsNothing);
    expect(find.text('筛选'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    await _capture(tester, key, 'drama_zone_layout');
  });
}
