import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duanju_app/tgdrama_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<TgdramaService> created;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tgdrama_test_');
    created = [];
  });

  tearDown(() async {
    for (final service in created) {
      await service.stop();
      service.dispose();
    }
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {}
  });

  Future<ByteData> realBinaryBytes(String assetPath) async {
    if (assetPath == TgdramaService.sessionAssetPath) {
      const fakeSession =
          '{"Version":1,"Data":{"Config":{},"DC":5,"Addr":"1.2.3.4:443",'
          '"AuthKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",'
          '"AuthKeyID":"AAAAAAAAAAA=","Salt":0}}';
      return ByteData.view(Uint8List.fromList(utf8.encode(fakeSession)).buffer);
    }
    expect(assetPath, TgdramaService.binaryAssetPath);
    final bytes = await File(assetPath).readAsBytes();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  TgdramaService createService({
    required MockClient client,
    _FakeProcess Function()? processFactory,
    Future<ByteData> Function(String assetPath)? assetLoader,
    bool Function()? isAndroidProvider,
  }) {
    final launches = <List<String>>[];
    final service = TgdramaService(
      httpClient: client,
      processLauncher: (command) async {
        launches.add(List<String>.from(command));
        return processFactory?.call() ?? _FakeProcess();
      },
      supportDirProvider: () async => tempDir,
      isAndroidProvider: isAndroidProvider ?? () => true,
      assetLoader: assetLoader ?? realBinaryBytes,
    );
    serviceLaunches[service] = launches;
    created.add(service);
    return service;
  }

  MockClient clientFor({
    int healthStatus = 200,
    Map<String, dynamic>? authBody,
    int authStatusCode = 200,
    int qrStatus = 200,
    int passwordStatus = 200,
    Map<String, dynamic>? passwordBody,
  }) {
    return MockClient((http.Request request) async {
      final path = request.url.path;
      if (path == '/') {
        return http.Response('', healthStatus);
      }
      if (path == '/api/auth/status') {
        return http.Response(
          jsonEncode(authBody ?? {'authorized': true}),
          authStatusCode,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/api/auth/qr') {
        return http.Response('', qrStatus);
      }
      if (path == '/api/auth/password') {
        return http.Response.bytes(
          utf8.encode(jsonEncode(passwordBody ?? {'ok': true})),
          passwordStatus,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('not found', 404);
    });
  }

  test('未启动时 ensureRunning 解压+chmod+启动+健康检查通过，第二次不再重复启动', () async {
    final service = createService(client: clientFor());
    expect(await service.ensureRunning(), isTrue);
    expect(service.isRunning, isTrue);
    expect(service.lastError, isNull);

    final launches = serviceLaunches[service]!;
    expect(launches.length, 1);
    final binaryPath = '${tempDir.path}/tgdrama/tgdrama-android';
    expect(launches.single, [
      binaryPath,
      '-port',
      '5278',
      '-bind',
      '127.0.0.1',
    ]);

    final binaryFile = File(binaryPath);
    expect(await binaryFile.exists(), isTrue);
    expect(
      md5.convert(await binaryFile.readAsBytes()).toString(),
      TgdramaService.binaryMd5,
    );

    expect(await service.ensureRunning(), isTrue);
    expect(launches.length, 1);
  });

  test('已落盘且 MD5 对得上时复用，不重拷；对不上重拷自愈', () async {
    var binaryLoads = 0;
    var sessionLoads = 0;
    Future<ByteData> countingLoader(String assetPath) async {
      if (assetPath == TgdramaService.sessionAssetPath) {
        sessionLoads++;
      } else {
        binaryLoads++;
      }
      return realBinaryBytes(assetPath);
    }

    final dir = Directory('${tempDir.path}/tgdrama');
    await dir.create(recursive: true);
    await File('${dir.path}/tgdrama-android').writeAsBytes([1, 2, 3]);

    final service = createService(
      client: clientFor(),
      assetLoader: countingLoader,
    );
    expect(await service.ensureRunning(), isTrue);
    expect(binaryLoads, 1);
    expect(sessionLoads, 1);
    expect(
      md5
          .convert(await File('${dir.path}/tgdrama-android').readAsBytes())
          .toString(),
      TgdramaService.binaryMd5,
    );

    final second = createService(
      client: clientFor(),
      assetLoader: countingLoader,
    );
    expect(await second.ensureRunning(), isTrue);
    expect(binaryLoads, 1);
    expect(sessionLoads, 1);
  });

  test('首次启动把预置 session.json 写进插件目录，已有会话不覆盖', () async {
    final service = createService(client: clientFor());
    expect(await service.ensureRunning(), isTrue);
    final sessionFile = File('${tempDir.path}/tgdrama/session.json');
    expect(await sessionFile.exists(), isTrue);
    final written = await sessionFile.readAsString();
    expect(written, contains('"Version":1'));
    expect(written, contains('"DC":5'));

    await sessionFile.writeAsBytes([7, 7, 7]);
    final second = createService(client: clientFor());
    expect(await second.ensureRunning(), isTrue);
    expect(await sessionFile.readAsBytes(), [7, 7, 7]);
  });

  test('包里没有预置会话时启动仍成功（best-effort，不拦插件）', () async {
    Future<ByteData> noSessionLoader(String assetPath) async {
      if (assetPath == TgdramaService.sessionAssetPath) {
        throw StateError('no session asset');
      }
      return realBinaryBytes(assetPath);
    }

    final service = createService(
      client: clientFor(),
      assetLoader: noSessionLoader,
    );
    expect(await service.ensureRunning(), isTrue);
    expect(
      await File('${tempDir.path}/tgdrama/session.json').exists(),
      isFalse,
    );
  });

  test('普通版占位会话不写入：asset 是 {} 时不产生 session.json', () async {
    Future<ByteData> placeholderLoader(String assetPath) async {
      if (assetPath == TgdramaService.sessionAssetPath) {
        return ByteData.view(Uint8List.fromList(utf8.encode('{}')).buffer);
      }
      return realBinaryBytes(assetPath);
    }

    final service = createService(
      client: clientFor(),
      assetLoader: placeholderLoader,
    );
    expect(await service.ensureRunning(), isTrue);
    expect(
      await File('${tempDir.path}/tgdrama/session.json').exists(),
      isFalse,
    );
  });

  test('健康检查一直失败回 false 且 lastError 有内容', () async {
    final service = createService(client: clientFor(healthStatus: 500));
    expect(await service.ensureRunning(), isFalse);
    expect(service.lastError, isNotNull);
    expect(service.lastError, isNotEmpty);
    expect(serviceLaunches[service]!.length, 1);
  });

  test('进程启动后立刻退出回 false 且 lastError 说明进程已退出', () async {
    final process = _FakeProcess();
    final service = createService(
      client: clientFor(healthStatus: 500),
      processFactory: () => process,
    );
    final running = service.ensureRunning();
    process.exitNow(1);
    expect(await running, isFalse);
    expect(service.lastError, contains('已退出'));
  });

  test('非 Android 直接回 false，lastError 写明仅支持 Android，不拉进程', () async {
    final service = createService(
      client: clientFor(),
      isAndroidProvider: () => false,
    );
    expect(await service.ensureRunning(), isFalse);
    expect(service.lastError, contains('仅支持 Android'));
    expect(serviceLaunches[service], isEmpty);
  });

  test('authStatus 多键解析：authorized 各形状都算已登录', () async {
    const bodies = [
      {'authorized': true},
      {'logged_in': true},
      {'loggedIn': true},
      {'authenticated': true},
      {'is_authorized': true},
      {'status': 'authorized'},
      {'status': 'ok'},
      {'status': 'logged_in'},
      {'phase': 'authorized'},
      {'state': 'logged_in'},
    ];
    for (final body in bodies) {
      final service = createService(client: clientFor(authBody: body));
      final status = await service.authStatus();
      expect(status.authorized, isTrue, reason: '$body');
      expect(status.needPassword, isFalse, reason: '$body');
    }
  });

  test('authStatus 多键解析：need_password 各形状都算需二步验证', () async {
    const bodies = [
      {'need_password': true},
      {'needPassword': true},
      {'password_required': true},
      {'status': 'need_password'},
      {'status': 'password'},
      {'phase': 'password_required'},
    ];
    for (final body in bodies) {
      final service = createService(client: clientFor(authBody: body));
      final status = await service.authStatus();
      expect(status.needPassword, isTrue, reason: '$body');
      expect(status.authorized, isFalse, reason: '$body');
    }
  });

  test('authStatus 未登录/解析失败/非 200 都按未登录回，不抛异常', () async {
    final empty = createService(client: clientFor(authBody: {}));
    final emptyStatus = await empty.authStatus();
    expect(emptyStatus.authorized, isFalse);
    expect(emptyStatus.needPassword, isFalse);

    final denied = createService(
      client: clientFor(authBody: {'authorized': false}),
    );
    expect((await denied.authStatus()).authorized, isFalse);

    final httpError = createService(
      client: clientFor(authStatusCode: 500, authBody: {'authorized': true}),
    );
    final httpErrorStatus = await httpError.authStatus();
    expect(httpErrorStatus.authorized, isFalse);
    expect(httpErrorStatus.message, contains('500'));

    final badJson = createService(
      client: MockClient((_) async => http.Response('not json', 200)),
    );
    expect((await badJson.authStatus()).authorized, isFalse);
  });

  test('submitPassword 非 200 抛 StateError，带状态码与服务端 message', () async {
    final service = createService(
      client: clientFor(passwordStatus: 401, passwordBody: {'message': '密码错误'}),
    );
    await expectLater(
      service.submitPassword('wrong'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('401'), contains('密码错误')),
        ),
      ),
    );
  });

  test('submitPassword 200 正常返回；startQrLogin 200 成功、非 200 抛错', () async {
    final service = createService(client: clientFor());
    await service.submitPassword('correct');
    await service.startQrLogin();

    final failing = createService(client: clientFor(qrStatus: 503));
    await expectLater(
      failing.startQrLogin(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('503'),
        ),
      ),
    );
  });

  test('stop 杀掉已启动的进程，isRunning 变 false', () async {
    final process = _FakeProcess();
    final service = createService(
      client: clientFor(),
      processFactory: () => process,
    );
    expect(await service.ensureRunning(), isTrue);
    expect(service.isRunning, isTrue);
    await service.stop();
    expect(process.killed, isTrue);
    expect(service.isRunning, isFalse);
  });

  test('stop 在未启动时什么也不做；qrImageUrl 拼对地址', () async {
    final service = createService(client: clientFor());
    await service.stop();
    expect(service.isRunning, isFalse);
    expect(service.qrImageUrl, '${TgdramaService.baseUrl}/api/auth/qr.png');
    expect(TgdramaService.baseUrl, 'http://127.0.0.1:5278');
    expect(TgdramaService.defaultPort, 5278);
  });
}

final Map<TgdramaService, List<List<String>>> serviceLaunches = {};

class _FakeProcess implements Process {
  _FakeProcess();

  final Completer<int> _exitCode = Completer<int>();
  bool killed = false;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => IOSink(StreamController<List<int>>());

  @override
  int get pid => 12345;

  @override
  Future<int> get exitCode => _exitCode.future;

  void exitNow(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    exitNow(-signal.hashCode);
    return true;
  }
}
