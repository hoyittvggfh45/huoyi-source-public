import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:duanju_app/app_build.dart';
import 'package:duanju_app/miniapp/bridge.dart';
import 'package:duanju_app/miniapp/installer.dart';
import 'package:duanju_app/miniapp/manifest.dart';
import 'package:duanju_app/miniapp/market.dart';
import 'package:duanju_app/miniapp/permissions.dart';
import 'package:duanju_app/miniapp/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MiniAppManifest _manifest() => const MiniAppManifest(
  id: 'hello',
  name: '你好示例',
  version: '1.0.0',
  versionCode: 1,
  renderer: 'webview',
  entry: 'index.html',
  description: '',
  permissions: ['storage', 'network'],
  networkAllowlist: ['example.org'],
);

void main() {
  test('manifest accepts appId fallback and navigate alias', () {
    final manifest = MiniAppManifest.fromJson({
      'appId': 'com.example.demo',
      'name': '演示',
      'entry': 'index.html',
      'permissions': ['navigate', 'storage'],
    });
    expect(manifest.id, 'com.example.demo');
    expect(manifest.permissions, ['navigation', 'storage']);
    expect(manifest.networkAllowlist, isEmpty);
  });

  test('manifest routes unknown permission to unsupportedPermissions', () {
    final manifest = MiniAppManifest.fromJson({
      'appId': 'ok',
      'name': 'x',
      'entry': 'index.html',
      'permissions': ['root'],
    });
    expect(manifest.permissions, isEmpty);
    expect(manifest.unsupportedPermissions, ['root']);
    expect(manifest.unavailablePermissions, ['root']);
  });

  test('market json parses apps list and skips bad rows', () {
    final items = parseMarketJson({
      'apps': [
        {
          'appId': 'com.example.one',
          'name': '一号',
          'version': '1.0.0',
          'versionCode': 1,
          'url': 'https://example.org/one.zip',
          'md5': 'abc',
          'size': 10,
          'author': 'someone',
          'description': 'desc',
        },
        {'name': '缺字段'},
        {
          'appId': 'com.example.two',
          'name': '二号',
          'url': 'https://example.org/two/manifest.json',
        },
      ],
    });
    expect(items.map((item) => item.appId), [
      'com.example.one',
      'com.example.two',
    ]);
    expect(items.first.isZip, isTrue);
    expect(items.last.isZip, isFalse);
  });

  test('market json rejects non-list shapes', () {
    expect(() => parseMarketJson({'apps': 'nope'}), throwsFormatException);
    expect(() => parseMarketJson('nope'), throwsFormatException);
  });

  test('installer installs zip at root and in a single subfolder', () async {
    final root = await Directory.systemTemp.createTemp('jhminiapp_root_');
    try {
      final flat = Archive()
        ..add(
          ArchiveFile.string(
            'manifest.json',
            '{"id":"flat","name":"平铺","entry":"index.html"}',
          ),
        )
        ..add(ArchiveFile.string('index.html', '<h1>hi</h1>'));
      final flatZip = ZipEncoder().encode(flat);
      final flatManifest = await MiniAppInstaller(root).installFromZip(flatZip);
      expect(flatManifest.id, 'flat');
      expect(
        await File('${root.path}/flat/index.html').readAsString(),
        '<h1>hi</h1>',
      );
      final nested = Archive()
        ..add(
          ArchiveFile.string(
            'pkg/manifest.json',
            '{"id":"nested","name":"嵌套","entry":"index.html"}',
          ),
        )
        ..add(ArchiveFile.string('pkg/index.html', '<h1>nested</h1>'));
      final nestedZip = ZipEncoder().encode(nested);
      final nestedManifest = await MiniAppInstaller(
        root,
      ).installFromZip(nestedZip);
      expect(nestedManifest.id, 'nested');
      expect(
        await File('${root.path}/nested/index.html').readAsString(),
        '<h1>nested</h1>',
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('installer rejects bad zip and md5 mismatch', () async {
    final root = await Directory.systemTemp.createTemp('jhminiapp_root_');
    try {
      final installer = MiniAppInstaller(root);
      expect(installer.installFromZip([1, 2, 3]), throwsFormatException);
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'manifest.json',
            '{"id":"x","name":"x","entry":"index.html"}',
          ),
        );
      final zip = ZipEncoder().encode(archive);
      expect(
        installer.installFromZip(zip, expectedMd5: 'deadbeef'),
        throwsFormatException,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'bridge request returns envelope and forwards headers and timeout',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Uri? seenUri;
      Map<String, String>? seenHeaders;
      Duration? seenTimeout;
      final bridge = MiniAppBridge(
        manifest: _manifest(),
        storage: MiniAppStorage(prefs, 'hello'),
        fetch: (uri, {headers = const {}, timeout}) async {
          seenUri = uri;
          seenHeaders = headers;
          seenTimeout = timeout;
          return MiniAppHttpResponse(
            status: 200,
            bytes: utf8.encode('{"ok":true}'),
            headers: {'content-type': 'application/json'},
          );
        },
      );
      final json = await bridge.invoke('request', {
        'url': 'https://example.org/x',
        'responseType': 'json',
        'headers': {'User-Agent': 'javryo-test', 'Host': 'example.org'},
        'timeout': 15000,
      });
      expect(json, {
        'statusCode': 200,
        'headers': {'content-type': 'application/json'},
        'data': {'ok': true},
        'responseType': 'json',
        'url': 'https://example.org/x',
        'byteLength': 11,
      });
      expect(seenUri.toString(), 'https://example.org/x');
      expect(seenHeaders, {'User-Agent': 'javryo-test'});
      expect(seenTimeout, const Duration(milliseconds: 15000));
      expect(await bridge.invoke('request', {'url': 'https://example.org/x'}), {
        'statusCode': 200,
        'headers': {'content-type': 'application/json'},
        'data': '{"ok":true}',
        'responseType': 'text',
        'url': 'https://example.org/x',
        'byteLength': 11,
      });
      final bytes =
          await bridge.invoke('request', {
                'url': 'https://example.org/x',
                'responseType': 'bytes',
              })
              as Map;
      expect(bytes['statusCode'], 200);
      expect(bytes['data'], base64Encode(utf8.encode('{"ok":true}')));
      expect(bytes['responseType'], 'bytes');
      expect(
        bridge.invoke('request', {
          'url': 'https://example.org/x',
          'method': 'POST',
        }),
        throwsA(isA<MiniAppDenied>()),
      );
    },
  );

  test('bridge getSystemInfo returns platform and app identity', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final bridge = MiniAppBridge(
      manifest: _manifest(),
      storage: MiniAppStorage(prefs, 'hello'),
    );
    final info = await bridge.invoke('getSystemInfo', {});
    expect(info, isA<Map>());
    final map = info as Map;
    expect(map['appSlug'], 'huoyi');
    expect(map['appBuild'], appBuild);
    expect(map['platform'], isNotEmpty);
  });

  test(
    'bridge injection script defines one ant object with jhminiapp alias',
    () {
      final script = MiniAppBridge.injectionScript;
      expect(script.contains('if (window.ant) return;'), isTrue);
      expect(script.contains('window.ant = core;'), isTrue);
      expect(script.contains('window.jhminiapp = core;'), isTrue);
      expect(script.contains('window.ant.request'), isTrue);
      expect(script.contains('window.ant.storage'), isTrue);
      expect(script.contains('window.ant.getSystemInfo'), isTrue);
      expect(script.contains('window.ant.tv'), isTrue);
      expect(script.contains('window.ant.ui'), isTrue);
      expect(script.contains('window.ant.navigateTo'), isTrue);
      expect(script.contains('window.ant.log'), isTrue);
      expect(script.contains('window.ant.version'), isTrue);
      expect(script.contains('window.ant.onShow'), isTrue);
      expect(script.contains('window.ant.source'), isTrue);
      expect(script.contains('window.ant.player'), isTrue);
    },
  );
}
