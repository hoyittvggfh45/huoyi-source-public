import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duanju_app/miniapp/bridge.dart';
import 'package:duanju_app/miniapp/manifest.dart';
import 'package:duanju_app/miniapp/permissions.dart';
import 'package:duanju_app/miniapp/service_manager.dart';
import 'package:duanju_app/miniapp/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MiniAppManifest _manifest({List<String> permissions = const ['network']}) =>
    MiniAppManifest(
      id: 'svc',
      name: '服务示例',
      version: '1.0.0',
      versionCode: 1,
      renderer: 'webview',
      entry: 'index.html',
      description: '',
      permissions: permissions,
      networkAllowlist: const [],
    );

Future<MiniAppBridge> _bridge({
  MiniAppServiceManager? services,
  List<String> permissions = const ['network'],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return MiniAppBridge(
    manifest: _manifest(permissions: permissions),
    storage: MiniAppStorage(prefs, 'svc'),
    serviceManager: services,
  );
}

MiniAppServiceRequest _request({String path = '/', String method = 'GET'}) =>
    MiniAppServiceRequest(
      method: method,
      path: path,
      query: const {},
      params: const {},
      headers: const {},
      body: const [],
      url: 'miniapp://svc$path',
    );

void main() {
  test('handler result mapping covers null, string, map and base64', () {
    expect(
      MiniAppServiceResponse.fromHandlerResult(null)?.status,
      503,
    );
    final text = MiniAppServiceResponse.fromHandlerResult('hello')!;
    expect(text.status, 200);
    expect(utf8.decode(text.body), 'hello');
    final mapped = MiniAppServiceResponse.fromHandlerResult({
      'status': 201,
      'headers': {'Content-Type': 'application/json'},
      'body': '{"ok":true}',
    })!;
    expect(mapped.status, 201);
    expect(utf8.decode(mapped.body), '{"ok":true}');
    final binary = MiniAppServiceResponse.fromHandlerResult({
      'bodyBase64': base64Encode([1, 2, 3]),
    })!;
    expect(binary.body, [1, 2, 3]);
    expect(
      MiniAppServiceResponse.fromHandlerResult({'bodyBase64': '!!!'})?.status,
      502,
    );
    expect(MiniAppServiceResponse.fromHandlerResult(42)?.status, 502);
  });

  test('registration caps at three and evicts least recently used', () async {
    final manager = MiniAppServiceManager();
    Future<MiniAppServiceResponse?> handler(
      MiniAppServiceRequest request,
    ) async => MiniAppServiceResponse.text('ok');
    await manager.register('a', handler);
    await manager.register('b', handler);
    await manager.register('c', handler);
    await manager.dispatchLocal('a', _request());
    await manager.register('d', handler);
    expect(manager.isRegistered('a'), isTrue);
    expect(manager.isRegistered('b'), isFalse);
    expect(manager.isRegistered('c'), isTrue);
    expect(manager.isRegistered('d'), isTrue);
    await manager.stop();
  });

  test('token stays stable across re-registration within one launch', () async {
    final manager = MiniAppServiceManager();
    Future<MiniAppServiceResponse?> handler(
      MiniAppServiceRequest request,
    ) async => MiniAppServiceResponse.text('ok');
    final first = await manager.register('svc', handler);
    manager.unregister(first.registrationId);
    final second = await manager.register('svc', handler);
    expect(second.token, first.token);
    await manager.stop();
  });

  test('dispatch maps null, throw, timeout and oversize bodies', () async {
    final manager = MiniAppServiceManager(
      callTimeout: const Duration(milliseconds: 100),
      maxBodyBytes: 20,
      maxInstances: 4,
    );
    await manager.register(
      'null',
      (_) async => null,
    );
    await manager.register(
      'boom',
      (_) async => throw StateError('boom'),
    );
    await manager.register(
      'slow',
      (_) => Completer<MiniAppServiceResponse?>().future,
    );
    await manager.register(
      'big',
      (_) async => MiniAppServiceResponse.text('1234567890123456789012345'),
    );
    expect(
      (await manager.dispatchLocal('null', _request()))?.status,
      503,
    );
    expect(
      (await manager.dispatchLocal('boom', _request()))?.status,
      503,
    );
    expect(
      (await manager.dispatchLocal('slow', _request()))?.status,
      504,
    );
    expect(
      (await manager.dispatchLocal('big', _request()))?.status,
      502,
    );
    expect(await manager.dispatchLocal('ghost', _request()), isNull);
    await manager.stop();
  });

  test('private ip gate accepts lan ranges and rejects public ips', () {
    expect(
      MiniAppServiceManager.isPrivateOrLoopbackIp(
        InternetAddress.loopbackIPv4,
      ),
      isTrue,
    );
    expect(
      MiniAppServiceManager.isPrivateOrLoopbackIp(
        InternetAddress('192.168.1.5'),
      ),
      isTrue,
    );
    expect(
      MiniAppServiceManager.isPrivateOrLoopbackIp(
        InternetAddress('10.0.0.1'),
      ),
      isTrue,
    );
    expect(
      MiniAppServiceManager.isPrivateOrLoopbackIp(
        InternetAddress('172.16.0.1'),
      ),
      isTrue,
    );
    expect(
      MiniAppServiceManager.isPrivateOrLoopbackIp(
        InternetAddress('172.32.0.1'),
      ),
      isFalse,
    );
    expect(
      MiniAppServiceManager.isPrivateOrLoopbackIp(
        InternetAddress('8.8.8.8'),
      ),
      isFalse,
    );
    expect(
      MiniAppServiceManager.isPrivateOrLoopbackIp(
        InternetAddress('169.254.1.1'),
      ),
      isTrue,
    );
  });

  test('http surface enforces token, unknown app and prefix', () async {
    final manager = MiniAppServiceManager();
    final instance = await manager.register(
      'svc',
      (request) async => MiniAppServiceResponse.json({
        'path': request.path,
      }),
    );
    final port = manager.port!;
    final client = HttpClient();
    try {
      Future<(int, String)> get(String path, {String? token}) async {
        final uri = Uri.parse('http://127.0.0.1:$port$path');
        final request = await client.getUrl(
          token == null ? uri : uri.replace(queryParameters: {'token': token}),
        );
        final response = await request.close();
        final body = await response.fold<List<int>>(
          [],
          (acc, chunk) => acc..addAll(chunk),
        );
        return (response.statusCode, utf8.decode(body));
      }

      final ok = await get('/miniapp/svc/hello', token: instance.token);
      expect(ok.$1, 200);
      expect(jsonDecode(ok.$2)['path'], '/hello');
      final wrong = await get('/miniapp/svc/hello', token: 'nope');
      expect(wrong.$1, 403);
      final missing = await get('/miniapp/svc/hello');
      expect(missing.$1, 403);
      final ghost = await get('/miniapp/ghost/hello', token: 'x');
      expect(ghost.$1, 503);
      final badPrefix = await get('/other/svc/hello', token: 'x');
      expect(badPrefix.$1, 404);
    } finally {
      client.close();
      await manager.stop();
    }
  });

  test('bridge serve registers only with the service permission', () async {
    var registered = false;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final bridge = MiniAppBridge(
      manifest: _manifest(permissions: const ['service']),
      storage: MiniAppStorage(prefs, 'svc'),
      onServeRegistered: () => registered = true,
    );
    final result = await bridge.invoke('serve', {});
    expect((result as Map)['registered'], isTrue);
    expect(registered, isTrue);

    final denied = await _bridge(permissions: const ['network']);
    await expectLater(
      denied.invoke('serve', {}),
      throwsA(isA<MiniAppDenied>()),
    );
  });

  test('bridge resolves miniapp scheme through the manager', () async {
    final manager = MiniAppServiceManager();
    await manager.register(
      'svc',
      (request) async => MiniAppServiceResponse.json({
        'path': request.path,
        'query': request.query,
      }),
    );
    final bridge = await _bridge(services: manager);
    final result = await bridge.invoke('request', {
      'url': 'miniapp://svc/hello?x=1',
      'responseType': 'json',
    });
    final data = (result as Map)['data'] as Map;
    expect(data['path'], '/hello');
    expect(data['query'], {'x': '1'});

    final stopped = await _bridge(services: manager);
    manager.unregisterApp('svc');
    await expectLater(
      stopped.invoke('request', {
        'url': 'miniapp://svc/hello',
        'responseType': 'text',
      }),
      throwsA(isA<MiniAppDenied>()),
    );
    await manager.stop();
  });
}
