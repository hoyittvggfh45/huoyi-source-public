import 'dart:async';

import 'package:flutter/material.dart';

import 'tgdrama_phone_login.dart';
import 'tgdrama_service.dart';

class TgdramaLoginPage extends StatefulWidget {
  const TgdramaLoginPage({super.key, this.service, this.phoneLoginService});

  final TgdramaService? service;

  final TgdramaPhoneLoginService? phoneLoginService;

  @override
  State<TgdramaLoginPage> createState() => _TgdramaLoginPageState();
}

class _TgdramaLoginPageState extends State<TgdramaLoginPage> {
  TgdramaService get _service => widget.service ?? TgdramaService.instance;
  TgdramaPhoneLoginService get _phoneLogin =>
      widget.phoneLoginService ?? TgdramaPhoneLoginService();

  final _phoneController = TextEditingController();

  bool _starting = true;
  bool _serviceRunning = false;
  bool _authorized = false;
  bool _loginSuccess = false;
  String? _statusError;
  String _serviceLog = '';

  bool _passwordDialogOpen = false;

  PhoneLoginAvailability? _phoneAvailability;
  bool _phoneBusy = false;
  String? _phoneMessage;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _refreshPhoneAvailability();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _starting = true;
      _statusError = null;
    });
    final running = await _service.ensureRunning();
    if (!mounted) return;
    if (!running) {
      setState(() {
        _starting = false;
        _serviceRunning = false;
        _statusError = _service.lastError ?? '本地服务未启动';
        _serviceLog = _service.lastLogTail;
      });
      return;
    }
    final status = await _service.authStatus();
    if (!mounted) return;
    setState(() {
      _starting = false;
      _serviceRunning = true;
      _authorized = status.authorized;
      _statusError = null;
      _serviceLog = '';
    });
  }

  Future<void> _refreshPhoneAvailability() async {
    final availability = await _phoneLogin.checkAvailability();
    if (!mounted) return;
    setState(() => _phoneAvailability = availability);
  }

  Future<void> _showPasswordDialog({String? phoneCode}) async {
    if (_passwordDialogOpen) return;
    _passwordDialogOpen = true;
    final controller = TextEditingController();
    var dialogError = '';
    var submitting = false;
    try {
      final submitted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('二步验证'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('该账号开启了二步验证，请输入 Telegram 二步验证密码。'),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('tgdrama_password_field'),
                  controller: controller,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '二步验证密码',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    if (!submitting) {
                      _submitPasswordFromDialog(
                        dialogContext,
                        controller.text,
                        phoneCode: phoneCode,
                        setDialogState: setDialogState,
                        setError: (value) => dialogError = value,
                        setSubmitting: (value) => submitting = value,
                      );
                    }
                  },
                ),
                if (dialogError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    dialogError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () => _submitPasswordFromDialog(
                        dialogContext,
                        controller.text,
                        phoneCode: phoneCode,
                        setDialogState: setDialogState,
                        setError: (value) => dialogError = value,
                        setSubmitting: (value) => submitting = value,
                      ),
                child: const Text('提交'),
              ),
            ],
          ),
        ),
      );
      if (submitted == true && mounted) {
        await _refreshStatus();
      }
    } finally {
      _passwordDialogOpen = false;
      controller.dispose();
    }
  }

  Future<void> _submitPasswordFromDialog(
    BuildContext dialogContext,
    String password, {
    String? phoneCode,
    required void Function(void Function()) setDialogState,
    required void Function(String value) setError,
    required void Function(bool value) setSubmitting,
  }) async {
    if (password.isEmpty) {
      setDialogState(() => setError('请先输入二步验证密码'));
      return;
    }
    setDialogState(() {
      setSubmitting(true);
      setError('');
    });
    try {
      await _phoneLogin.verifyCode(
        phone: _phoneController.text,
        code: phoneCode ?? '',
        password: password,
      );
    } catch (e) {
      if (!dialogContext.mounted) return;
      setDialogState(() {
        setSubmitting(false);
        setError(_plainError(e));
      });
      return;
    }
    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop(true);
  }

  Future<void> _sendPhoneCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _phoneMessage = '请先输入手机号');
      return;
    }
    setState(() {
      _phoneBusy = true;
      _phoneMessage = null;
    });
    try {
      await _phoneLogin.sendCode(phone);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phoneBusy = false;
        _phoneMessage = _plainError(e);
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _phoneBusy = false;
      _codeSent = true;
      _phoneMessage = '验证码已发送到 $phone，请在弹窗里输入';
    });
    await _showCodeDialog();
  }

  Future<void> _showCodeDialog() async {
    final controller = TextEditingController();
    var dialogError = '';
    var submitting = false;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('输入验证码'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('验证码已发送到 ${_phoneController.text.trim()}，请在下方输入。'),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('tgdrama_code_field'),
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '短信验证码',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    if (!submitting) {
                      _submitCodeFromDialog(
                        dialogContext,
                        controller.text,
                        setDialogState: setDialogState,
                        setError: (value) => dialogError = value,
                        setSubmitting: (value) => submitting = value,
                      );
                    }
                  },
                ),
                if (dialogError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    dialogError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () => _submitCodeFromDialog(
                        dialogContext,
                        controller.text,
                        setDialogState: setDialogState,
                        setError: (value) => dialogError = value,
                        setSubmitting: (value) => submitting = value,
                      ),
                child: const Text('登录'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _submitCodeFromDialog(
    BuildContext dialogContext,
    String code, {
    required void Function(void Function()) setDialogState,
    required void Function(String value) setError,
    required void Function(bool value) setSubmitting,
  }) async {
    if (code.trim().isEmpty) {
      setDialogState(() => setError('请先输入短信验证码'));
      return;
    }
    setDialogState(() {
      setSubmitting(true);
      setError('');
    });
    try {
      await _phoneLogin.verifyCode(phone: _phoneController.text, code: code);
    } catch (e) {
      final message = _plainError(e);
      if (!dialogContext.mounted) return;
      if (_looksLikePasswordNeeded(message)) {
        Navigator.of(dialogContext).pop();
        await _showPasswordDialog(phoneCode: code);
        return;
      }
      setDialogState(() {
        setSubmitting(false);
        setError(message);
      });
      return;
    }
    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
    if (!mounted) return;
    setState(() {
      _phoneMessage = null;
      _loginSuccess = true;
    });
    await _refreshStatus();
  }

  bool _looksLikePasswordNeeded(String message) {
    final lower = message.toLowerCase();
    return message.contains('二步') ||
        lower.contains('password') ||
        lower.contains('session_password_needed') ||
        lower.contains('2fa');
  }

  String _plainError(Object e) {
    if (e is StateError) return e.message;
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Telegram 登录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(context),
          const SizedBox(height: 16),
          _buildPhoneSection(context),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    late final String title;
    late final String subtitle;
    late final IconData icon;
    if (_starting) {
      title = '正在检查本地服务…';
      subtitle = '';
      icon = Icons.hourglass_empty;
    } else if (!_serviceRunning) {
      title = '本地服务未启动';
      subtitle = _statusError ?? 'TG影视库本地服务未启动';
      icon = Icons.cloud_off;
    } else if (_authorized) {
      title = '已登录';
      subtitle = '登录态存在插件本地，重启不用重登';
      icon = Icons.check_circle;
    } else {
      title = '未登录';
      subtitle = '请用下面的手机号登录';
      icon = Icons.account_circle;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (!_starting && !_serviceRunning)
                  TextButton(
                    onPressed: _refreshStatus,
                    child: const Text('重试'),
                  ),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle),
            ],
            if (!_starting && !_serviceRunning && _serviceLog.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '进程日志（最后几行）：',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              SelectableText(
                _serviceLog,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ],
            if (_loginSuccess) ...[
              const SizedBox(height: 4),
              Text('登录成功', style: TextStyle(color: theme.colorScheme.primary)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneSection(BuildContext context) {
    final availability = _phoneAvailability;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('手机号登录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('输手机号收短信验证码登录。验证码与二步验证密码都在弹窗里输入。'),
            if (availability != null && !availability.available) ...[
              const SizedBox(height: 8),
              Text(
                availability.reason,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('tgdrama_phone_field'),
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '手机号',
                prefixText: '+86 ',
                hintText: '11 位手机号',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: _phoneBusy ? null : _sendPhoneCode,
                  child: Text(_phoneBusy ? '发送中…' : '发送验证码'),
                ),
                if (_codeSent) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _showCodeDialog,
                    child: const Text('输入验证码'),
                  ),
                ],
              ],
            ),
            if (_phoneMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _phoneMessage!,
                style: TextStyle(
                  color: _phoneMessage!.startsWith('验证码已发送')
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
