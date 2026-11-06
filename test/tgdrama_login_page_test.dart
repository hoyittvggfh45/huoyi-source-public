import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duanju_app/tgdrama_login_page.dart';
import 'package:duanju_app/tgdrama_phone_login.dart';
import 'package:duanju_app/tgdrama_service.dart';

class FakeTgdramaService extends TgdramaService {
  bool running = true;
  String? errorOverride;
  bool authorized = false;
  bool needPassword = false;
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
}

class FakePhoneLoginService extends TgdramaPhoneLoginService {
  bool available = false;
  String reason = '手机号登录暂不可用：缺少 Telegram API 凭证';
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

  testWidgets('未登录时只显示手机号登录区，扫码区已撤掉', (tester) async {
    await pumpPage(tester);

    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('扫码登录'), findsNothing);
    expect(find.text('开始扫码'), findsNothing);
    expect(find.text('手机号登录'), findsOneWidget);
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
}
