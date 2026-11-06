import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duanju_app/tdlib_route.dart';
import 'package:duanju_app/tdlib_service.dart';
import 'package:duanju_app/tgdrama_login_page.dart';
import 'package:duanju_app/tgdrama_phone_login.dart';
import 'package:duanju_app/tgdrama_service.dart';

class FakeTgdramaService extends TgdramaService {
  bool running = true;
  String? errorOverride;
  bool authorized = false;
  bool needPassword = false;
  bool qrStarted = false;
  String? submittedPassword;
  String logTail = '';
  int? exitCode;
  int authStatusCalls = 0;

  @override
  Future<bool> ensureRunning() async => running;

  @override
  String? get lastError => errorOverride;

  @override
  String get lastLogTail => logTail;

  @override
  int? get lastExitCode => exitCode;

  @override
  Future<TgdramaAuthStatus> authStatus() async {
    authStatusCalls++;
    return TgdramaAuthStatus(
      authorized: authorized,
      needPassword: needPassword,
    );
  }

  @override
  Future<void> startQrLogin() async {
    qrStarted = true;
  }

  @override
  String get qrImageUrl => 'http://127.0.0.1:5278/api/auth/qr.png';

  @override
  Future<void> submitPassword(String password) async {
    submittedPassword = password;
  }
}

class FakePhoneLoginService extends TgdramaPhoneLoginService {
  bool available = false;
  String reason = '手机号登录暂不可用：缺少 Telegram API 凭证，请先用扫码登录';
  int sendCodeCalls = 0;
  int verifyCodeCalls = 0;
  String? lastCode;
  String? lastPassword;
  String? verifyError;
  bool verifyNeedsPassword = false;

  @override
  Future<PhoneLoginAvailability> checkAvailability() async {
    return PhoneLoginAvailability(available: available, reason: reason);
  }

  @override
  Future<void> sendCode(String phone) async {
    sendCodeCalls++;
    if (!available) throw StateError(reason);
  }

  @override
  Future<void> verifyCode({
    required String phone,
    required String code,
    String? password,
  }) async {
    verifyCodeCalls++;
    lastCode = code;
    lastPassword = password;
    if (verifyError != null) throw StateError(verifyError!);
    if (verifyNeedsPassword && (password == null || password.isEmpty)) {
      throw StateError('SESSION_PASSWORD_NEEDED：该账号开了二步验证');
    }
  }
}

class FakeTdlibService extends TdlibService {
  final _events = StreamController<TdlibAuthState>();
  var initialState = const TdlibAuthState(
    name: TdlibAuthStateName.waitPhoneNumber,
  );
  var qrRequested = false;
  String? lastPhone;
  String? lastCode;
  String? lastPassword;
  var logoutCalled = false;

  @override
  bool get isSupported => true;

  @override
  Stream<TdlibAuthState> get authStateStream => _events.stream;

  @override
  Future<TdlibAuthState> init() async => initialState;

  @override
  Future<void> requestQr() async {
    qrRequested = true;
    initialState = const TdlibAuthState(
      name: TdlibAuthStateName.showQr,
      link: 'tg://login?token=tdlib-test',
    );
    _events.add(initialState);
  }

  @override
  Future<void> requestPhone(String phone) async {
    lastPhone = phone;
    initialState = const TdlibAuthState(name: TdlibAuthStateName.waitCode);
    _events.add(initialState);
  }

  @override
  Future<void> submitCode(String code) async {
    lastCode = code;
    if (code == '99999') {
      initialState = const TdlibAuthState(
        name: TdlibAuthStateName.waitPassword,
      );
    } else {
      initialState = const TdlibAuthState(name: TdlibAuthStateName.ready);
    }
    _events.add(initialState);
  }

  @override
  Future<void> submitPassword(String password) async {
    lastPassword = password;
    initialState = const TdlibAuthState(name: TdlibAuthStateName.ready);
    _events.add(initialState);
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
    initialState = const TdlibAuthState(name: TdlibAuthStateName.loggedOut);
    _events.add(initialState);
  }

  @override
  Future<TdlibMe> getMe() async => const TdlibMe(
    id: 123,
    firstName: 'Test',
    lastName: 'User',
    username: 'testuser',
  );

  void dispose() {
    _events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTgdramaService fakeService;
  late FakePhoneLoginService fakePhone;

  setUp(() {
    fakeService = FakeTgdramaService();
    fakePhone = FakePhoneLoginService();
  });

  tearDown(() {
    fakeService.dispose();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TgdramaLoginPage(
          service: fakeService,
          phoneLoginService: fakePhone,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('未登录时显示状态与两种登录区，手机号不可用原因原样显示', (tester) async {
    await pumpPage(tester);

    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);
    expect(find.text('手机号登录'), findsOneWidget);
    expect(find.text('开始扫码'), findsOneWidget);
    expect(find.text('发送验证码'), findsOneWidget);
    expect(find.text(fakePhone.reason), findsOneWidget);
    expect(find.byKey(const ValueKey('tgdrama_code_field')), findsNothing);
    expect(find.byKey(const ValueKey('tgdrama_password_field')), findsNothing);
  });

  testWidgets('服务未启动时显示未启动与重试', (tester) async {
    fakeService.running = false;
    fakeService.errorOverride = '本地服务未启动：测试原因';
    await pumpPage(tester);

    expect(find.text('本地服务未启动'), findsWidgets);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('服务未启动且有进程日志时原样显示日志尾', (tester) async {
    fakeService.running = false;
    fakeService.errorOverride = '本地服务未启动：测试原因';
    fakeService.logTail = 'fatal: config.yaml not found';
    await pumpPage(tester);

    expect(find.text('进程日志（最后几行）：'), findsOneWidget);
    expect(find.text('fatal: config.yaml not found'), findsOneWidget);
  });

  testWidgets('扫码流程：点开始扫码弹窗出二维码，轮询成功关弹窗显示登录成功', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('开始扫码'));
    await tester.pump();
    await tester.pump();

    expect(fakeService.qrStarted, isTrue);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('等待扫码…（最多 5 分钟）'), findsOneWidget);

    fakeService.authorized = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('登录成功'), findsOneWidget);
    expect(find.text('已登录'), findsOneWidget);
  });

  testWidgets('扫码二步验证：轮询到 needPassword 弹密码框，提交后继续轮询', (tester) async {
    fakeService.needPassword = true;
    await pumpPage(tester);

    await tester.tap(find.text('开始扫码'));
    await tester.pump();
    await tester.pump();

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('二步验证'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('tgdrama_password_field')),
      'pw123',
    );
    await tester.tap(find.text('提交'));
    await tester.pump();
    await tester.pump();

    expect(fakeService.submittedPassword, 'pw123');
    expect(find.text('二步验证'), findsNothing);

    fakeService.needPassword = false;
    fakeService.authorized = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('登录成功'), findsOneWidget);
  });

  testWidgets('扫码密码框点取消：两层弹窗都关、停轮询、回登录页状态', (tester) async {
    fakeService.needPassword = true;
    await pumpPage(tester);

    await tester.tap(find.text('开始扫码'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('二步验证'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('二步验证'),
          matching: find.byType(AlertDialog),
        ),
        matching: find.text('取消'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('二步验证'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('开始扫码'), findsOneWidget);
    final callsAfterCancel = fakeService.authStatusCalls;
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(fakeService.authStatusCalls, callsAfterCancel);
  });

  testWidgets('手机号区点发送时服务不可用，页内原样显示中文原因', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey('tgdrama_phone_field')),
      '13800000000',
    );
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    await tester.pump();

    expect(fakePhone.sendCodeCalls, 1);
    expect(find.text(fakePhone.reason), findsWidgets);
    expect(find.text('输入验证码'), findsNothing);
  });

  testWidgets('手机号可用：发码成功弹验证码框，输码登录成功', (tester) async {
    fakePhone.available = true;
    fakePhone.reason = '可用';
    fakeService.authorized = true;
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey('tgdrama_phone_field')),
      '13800000000',
    );
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    await tester.pump();

    expect(fakePhone.sendCodeCalls, 1);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('输入验证码'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('tgdrama_code_field')),
      '12345',
    );
    await tester.tap(find.text('登录'));
    await tester.pump();
    await tester.pump();

    expect(fakePhone.verifyCodeCalls, 1);
    expect(fakePhone.lastCode, '12345');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('登录成功'), findsOneWidget);
  });

  testWidgets('验证码输错：在弹窗里显示错误，可重输，不闪退', (tester) async {
    fakePhone.available = true;
    fakePhone.reason = '可用';
    fakePhone.verifyError = '验证码不正确，请重新输入';
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey('tgdrama_phone_field')),
      '13800000000',
    );
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('tgdrama_code_field')),
      '00000',
    );
    await tester.tap(find.text('登录'));
    await tester.pump();
    await tester.pump();

    expect(find.text('验证码不正确，请重新输入'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('输入验证码'),
      ),
      findsOneWidget,
    );

    fakePhone.verifyError = null;
    await tester.enterText(
      find.byKey(const ValueKey('tgdrama_code_field')),
      '12345',
    );
    await tester.tap(find.text('登录'));
    await tester.pump();
    await tester.pump();

    expect(fakePhone.verifyCodeCalls, 2);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('手机号二步验证：验证码框提交后改弹密码框', (tester) async {
    fakePhone.available = true;
    fakePhone.reason = '可用';
    fakePhone.verifyNeedsPassword = true;
    fakeService.authorized = true;
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey('tgdrama_phone_field')),
      '13800000000',
    );
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('tgdrama_code_field')),
      '12345',
    );
    await tester.tap(find.text('登录'));
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('输入验证码'),
      ),
      findsNothing,
    );
    expect(find.text('二步验证'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('tgdrama_password_field')),
      'pw123',
    );
    await tester.tap(find.text('提交'));
    await tester.pump();
    await tester.pump();

    expect(fakePhone.lastPassword, 'pw123');
    expect(find.text('二步验证'), findsNothing);
  });

  group('TDLib 登录', () {
    late FakeTdlibService fakeTdlib;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeTdlib = FakeTdlibService();
    });

    tearDown(() {
      fakeTdlib.dispose();
    });

    Future<void> pumpTdlibPage(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: TgdramaLoginPage(
            service: fakeService,
            phoneLoginService: fakePhone,
            tdlibService: fakeTdlib,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Finder tdlibSendCodeButton() {
      final card = find.ancestor(
        of: find.byKey(const ValueKey('tdlib_phone_field')),
        matching: find.byType(Card),
      );
      return find.descendant(of: card, matching: find.text('发送验证码'));
    }

    testWidgets('不支持时不显示 TDLib 卡', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TgdramaLoginPage(
            service: fakeService,
            phoneLoginService: fakePhone,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('TDLib 登录'), findsNothing);
    });

    testWidgets('支持时显示 TDLib 卡与未登录状态', (tester) async {
      await pumpTdlibPage(tester);

      expect(find.text('TDLib 登录'), findsOneWidget);
      expect(find.text('未登录：请选择手机号登录或扫码登录'), findsOneWidget);
      expect(find.byKey(const ValueKey('tdlib_phone_field')), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, '扫码登录'),
        findsOneWidget,
      );
      expect(tdlibSendCodeButton(), findsOneWidget);
    });

    testWidgets('扫码流程：点扫码登录弹窗出本地二维码', (tester) async {
      await pumpTdlibPage(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, '扫码登录'));
      await tester.pump();
      await tester.pump();

      expect(fakeTdlib.qrRequested, isTrue);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('等待扫码…'), findsOneWidget);
    });

    testWidgets('手机号流程：发码后弹窗输验证码，登录成功切到 TDLib 路', (tester) async {
      await pumpTdlibPage(tester);

      await tester.enterText(
        find.byKey(const ValueKey('tdlib_phone_field')),
        '13800000000',
      );
      await tester.tap(tdlibSendCodeButton());
      await tester.pump();
      await tester.pump();

      expect(fakeTdlib.lastPhone, '13800000000');
      expect(find.text('输入验证码'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('tgdrama_code_field')),
        '12345',
      );
      await tester.tap(find.text('登录'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(fakeTdlib.lastCode, '12345');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('已登录：Test User'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
      expect(find.text('TG影视库内容当前走 TDLib'), findsOneWidget);
      expect(await TdlibRoute.current(), TdlibRoute.tdlib);
    });

    testWidgets('验证码后需二步验证：弹密码框，提交后登录成功', (tester) async {
      await pumpTdlibPage(tester);

      await tester.enterText(
        find.byKey(const ValueKey('tdlib_phone_field')),
        '13800000000',
      );
      await tester.tap(tdlibSendCodeButton());
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('tgdrama_code_field')),
        '99999',
      );
      await tester.tap(find.text('登录'));
      await tester.pump();
      await tester.pump();

      expect(find.text('二步验证'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('tgdrama_password_field')),
        'pw123',
      );
      await tester.tap(find.text('提交'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(fakeTdlib.lastPassword, 'pw123');
      expect(find.text('二步验证'), findsNothing);
      expect(find.text('已登录：Test User'), findsOneWidget);
    });

    testWidgets('退出登录后路由切回插件路', (tester) async {
      fakeTdlib.initialState = const TdlibAuthState(
        name: TdlibAuthStateName.ready,
      );
      await pumpTdlibPage(tester);

      expect(find.text('已登录：Test User'), findsOneWidget);
      expect(find.text('切回插件路'), findsOneWidget);

      await tester.tap(find.text('退出登录'));
      await tester.pump();
      await tester.pump();

      expect(fakeTdlib.logoutCalled, isTrue);
      expect(find.text('已退出登录'), findsOneWidget);
      expect(find.text('TG影视库内容当前走 TDLib'), findsNothing);
      expect(await TdlibRoute.current(), TdlibRoute.plugin);
    });

    testWidgets('切回插件路只改路由不退出登录', (tester) async {
      fakeTdlib.initialState = const TdlibAuthState(
        name: TdlibAuthStateName.ready,
      );
      await pumpTdlibPage(tester);

      await tester.tap(find.text('切回插件路'));
      await tester.pump();
      await tester.pump();

      expect(find.text('已登录：Test User'), findsOneWidget);
      expect(find.text('TG影视库内容当前走 TDLib'), findsNothing);
      expect(await TdlibRoute.current(), TdlibRoute.plugin);
    });
  });
}
