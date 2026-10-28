import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:duanju_app/miniapp/bridge.dart';
import 'package:duanju_app/miniapp/installer.dart';
import 'package:duanju_app/miniapp/manifest.dart';
import 'package:duanju_app/miniapp/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _javryoManifest = '''
{
  "appId": "com.example.sehuatang",
  "app_id": "com.javryo.video",
  "name": "JAVRYO",
  "version": "1.0.0",
  "versionCode": 1,
  "renderer": "webview",
  "entry": "index.html",
  "permissions": ["ui", "storage", "network", "player", "source", "navigate"]
}
''';

List<int> _javryoZip() {
  final archive = Archive()
    ..add(ArchiveFile.string('manifest.json', _javryoManifest))
    ..add(ArchiveFile.string('index.html', '<h1>JAVRYO</h1>'))
    ..add(ArchiveFile.string('app.js', 'window.JAVRYO = true;'))
    ..add(ArchiveFile.string('style.css', 'body{}'));
  return ZipEncoder().encode(archive);
}

void main() {
  test(
    'javryo shaped zip installs with appId priority and mapped perms',
    () async {
      final root = await Directory.systemTemp.createTemp('jhminiapp_javryo_');
      try {
        final manifest = await MiniAppInstaller(
          root,
        ).installFromZip(_javryoZip());
        expect(manifest.id, 'com.example.sehuatang');
        expect(manifest.name, 'JAVRYO');
        expect(manifest.entry, 'index.html');
        expect(manifest.renderer, 'webview');
        expect(
          manifest.permissions,
          containsAll(['ui', 'storage', 'network', 'player', 'source']),
        );
        expect(manifest.permissions, contains('navigation'));
        expect(manifest.permissions, isNot(contains('navigate')));
        expect(
          await File('${root.path}/com.example.sehuatang/app.js').exists(),
          isTrue,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'javryo fetch pattern sees a real status code, never undefined',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var status = 200;
      final bridge = MiniAppBridge(
        manifest: const MiniAppManifest(
          id: 'javryo',
          name: 'JAVRYO',
          version: '1.0.0',
          versionCode: 1,
          renderer: 'webview',
          entry: 'index.html',
          description: '',
          permissions: ['network'],
          networkAllowlist: [],
        ),
        storage: MiniAppStorage(prefs, 'javryo'),
        fetch: (uri, {headers = const {}, timeout}) async =>
            MiniAppHttpResponse(
              status: status,
              bytes: utf8.encode('<html>feed</html>'),
            ),
      );
      final ok =
          await bridge.invoke('request', {
                'url': 'https://javryo.com/feed',
                'headers': {'User-Agent': 'javryo-test'},
                'timeout': 15000,
              })
              as Map;
      expect(ok['statusCode'], 200);
      expect(ok['data'], '<html>feed</html>');
      expect(ok['responseType'], 'text');
      expect(ok['byteLength'], 17);
      status = 404;
      final missing =
          await bridge.invoke('request', {'url': 'https://javryo.com/missing'})
              as Map;
      expect(missing['statusCode'], 404);
      expect(missing['statusCode'] == 200, isFalse);
    },
  );

  test('injection exposes source play category search and version number', () {
    final script = MiniAppBridge.injectionScript;
    expect(script.contains('window.ant.version = 4;'), isTrue);
    expect(script.contains("source.play"), isTrue);
    expect(script.contains("source.category"), isTrue);
    expect(script.contains("source.search"), isTrue);
    expect(script.contains("typeof params === 'string'"), isTrue);
  });
}
