import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'tgdrama_credentials.dart';

class TgdramaAuthStatus {
  const TgdramaAuthStatus({
    required this.authorized,
    required this.needPassword,
    this.message = '',
  });

  final bool authorized;

  final bool needPassword;

  final String message;
}

class TgdramaService with WidgetsBindingObserver {
  TgdramaService({
    http.Client? httpClient,
    Future<Process> Function(List<String> command, {String? workingDirectory})?
    processLauncher,
    Future<Directory> Function()? supportDirProvider,
    this._isAndroidProvider,
    Future<ByteData> Function(String assetPath)? assetLoader,
    Future<ProcessResult> Function(String executable, List<String> args)?
    chmodRunner,
  }) : _httpClient = httpClient ?? http.Client(),
       _processLauncher = processLauncher ?? _defaultProcessLauncher,
       _supportDirProvider =
           supportDirProvider ?? getApplicationSupportDirectory,
       _assetLoader = assetLoader ?? rootBundle.load,
       _chmodRunner = chmodRunner ?? Process.run {
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      _observing = false;
    }
  }

  static const baseUrl = 'http://127.0.0.1:5278';
  static const defaultPort = 5278;

  static const binaryAssetPath = 'assets/tgdrama/tgdrama-android';

  static const sessionAssetPath = 'assets/tgdrama_session.json';

  static const binaryMd5 = 'ae95f3c5b030d90d3af239fc9523e0d0';

  static const _binaryDirName = 'tgdrama';
  static const _binaryFileName = 'tgdrama-android';

  static const _healthTimeout = Duration(seconds: 8);

  static const _healthPollAttempts = 16;
  static const _healthPollInterval = Duration(milliseconds: 500);

  static final TgdramaService _instance = TgdramaService();
  static TgdramaService get instance => _instance;

  final http.Client _httpClient;
  final Future<Process> Function(
    List<String> command, {
    String? workingDirectory,
  })
  _processLauncher;
  final Future<Directory> Function() _supportDirProvider;
  final bool Function()? _isAndroidProvider;
  final Future<ByteData> Function(String assetPath) _assetLoader;
  final Future<ProcessResult> Function(String executable, List<String> args)
  _chmodRunner;

  static const _linkerPath = '/system/bin/linker64';
  static const _chmodPath = '/system/bin/chmod';
  static const _maxLogChars = 4000;

  String? get lastError => _lastError;

  String get lastLogTail => _logBuffer.toString();

  int? get lastExitCode => _lastExitCode;

  Process? _process;
  bool _processExited = false;
  bool _everStarted = false;
  bool _observing = false;
  Future<bool>? _starting;
  String? _lastError;
  int? _lastExitCode;
  final StringBuffer _logBuffer = StringBuffer();
  IOSink? _logSink;

  bool get isRunning => _process != null && !_processExited;

  bool get _isAndroid => _isAndroidProvider?.call() ?? Platform.isAndroid;

  static Future<Process> _defaultProcessLauncher(
    List<String> command, {
    String? workingDirectory,
  }) => Process.start(
    command.first,
    command.sublist(1),
    workingDirectory: workingDirectory,
  );

  void dispose() {
    if (_observing) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _everStarted) {
      unawaited(ensureRunning());
    }
  }

  Future<bool> ensureRunning() async {
    if (_starting != null) return _starting!;
    final starting = _ensureRunning();
    _starting = starting;
    try {
      return await starting;
    } finally {
      _starting = null;
    }
  }

  Future<bool> _ensureRunning() async {
    if (!_isAndroid) {
      _lastError = 'TG影视库本地服务仅支持 Android';
      return false;
    }
    if (isRunning) {
      if (await healthCheck()) return true;
      await stop();
    }
    _lastError = null;
    late final String binaryPath;
    try {
      binaryPath = await _resolveBinary();
    } catch (error) {
      _lastError = 'TG影视库二进制解压失败：$error';
      return false;
    }
    await _seedSessionAndConfig(File(binaryPath).parent);
    final execNote = await _ensureExecutable(binaryPath);
    try {
      final process = await _launch(
        [binaryPath, '-port', '$defaultPort', '-bind', '127.0.0.1'],
        workingDirectory: File(binaryPath).parent.path,
      );
      _trackProcess(process, File(binaryPath).parent);
    } catch (error) {
      _lastError =
          'TG影视库本地服务启动失败：$error'
          '${execNote == null ? '' : '（$execNote）'}';
      return false;
    }
    _everStarted = true;
    for (var attempt = 0; attempt < _healthPollAttempts; attempt++) {
      if (await healthCheck()) {
        _lastError = null;
        return true;
      }
      if (!isRunning) {
        _lastError = 'TG影视库本地服务进程已退出${_exitDetail()}';
        return false;
      }
      if (attempt < _healthPollAttempts - 1) {
        await Future.delayed(_healthPollInterval);
      }
    }
    _lastError = 'TG影视库本地服务健康检查超时（$baseUrl 未在 8 秒内就绪）${_exitDetail()}';
    return false;
  }

  String _exitDetail() {
    final parts = <String>[];
    if (_lastExitCode != null) parts.add('退出码 $_lastExitCode');
    final tail = lastLogTail.trim();
    if (tail.isNotEmpty) parts.add('进程日志：$tail');
    if (parts.isEmpty) return '';
    return '（${parts.join('；')}）';
  }

  Future<bool> healthCheck() async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$baseUrl/'))
          .timeout(_healthTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<TgdramaAuthStatus> authStatus() async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$baseUrl/api/auth/status'))
          .timeout(_healthTimeout);
      if (response.statusCode != 200) {
        return TgdramaAuthStatus(
          authorized: false,
          needPassword: false,
          message: 'HTTP ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const TgdramaAuthStatus(authorized: false, needPassword: false);
      }
      return _parseAuthStatus(decoded);
    } catch (_) {
      return const TgdramaAuthStatus(authorized: false, needPassword: false);
    }
  }

  TgdramaAuthStatus _parseAuthStatus(Map<String, dynamic> body) {
    var authorized = false;
    for (final key in const [
      'authorized',
      'logged_in',
      'loggedIn',
      'authenticated',
      'is_authorized',
    ]) {
      if (body[key] == true) authorized = true;
    }
    var needPassword = false;
    for (final key in const [
      'need_password',
      'needPassword',
      'password_required',
    ]) {
      if (body[key] == true) needPassword = true;
    }
    final phase = _phaseString(body);
    if (phase != null) {
      if (const {
        'authorized',
        'ok',
        'logged_in',
        'loggedin',
        'authenticated',
      }.contains(phase)) {
        authorized = true;
      }
      if (const {
        'need_password',
        'password',
        'password_required',
      }.contains(phase)) {
        needPassword = true;
      }
    }
    final message = _firstString(body, const ['message', 'msg', 'error']);
    return TgdramaAuthStatus(
      authorized: authorized,
      needPassword: needPassword,
      message: message,
    );
  }

  String? _phaseString(Map<String, dynamic> body) {
    final raw = _firstString(body, const ['status', 'phase', 'state']);
    if (raw.isEmpty) return null;
    return raw.trim().toLowerCase();
  }

  String _firstString(Map<String, dynamic> body, List<String> keys) {
    for (final key in keys) {
      final value = body[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return '';
  }

  Future<void> startQrLogin() async {
    final response = await _httpClient
        .get(Uri.parse('$baseUrl/api/auth/qr'))
        .timeout(_healthTimeout);
    if (response.statusCode != 200) {
      throw StateError('扫码登录启动失败：HTTP ${response.statusCode}');
    }
  }

  String get qrImageUrl => '$baseUrl/api/auth/qr.png';

  Future<void> submitPassword(String password) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/api/auth/password'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'password': password}),
        )
        .timeout(_healthTimeout);
    if (response.statusCode == 200) return;
    var detail = '';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        detail = _firstString(decoded, const ['message', 'msg', 'error']);
      }
    } catch (_) {}
    throw StateError(
      '二步验证密码提交失败：HTTP ${response.statusCode}'
      '${detail.isEmpty ? '' : '，$detail'}',
    );
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    _processExited = false;
    if (process == null) {
      _closeLogSink();
      return;
    }
    try {
      process.kill();
    } catch (_) {}
    _closeLogSink();
  }

  void _trackProcess(Process process, Directory workDir) {
    _process = process;
    _processExited = false;
    _lastExitCode = null;
    _logBuffer.clear();
    try {
      _logSink = File(
        '${workDir.path}/plugin.log',
      ).openWrite(mode: FileMode.write);
    } catch (_) {
      _logSink = null;
    }
    void appendChunk(String chunk) {
      if (chunk.isEmpty) return;
      _logBuffer.write(chunk);
      if (_logBuffer.length > _maxLogChars) {
        final kept = _logBuffer.toString().substring(
          _logBuffer.length - _maxLogChars,
        );
        _logBuffer
          ..clear()
          ..write(kept);
      }
      try {
        _logSink?.write(chunk);
      } catch (_) {}
    }

    process.stdout.transform(utf8.decoder).listen(appendChunk, onError: (_) {});
    process.stderr.transform(utf8.decoder).listen(appendChunk, onError: (_) {});
    unawaited(
      process.exitCode.then((code) {
        _lastExitCode = code;
        if (identical(_process, process)) {
          _process = null;
          _processExited = true;
        }
        _closeLogSink();
      }),
    );
  }

  void _closeLogSink() {
    final sink = _logSink;
    _logSink = null;
    try {
      sink?.close();
    } catch (_) {}
  }

  Future<Process> _launch(
    List<String> command, {
    required String workingDirectory,
  }) async {
    try {
      return await _processLauncher(
        command,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (error) {
      if (!_isPermissionDenied(error)) rethrow;
      return await _processLauncher(
        [_linkerPath, ...command],
        workingDirectory: workingDirectory,
      );
    }
  }

  bool _isPermissionDenied(ProcessException error) =>
      error.errorCode == 13 || error.message.contains('Permission denied');

  Future<String?> _ensureExecutable(String binaryPath) async {
    const attempts = [
      ('chmod', '755'),
      (_chmodPath, '755'),
      (_chmodPath, '777'),
    ];
    for (final attempt in attempts) {
      try {
        final result = await _chmodRunner(attempt.$1, [attempt.$2, binaryPath]);
        if (result.exitCode != 0) continue;
      } catch (_) {
        continue;
      }
      if (await _hasOwnerExecBit(binaryPath)) return null;
    }
    if (await _hasOwnerExecBit(binaryPath)) return null;
    final mode = await _fileModeOctal(binaryPath);
    return '二进制文件未含执行位（mode $mode），已尝试链接器兜底启动';
  }

  Future<bool> _hasOwnerExecBit(String path) async {
    try {
      final stat = await File(path).stat();
      return (stat.mode & 0x40) != 0;
    } catch (_) {
      return false;
    }
  }

  Future<String> _fileModeOctal(String path) async {
    try {
      final stat = await File(path).stat();
      return (stat.mode & 0x1FF).toRadixString(8).padLeft(3, '0');
    } catch (_) {
      return '未知';
    }
  }

  Future<String> _resolveBinary() async {
    final supportDir = await _supportDirProvider();
    final dir = Directory('${supportDir.path}/$_binaryDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    final target = File('${dir.path}/$_binaryFileName');
    if (await target.exists()) {
      try {
        final current = md5.convert(await target.readAsBytes()).toString();
        if (current == binaryMd5) return target.path;
      } catch (_) {}
    }
    final bytes = await _assetLoader(binaryAssetPath);
    await target.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    return target.path;
  }

  Future<void> _seedSessionAndConfig(Directory tgdramaDir) async {
    try {
      final sessionFile = File('${tgdramaDir.path}/session.json');
      if (!await sessionFile.exists()) {
        try {
          final bytes = await _assetLoader(sessionAssetPath);
          final raw = bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          );
          if (_looksLikeSession(raw)) {
            await sessionFile.writeAsBytes(raw, flush: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
    try {
      await TgdramaCredentials.ensureConfigYaml(tgdramaDir);
    } catch (_) {}
  }

  bool _looksLikeSession(List<int> raw) {
    try {
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map<String, dynamic>) return false;
      if (decoded['Version'] != 1) return false;
      final data = decoded['Data'];
      if (data is! Map<String, dynamic>) return false;
      final authKey = data['AuthKey'];
      return authKey is String && authKey.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
