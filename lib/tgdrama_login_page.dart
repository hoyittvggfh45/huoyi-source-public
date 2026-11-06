import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'tdlib_route.dart';
import 'tdlib_service.dart';
import 'tgdrama_phone_login.dart';
import 'tgdrama_service.dart';

class TgdramaLoginPage extends StatefulWidget {
  const TgdramaLoginPage({
    super.key,
    this.service,
    this.phoneLoginService,
    this.tdlibService,
  });

  final TgdramaService? service;

  final TgdramaPhoneLoginService? phoneLoginService;

  final TdlibService? tdlibService;

  @override
  State<TgdramaLoginPage> createState() => _TgdramaLoginPageState();
}

class _TgdramaLoginPageState extends State<TgdramaLoginPage> {
  TgdramaService get _service => widget.service ?? TgdramaService.instance;
  TgdramaPhoneLoginService get _phoneLogin =>
      widget.phoneLoginService ?? TgdramaPhoneLoginService();
  TdlibService get _tdlib => widget.tdlibService ?? TdlibService.instance;

  final _phoneController = TextEditingController();
  final _tdlibPhoneController = TextEditingController();

  bool _starting = true;
  bool _serviceRunning = false;
  bool _authorized = false;
  bool _loginSuccess = false;
  String? _statusError;
  String _serviceLog = '';

  TdlibAuthState? _tdlibState;
  bool _tdlibBusy = false;
  bool _tdlibStarted = false;
  bool _tdlibStarting = false;
  String? _tdlibError;
  String _tdlibMeName = '';
  String _tdlibRoute = TdlibRoute.plugin;
  String _tdlibQrLink = '';
  bool _tdlibQrActive = false;
  bool _codeDialogOpen = false;
  StreamSubscription<TdlibAuthState>? _tdlibAuthSub;

  bool _qrActive = false;
  bool _qrBusy = false;
  String? _qrError;
  int _qrTimestamp = 0;
  Timer? _pollTimer;
  int _pollCount = 0;
  bool _passwordDialogOpen = false;
  bool _qrDialogOpen = false;
  bool _qrRegenerating = false;
  bool _qrSuspendedForPassword = false;
  StateSetter? _qrDialogRefresh;

  PhoneLoginAvailability? _phoneAvailability;
  bool _phoneBusy = false;
  String? _phoneMessage;
  bool _codeSent = false;

  static const _pollInterval = Duration(seconds: 2);
  static const _maxPolls = 150;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _refreshPhoneAvailability();
    _refreshTdlibRoute();
  }

  Future<void> _refreshTdlibRoute() async {
    final route = await TdlibRoute.current();
    if (!mounted) return;
    setState(() => _tdlibRoute = route);
  }

  Future<bool> _ensureTdlibInitialized() async {
    if (_tdlibStarted) return true;
    if (_tdlibStarting) return false;
    if (!_tdlib.isSupported) {
      setState(() {
        _tdlibRoute = TdlibRoute.plugin;
        _tdlibError = '当前设备不支持 TDLib 登录，请用扫码或手机号登录';
      });
      return false;
    }
    setState(() {
      _tdlibStarting = true;
      _tdlibError = null;
    });
    try {
      _tdlibAuthSub ??= _tdlib.authStateStream.listen(
        _onTdlibAuthState,
        onError: (_) {},
      );
      final state = await _tdlib.init();
      if (!mounted) return false;
      final route = await TdlibRoute.current();
      setState(() {
        _tdlibState = state;
        _tdlibRoute = route;
        _tdlibStarted = true;
        _tdlibStarting = false;
        _tdlibError = null;
      });
      await _applyTdlibState(state);
      return true;
    } catch (e) {
      unawaited(_tdlibAuthSub?.cancel());
      _tdlibAuthSub = null;
      unawaited(TdlibRoute.set(TdlibRoute.plugin));
      if (!mounted) return false;
      setState(() {
        _tdlibStarting = false;
        _tdlibRoute = TdlibRoute.plugin;
        _tdlibError = _plainError(e);
      });
      return false;
    }
  }

  @override
  void dispose() {
    _tdlibAuthSub?.cancel();
    _stopPolling();
    if (_qrDialogOpen) {
      _qrDialogOpen = false;
      try {
        Navigator.of(context).maybePop();
      } catch (_) {}
    }
    _phoneController.dispose();
    _tdlibPhoneController.dispose();
    super.dispose();
  }

  Future<void> _refreshTdlibStatus() async {
    if (!_tdlibStarted) {
      await _ensureTdlibInitialized();
      return;
    }
    if (!_tdlib.isSupported) return;
    try {
      final state = await _tdlib.init();
      if (!mounted) return;
      final route = await TdlibRoute.current();
      setState(() {
        _tdlibState = state;
        _tdlibRoute = route;
        _tdlibError = null;
      });
      await _applyTdlibState(state);
    } catch (e) {
      if (!mounted) return;
      setState(() => _tdlibError = _plainError(e));
    }
  }

  Future<void> _onTdlibAuthState(TdlibAuthState state) async {
    if (!mounted) return;
    setState(() => _tdlibState = state);
    await _applyTdlibState(state);
  }

  Future<void> _applyTdlibState(TdlibAuthState state) async {
    if (!mounted) return;
    switch (state.name) {
      case TdlibAuthStateName.showQr:
        setState(() {
          _tdlibQrLink = state.link;
          _tdlibQrActive = state.link.isNotEmpty;
          _tdlibError = null;
        });
        if (_tdlibQrActive) _showQrDialog();
      case TdlibAuthStateName.waitCode:
        if (!_codeDialogOpen && !_passwordDialogOpen) {
          await _showCodeDialog(tdlib: true);
        }
      case TdlibAuthStateName.waitPassword:
        if (_tdlibQrActive) {
          setState(() => _tdlibQrActive = false);
          _closeQrDialog();
        }
        if (!_passwordDialogOpen) {
          await _showPasswordDialog(forQr: true, tdlib: true);
        }
      case TdlibAuthStateName.ready:
        setState(() {
          _tdlibQrActive = false;
          _tdlibError = null;
          _loginSuccess = true;
        });
        _closeQrDialog();
        await TdlibRoute.set(TdlibRoute.tdlib);
        try {
          final me = await _tdlib.getMe();
          if (!mounted) return;
          setState(() {
            _tdlibMeName = me.displayName;
            _tdlibRoute = TdlibRoute.tdlib;
          });
        } catch (_) {}
      case TdlibAuthStateName.loggedOut:
        await TdlibRoute.set(TdlibRoute.plugin);
        if (!mounted) return;
        setState(() {
          _tdlibMeName = '';
          _tdlibQrActive = false;
          _tdlibRoute = TdlibRoute.plugin;
        });
      case TdlibAuthStateName.error:
        setState(() => _tdlibError = state.message);
      case TdlibAuthStateName.initializing:
      case TdlibAuthStateName.waitPhoneNumber:
      case TdlibAuthStateName.signingOut:
        break;
    }
  }

  Future<void> _tdlibRequestQr() async {
    if (!await _ensureTdlibInitialized()) return;
    setState(() {
      _tdlibBusy = true;
      _tdlibError = null;
    });
    try {
      await _tdlib.requestQr();
    } catch (e) {
      if (!mounted) return;
      setState(() => _tdlibError = _plainError(e));
    } finally {
      if (mounted) setState(() => _tdlibBusy = false);
    }
  }

  Future<void> _tdlibSendPhoneCode() async {
    final phone = _tdlibPhoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _tdlibError = '请先输入手机号');
      return;
    }
    if (!await _ensureTdlibInitialized()) return;
    setState(() {
      _tdlibBusy = true;
      _tdlibError = null;
    });
    try {
      await _tdlib.requestPhone(phone);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tdlibBusy = false;
        _tdlibError = _plainError(e);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _tdlibBusy = false);
    await _showCodeDialog(tdlib: true);
  }

  Future<void> _tdlibLogout() async {
    if (!_tdlibStarted) return;
    setState(() => _tdlibBusy = true);
    try {
      await _tdlib.logout();
    } catch (e) {
      if (!mounted) return;
      setState(() => _tdlibError = _plainError(e));
    } finally {
      if (mounted) setState(() => _tdlibBusy = false);
    }
  }

  Future<void> _tdlibSwitchToPlugin() async {
    await TdlibRoute.set(TdlibRoute.plugin);
    if (!mounted) return;
    setState(() => _tdlibRoute = TdlibRoute.plugin);
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

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _startQr() async {
    setState(() {
      _qrBusy = true;
      _qrError = null;
      _loginSuccess = false;
    });
    try {
      await _service.startQrLogin();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qrBusy = false;
        _qrError = _plainError(e);
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _qrBusy = false;
      _qrActive = true;
      _qrTimestamp = DateTime.now().millisecondsSinceEpoch;
      _pollCount = 0;
    });
    _showQrDialog();
    _startPolling();
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  void _refreshQrDialog() {
    _qrDialogRefresh?.call(() {});
  }

  Future<void> _showQrDialog() async {
    if (_qrDialogOpen) return;
    _qrDialogOpen = true;
    _qrRegenerating = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          _qrDialogRefresh = setDialogState;
          return AlertDialog(
            title: const Text('扫码登录'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tdlibQrActive
                    ? SizedBox(
                        width: 260,
                        height: 260,
                        child: QrImageView(
                          data: _tdlibQrLink,
                          version: QrVersions.auto,
                          size: 260,
                        ),
                      )
                    : Image.network(
                        '${_service.qrImageUrl}?t=$_qrTimestamp',
                        width: 260,
                        height: 260,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(
                              width: 260,
                              height: 260,
                              child: Center(
                                child: Text('二维码加载失败，请点“重新生成”重试'),
                              ),
                            ),
                      ),
                const SizedBox(height: 8),
                const Text('打开手机 Telegram，扫一扫上面的二维码。'),
                const SizedBox(height: 4),
                Text(_tdlibQrActive ? '等待扫码…' : '等待扫码…（最多 5 分钟）'),
                if (_qrError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _qrError!,
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
                onPressed: _qrBusy || _tdlibBusy
                    ? null
                    : () {
                        _qrRegenerating = true;
                        Navigator.of(dialogContext).pop();
                        if (_tdlibQrActive) {
                          _tdlibRequestQr();
                        } else {
                          _startQr();
                        }
                      },
                child: const Text('重新生成'),
              ),
            ],
          );
        },
      ),
    );
    _qrDialogRefresh = null;
    _qrDialogOpen = false;
    if (_qrRegenerating) {
      _qrRegenerating = false;
      return;
    }
    if (_qrSuspendedForPassword) {
      _qrSuspendedForPassword = false;
      return;
    }
    if (_tdlibQrActive) {
      setState(() => _tdlibQrActive = false);
    }
    if (_qrActive) _cancelQr();
  }

  void _closeQrDialog() {
    if (!_qrDialogOpen) return;
    _qrDialogOpen = false;
    try {
      Navigator.of(context).pop();
    } catch (_) {}
  }

  Future<void> _pollOnce() async {
    if (!mounted || !_qrActive) return;
    _pollCount++;
    if (_pollCount > _maxPolls) {
      _stopPolling();
      if (!mounted) return;
      setState(() {
        _qrActive = false;
        _qrError = '扫码已超时（5 分钟），请点“重新生成”再扫一次';
      });
      _refreshQrDialog();
      return;
    }
    TgdramaAuthStatus status;
    try {
      status = await _service.authStatus();
    } catch (e) {
      _stopPolling();
      if (!mounted) return;
      setState(() {
        _qrActive = false;
        _qrError = '轮询登录状态出错：${_plainError(e)}';
      });
      _refreshQrDialog();
      return;
    }
    if (!mounted || !_qrActive) return;
    if (status.authorized) {
      _stopPolling();
      setState(() {
        _qrActive = false;
        _authorized = true;
        _loginSuccess = true;
        _qrError = null;
      });
      if (!_passwordDialogOpen) _closeQrDialog();
      return;
    }
    if (status.needPassword && !_passwordDialogOpen) {
      _qrSuspendedForPassword = true;
      _closeQrDialog();
      _showPasswordDialog(forQr: true);
    }
  }

  void _cancelQr() {
    _stopPolling();
    setState(() {
      _qrActive = false;
      _qrError = null;
    });
  }

  Future<void> _showPasswordDialog({
    required bool forQr,
    String? phoneCode,
    bool tdlib = false,
  }) async {
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
                        forQr: forQr,
                        phoneCode: phoneCode,
                        tdlib: tdlib,
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
                onPressed: () {
                  if (forQr) _cancelQr();
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () => _submitPasswordFromDialog(
                        dialogContext,
                        controller.text,
                        forQr: forQr,
                        phoneCode: phoneCode,
                        tdlib: tdlib,
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
        if (tdlib) {
          await _refreshTdlibStatus();
        } else if (forQr) {
          if (_qrActive) _startPolling();
        } else {
          await _refreshStatus();
        }
      }
    } finally {
      _passwordDialogOpen = false;
      controller.dispose();
    }
  }

  Future<void> _submitPasswordFromDialog(
    BuildContext dialogContext,
    String password, {
    required bool forQr,
    String? phoneCode,
    bool tdlib = false,
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
      if (tdlib) {
        await _tdlib.submitPassword(password);
      } else if (forQr) {
        await _service.submitPassword(password);
      } else {
        await _phoneLogin.verifyCode(
          phone: _phoneController.text,
          code: phoneCode ?? '',
          password: password,
        );
      }
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

  Future<void> _showCodeDialog({bool tdlib = false}) async {
    if (_codeDialogOpen) return;
    _codeDialogOpen = true;
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
                Text(
                  '验证码已发送到 ${tdlib ? _tdlibPhoneController.text.trim() : _phoneController.text.trim()}，请在下方输入。',
                ),
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
                        tdlib: tdlib,
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
                        tdlib: tdlib,
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
      _codeDialogOpen = false;
      controller.dispose();
    }
  }

  Future<void> _submitCodeFromDialog(
    BuildContext dialogContext,
    String code, {
    bool tdlib = false,
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
      if (tdlib) {
        await _tdlib.submitCode(code);
      } else {
        await _phoneLogin.verifyCode(phone: _phoneController.text, code: code);
      }
    } catch (e) {
      final message = _plainError(e);
      if (!dialogContext.mounted) return;
      if (_looksLikePasswordNeeded(message)) {
        Navigator.of(dialogContext).pop();
        await _showPasswordDialog(forQr: false, phoneCode: code, tdlib: tdlib);
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
    if (tdlib) {
      await _refreshTdlibStatus();
    } else {
      await _refreshStatus();
    }
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
          _buildQrSection(context),
          const SizedBox(height: 16),
          _buildPhoneSection(context),
          if (_tdlib.isSupported) ...[
            const SizedBox(height: 16),
            _buildTdlibSection(context),
          ],
        ],
      ),
    );
  }

  String _tdlibStatusText() {
    if (_tdlibError != null) return _tdlibError!;
    if (_tdlibStarting) return '正在启用 TDLib…';
    if (!_tdlibStarted) return '尚未启用：点“启用 TDLib 登录”开始，失败仍可用扫码或手机号登录';
    final state = _tdlibState;
    if (state == null) return '正在初始化…';
    switch (state.name) {
      case TdlibAuthStateName.initializing:
        return '正在初始化…';
      case TdlibAuthStateName.waitPhoneNumber:
        return '未登录：请选择手机号登录或扫码登录';
      case TdlibAuthStateName.showQr:
        return '正在等待扫码…';
      case TdlibAuthStateName.waitCode:
        return '验证码已发送，请在弹窗里输入';
      case TdlibAuthStateName.waitPassword:
        return '该账号开启了二步验证，请输入二步验证密码';
      case TdlibAuthStateName.ready:
        return _tdlibMeName.isEmpty ? '已登录' : '已登录：$_tdlibMeName';
      case TdlibAuthStateName.signingOut:
        return '正在退出登录…';
      case TdlibAuthStateName.loggedOut:
        return '已退出登录';
      case TdlibAuthStateName.error:
        return state.message.isEmpty ? '登录出错' : state.message;
    }
  }

  Widget _buildTdlibSection(BuildContext context) {
    final ready = _tdlibState?.name == TdlibAuthStateName.ready;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TDLib 登录', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('应用内直连 Telegram，不用起插件进程。手机号登录为主，扫码备用。'),
            const SizedBox(height: 8),
            Text(_tdlibStatusText()),
            if (_tdlibStarted && _tdlibRoute == TdlibRoute.tdlib) ...[
              const SizedBox(height: 4),
              const Text('TG影视库内容当前走 TDLib'),
            ],
            const SizedBox(height: 12),
            if (!_tdlibStarted) ...[
              FilledButton(
                onPressed: _tdlibStarting ? null : _ensureTdlibInitialized,
                child: Text(_tdlibStarting ? '正在启用…' : '启用 TDLib 登录'),
              ),
              const SizedBox(height: 12),
            ],
            if (ready) ...[
              Row(
                children: [
                  FilledButton(
                    onPressed: _tdlibBusy ? null : _tdlibLogout,
                    child: Text(_tdlibBusy ? '请稍候…' : '退出登录'),
                  ),
                  if (_tdlibRoute == TdlibRoute.tdlib) ...[
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _tdlibSwitchToPlugin,
                      child: const Text('切回插件路'),
                    ),
                  ],
                ],
              ),
            ] else ...[
              TextField(
                key: const ValueKey('tdlib_phone_field'),
                controller: _tdlibPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '手机号',
                  prefixText: '+86 ',
                  hintText: '11 位手机号',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: _tdlibBusy ? null : _tdlibSendPhoneCode,
                    child: Text(_tdlibBusy ? '发送中…' : '发送验证码'),
                  ),
                  OutlinedButton(
                    onPressed: _tdlibBusy ? null : _tdlibRequestQr,
                    child: const Text('扫码登录'),
                  ),
                  if (_tdlibQrActive)
                    OutlinedButton(
                      onPressed: _showQrDialog,
                      child: const Text('查看二维码'),
                    ),
                ],
              ),
            ],
            if (_tdlibError != null) ...[
              const SizedBox(height: 8),
              Text(
                _tdlibError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
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
      subtitle = '请用下面的扫码或手机号登录';
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

  Widget _buildQrSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('扫码登录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('点“开始扫码”，弹窗出二维码，用手机 Telegram 扫一扫。'),
            const SizedBox(height: 12),
            if (_qrActive) ...[
              const Text('正在等待扫码…'),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _showQrDialog,
                    child: const Text('查看二维码'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(onPressed: _cancelQr, child: const Text('取消')),
                ],
              ),
            ] else ...[
              FilledButton(
                onPressed: _qrBusy ? null : _startQr,
                child: Text(_qrBusy ? '正在开始…' : '开始扫码'),
              ),
            ],
            if (_qrError != null) ...[
              const SizedBox(height: 8),
              Text(
                _qrError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
