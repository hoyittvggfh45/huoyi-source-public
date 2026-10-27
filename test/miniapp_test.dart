import 'dart:convert';
import 'dart:io';

import 'package:duanju_app/miniapp/bridge.dart';
import 'package:duanju_app/miniapp/installer.dart';
import 'package:duanju_app/miniapp/manifest.dart';
import 'package:duanju_app/miniapp/permissions.dart';
import 'package:duanju_app/miniapp/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MiniAppManifest _manifest({
  List<String> permissions = const ['storage', 'network'],
  List<String> allowlist = const ['example.org'],
}) => MiniAppManifest(
  id: 'hello',
  name: '你好示例',
  version: '1.0.0',
  versionCode: 1,
  renderer: 'webview',
  entry: 'index.html',
  description: '',
  permissions: permissions,
  networkAllowlist: allowlist,
);

Future<MiniAppBridge> _bridge({
  List<String> permissions = const ['storage', 'network'],
  List<String> allowlist = const ['example.org'],
  MiniAppFetch? fetch,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return MiniAppBridge(
    manifest: _manifest(permissions: permissions, allowlist: allowlist),
    storage: MiniAppStorage(prefs, 'hello'),
    fetch: fetch,
  );
}

void main() {
  test('manifest parses and normalizes allowlist hosts', () {
    final manifest = MiniAppManifest.fromJson({
      'id': 'hello',
      'name': '你好示例',
      'version': '1.0.0',
      'versionCode': 1,
      'renderer': 'webview',
      'entry': 'index.html',
      'permissions': ['storage'],
      'networkAllowlist': ['https://Example.ORG/docs', 'api.example.com:8443'],
    });
    expect(manifest.networkAllowlist, ['example.org', 'api.example.com']);
  });

  test('manifest rejects bad id, entry, renderer and permission', () {
    expect(
      () => MiniAppManifest.fromJson({
        'id': '../escape',
        'name': 'x',
        'entry': 'index.html',
      }),
      throwsFormatException,
    );
    expect(
      () => MiniAppManifest.fromJson({
        'id': 'ok',
        'name': 'x',
        'entry': '/abs.html',
      }),
      throwsFormatException,
    );
    expect(
      () => MiniAppManifest.fromJson({
        'id': 'ok',
        'name': 'x',
        'entry': 'index.html',
        'renderer': 'native',
      }),
      throwsFormatException,
    );
    expect(
      () => MiniAppManifest.fromJson({
        'id': 'ok',
        'name': 'x',
        'entry': 'index.html',
        'permissions': ['root'],
      }),
      throwsFormatException,
    );
  });

  test('bridge storage round-trips through invoke', () async {
    final bridge = await _bridge();
    await bridge.invoke('storage.set', {'key': 'hello', 'value': 'world'});
    expect(await bridge.invoke('storage.get', {'key': 'hello'}), 'world');
    expect(await bridge.invoke('storage.get', {'key': 'missing'}), isNull);
  });

  test('bridge denies undeclared storage permission', () async {
    final bridge = await _bridge(permissions: ['network']);
    expect(
      bridge.invoke('storage.get', {'key': 'hello'}),
      throwsA(isA<MiniAppDenied>()),
    );
  });

  test('bridge network checks permission then allowlist', () async {
    var fetched = 0;
    final bridge = await _bridge(
      fetch: (_) async {
        fetched++;
        return MiniAppHttpResponse(
          status: 200,
          bytes: utf8.encode('{"ok":true}'),
        );
      },
    );
    expect(
      await bridge.invoke('network.json', {'url': 'https://example.org/x'}),
      {'ok': true},
    );
    expect(fetched, 1);
    expect(
      bridge.invoke('network.text', {'url': 'https://example.com/'}),
      throwsA(isA<MiniAppDenied>()),
    );
    expect(fetched, 1);
    final noNetwork = await _bridge(permissions: ['storage']);
    expect(
      noNetwork.invoke('network.text', {'url': 'https://example.org/x'}),
      throwsA(isA<MiniAppDenied>()),
    );
  });

  test('bridge allows any host when allowlist is empty', () async {
    var fetched = 0;
    final bridge = await _bridge(
      allowlist: const [],
      fetch: (_) async {
        fetched++;
        return MiniAppHttpResponse(
          status: 200,
          bytes: utf8.encode('{"ok":true}'),
        );
      },
    );
    expect(
      await bridge.invoke('network.json', {
        'url': 'https://anything.example/x',
      }),
      {'ok': true},
    );
    expect(fetched, 1);
  });

  test('bridge refuses player and source calls even when declared', () async {
    final bridge = await _bridge(permissions: ['player', 'source']);
    expect(bridge.invoke('player.play', {}), throwsA(isA<MiniAppDenied>()));
    expect(bridge.invoke('source.read', {}), throwsA(isA<MiniAppDenied>()));
    expect(bridge.invoke('no.such.api', {}), throwsArgumentError);
  });

  test('bridge handleMessage replies through onReply', () async {
    Object? replied;
    String? repliedError;
    int? repliedId;
    final bridge = await _bridge();
    final replying = MiniAppBridge(
      manifest: bridge.manifest,
      storage: bridge.storage,
      onReply: (id, result, error) {
        repliedId = id;
        replied = result;
        repliedError = error;
      },
    );
    await replying.handleMessage(
      jsonEncode({
        'type': 'invoke',
        'id': 7,
        'api': 'storage.set',
        'params': {'key': 'k', 'value': 1},
      }),
    );
    expect(repliedId, 7);
    expect(replied, isTrue);
    expect(repliedError, isNull);
    await replying.handleMessage(
      jsonEncode({
        'type': 'invoke',
        'id': 8,
        'api': 'storage.get',
        'params': {'key': 'k'},
      }),
    );
    expect(replied, 1);
  });

  test('bridge emit forwards json to onEmit', () async {
    String? event;
    String? data;
    final inner = await _bridge();
    final bridge = MiniAppBridge(
      manifest: inner.manifest,
      storage: inner.storage,
      onEmit: (name, json) {
        event = name;
        data = json;
      },
    );
    bridge.emit('ready', {'app': 'hello'});
    expect(event, 'ready');
    expect(jsonDecode(data!), {'app': 'hello'});
  });

  test('installer installs lists and removes', () async {
    final root = await Directory.systemTemp.createTemp('jhminiapp_root_');
    final files = await Directory.systemTemp.createTemp('jhminiapp_src_');
    try {
      await File('${files.path}/index.html').writeAsString('<h1>hi</h1>');
      await File('${files.path}/app.js').writeAsString('console.log(1);');
      const manifestJson =
          '{"id":"demo","name":"演示","entry":"index.html","permissions":["storage"]}';
      final installer = MiniAppInstaller(root);
      final manifest = await installer.install(
        manifestJson: manifestJson,
        files: files,
      );
      expect(manifest.id, 'demo');
      expect(
        await File('${root.path}/demo/index.html').readAsString(),
        '<h1>hi</h1>',
      );
      expect(
        await File('${root.path}/demo/manifest.json').readAsString(),
        manifestJson,
      );
      final listed = await installer.list();
      expect(listed.map((app) => app.id), ['demo']);
      await installer.remove('demo');
      expect(await installer.list(), isEmpty);
    } finally {
      await root.delete(recursive: true);
      await files.delete(recursive: true);
    }
  });

  test('installer skips directories without a valid manifest', () async {
    final root = await Directory.systemTemp.createTemp('jhminiapp_root_');
    try {
      final bad = Directory('${root.path}/bad');
      await bad.create();
      await File('${bad.path}/manifest.json').writeAsString('not json');
      expect(await MiniAppInstaller(root).list(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
