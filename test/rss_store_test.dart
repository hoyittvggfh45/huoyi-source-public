import 'dart:io';

import 'package:duanju_app/rss_model.dart';
import 'package:duanju_app/rss_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rssJson =
    '{"sourceName": "测试订阅", "sourceUrl": "http://example.com/feed", '
    '"ruleArticles": ".item", "ruleTitle": "a@text", "ruleLink": "a@href"}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('rss_store_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  test('import load and remove round trip', () async {
    final imported = await RssSourceStore.importJson(_rssJson);
    expect(imported.name, '测试订阅');
    final loaded = await RssSourceStore.loadSources();
    expect(loaded.length, 1);
    expect(loaded.single.sourceUrl, 'http://example.com/feed');
    await RssSourceStore.importJson(_rssJson);
    expect((await RssSourceStore.loadSources()).length, 1);
    await RssSourceStore.remove(imported.id);
    expect(await RssSourceStore.loadSources(), isEmpty);
  });

  test('invalid import throws and saves nothing', () async {
    await expectLater(
      RssSourceStore.importJson('{"sourceUrl": "http://example.com"}'),
      throwsA(isA<RssFailure>()),
    );
    expect(await RssSourceStore.loadSources(), isEmpty);
  });
}
