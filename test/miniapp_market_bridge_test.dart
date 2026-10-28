import 'dart:io';

import 'package:archive/archive.dart';
import 'package:duanju_app/miniapp/bridge.dart';
import 'package:duanju_app/miniapp/installer.dart';
import 'package:duanju_app/miniapp/manifest.dart';
import 'package:duanju_app/miniapp/market.dart';
import 'package:duanju_app/miniapp/permissions.dart';
import 'package:duanju_app/miniapp/renderer.dart';
import 'package:duanju_app/miniapp/storage.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubHost extends MiniAppHost {
  final calls = <String>[];
  Map<String, Object?>? lastParams;
  List<String>? lastOptions;
  String? lastUrl;

  @override
  Future<List<Map<String, Object?>>> sourceList() async {
    calls.add('source.list');
    return [
      {'key': 'custom:x', 'id': 'custom:x', 'name': '配置站', 'type': 1},
    ];
  }

  @override
  Future<Map<String, Object?>> sourceHome(Map<String, Object?> params) async {
    calls.add('source.home');
    lastParams = params;
    return {
      'class': [
        {'id': 'c1', 'name': '分类一'},
      ],
      'list': [],
    };
  }

  @override
  Future<Map<String, Object?>> sourceDetail(Map<String, Object?> params) async {
    calls.add('source.detail');
    lastParams = params;
    return {'id': 'v1', 'title': '剧一', 'episodes': []};
  }

  @override
  Future<Map<String, Object?>> playerOpen(Map<String, Object?> params) async {
    calls.add('player.open');
    lastParams = params;
    return {'route': '/player'};
  }

  @override
  void toast(String message) {
    calls.add('ui.toast:$message');
  }

  @override
  void showLoading(String message) {
    calls.add('ui.loading:$message');
  }

  @override
  void hideLoading() {
    calls.add('ui.hideLoading');
  }

  @override
  Future<int> actionSheet(List<String> options) async {
    calls.add('ui.actionSheet');
    lastOptions = options;
    return 2;
  }

  @override
  Future<Object?> navigateTo(String url) async {
    calls.add('navigateTo');
    lastUrl = url;
    return {'url': url, 'opened': true};
  }

  @override
  Future<bool> navigateBack() async {
    calls.add('navigateBack');
    return true;
  }
}

MiniAppManifest _manifest(List<String> permissions) => MiniAppManifest(
  id: 'bridge',
  name: '桥测试',
  version: '1.0.0',
  versionCode: 1,
  renderer: 'webview',
  entry: 'index.html',
  description: '',
  permissions: permissions,
  networkAllowlist: ['example.org'],
);

Future<MiniAppBridge> _bridge(
  List<String> permissions, {
  MiniAppHost? host,
  MiniAppFetch? fetch,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return MiniAppBridge(
    manifest: _manifest(permissions),
    storage: MiniAppStorage(prefs, 'bridge'),
    fetch: fetch,
    host: host,
  );
}

void main() {
  test('permission sets split known from supported', () {
    expect(
      MiniAppPermissions.known,
      containsAll([
        'network',
        'storage',
        'ui',
        'navigation',
        'player',
        'source',
        'service',
        'node',
        'miniapp',
      ]),
    );
    expect(MiniAppPermissions.known.length, 9);
    expect(
      MiniAppPermissions.supported,
      containsAll([
        'network',
        'storage',
        'ui',
        'navigation',
        'player',
        'source',
      ]),
    );
    expect(MiniAppPermissions.supported.length, 6);
    expect(MiniAppPermissions.supported.contains('service'), isFalse);
    expect(MiniAppPermissions.supported.contains('node'), isFalse);
    expect(MiniAppPermissions.supported.contains('miniapp'), isFalse);
  });

  test('manifest splits known, deferred and unknown permissions', () {
    final manifest = MiniAppManifest.fromJson({
      'id': 'x',
      'name': 'x',
      'entry': 'index.html',
      'permissions': ['service', 'node', 'miniapp', 'navigate', 'root'],
    });
    expect(manifest.permissions, ['service', 'node', 'miniapp', 'navigation']);
    expect(manifest.unsupportedPermissions, ['root']);
    expect(manifest.unavailablePermissions, [
      'service',
      'node',
      'miniapp',
      'root',
    ]);
  });

  test('market permission audit fixtures all parse without throw', () {
    final audit = <String, List<String>>{
      'logvar-webview': ['network', 'storage', 'ui', 'service'],
      'logvar-node': ['node', 'ui'],
      'emby': ['ui', 'storage', 'navigate', 'player', 'source'],
      'demo': [
        'network',
        'storage',
        'ui',
        'navigate',
        'miniapp',
        'player',
        'source',
      ],
      'launch-target': ['ui', 'storage', 'navigate'],
      'launcher': ['ui', 'miniapp'],
      'web-links': ['ui', 'navigate'],
      'cctv': ['ui', 'navigate'],
      'cms-t4': ['ui', 'storage', 'network', 'service'],
      'source-t4': ['ui', 'storage', 'service', 'source'],
      'tetris': ['ui', 'storage', 'navigate'],
      'node-demo': ['node'],
      'drpy-node': ['node', 'ui'],
      'migu': ['node', 'ui', 'network', 'player', 'storage'],
    };
    for (final entry in audit.entries) {
      final manifest = MiniAppManifest.fromJson({
        'id': entry.key,
        'name': entry.key,
        'entry': 'index.html',
        'permissions': entry.value,
      });
      expect(manifest.unsupportedPermissions, isEmpty, reason: entry.key);
    }
    final emby = MiniAppManifest.fromJson({
      'id': 'com.ant.emby',
      'name': '影视库',
      'entry': 'index.html',
      'permissions': ['ui', 'storage', 'navigate', 'player', 'source'],
    });
    expect(emby.permissions, contains('navigation'));
    expect(emby.unavailablePermissions, isEmpty);
    final logvar = MiniAppManifest.fromJson({
      'id': 'com.logvar.danmu',
      'name': '弹幕',
      'entry': 'index.html',
      'permissions': ['network', 'storage', 'ui', 'service'],
    });
    expect(logvar.unavailablePermissions, ['service']);
  });

  test('bridge storage json variants round-trip with fallback', () async {
    final bridge = await _bridge(['storage']);
    await bridge.invoke('storage.setJSON', {
      'key': 'list',
      'value': [1, 2],
    });
    expect(await bridge.invoke('storage.getJSON', {'key': 'list'}), [1, 2]);
    expect(
      await bridge.invoke('storage.getJSON', {
        'key': 'missing',
        'fallback': ['fb'],
      }),
      ['fb'],
    );
    await bridge.storage.set('raw', 'not-json');
    expect(
      await bridge.invoke('storage.getJSON', {'key': 'raw', 'fallback': 'fb'}),
      'fb',
    );
  });

  test('bridge ui navigate log version env pass through stub host', () async {
    final host = _StubHost();
    final bridge = await _bridge([
      'storage',
      'ui',
      'navigation',
      'network',
    ], host: host);
    await bridge.invoke('ui.toast', {'message': 'hi'});
    await bridge.invoke('ui.loading', {'message': 'wait'});
    await bridge.invoke('ui.hideLoading', {});
    expect(
      await bridge.invoke('ui.actionSheet', {
        'items': ['a', 'b', 'c'],
      }),
      2,
    );
    expect(host.lastOptions, ['a', 'b', 'c']);
    expect(await bridge.invoke('navigateTo', {'url': 'detail.html'}), {
      'url': 'detail.html',
      'opened': true,
    });
    expect(host.lastUrl, 'detail.html');
    expect(await bridge.invoke('navigateBack', {}), {'moved': true});
    expect(await bridge.invoke('log', {'message': 'hello'}), isTrue);
    expect(await bridge.invoke('version', {}), 2);
    final info = await bridge.invoke('getSystemInfo', {}) as Map;
    expect(info['version'], 2);
    expect(info['sdkVersion'], 2);
    expect(info['appId'], 'bridge');
    expect(info['permissions'], contains('ui'));
    final env = await bridge.invoke('env.getSystemInfo', {}) as Map;
    expect(env['sdkVersion'], 2);
    expect(host.calls, containsAll(['ui.toast:hi', 'ui.loading:wait']));
  });

  test('bridge source and player pass params through stub host', () async {
    final host = _StubHost();
    final bridge = await _bridge(['source', 'player'], host: host);
    final list = await bridge.invoke('source.list', {});
    expect((list as List).single['key'], 'custom:x');
    await bridge.invoke('source.home', {'source': 'custom:x'});
    expect(host.lastParams, {'source': 'custom:x'});
    await bridge.invoke('source.detail', {'source': 'custom:x', 'id': 'v1'});
    expect(host.lastParams, {'source': 'custom:x', 'id': 'v1'});
    await bridge.invoke('player.open', {'url': 'https://x/y.m3u8'});
    expect(host.lastParams, {'url': 'https://x/y.m3u8'});
    expect(host.calls, contains('player.open'));
  });

  test('bridge denies deferred apis with not-provided message', () async {
    final bridge = await _bridge([
      'service',
      'miniapp',
      'player',
      'source',
      'network',
    ]);
    await expectLater(
      bridge.invoke('serve', {}),
      throwsA(
        isA<MiniAppDenied>().having(
          (error) => error.message,
          'message',
          contains('本版未提供'),
        ),
      ),
    );
    await expectLater(
      bridge.invoke('miniApp.exitMiniApp', {}),
      throwsA(
        isA<MiniAppDenied>().having(
          (error) => error.message,
          'message',
          contains('本版未提供'),
        ),
      ),
    );
    await expectLater(
      bridge.invoke('player.getState', {}),
      throwsA(
        isA<MiniAppDenied>().having(
          (error) => error.message,
          'message',
          contains('本版未提供'),
        ),
      ),
    );
    await expectLater(
      bridge.invoke('clipboard.get', {}),
      throwsA(
        isA<MiniAppDenied>().having(
          (error) => error.message,
          'message',
          contains('本版未提供'),
        ),
      ),
    );
    await expectLater(
      bridge.invoke('requestBytes', {'url': 'https://example.org/x'}),
      throwsA(
        isA<MiniAppDenied>().having(
          (error) => error.message,
          'message',
          contains('本版未提供'),
        ),
      ),
    );
    await expectLater(
      bridge.invoke('source.play', {}),
      throwsA(
        isA<MiniAppDenied>().having(
          (error) => error.message,
          'message',
          contains('本版未提供'),
        ),
      ),
    );
    await expectLater(
      bridge.invoke('request', {'url': 'miniapp://svc/api'}),
      throwsA(
        isA<MiniAppDenied>().having(
          (error) => error.message,
          'message',
          contains('本版未提供'),
        ),
      ),
    );
    await expectLater(
      bridge.invoke('nope.thing', {}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('bridge still denies undeclared permissions and missing host', () async {
    final bridge = await _bridge(['network']);
    await expectLater(
      bridge.invoke('storage.get', {'key': 'k'}),
      throwsA(isA<MiniAppDenied>()),
    );
    await expectLater(
      bridge.invoke('ui.toast', {'message': 'x'}),
      throwsA(isA<MiniAppDenied>()),
    );
    final noHost = await _bridge(['ui']);
    await expectLater(
      noHost.invoke('ui.toast', {'message': 'x'}),
      throwsA(
        isA<MiniAppDenied>().having(
          (error) => error.message,
          'message',
          contains('ui is not available'),
        ),
      ),
    );
  });

  test('bootstrap injects before existing scripts', () {
    const script = 'window.ant = 1;';
    final withHead = injectMiniAppBootstrap(
      '<html><head><title>t</title><script>old();</script></head><body></body></html>',
      script,
    );
    expect(withHead.indexOf('<script>window.ant = 1;</script>'), isNot(-1));
    expect(
      withHead.indexOf('<script>window.ant = 1;</script>'),
      lessThan(withHead.indexOf('<script>old();</script>')),
    );
    final headAttrs = injectMiniAppBootstrap(
      '<html><head lang="x"><script>old();</script></head></html>',
      script,
    );
    expect(headAttrs.indexOf(script), lessThan(headAttrs.indexOf('old();')));
    final noHead = injectMiniAppBootstrap(
      '<html><body>x</body></html>',
      script,
    );
    expect(noHead.startsWith('<html><script>window.ant = 1;</script>'), isTrue);
    final bare = injectMiniAppBootstrap('plain', script);
    expect(bare.startsWith('<script>window.ant = 1;</script>'), isTrue);
  });

  test('market settings record market app id to manifest id', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = MarketSettings(prefs);
    expect(settings.installedIdMap, isEmpty);
    await settings.recordInstalled('com.leospring.emby', 'com.ant.emby');
    await settings.recordInstalled('com.example.one', 'com.example.one');
    expect(settings.installedIdMap, {
      'com.leospring.emby': 'com.ant.emby',
      'com.example.one': 'com.example.one',
    });
    await prefs.setString('miniapp.marketInstalledMap', 'not-json');
    expect(settings.installedIdMap, isEmpty);
  });

  test('installer keeps deferred and unknown permissions after reload', () async {
    final root = await Directory.systemTemp.createTemp('jhminiapp_bridge_');
    try {
      final installer = MiniAppInstaller(root);
      final serviceZip = ZipEncoder().encode(
        Archive()
          ..add(
            ArchiveFile.string(
              'manifest.json',
              '{"id":"svc","name":"服务","entry":"index.html","permissions":["ui","service"]}',
            ),
          )
          ..add(ArchiveFile.string('index.html', '<h1>hi</h1>')),
      );
      final svc = await installer.installFromZip(serviceZip);
      expect(svc.permissions, contains('service'));
      expect(svc.unavailablePermissions, ['service']);
      final reloaded = await installer.load(installer.directoryFor('svc'));
      expect(reloaded.permissions, contains('service'));
      expect(reloaded.unavailablePermissions, ['service']);
      final unknownZip = ZipEncoder().encode(
        Archive()
          ..add(
            ArchiveFile.string(
              'manifest.json',
              '{"id":"unk","name":"未知","entry":"index.html","permissions":["root"]}',
            ),
          )
          ..add(ArchiveFile.string('index.html', '<h1>hi</h1>')),
      );
      final unk = await installer.installFromZip(unknownZip);
      expect(unk.permissions, isEmpty);
      expect(unk.unsupportedPermissions, ['root']);
      final unkReloaded = await installer.load(installer.directoryFor('unk'));
      expect(unkReloaded.unsupportedPermissions, ['root']);
      expect(unkReloaded.unavailablePermissions, ['root']);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('vod and midnight predicates split by origin', () {
    SourceSite site(String id, String section, String origin, String type) =>
        SourceSite(
          id,
          id,
          '',
          section: section,
          origin: origin,
          importType: type,
        );
    final cases = [
      (site('v1', 'video', 'builtin', ''), false, true),
      (site('cfg', 'video', 'config', ''), true, false),
      (site('py', 'video', 'import', 'py'), true, false),
      (site('js', 'video', 'import', 'js'), false, false),
      (site('bd', 'drama', 'builtin', ''), false, false),
      (site('cd', 'drama', 'config', ''), false, false),
    ];
    for (final entry in cases) {
      expect(isVodZoneSource(entry.$1), entry.$2, reason: entry.$1.id);
      expect(isMidnightZoneSource(entry.$1), entry.$3, reason: entry.$1.id);
    }
  });
}
