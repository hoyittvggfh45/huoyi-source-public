import 'dart:convert';
import 'dart:io';

import 'package:duanju_app/service_center.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults point at duoju on 5689', () {
    final config = DuojuServiceConfig.defaults();
    expect(config.name, 'duoju');
    expect(config.port, 5689);
    expect(config.bind, '127.0.0.1');
    expect(config.runtime, 'Node.js');
    expect(config.webUrl, 'http://127.0.0.1:5689/');
    expect(config.followApp, isTrue);
    expect(config.lifecycleLabel, '跟随 app');
    expect(config.copyWith(followApp: false).lifecycleLabel, '常驻前台');
  });

  test('config json round-trips', () {
    final config = DuojuServiceConfig.defaults().copyWith(
      port: 5690,
      description: 'test',
      autoStart: true,
    );
    final restored = DuojuServiceConfig.fromJson(
      jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
    );
    expect(restored.port, 5690);
    expect(restored.description, 'test');
    expect(restored.autoStart, isTrue);
    expect(restored.name, 'duoju');
  });

  test('config fromJson falls back on bad values', () {
    final restored = DuojuServiceConfig.fromJson({
      'name': '',
      'port': 'not-a-port',
    });
    expect(restored.name, 'duoju');
    expect(restored.port, 5689);
  });

  test('service log caps at 100 entries', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < 105; i++) {
      await DuojuServiceStore.appendLog(prefs, 'entry $i');
    }
    final entries = DuojuServiceStore.readLog(prefs);
    expect(entries.length, 100);
    expect(entries.first.text, 'entry 5');
    expect(entries.last.text, 'entry 104');
    await DuojuServiceStore.clearLog(prefs);
    expect(DuojuServiceStore.readLog(prefs), isEmpty);
  });

  test('probe reports a listening port as running', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final result = await probeDuojuService(
        host: '127.0.0.1',
        port: server.port,
      );
      expect(result.running, isTrue);
    } finally {
      await server.close();
    }
  });

  test('probe reports a closed port as stopped', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    final result = await probeDuojuService(host: '127.0.0.1', port: port);
    expect(result.running, isFalse);
  });
}
