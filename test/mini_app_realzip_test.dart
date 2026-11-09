import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duanju_app/miniapp/mini_app_manifest.dart';
import 'package:duanju_app/miniapp/mini_app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('builtin miniapps from bundled assets', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('miniapp_realzip_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    Future<List<int>> loadAssetBytes(String path) async {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    test('installs the bundled demo zip', () async {
      final store = MiniAppStore(rootOverride: temp);
      final bytes = await loadAssetBytes(
        'assets/miniapps/builtin/com.leospring.demo.zip',
      );
      final manifest = await store.installFromZipBytes(bytes);
      expect(manifest.appId, 'com.leospring.demo');
      final dir = await store.installedDir('com.leospring.demo');
      expect(dir, isNotNull);
      expect(await File('${dir!.path}/manifest.json').exists(), isTrue);
      expect(await File('${dir.path}/index.html').exists(), isTrue);
    });

    test('installs the bundled emby zip under its in-zip app id', () async {
      final store = MiniAppStore(rootOverride: temp);
      final bytes = await loadAssetBytes(
        'assets/miniapps/builtin/com.ant.emby.zip',
      );
      final manifest = await store.installFromZipBytes(bytes);
      expect(manifest.appId, 'com.ant.emby');
      final dir = await store.installedDir('com.ant.emby');
      expect(dir, isNotNull);
      expect(await File('${dir!.path}/manifest.json').exists(), isTrue);
      expect(await File('${dir.path}/index.html').exists(), isTrue);
      expect(
        await store.installedDir('com.leospring.emby'),
        isNull,
      );
    });

    test('bundled market.json lists 17 apps matching the files on disk', () async {
      final file = File('assets/miniapps/builtin/market.json');
      expect(await file.exists(), isTrue);
      final raw = await file.readAsString();
      final items = parseMiniAppMarketJson(raw);
      expect(items.length, 17);
      for (final item in items) {
        final assetName = item.url.endsWith('.json')
            ? '${item.appId}.manifest.json'
            : '${item.appId}.zip';
        final asset = File('assets/miniapps/builtin/$assetName');
        expect(
          await asset.exists(),
          isTrue,
          reason: 'missing builtin asset for ${item.appId}',
        );
        if (item.size != null) {
          expect(
            await asset.length(),
            item.size,
            reason: 'size mismatch for ${item.appId}',
          );
        }
        if (item.md5 != null) {
          final digest = await md5.bind(asset.openRead()).first;
          expect(
            digest.toString(),
            item.md5,
            reason: 'md5 mismatch for ${item.appId}',
          );
        }
      }
    });
  });
}
