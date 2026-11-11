import 'dart:io';
import 'dart:ui' as ui;

import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/ui_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

const _outDir = '/home/hatch/workspace/huoyi_new/moyi_style_preview_104';

Future<LocalStore> _previewStore() async {
  SharedPreferences.setMockInitialValues({});
  return LocalStore(await SharedPreferences.getInstance());
}

Future<GlobalKey> _pumpApp(WidgetTester tester, LocalStore store) async {
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
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  return key;
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

Future<void> _step(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('moyi cap mine', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    final store = await _previewStore();
    final key = await _pumpApp(tester, store);
    await tester.tap(find.text('我的'));
    await _step(tester);
    await _capture(tester, key, 'moyi_mine');
  });

  testWidgets('moyi cap drama', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    final store = await _previewStore();
    final key = await _pumpApp(tester, store);
    await tester.tap(find.text('剧场'));
    await _step(tester);
    await _capture(tester, key, 'moyi_drama');
  });

  testWidgets('moyi cap video', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    final store = await _previewStore();
    final key = await _pumpApp(tester, store);
    await tester.tap(find.text('剧场'));
    await _step(tester);
    await tester.tap(find.byKey(const ValueKey('theater-menu')));
    await _step(tester);
    await tester.tap(find.text('点播'));
    await _step(tester);
    await _capture(tester, key, 'moyi_video');
  });

  testWidgets('moyi cap midnight', (tester) async {
    dramaUiStyleNotifier.value = DramaUiStyle.ant;
    final store = await _previewStore();
    final key = await _pumpApp(tester, store);
    await tester.tap(find.text('剧场'));
    await _step(tester);
    await tester.tap(find.byKey(const ValueKey('theater-menu')));
    await _step(tester);
    await tester.tap(find.text('点播'));
    await _step(tester);
    await tester.tap(find.byKey(const ValueKey('open-app-drawer')));
    await _step(tester);
    await tester.tap(find.text('午夜'));
    await _step(tester);
    await _capture(tester, key, 'moyi_midnight');
  });
}
