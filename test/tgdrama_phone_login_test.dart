import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:duanju_app/tgdrama_phone_login.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tgdrama_phone_login_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  TgdramaPhoneLoginService serviceWith({
    Future<ByteData> Function(String assetPath)? assetLoader,
    Future<ProcessResult> Function(String executable, List<String> args)?
    runProcess,
    String? bundledApiId,
    String? bundledApiHash,
  }) {
    return TgdramaPhoneLoginService(
      supportDir: tempDir,
      assetLoader:
          assetLoader ?? (_) async => throw StateError('no asset in test'),
      runProcess: runProcess,
      bundledApiId: bundledApiId,
      bundledApiHash: bundledApiHash,
    );
  }

  Future<void> putHelper() async {
    final file = File('${tempDir.path}/tgdrama/tgphone');
    await file.create(recursive: true);
    await file.writeAsString('fake-helper');
  }

  Future<void> putConfig(String content) async {
    final file = File('${tempDir.path}/tgdrama/config.yaml');
    await file.create(recursive: true);
    await file.writeAsString(content);
  }

  group('checkAvailability', () {
    test('助手不存在时不可用，reason 非空且点出助手未就绪', () async {
      final service = serviceWith();
      final result = await service.checkAvailability();
      expect(result.available, isFalse);
      expect(result.reason, isNotEmpty);
      expect(result.reason, contains('tgphone 未安装'));
    });

    test('助手在但 config 不存在时不可用', () async {
      await putHelper();
      final service = serviceWith();
      final result = await service.checkAvailability();
      expect(result.available, isFalse);
      expect(result.reason, contains('Telegram API 凭证'));
    });

    test('config 里没有 api_id/api_hash 时不可用', () async {
      await putHelper();
      await putConfig('telegram:\n  api_id: ""\n  api_hash: ""\n');
      final service = serviceWith();
      final result = await service.checkAvailability();
      expect(result.available, isFalse);
      expect(result.reason, contains('api_id'));
    });

    test('助手在且 config 里有凭证时可用', () async {
      await putHelper();
      await putConfig(
        'telegram:\n  api_id: 123456\n  api_hash: 0123456789abcdef0123456789abcdef\n',
      );
      final service = serviceWith();
      final result = await service.checkAvailability();
      expect(result.available, isTrue);
    });
  });

  group('ensureReady', () {
    test('asset 里有助手 + 注入凭证时，解出助手、写好 config，变可用', () async {
      final service = serviceWith(
        assetLoader: (_) async =>
            ByteData.view(Uint8List.fromList([1, 2, 3, 4]).buffer),
        bundledApiId: '123456',
        bundledApiHash: 'abcdef0123456789abcdef0123456789',
      );
      final ready = await service.ensureReady();
      expect(ready, isTrue);
      final helper = File('${tempDir.path}/tgdrama/tgphone');
      expect(await helper.exists(), isTrue);
      expect(await helper.readAsBytes(), [1, 2, 3, 4]);
      final config = File('${tempDir.path}/tgdrama/config.yaml');
      expect(await config.exists(), isTrue);
      final text = await config.readAsString();
      expect(text, contains('api_id: 123456'));
      expect(text, contains('api_hash: abcdef0123456789abcdef0123456789'));
      final availability = await service.checkAvailability();
      expect(availability.available, isTrue);
    });

    test('助手解出来了但没有凭证时，仍不可用', () async {
      final service = serviceWith(
        assetLoader: (_) async =>
            ByteData.view(Uint8List.fromList([9, 9, 9]).buffer),
      );
      final ready = await service.ensureReady();
      expect(ready, isFalse);
      final availability = await service.checkAvailability();
      expect(availability.available, isFalse);
      expect(availability.reason, contains('Telegram API 凭证'));
    });

    test('已有 config 带凭证时不覆盖，助手仍解', () async {
      await putConfig('telegram:\n  api_id: 777\n  api_hash: deadbeef\n');
      final service = serviceWith(
        assetLoader: (_) async =>
            ByteData.view(Uint8List.fromList([5, 6]).buffer),
        bundledApiId: '123456',
        bundledApiHash: 'abcdef',
      );
      final ready = await service.ensureReady();
      expect(ready, isTrue);
      final config = File('${tempDir.path}/tgdrama/config.yaml');
      expect(await config.readAsString(), contains('api_id: 777'));
    });
  });

  group('sendCode', () {
    test('助手不存在时直接抛 StateError，不跑进程', () async {
      final service = serviceWith();
      await expectLater(
        service.sendCode('13800000000'),
        throwsA(isA<StateError>()),
      );
    });

    test('config 无凭证时直接抛 StateError', () async {
      await putHelper();
      await putConfig('telegram:\n  api_id: 123\n');
      final service = serviceWith();
      await expectLater(
        service.sendCode('13800000000'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('api_hash'),
          ),
        ),
      );
    });

    test('助手直接跑报 Permission denied 时走链接器兜底重跑', () async {
      await putHelper();
      await putConfig(
        'telegram:\n  api_id: 123456\n  api_hash: 0123456789abcdef0123456789abcdef\n',
      );
      final stateFile = File('${tempDir.path}/tgdrama/phone_login_state.json');
      await stateFile.create(recursive: true);
      await stateFile.writeAsString('{"phone_code_hash":"abc123"}');
      final calls = <List<String>>[];
      Future<ProcessResult> denyDirect(
        String executable,
        List<String> args,
      ) async {
        calls.add([executable, ...args]);
        if (executable == '/system/bin/linker64') {
          return ProcessResult(0, 0, '', '');
        }
        throw ProcessException(executable, args, 'Permission denied', 13);
      }

      final service = serviceWith(runProcess: denyDirect);
      await service.sendCode('13800000000');
      expect(calls.length, 2);
      expect(calls[0].first, contains('tgphone'));
      expect(calls[1].first, '/system/bin/linker64');
      expect(calls[1][1], contains('tgphone'));
    });
  });

  group('parseTelegramCredentials', () {
    test('只取 telegram 小节下的两键，值去引号', () {
      final (
        apiId,
        apiHash,
      ) = TgdramaPhoneLoginService.parseTelegramCredentials(
        'other:\n  api_id: 999\ntelegram:\n  api_id: "123456"\n  api_hash: \'abcdef\'\n',
      );
      expect(apiId, '123456');
      expect(apiHash, 'abcdef');
    });

    test('没有 telegram 小节时返回空', () {
      final (apiId, apiHash) =
          TgdramaPhoneLoginService.parseTelegramCredentials('foo: bar\n');
      expect(apiId, isNull);
      expect(apiHash, isNull);
    });
  });

  group('normalizePhone', () {
    test('11 位手机号默认补 +86', () {
      expect(
        TgdramaPhoneLoginService.normalizePhone('13800000000'),
        '+8613800000000',
      );
    });

    test('带 +86 的全号原样保留', () {
      expect(
        TgdramaPhoneLoginService.normalizePhone('+8613800000000'),
        '+8613800000000',
      );
    });

    test('空格与横杠去掉', () {
      expect(
        TgdramaPhoneLoginService.normalizePhone('138-0000-0000'),
        '+8613800000000',
      );
    });
  });
}
