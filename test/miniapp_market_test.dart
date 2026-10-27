import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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

  test('manifest rejects unknown permission after aliasing', () {
    expect(
      () => MiniAppManifest.fromJson({
        'appId': 'ok',
        'name': 'x',
        'entry': 'index.html',
        'permissions': ['root'],
      }),
      throwsFormatException,
    );
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

  test('bridge request maps response types and denies non-get', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final bridge = MiniAppBridge(
      manifest: _manifest(),
      storage: MiniAppStorage(prefs, 'hello'),
      fetch: (_) async =>
          MiniAppHttpResponse(status: 200, bytes: utf8.encode('{"ok":true}')),
    );
    expect(
      await bridge.invoke('request', {
        'url': 'https://example.org/x',
        'responseType': 'json',
      }),
      {'ok': true},
    );
    expect(
      await bridge.invoke('request', {'url': 'https://example.org/x'}),
      '{"ok":true}',
    );
    expect(
      bridge.invoke('request', {
        'url': 'https://example.org/x',
        'method': 'POST',
      }),
      throwsA(isA<MiniAppDenied>()),
    );
  });

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
    expect(map['appBuild'], 1);
    expect(map['platform'], isNotEmpty);
  });

  test('bridge injection script exposes four compat groups', () {
    final script = MiniAppBridge.injectionScript;
    expect(script.contains('jhminiapp.request'), isTrue);
    expect(script.contains('jhminiapp.storage'), isTrue);
    expect(script.contains('jhminiapp.getSystemInfo'), isTrue);
    expect(script.contains('jhminiapp.tv'), isTrue);
  });
}
