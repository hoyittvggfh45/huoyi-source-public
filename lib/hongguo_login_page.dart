import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'hongguo_account.dart';

class HongguoLoginPage extends StatefulWidget {
  const HongguoLoginPage({super.key, required this.controller});

  final HongguoAccountController controller;

  @override
  State<HongguoLoginPage> createState() => _HongguoLoginPageState();
}

class _HongguoLoginPageState extends State<HongguoLoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String _countryCode = '86';
  String _mobile = '';
  HongguoSmsCountdown? _countdown;
  Timer? _timer;
  HongguoQrCode? _qrCode;
  HongguoQrCountdown? _qrCountdown;
  Timer? _qrTimer;
  Timer? _pollTimer;
  bool _qrMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _qrTimer?.cancel();
    _pollTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    _countdown = HongguoSmsCountdown(retrySeconds: seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _countdown?.tick();
        if (_countdown?.canResend == true) _timer?.cancel();
      });
    });
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mobile = formatHongguoPhone(
        _countryCode,
        _phoneController.text,
      );
      final sent = await widget.controller.transportSendSmsCode(mobile);
      if (!mounted) return;
      _mobile = mobile;
      setState(() => _countdown = null);
      _startCountdown(sent.retrySeconds);
    } on HongguoLoginFailure catch (error) {
      if (!mounted) return;
      if (error.errorCode == 7) {
        setState(() => _error = error.message);
        _startCountdown(60);
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '发送失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_mobile.isEmpty) {
      setState(() => _error = '请先获取验证码');
      return;
    }
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.loginWithSms(mobile: _mobile, code: code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on HongguoLoginFailure catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '登录失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadQr() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final qr = await widget.controller.transportFetchQrCode();
      if (!mounted) return;
      _qrTimer?.cancel();
      _pollTimer?.cancel();
      setState(() => _qrCode = qr);
      _qrCountdown = HongguoQrCountdown(expiresInSeconds: qr.expiresInSeconds);
      _qrTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _qrCountdown?.tick();
          if (_qrCountdown?.expired == true) {
            _qrTimer?.cancel();
            _pollTimer?.cancel();
          }
        });
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (!mounted) return;
        try {
          final result = await widget.controller.transportPollQrCode();
          if (result == HongguoQrPollResult.confirmed) {
            _pollTimer?.cancel();
            await widget.controller.loginWithQr();
            if (!mounted) return;
            Navigator.of(context).pop(true);
          } else if (result == HongguoQrPollResult.expired) {
            _pollTimer?.cancel();
            if (mounted) {
              setState(() => _error = '二维码已过期，请重新获取');
            }
          }
        } catch (error) {
          _pollTimer?.cancel();
          if (!mounted) return;
          if (error is HongguoLoginFailure) {
            setState(() => _error = error.message);
          } else {
            setState(() => _error = '登录失败，请稍后重试');
          }
        }
      });
    } on HongguoLoginFailure catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '取二维码失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_qrMode ? '扫码登录' : '手机号登录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_qrMode) _qrBody() else _phoneBody(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          TextButton(
            onPressed:
                _busy
                    ? null
                    : () {
                      setState(() {
                        _qrMode = !_qrMode;
                        _error = null;
                      });
                      if (_qrMode && _qrCode == null) _loadQr();
                    },
            child: Text(_qrMode ? '改用手机号登录' : '改用扫码登录'),
          ),
          const SizedBox(height: 8),
          const Text('本机历史与云端记录分别保留；退出登录会停止上传。'),
        ],
      ),
    );
  }

  Widget _phoneBody() {
    final countdown = _countdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DropdownButton<String>(
              value: _countryCode,
              items:
                  hongguoCountryCodes
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.code,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
              onChanged:
                  _busy
                      ? null
                      : (value) {
                        if (value != null) {
                          setState(() => _countryCode = value);
                        }
                      },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '手机号',
                  hintText: '大陆 11 位手机号',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '短信验证码'),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed:
                  _busy || (countdown != null && !countdown.canResend)
                      ? null
                      : _sendCode,
              child: Text(
                countdown != null && !countdown.canResend
                    ? '${countdown.remainingSeconds} 秒后重发'
                    : '获取验证码',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _verifyCode,
          child: const Text('登录'),
        ),
      ],
    );
  }

  Widget _qrBody() {
    final qr = _qrCode;
    final countdown = _qrCountdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (qr == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          Center(
            child: Image.memory(
              Uint8List.fromList(qr.imageBytes),
              width: 220,
              height: 220,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              countdown != null && !countdown.expired
                  ? '请用手机扫码确认，${countdown.remainingSeconds} 秒后过期'
                  : '二维码已过期',
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _loadQr,
          child: const Text('重新获取二维码'),
        ),
        const SizedBox(height: 8),
        const Text('只有一台手机时请优先用手机号登录，扫码为备用。'),
      ],
    );
  }
}
