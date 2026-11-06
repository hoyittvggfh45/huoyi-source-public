import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/tdlib_service.dart';

class _PushStreamHandler implements MockStreamHandler {
  _PushStreamHandler(this.stream);

  final Stream<Map<String, dynamic>> stream;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {
    _sub = stream.listen(
      (event) => events.success(event),
      onError: (Object e) => events.error(code: 'error', message: '$e'),
      onDone: () => events.endOfStream(),
    );
  }

  @override
  void onCancel(Object? arguments) {
    _sub?.cancel();
    _sub = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('huoyi/tdlib');
  const authChannel = EventChannel('huoyi/tdlib/auth');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late TdlibService service;
  late Map<String, dynamic> lastCall;
  late Map<String, dynamic> lastArgs;
  final authEvents = StreamController<Map<String, dynamic>>();

  Map<String, dynamic> messageMap({
    required int messageId,
    required int chatId,
    int fileId = 11,
    int thumbFileId = 0,
    String caption = '',
    String fileName = 'video.mp4',
  }) => {
    'messageId': messageId,
    'chatId': chatId,
    'date': 1700000000 + messageId,
    'duration': 600,
    'width': 1280,
    'height': 720,
    'fileName': fileName,
    'mimeType': 'video/mp4',
    'supportsStreaming': true,
    'fileId': fileId,
    'fileSize': 1000,
    'thumbFileId': thumbFileId,
    'thumbWidth': 320,
    'thumbHeight': 180,
    'caption': caption,
  };

  setUp(() {
    lastCall = {};
    lastArgs = {};
    service = TdlibService(isAndroidProvider: () => true);
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      lastCall = {'method': call.method};
      lastArgs = Map<String, dynamic>.from(call.arguments as Map? ?? const {});
      return switch (call.method) {
        'authState' => {
          'state': {'name': 'waitPhoneNumber'},
        },
        'chats' => {
          'chats': [
            {'id': 100, 'title': '频道A', 'type': 'channel'},
            {'id': 101, 'title': '群组B', 'type': 'supergroup'},
            {'id': 102, 'title': '私聊C', 'type': 'private'},
          ],
        },
        'chatHistory' => {
          'messages': [
            messageMap(messageId: 5, chatId: 100),
            messageMap(messageId: 4, chatId: 100),
          ],
          'nextFromMessageId': 3,
        },
        'searchMessages' => {
          'messages': [messageMap(messageId: 9, chatId: 100)],
        },
        'searchChatMessages' => {
          'messages': [messageMap(messageId: 8, chatId: 101)],
          'nextFromMessageId': 0,
        },
        'downloadFile' => {
          'id': 11,
          'size': 1000,
          'expectedSize': 1000,
          'localPath': '/tmp/tdlib/11.mp4',
          'downloadedPrefixSize': 1000,
          'downloadOffset': 0,
          'isDownloadingCompleted': true,
          'isDownloadingActive': false,
        },
        'getFile' => {
          'id': 11,
          'size': 1000,
          'expectedSize': 1000,
          'localPath': '/tmp/tdlib/11.mp4',
          'downloadedPrefixSize': 1000,
          'downloadOffset': 0,
          'isDownloadingCompleted': true,
          'isDownloadingActive': false,
        },
        'getMe' => {
          'id': 123,
          'firstName': 'Test',
          'lastName': 'User',
          'username': 'testuser',
        },
        _ => <String, dynamic>{},
      };
    });
    messenger.setMockStreamHandler(
      authChannel,
      _PushStreamHandler(authEvents.stream),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(authChannel, null);
  });

  test('态名字符串映射到枚举，showQr 带链接、error 带消息', () {
    expect(
      TdlibAuthState.fromMap({'name': 'showQr', 'link': 'tg://login?token=x'}).name,
      TdlibAuthStateName.showQr,
    );
    expect(
      TdlibAuthState.fromMap({'name': 'showQr', 'link': 'tg://login?token=x'}).link,
      'tg://login?token=x',
    );
    expect(
      TdlibAuthState.fromMap({'name': 'waitCode'}).name,
      TdlibAuthStateName.waitCode,
    );
    expect(
      TdlibAuthState.fromMap({'name': 'waitPassword'}).name,
      TdlibAuthStateName.waitPassword,
    );
    expect(
      TdlibAuthState.fromMap({'name': 'ready'}).isReady,
      isTrue,
    );
    expect(
      TdlibAuthState.fromMap({'name': 'error', 'message': '炸了'}).message,
      '炸了',
    );
    expect(
      TdlibAuthState.fromMap({'name': '不知道'}).name,
      TdlibAuthStateName.initializing,
    );
  });

  test('init 无凭证时报缺少凭证，不调原生', () async {
    await expectLater(
      service.init(),
      throwsA(isA<AppFailure>().having((e) => e.message, 'message', '缺少 Telegram API 凭证')),
    );
    expect(lastCall, isEmpty);
  });

  test('非安卓上报不支持', () async {
    final unsupported = TdlibService(isAndroidProvider: () => false);
    expect(unsupported.isSupported, isFalse);
    await expectLater(
      unsupported.init(),
      throwsA(isA<AppFailure>().having((e) => e.message, 'message', '当前平台不支持 TDLib 登录')),
    );
  });

  test('authState 与登录动作按方法名调通道并传参', () async {
    final state = await service.authState();
    expect(state.name, TdlibAuthStateName.waitPhoneNumber);
    expect(lastCall['method'], 'authState');

    await service.requestQr();
    expect(lastCall['method'], 'requestQr');

    await service.requestPhone('13800000000');
    expect(lastCall['method'], 'requestPhone');
    expect(lastArgs['phone'], '13800000000');

    await service.submitCode('12345');
    expect(lastCall['method'], 'submitCode');
    expect(lastArgs['code'], '12345');

    await service.submitPassword('pw');
    expect(lastCall['method'], 'submitPassword');
    expect(lastArgs['password'], 'pw');

    await service.restartQr();
    expect(lastCall['method'], 'restartQr');

    await service.logout();
    expect(lastCall['method'], 'logout');
  });

  test('getMe 取显示名，chats 只在 Dart 侧不过滤', () async {
    final me = await service.getMe();
    expect(me.displayName, 'Test User');

    final chats = await service.chats(limit: 40);
    expect(chats.length, 3);
    expect(chats.map((c) => c.title).toList(), ['频道A', '群组B', '私聊C']);
    expect(chats[0].isVideoChannel, isTrue);
    expect(chats[1].isVideoChannel, isTrue);
    expect(chats[2].isVideoChannel, isFalse);
    expect(lastArgs['limit'], 40);
  });

  test('chatHistory 带翻页游标，搜索两路回消息', () async {
    final page = await service.chatHistory(chatId: 100, fromMessageId: 0, limit: 100);
    expect(page.messages.length, 2);
    expect(page.messages.first.messageId, 5);
    expect(page.nextFromMessageId, 3);

    final global = await service.searchMessages(query: '测试');
    expect(global.length, 1);
    expect(global.first.messageId, 9);

    final inChat = await service.searchChatMessages(chatId: 101, query: '测试');
    expect(inChat.messages.length, 1);
    expect(inChat.messages.first.messageId, 8);
    expect(inChat.nextFromMessageId, 0);
  });

  test('downloadFileAndWait 已完成时直接回本地路径', () async {
    final file = await service.downloadFileAndWait(11);
    expect(file.localPath, '/tmp/tdlib/11.mp4');
    expect(file.isDownloadingCompleted, isTrue);
  });

  test('登录态事件流只推带 state 的事件并映射', () async {
    final seen = <TdlibAuthState>[];
    final sub = service.authStateStream.listen(seen.add);
    authEvents.add({'connected': true});
    authEvents.add({'state': {'name': 'showQr', 'link': 'tg://login?token=y'}});
    authEvents.add({'state': {'name': 'ready'}});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();
    expect(seen.length, 2);
    expect(seen[0].name, TdlibAuthStateName.showQr);
    expect(seen[0].link, 'tg://login?token=y');
    expect(seen[1].isReady, isTrue);
  });

  test('未集成桥时 MissingPluginException 转成中文提示', () async {
    messenger.setMockMethodCallHandler(methodChannel, null);
    await expectLater(
      service.authState(),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.message,
          'message',
          '当前安装包未集成 TDLib 桥',
        ),
      ),
    );
  });
}
