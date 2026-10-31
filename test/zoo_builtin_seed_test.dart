import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
  test('builtin config seed data is empty after builtin removal', () {
    final decoded = jsonDecode(zooBuiltinConfigsJson);
    expect(decoded, isA<List>());
    expect((decoded as List), isEmpty);
    expect(ZooBuiltinSeeder.dataConfigs(), isEmpty);
  });

  test('builtin config predicate covers zoo and luna seeds', () {
    expect(ZooBuiltinSeeder.isBuiltinConfig('zoo_abcdef123456'), isTrue);
    expect(ZooBuiltinSeeder.isBuiltinConfig('luna_abcdef123456'), isTrue);
    expect(ZooBuiltinSeeder.isBuiltinConfig('a1b2c3d4e5f6'), isFalse);
    expect(ZooBuiltinSeeder.dataConfigs().length, 0);
  });
}
