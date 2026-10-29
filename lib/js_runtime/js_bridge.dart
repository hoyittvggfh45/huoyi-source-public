import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'host_api.dart';
import 'host_js.dart';
import 'js_engine.dart';

abstract class BridgeHttpClient {
  Future<HostHttpResponse> get(String url, {Map<String, String> headers});

  Future<HostHttpResponse> post(
    String url, {
    Map<String, String> headers,
    Object? body,
    String? contentType,
  });
}

abstract class BridgeKeyValue {
  String? read(String key);

  Future<void> write(String key, String value);

  List<String> keys();
}

class _HostHttpAdapter implements BridgeHttpClient {
  _HostHttpAdapter(this._http);

  final HostHttp _http;

  @override
  Future<HostHttpResponse> get(
    String url, {
    Map<String, String> headers = const {},
  }) =>
      _http.get(url, headers: headers);

  @override
  Future<HostHttpResponse> post(
    String url, {
    Map<String, String> headers = const {},
    Object? body,
    String? contentType,
  }) =>
      _http.post(url, headers: headers, body: body, contentType: contentType);
}

class _HostLocalAdapter implements BridgeKeyValue {
  _HostLocalAdapter(this._local);

  final HostLocal _local;

  @override
  String? read(String key) => _local.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _local.setString(key, value);
  }

  @override
  List<String> keys() => _local.keys();
}

class RuleOutcome {
  const RuleOutcome({
    this.setResultJson,
    this.setResult,
    this.error,
    this.timedOut = false,
  });

  final String? setResultJson;
  final dynamic setResult;
  final String? error;
  final bool timedOut;

  bool get ok => !timedOut && error == null;
}

class JsBridge {
  JsBridge._(
    this.engine,
    this._http,
    this._storage,
    this._storagePublic,
    this._paths, [
    this._fileReader,
  ]);

  factory JsBridge.fromHostApi(
    QuickJsEngine engine,
    HostApi api, {
    Future<String> Function(String resolvedPath, bool isAsset)? fileReader,
  }) {
    return JsBridge._(
      engine,
      _HostHttpAdapter(api.http),
      _HostLocalAdapter(api.local),
      _HostLocalAdapter(api.localPublic),
      api.paths,
      fileReader,
    );
  }

  factory JsBridge.test({
    required QuickJsEngine engine,
    required BridgeHttpClient http,
    required BridgeKeyValue storage,
    required BridgeKeyValue storagePublic,
    required HostPaths paths,
    Future<String> Function(String resolvedPath, bool isAsset)? fileReader,
  }) {
    return JsBridge._(
      engine,
      http,
      storage,
      storagePublic,
      paths,
      fileReader,
    );
  }

  final QuickJsEngine engine;
  final BridgeHttpClient _http;
  final BridgeKeyValue _storage;
  final BridgeKeyValue _storagePublic;
  final HostPaths _paths;
  final Future<String> Function(String resolvedPath, bool isAsset)?
  _fileReader;
  bool _installed = false;

  void _requireInstalled() {
    if (!_installed) {
      throw StateError('JsBridge is not installed');
    }
  }

  Future<void> install() async {
    final storageMap = <String, String>{};
    for (final key in _storage.keys()) {
      final value = _storage.read(key);
      if (value != null) storageMap[key] = value;
    }
    final storagePublicMap = <String, String>{};
    for (final key in _storagePublic.keys()) {
      final value = _storagePublic.read(key);
      if (value != null) storagePublicMap[key] = value;
    }
    engine.eval(
      buildHostPrelude(
        pageCacheJson: '{}',
        storageJson: jsonEncode(storageMap),
        storagePublicJson: jsonEncode(storagePublicMap),
        filesDirJson: jsonEncode(_paths.filesDir),
      ),
    );
    _installed = true;
  }

  Future<void> evalExtra(String code) async {
    _requireInstalled();
    engine.eval(code);
  }

  Future<void> setPageCache(Map<String, String> cache) async {
    _requireInstalled();
    engine.eval('globalThis.__pageCache = ${jsonEncode(cache)};');
  }

  Future<void> setContext({dynamic preResult, String? pageHtml}) async {
    _requireInstalled();
    engine.eval('globalThis.__preResult = ${jsonEncode(preResult)};');
    if (pageHtml != null) {
      engine.eval('globalThis.__pageHtml = ${jsonEncode(pageHtml)};');
    }
  }

  Future<RuleOutcome> runJsCode(
    String code, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _requireInstalled();
    engine.eval(
      'globalThis.__setResultValue = null; globalThis.__ruleDone = false; globalThis.__ruleError = null; globalThis.__pending = []; globalThis.__fetchRegistry = {};',
    );
    final wrapped =
        '(async () => { try { $code } catch (e) { globalThis.__ruleError = String(e); } finally { globalThis.__ruleDone = true; } })();';
    try {
      engine.eval(wrapped);
    } catch (e) {
      return RuleOutcome(error: 'rule wrapper eval failed: $e');
    }
    final delivered = <String>{};
    String? firstError;
    final stopwatch = Stopwatch()..start();
    while (true) {
      try {
        final pendingRaw = engine.eval('JSON.stringify(globalThis.__pending)');
        final pending =
            (jsonDecode(pendingRaw) as List).cast<Map<String, dynamic>>();
        for (final job in pending) {
          final id = job['id'] as String? ?? '';
          if (id.isEmpty || delivered.contains(id)) continue;
          delivered.add(id);
          _dispatch(job);
        }
      } catch (e) {
        firstError ??= 'pending read failed: $e';
      }
      try {
        engine.executePendingJob();
      } catch (e) {
        firstError ??= 'job failed: $e';
      }
      String done = '0';
      String registrySize = '1';
      try {
        done = engine.eval('globalThis.__ruleDone ? "1" : "0"');
        registrySize = engine.eval(
          'String(Object.keys(globalThis.__fetchRegistry).length)',
        );
      } catch (e) {
        firstError ??= 'done check failed: $e';
      }
      if (done == '1' && registrySize == '0') break;
      if (stopwatch.elapsed > timeout) {
        return RuleOutcome(
          timedOut: true,
          error: 'rule timed out after ${timeout.inSeconds}s',
        );
      }
      await Future.delayed(const Duration(milliseconds: 5));
    }
    String? errorText;
    try {
      final errRaw = engine.eval(
        'globalThis.__ruleError === null ? "" : String(globalThis.__ruleError)',
      );
      if (errRaw.isNotEmpty) errorText = errRaw;
    } catch (_) {}
    errorText ??= firstError;
    String? setResultJson;
    dynamic setResult;
    try {
      setResultJson = engine.eval(
        'JSON.stringify(globalThis.__setResultValue === undefined ? null : globalThis.__setResultValue)',
      );
      setResult = jsonDecode(setResultJson);
    } catch (e) {
      errorText ??= 'setResult not JSON-serializable: $e';
    }
    await syncStorageBack();
    return RuleOutcome(
      setResultJson: setResultJson,
      setResult: setResult,
      error: errorText,
    );
  }

  Future<List<String>> pdfaList(String html, String rule) async {
    _requireInstalled();
    final raw = engine.eval(
      'JSON.stringify(pdfa(${jsonEncode(html)}, ${jsonEncode(rule)}))',
    );
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).toList();
    }
    return <String>[];
  }

  Future<String> pdfhValue(String html, String rule) async {
    _requireInstalled();
    final raw = engine.eval(
      'JSON.stringify(pdfh(${jsonEncode(html)}, ${jsonEncode(rule)}))',
    );
    final decoded = jsonDecode(raw);
    if (decoded == null) return '';
    return decoded.toString();
  }

  Future<List<String>> readLogs() async {
    _requireInstalled();
    final raw = engine.eval('JSON.stringify(globalThis.__logs)');
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).toList();
    }
    return <String>[];
  }

  Future<void> syncStorageBack() async {
    _requireInstalled();
    final raw = engine.eval(
      'JSON.stringify({priv: globalThis.__storage, pub: globalThis.__storagePublic})',
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final priv = (decoded['priv'] as Map).cast<String, dynamic>();
    final pub = (decoded['pub'] as Map).cast<String, dynamic>();
    for (final entry in priv.entries) {
      await _storage.write(
        entry.key,
        entry.value is String ? entry.value as String : jsonEncode(entry.value),
      );
    }
    for (final entry in pub.entries) {
      await _storagePublic.write(
        entry.key,
        entry.value is String ? entry.value as String : jsonEncode(entry.value),
      );
    }
  }

  void _dispatch(Map<String, dynamic> job) {
    final id = job['id'] as String;
    final kind = job['kind'] as String? ?? '';
    switch (kind) {
      case 'http':
        final url = job['url'] as String? ?? '';
        final method = (job['method'] as String? ?? 'GET').toUpperCase();
        final headers = _stringMap(job['headers']);
        final body = job['body'];
        final future = method == 'POST'
            ? _http.post(
                url,
                headers: headers,
                body: body is String
                    ? body
                    : (body == null ? null : jsonEncode(body)),
              )
            : _http.get(url, headers: headers);
        future.then(
          (resp) => _deliver(id, true, resp.body),
          onError: (Object e) => _deliver(id, false, e.toString()),
        );
      case 'file':
        final path = job['url'] as String? ?? '';
        _readFile(path).then(
          (text) => _deliver(id, true, text),
          onError: (Object e) => _deliver(id, false, e.toString()),
        );
      case 'download':
        final url = job['url'] as String? ?? '';
        final virtualPath = job['body'] as String? ?? '';
        final headers = _stringMap(job['headers']);
        _download(url, virtualPath, headers).then(
          (saved) => _deliver(id, true, saved),
          onError: (Object e) => _deliver(id, false, e.toString()),
        );
      default:
        _deliver(id, false, 'unknown pending kind: $kind');
    }
  }

  void _deliver(String id, bool ok, String payload) {
    try {
      engine.eval(
        'globalThis.__deliver(${jsonEncode(id)}, ${ok ? 'true' : 'false'}, ${jsonEncode(payload)})',
      );
    } catch (_) {}
  }

  Future<String> _readFile(String path) async {
    final reader = _fileReader;
    if (reader != null) {
      return reader(path, !path.startsWith('/'));
    }
    if (path.startsWith('/')) {
      return File(path).readAsString();
    }
    return HostAssets().loadString(path);
  }

  Future<String> _download(
    String url,
    String virtualPath,
    Map<String, String> headers,
  ) async {
    final resolved = _paths.resolve(virtualPath);
    final resp = await _http.get(url, headers: headers);
    final file = File(resolved);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(resp.bodyBytes);
    return resolved;
  }

  Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) return <String, String>{};
    final out = <String, String>{};
    value.forEach((key, val) {
      out[key.toString()] = val.toString();
    });
    return out;
  }
}
