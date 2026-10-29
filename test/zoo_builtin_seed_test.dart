import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:duanju_app/jar_bridge.dart';
import 'package:duanju_app/zoo_builtin_data.dart';
import 'package:duanju_app/zoo_builtin_seed.dart';

const _credentialKeys = {
  'password',
  'passwd',
  'pwd',
  'secret',
  'api_key',
  'apikey',
  'access_key',
  'accesskey',
  'auth',
  'token',
  'cookie',
  'session',
  'account',
  'username',
  'phone',
};

void _checkNoCredentials(dynamic node, List<String> path) {
  if (node is Map) {
    for (final entry in node.entries) {
      final key = entry.key.toString().toLowerCase();
      final value = entry.value;
      if (_credentialKeys.contains(key) &&
          value is String &&
          value.isNotEmpty &&
          !value.contains('{')) {
        fail('credential value kept at ${[...path, entry.key].join('/')}');
      }
      _checkNoCredentials(value, [...path, entry.key.toString()]);
    }
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      _checkNoCredentials(node[i], [...path, '$i']);
    }
  }
}

void main() {
  test('builtin config seed data invariants', () {
    final decoded = jsonDecode(zooBuiltinConfigsJson);
    expect(decoded, isA<List>());
    final configs = decoded as List;
    expect(configs.length, 18);

    var total = 0;
    final kinds = <String, int>{};
    final pyUrls = <String>{};
    final jarKeys = <String>{};
    final apiIds = <String>{};
    var zooConfigs = 0;
    var lunaConfigs = 0;

    for (final row in configs) {
      final config = row as Map<String, dynamic>;
      final configId = config['configId'] as String;
      expect(
        configId.startsWith('zoo_') || configId.startsWith('luna_'),
        isTrue,
        reason: 'configId $configId has unexpected prefix',
      );
      if (configId.startsWith('zoo_')) {
        zooConfigs++;
      } else {
        lunaConfigs++;
      }
      expect((config['name'] as String).isNotEmpty, isTrue);
      expect((config['url'] as String).startsWith('http'), isTrue);
      final sites = config['sites'] as List;
      for (final siteRow in sites) {
        final site = siteRow as Map<String, dynamic>;
        total++;
        final kind = site['kind'] as String;
        kinds[kind] = (kinds[kind] ?? 0) + 1;
        expect((site['name'] as String).isNotEmpty, isTrue);
        switch (kind) {
          case 'py':
            expect((site['siteId'] as String).isNotEmpty, isTrue);
            expect((site['remoteUrl'] as String).startsWith('http'), isTrue);
            expect(
              pyUrls.add(site['remoteUrl'] as String),
              isTrue,
              reason: 'duplicate py url ${site['remoteUrl']}',
            );
          case 'jar':
            expect((site['siteId'] as String).isNotEmpty, isTrue);
            expect((site['className'] as String).isNotEmpty, isTrue);
            expect((site['jarUrl'] as String).isNotEmpty, isTrue);
            expect(
              jarKeys.add('${site['className']}@${site['jarUrl']}'),
              isTrue,
              reason: 'duplicate jar ${site['className']}@${site['jarUrl']}',
            );
          case 'api':
            expect((site['coreId'] as String).startsWith('custom:'), isTrue);
            expect((site['coreId'] as String).length, 'custom:'.length + 16);
            expect((site['base'] as String).startsWith('http'), isTrue);
            expect(
              apiIds.add(site['coreId'] as String),
              isTrue,
              reason: 'duplicate api coreId ${site['coreId']}',
            );
          default:
            fail('unexpected kind $kind');
        }
        final ext = site['ext'] as String? ?? '';
        if (ext.startsWith('{')) {
          try {
            _checkNoCredentials(jsonDecode(ext), ['ext']);
          } catch (_) {}
        }
      }
    }

    expect(total, 914);
    expect(kinds, {'jar': 717, 'api': 146, 'py': 51});
    expect(zooConfigs, 17);
    expect(lunaConfigs, 1);
  });

  test('builtin config predicate covers zoo and luna seeds', () {
    expect(ZooBuiltinSeeder.isBuiltinConfig('zoo_abcdef123456'), isTrue);
    expect(ZooBuiltinSeeder.isBuiltinConfig('luna_abcdef123456'), isTrue);
    expect(ZooBuiltinSeeder.isBuiltinConfig('a1b2c3d4e5f6'), isFalse);
    expect(ZooBuiltinSeeder.dataConfigs().length, 18);
  });

  test('dead jar urls are gone from seed data', () {
    for (final config in ZooBuiltinSeeder.dataConfigs()) {
      final sites = config['sites'] as List;
      for (final site in sites) {
        final row = site as Map;
        if (row['kind'] == 'jar') {
          expect(
            ZooBuiltinSeeder.deadJarUrls.contains(row['jarUrl']),
            isFalse,
            reason: 'dead jar still seeded: ${row['key']}',
          );
        }
      }
    }
  });

  test('jar cache key separates urls within one config', () {
    expect(
      JarBridge.jarCacheKey('zoo_x', 'https://example.com/a.jar'),
      isNot(
        equals(JarBridge.jarCacheKey('zoo_x', 'https://example.com/b.jar')),
      ),
    );
    expect(
      JarBridge.jarCacheKey('zoo_x', 'https://example.com/a.jar'),
      JarBridge.jarCacheKey('zoo_x', 'https://example.com/a.jar'),
    );
    expect(
      JarBridge.jarCacheKey('zoo_x', 'https://example.com/a.jar'),
      isNot(
        equals(JarBridge.jarCacheKey('zoo_y', 'https://example.com/a.jar')),
      ),
    );
  });
}
