import 'dart:async';

import 'package:flutter/material.dart';

import 'hongguo_account.dart';
import 'passport_client.dart';

const loginLimitationNote =
    '短信登录使用你自己的手机号接收验证码。登录仅用于账号身份展示，不会解除设备限流、不解决加密播放限制、不开通会员。';

class LoginScreen extends StatefulWidget {
  LoginScreen({super.key, PassportClient? client})
    : client = client ?? PassportClient();

  final PassportClient client;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sending = false;
  bool _loggingIn = false;
  int _countdown = 0;
  Timer? _countdownTimer;
  String? _smsError;
  QrTicket? _ticket;
  String? _qrError;
  bool _qrLoading = false;
  Timer? _qrPollTimer;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index == 1 && _ticket == null && !_qrLoading) {
        unawaited(_loadQrTicket());
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _phone.dispose();
    _code.dispose();
    _countdownTimer?.cancel();
    _qrPollTimer?.cancel();
    super.dispose();
  }

  bool get _phoneValid => RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone.text.trim());

  Future<void> _sendCode() async {
    if (!_phoneValid || _sending || _countdown > 0) return;
    setState(() {
      _sending = true;
      _smsError = null;
    });
    try {
      await widget.client.requestSmsCode(_phone.text.trim());
      if (!mounted) return;
      setState(() => _countdown = 60);
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_countdown <= 1) {
          timer.cancel();
          setState(() => _countdown = 0);
        } else {
          setState(() => _countdown--);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _smsError = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loginSms() async {
    if (!_phoneValid || _code.text.trim().isEmpty || _loggingIn) return;
    setState(() {
      _loggingIn = true;
      _smsError = null;
    });
    try {
      final account = await widget.client.verifySmsCode(
        _phone.text.trim(),
        _code.text.trim(),
      );
      await saveHongguoAccount(account);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _smsError = error.toString());
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  Future<void> _loadQrTicket() async {
    setState(() {
      _qrLoading = true;
      _qrError = null;
      _ticket = null;
    });
    try {
      final ticket = await widget.client.createQrTicket();
      if (!mounted) return;
      setState(() => _ticket = ticket);
      _qrPollTimer?.cancel();
      _qrPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (!mounted) return;
        try {
          final account = await widget.client.pollQrTicket(ticket.ticket);
          if (account != null) {
            _qrPollTimer?.cancel();
            await saveHongguoAccount(account);
            if (mounted) Navigator.of(context).pop(true);
          }
        } catch (error) {
          _qrPollTimer?.cancel();
          if (mounted) setState(() => _qrError = error.toString());
        }
      });
    } catch (error) {
      if (mounted) setState(() => _qrError = error.toString());
    } finally {
      if (mounted) setState(() => _qrLoading = false);
    }
  }

  Widget _smsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: '手机号',
            hintText: '请输入你自己的手机号',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '验证码',
                  hintText: '请输入短信验证码',
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: _phoneValid && !_sending && _countdown == 0
                  ? _sendCode
                  : null,
              child: Text(
                _sending
                    ? '发送中'
                    : _countdown > 0
                    ? '$_countdown秒后重发'
                    : '获取验证码',
              ),
            ),
          ],
        ),
        if (_smsError != null) ...[
          const SizedBox(height: 12),
          Text(_smsError!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loggingIn ? null : _loginSms,
          child: Text(_loggingIn ? '登录中' : '登录'),
        ),
        const SizedBox(height: 16),
        const Text(loginLimitationNote),
      ],
    );
  }

  Widget _qrTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_qrLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_ticket != null && _ticket!.imageUrl.isNotEmpty)
          Center(
            child: Image.network(
              _ticket!.imageUrl,
              width: 220,
              height: 220,
              errorBuilder: (_, _, _) => const Text('二维码加载失败，请重新获取'),
            ),
          )
        else if (_ticket != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text('二维码加载失败，请重新获取')),
          ),
        if (_qrError != null) ...[
          const SizedBox(height: 12),
          Text(_qrError!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        const Text('请用官方 App 扫码确认登录，扫码后本页自动完成登录。', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _qrLoading ? null : _loadQrTicket,
          child: const Text('重新获取二维码'),
        ),
        const SizedBox(height: 16),
        const Text(loginLimitationNote),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '短信登录'),
            Tab(text: '扫码登录'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [_smsTab(), _qrTab()]),
    );
  }
}
