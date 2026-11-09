import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duanju_app/miniapp/mini_app_builtin.dart';
import 'package:duanju_app/miniapp/mini_app_manifest.dart';
import 'package:duanju_app/miniapp/mini_app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    temp = await Directory.systemTemp.createTemp('miniapp_builtin_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Uint8List fakeZipBytes(String appId) {
    final manifest = utf8.encode(
      jsonEncode({
        'appId': appId,
        'name': appId,
        'version': '1.0.0',
        'versionCode': 1,
        'entry': 'index.html',
      }),
    );
    final html = utf8.encode('<h1>hi</h1>');
    final archive = Archive()
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('index.html', html.length, html));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  String marketJson(List<Map<String, dynamic>> apps) {
    return jsonEncode({'apps': apps});
  }

  Future<ByteData> Function(String) loader(Map<String, Uint8List> assets) {
    return (String path) async {
      final bytes = assets[path];
      if (bytes == null) throw StateError('missing asset: $path');
      return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    };
  }

  group('MiniAppBuiltin.ensureSeeded', () {
    test('seeds a fake zip and a fake manifest-only app, then sets the marker', () async {
      final zipBytes = fakeZipBytes('com.example.zipapp');
      final zipMd5 = md5.convert(zipBytes).toString();
      const siteManifest = '''
{"appId": "com.example.site", "name": "Site", "version": "1.0.0",
 "versionCode": 1, "entry": "https://example.com/"}
''';
      final assets = <String, Uint8List>{
        MiniAppBuiltin.marketAsset: Uint8List.fromList(
          utf8.encode(
            marketJson([
              {
                'appId': 'com.example.zipapp',
                'name': 'ZipApp',
                'url': 'https://example.com/zipapp.zip',
                'md5': zipMd5,
                'size': zipBytes.length,
              },
              {
                'appId': 'com.example.site',
                'name': 'Site',
                'url': 'https://example.com/manifest.json',
              },
            ]),
          ),
        ),
        'assets/miniapps/builtin/com.example.zipapp.zip': zipBytes,
        'assets/miniapps/builtin/com.example.site.manifest.json':
            Uint8List.fromList(utf8.encode(siteManifest)),
      };
      final store = MiniAppStore(rootOverride: temp);
      final result = await MiniAppBuiltin.ensureSeeded(
        store,
        prefs: prefs,
        loadAsset: loader(assets),
      );
      expect(result.failed, isEmpty);
      expect(result.installed, containsAll(['com.example.zipapp', 'com.example.site']));
      expect(prefs.getBool(MiniAppBuiltin.seededKey), isTrue);
      final installed = await store.listInstalled();
      expect(installed.map((e) => e.appId), containsAll(['com.example.zipapp', 'com.example.site']));
      final zipDir = await store.installedDir('com.example.zipapp');
      expect(await File('${zipDir!.path}/index.html').exists(), isTrue);
      final siteDir = await store.installedDir('com.example.site');
      expect(await File('${siteDir!.path}/manifest.json').exists(), isTrue);
    });

    test('second call is a no-op and does not reinstall a deleted app', () async {
      final zipBytes = fakeZipBytes('com.example.zipapp');
      final assets = <String, Uint8List>{
        MiniAppBuiltin.marketAsset: Uint8List.fromList(
          utf8.encode(
            marketJson([
              {
                'appId': 'com.example.zipapp',
                'name': 'ZipApp',
                'url': 'https://example.com/zipapp.zip',
                'md5': md5.convert(zipBytes).toString(),
                'size': zipBytes.length,
              },
            ]),
          ),
        ),
        'assets/miniapps/builtin/com.example.zipapp.zip': zipBytes,
      };
      final store = MiniAppStore(rootOverride: temp);
      final first = await MiniAppBuiltin.ensureSeeded(
        store,
        prefs: prefs,
        loadAsset: loader(assets),
      );
      expect(first.installed, ['com.example.zipapp']);
      expect(prefs.getBool(MiniAppBuiltin.seededKey), isTrue);
      await store.deleteApp('com.example.zipapp');
      expect(await store.listInstalled(), isEmpty);
      final second = await MiniAppBuiltin.ensureSeeded(
        store,
        prefs: prefs,
        loadAsset: loader(assets),
      );
      expect(second.installed, isEmpty);
      expect(second.failed, isEmpty);
      expect(second.skipped, ['com.example.zipapp']);
      expect(await store.listInstalled(), isEmpty);
    });

    test('a corrupted item lands in failed and the marker is not set', () async {
      final zipBytes = fakeZipBytes('com.example.good');
      final badBytes = fakeZipBytes('com.example.bad');
      final assets = <String, Uint8List>{
        MiniAppBuiltin.marketAsset: Uint8List.fromList(
          utf8.encode(
            marketJson([
              {
                'appId': 'com.example.good',
                'name': 'Good',
                'url': 'https://example.com/good.zip',
                'md5': md5.convert(zipBytes).toString(),
                'size': zipBytes.length,
              },
              {
                'appId': 'com.example.bad',
                'name': 'Bad',
                'url': 'https://example.com/bad.zip',
                'md5': '0' * 32,
                'size': badBytes.length,
              },
            ]),
          ),
        ),
        'assets/miniapps/builtin/com.example.good.zip': zipBytes,
        'assets/miniapps/builtin/com.example.bad.zip': badBytes,
      };
      final store = MiniAppStore(rootOverride: temp);
      final result = await MiniAppBuiltin.ensureSeeded(
        store,
        prefs: prefs,
        loadAsset: loader(assets),
      );
      expect(result.installed, ['com.example.good']);
      expect(result.failed.length, 1);
      expect(result.failed.first.appId, 'com.example.bad');
      expect(result.failed.first.reason, isNotEmpty);
      expect(prefs.getBool(MiniAppBuiltin.seededKey), isNot(true));
      expect(
        (await store.listInstalled()).map((e) => e.appId),
        ['com.example.good'],
      );
    });

    test('already installed apps are skipped without reinstalling', () async {
      final zipBytes = fakeZipBytes('com.example.zipapp');
      final assets = <String, Uint8List>{
        MiniAppBuiltin.marketAsset: Uint8List.fromList(
          utf8.encode(
            marketJson([
              {
                'appId': 'com.example.zipapp',
                'name': 'ZipApp',
                'url': 'https://example.com/zipapp.zip',
                'md5': md5.convert(zipBytes).toString(),
                'size': zipBytes.length,
              },
            ]),
          ),
        ),
        'assets/miniapps/builtin/com.example.zipapp.zip': zipBytes,
      };
      final store = MiniAppStore(rootOverride: temp);
      await store.installFromZipBytes(zipBytes);
      final result = await MiniAppBuiltin.ensureSeeded(
        store,
        prefs: prefs,
        loadAsset: loader(assets),
      );
      expect(result.installed, isEmpty);
      expect(result.skipped, ['com.example.zipapp']);
      expect(result.failed, isEmpty);
      expect(prefs.getBool(MiniAppBuiltin.seededKey), isTrue);
    });

    test('a broken builtin catalog parses to an empty list and sets no marker', () async {
      expect(parseMiniAppMarketJson('not json'), isEmpty);
      final assets = <String, Uint8List>{
        MiniAppBuiltin.marketAsset: Uint8List.fromList(
          utf8.encode('not json'),
        ),
      };
      final store = MiniAppStore(rootOverride: temp);
      final result = await MiniAppBuiltin.ensureSeeded(
        store,
        prefs: prefs,
        loadAsset: loader(assets),
      );
      expect(result.installed, isEmpty);
      expect(result.skipped, isEmpty);
      expect(result.failed, isEmpty);
      expect(prefs.getBool(MiniAppBuiltin.seededKey), isNot(true));
    });
  });
}
