import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'tgdrama_credentials.dart';

class PhoneLoginAvailability {
  const PhoneLoginAvailability({required this.available, required this.reason});

  final bool available;

  final String reason;
}

class TgdramaPhoneLoginService {
  TgdramaPhoneLoginService({
    Directory? supportDir,
    String? helperPath,
    String? configPath,
    String? sessionPath,
    String? statePath,
    Future<ProcessResult> Function(String executable, List<String> args)?
    runProcess,
    Future<ByteData> Function(String assetPath)? assetLoader,
    this._bundledApiId,
    this._bundledApiHash,
  }) : _supportDirOverride = supportDir,
       _helperPathOverride = helperPath,
       _configPathOverride = configPath,
       _sessionPathOverride = sessionPath,
       _statePathOverride = statePath,
       _runProcess = runProcess ?? Process.run,
       _assetLoader = assetLoader ?? rootBundle.load;

  final Directory? _supportDirOverride;
  final String? _helperPathOverride;
  final String? _configPathOverride;
  final String? _sessionPathOverride;
  final String? _statePathOverride;
  final Future<ProcessResult> Function(String executable, List<String> args)
  _runProcess;
  final Future<ByteData> Function(String assetPath) _assetLoader;

  final String? _bundledApiId;
  final String? _bundledApiHash;

  static const String helperAssetPath = 'assets/tgdrama/tgphone';
  static const String helperRelativePath = 'tgdrama/tgphone';
  static const String configRelativePath = 'tgdrama/config.yaml';
  static const String sessionRelativePath = 'tgdrama/session.json';
  static const String stateRelativePath = 'tgdrama/phone_login_state.json';

  Future<Directory> _supportDir() async {
    final override = _supportDirOverride;
    if (override != null) return override;
    return getApplicationSupportDirectory();
  }

  Future<Directory> _tgdramaDir() async {
    final support = await _supportDir();
    return Directory('${support.path}/tgdrama');
  }

  Future<String> _helperPath() async {
    final override = _helperPathOverride;
    if (override != null) return override;
    final dir = await _tgdramaDir();
    return '${dir.path}/tgphone';
  }

  Future<String> _configPath() async {
    final override = _configPathOverride;
    if (override != null) return override;
    final dir = await _tgdramaDir();
    return '${dir.path}/config.yaml';
  }

  Future<String> _sessionPath() async {
    final override = _sessionPathOverride;
    if (override != null) return override;
    final dir = await _tgdramaDir();
    return '${dir.path}/session.json';
  }

  Future<String> _statePath() async {
    final override = _statePathOverride;
    if (override != null) return override;
    final dir = await _tgdramaDir();
    return '${dir.path}/phone_login_state.json';
  }

  String get _apiId => _bundledApiId ?? TgdramaCredentials.apiId;
  String get _apiHash => _bundledApiHash ?? TgdramaCredentials.apiHash;

  Future<bool> ensureReady() async {
    var helperOk = false;
    var credsOk = false;
    try {
      helperOk = await _ensureHelperExtracted();
    } catch (_) {
      helperOk = false;
    }
    try {
      final dir = await _tgdramaDir();
      credsOk = await _ensureConfigYaml(dir);
    } catch (_) {
      credsOk = false;
    }
    return helperOk && credsOk;
  }

  Future<bool> _ensureHelperExtracted() async {
    final path = await _helperPath();
    final file = File(path);
    try {
      final bytes = (await _assetLoader(helperAssetPath)).buffer.asUint8List();
      final digest = md5.convert(bytes).toString();
      if (await file.exists()) {
        final current = md5.convert(await file.readAsBytes()).toString();
        if (current == digest) {
          return true;
        }
      }
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      try {
        await Process.run('chmod', ['755', path]);
      } catch (_) {}
      return await file.exists();
    } catch (_) {
      return await file.exists();
    }
  }

  Future<bool> _ensureConfigYaml(Directory tgdramaDir) async {
    final configFile = File('${tgdramaDir.path}/config.yaml');
    try {
      if (await configFile.exists()) {
        final text = await configFile.readAsString();
        final creds = parseTelegramCredentials(text);
        if (creds.$1 != null &&
            creds.$1!.isNotEmpty &&
            creds.$2 != null &&
            creds.$2!.isNotEmpty) {
          return true;
        }
      }
    } catch (_) {}
    final apiId = _apiId;
    final apiHash = _apiHash;
    if (apiId.isEmpty || apiHash.isEmpty) return false;
    try {
      await tgdramaDir.create(recursive: true);
      await configFile.writeAsString(
        TgdramaCredentials.buildConfigYaml(
          apiId: apiId,
          apiHash: apiHash,
          dataDir: tgdramaDir.path,
        ),
        flush: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<PhoneLoginAvailability> checkAvailability() async {
    try {
      await ensureReady();
    } catch (_) {}
    final helper = File(await _helperPath());
    if (!await helper.exists()) {
      return const PhoneLoginAvailability(
        available: false,
        reason: '手机号登录暂不可用：登录助手未就绪（tgphone 未安装）',
      );
    }
    final config = File(await _configPath());
    if (!await config.exists()) {
      return const PhoneLoginAvailability(
        available: false,
        reason: '手机号登录暂不可用：插件配置文件不存在，缺少 Telegram API 凭证',
      );
    }
    final creds = await _readTelegramCredentials(config);
    if (creds.$1 == null ||
        creds.$1!.isEmpty ||
        creds.$2 == null ||
        creds.$2!.isEmpty) {
      return const PhoneLoginAvailability(
        available: false,
        reason:
            '手机号登录暂不可用：缺少 Telegram API 凭证（config.yaml 里没有 api_id/api_hash）',
      );
    }
    return const PhoneLoginAvailability(available: true, reason: '可用');
  }

  Future<void> sendCode(String phone) async {
    final availability = await checkAvailability();
    if (!availability.available) {
      throw StateError(availability.reason);
    }
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) {
      throw StateError('请先输入手机号');
    }
    final helper = await _helperPath();
    final result = await _runHelper(helper, [
      'send-code',
      '--phone',
      normalized,
      '--config',
      await _configPath(),
      '--session',
      await _sessionPath(),
      '--state',
      await _statePath(),
    ]);
    _throwIfHelperFailed(result, '发送验证码失败');
    final state = File(await _statePath());
    if (!await state.exists()) {
      throw StateError('发送验证码失败：助手未返回验证码凭证（state 文件缺失）');
    }
    final hash = _readPhoneCodeHash(await state.readAsString());
    if (hash == null || hash.isEmpty) {
      throw StateError('发送验证码失败：助手未返回验证码凭证（phone_code_hash 为空）');
    }
  }

  Future<void> verifyCode({
    required String phone,
    required String code,
    String? password,
  }) async {
    final availability = await checkAvailability();
    if (!availability.available) {
      throw StateError(availability.reason);
    }
    if (code.trim().isEmpty) {
      throw StateError('请先输入短信验证码');
    }
    final state = File(await _statePath());
    if (!await state.exists()) {
      throw StateError('请先点“发送验证码”，收到短信后再输验证码登录');
    }
    final hash = _readPhoneCodeHash(await state.readAsString());
    if (hash == null || hash.isEmpty) {
      throw StateError('验证码凭证已失效，请重新点“发送验证码”');
    }
    final args = <String>[
      'verify',
      '--phone',
      normalizePhone(phone),
      '--code',
      code.trim(),
      '--config',
      await _configPath(),
      '--session',
      await _sessionPath(),
      '--state',
      await _statePath(),
    ];
    final pwd = password?.trim() ?? '';
    if (pwd.isNotEmpty) {
      args.addAll(['--password', pwd]);
    }
    final helper = await _helperPath();
    final result = await _runHelper(helper, args);
    _throwIfHelperFailed(result, '登录失败');
    try {
      if (await state.exists()) await state.delete();
    } catch (_) {}
  }

  static String normalizePhone(String phone) {
    var p = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.isEmpty) return p;
    if (p.startsWith('+')) return p;
    if (p.startsWith('86') && p.length == 13) return '+$p';
    if (p.length == 11 && p.startsWith('1')) return '+86$p';
    return p;
  }

  Future<(String?, String?)> _readTelegramCredentials(File config) async {
    final text = await config.readAsString();
    return parseTelegramCredentials(text);
  }

  static (String?, String?) parseTelegramCredentials(String yamlText) {
    String? apiId;
    String? apiHash;
    var inTelegramSection = false;
    for (final rawLine in yamlText.split('\n')) {
      final line = rawLine.split('#').first;
      if (line.trim().isEmpty) continue;
      final indent = line.length - line.trimLeft().length;
      final trimmed = line.trim();
      if (indent == 0 && trimmed.endsWith(':')) {
        inTelegramSection = trimmed == 'telegram:';
        continue;
      }
      final colon = trimmed.indexOf(':');
      if (colon <= 0) continue;
      final key = trimmed.substring(0, colon).trim();
      if (key != 'api_id' && key != 'api_hash') continue;
      if (!inTelegramSection && indent == 0) {
        if (key == 'api_id' && apiId == null) {
          apiId = _unquote(trimmed.substring(colon + 1).trim());
        } else if (key == 'api_hash' && apiHash == null) {
          apiHash = _unquote(trimmed.substring(colon + 1).trim());
        }
        continue;
      }
      if (inTelegramSection) {
        if (key == 'api_id') {
          apiId = _unquote(trimmed.substring(colon + 1).trim());
        } else {
          apiHash = _unquote(trimmed.substring(colon + 1).trim());
        }
      }
    }
    return (apiId, apiHash);
  }

  static String _unquote(String value) {
    var v = value.trim();
    if (v.length >= 2) {
      if ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
    }
    return v.trim();
  }

  static String? _readPhoneCodeHash(String stateJson) {
    final match = RegExp(
      r'"phone_code_hash"\s*:\s*"([^"]*)"',
    ).firstMatch(stateJson);
    return match?.group(1);
  }

  Future<ProcessResult> _runHelper(String helper, List<String> args) async {
    try {
      return await _runProcess(helper, args);
    } on ProcessException catch (error) {
      final denied =
          error.errorCode == 13 || error.message.contains('Permission denied');
      if (!denied) rethrow;
      return await _runProcess('/system/bin/linker64', [helper, ...args]);
    }
  }

  void _throwIfHelperFailed(ProcessResult result, String action) {
    final out = StringBuffer();
    if (result.stdout != null) out.write(result.stdout.toString());
    if (result.stderr != null) {
      if (out.isNotEmpty) out.write('\n');
      out.write(result.stderr.toString());
    }
    final output = out.toString().trim();
    if (result.exitCode != 0 || output.toLowerCase().contains('error')) {
      throw StateError('$action：${_lastLines(output, 5)}');
    }
  }

  static String _lastLines(String text, int count) {
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '助手未返回错误详情';
    if (lines.length <= count) return lines.join('\n');
    return lines.sublist(lines.length - count).join('\n');
  }
}
