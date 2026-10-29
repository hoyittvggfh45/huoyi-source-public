import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:duanju_app/js_runtime/host_api.dart';
import 'package:duanju_app/js_runtime/host_js.dart';
import 'package:duanju_app/js_runtime/js_bridge.dart';
import 'package:duanju_app/js_runtime/js_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements BridgeKeyValue {
  final _map = <String, String>{};

  @override
  String? read(String key) => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  List<String> keys() => _map.keys.toList();
}

class _StubHttp implements BridgeHttpClient {
  _StubHttp(this._bodies);

  final Map<String, String> _bodies;

  @override
  Future<HostHttpResponse> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final body = _bodies[url];
    if (body == null) throw Exception('stub: no body for $url');
    return HostHttpResponse(
      statusCode: 200,
      body: body,
      bodyBytes: utf8.encode(body),
      headers: const {},
    );
  }

  @override
  Future<HostHttpResponse> post(
    String url, {
    Map<String, String> headers = const {},
    Object? body,
    String? contentType,
  }) async {
    return get(url, headers: headers);
  }
}

Future<JsBridge> _openBridge({
  Map<String, String> bodies = const {},
  String filesDir = '/tmp/js_bridge_files',
  Future<String> Function(String resolvedPath, bool isAsset)? fileReader,
}) async {
  final engine = QuickJsEngine.open('/tmp/libquickjs.so');
  final storage = _MemoryStorage();
  final storagePublic = _MemoryStorage();
  final bridge = JsBridge.test(
    engine: engine,
    http: _StubHttp(bodies),
    storage: storage,
    storagePublic: storagePublic,
    paths: HostPaths(filesDir: filesDir),
    fileReader: fileReader,
  );
  await bridge.install();
  addTearDown(engine.dispose);
  return bridge;
}

BigInt _randomPrime(int bits, Random random) {
  BigInt randomOdd(int bits) {
    var value = BigInt.zero;
    for (var i = 0; i < bits; i++) {
      if (random.nextBool()) value |= (BigInt.one << i);
    }
    value |= (BigInt.one << (bits - 1)) | BigInt.one;
    return value;
  }

  bool isProbablePrime(BigInt n) {
    if (n < BigInt.two) return false;
    for (final p in <int>[2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]) {
      if (n == BigInt.from(p)) return true;
      if (n % BigInt.from(p) == BigInt.zero) return false;
    }
    var d = n - BigInt.one;
    var s = 0;
    while (d.isEven) {
      d ~/= BigInt.two;
      s++;
    }
    for (var i = 0; i < 20; i++) {
      final a = BigInt.from(2) +
          (BigInt.from(random.nextInt(1 << 32)) % (n - BigInt.from(4)));
      var x = a.modPow(d, n);
      if (x == BigInt.one || x == n - BigInt.one) continue;
      var cont = false;
      for (var r = 1; r < s; r++) {
        x = (x * x) % n;
        if (x == n - BigInt.one) {
          cont = true;
          break;
        }
      }
      if (cont) continue;
      return false;
    }
    return true;
  }

  while (true) {
    final candidate = randomOdd(bits);
    if (isProbablePrime(candidate)) return candidate;
  }
}

void main() {
  test('setResult capture', () async {
    final bridge = await _openBridge();
    final outcome = await bridge.runJsCode('setResult({a: 1, b: [2, 3]});');
    expect(outcome.ok, isTrue);
    expect(outcome.setResult, {'a': 1, 'b': [2, 3]});
  });

  test('storage private public and storage0 json', () async {
    final bridge = await _openBridge();
    final outcome = await bridge.runJsCode(
      'windows.setItem("k", "v"); windows.setPublicItem("p", "q"); '
      'windows.storage0.setItem("o", {x: 9}); '
      'setResult([windows.getItem("k"), windows.getPublicItem("p"), windows.storage0.getItem("o").x]);',
    );
    expect(outcome.ok, isTrue);
    expect(outcome.setResult, ['v', 'q', 9]);
  });

  test('storage sync back to dart', () async {
    final storage = _MemoryStorage();
    final engine = QuickJsEngine.open('/tmp/libquickjs.so');
    addTearDown(engine.dispose);
    final bridge = JsBridge.test(
      engine: engine,
      http: _StubHttp(const {}),
      storage: storage,
      storagePublic: _MemoryStorage(),
      paths: HostPaths(filesDir: '/tmp/js_bridge_files'),
    );
    await bridge.install();
    await bridge.runJsCode('windows.setItem("back", "yes");');
    expect(storage.read('back'), 'yes');
  });

  test('cached fetch returns synchronously', () async {
    final bridge = await _openBridge();
    await bridge.setPageCache({'http://x/list': '<html>cached</html>'});
    final outcome = await bridge.runJsCode(
      'var h = fetch("http://x/list"); setResult(h);',
    );
    expect(outcome.ok, isTrue);
    expect(outcome.setResult, '<html>cached</html>');
  });

  test('uncached fetch awaited through job drain', () async {
    final bridge = await _openBridge(
      bodies: {'http://x/api': 'api-body'},
    );
    final outcome = await bridge.runJsCode(
      'var h = await fetch("http://x/api"); setResult(h);',
    );
    expect(outcome.ok, isTrue);
    expect(outcome.setResult, 'api-body');
  });

  test('http complete callback fires after delivery', () async {
    final bridge = await _openBridge(
      bodies: {'http://x/api': 'cb-body'},
    );
    final outcome = await bridge.runJsCode(
      '_http("http://x/api", {complete: function(r) { setResult(r); }});',
    );
    expect(outcome.ok, isTrue);
    expect(outcome.setResult, 'cb-body');
  });

  test('getPath virtual mapping', () async {
    final bridge = await _openBridge(filesDir: '/tmp/js_bridge_files');
    final outcome = await bridge.runJsCode(
      'setResult([getPath("hiker://files/a/b.txt"), getPath("hiker://assets/x.js"), getPath("hiker://empty")]);',
    );
    expect(outcome.ok, isTrue);
    expect(outcome.setResult, ['/tmp/js_bridge_files/a/b.txt', 'x.js', '']);
  });

  test('base64 round trip', () async {
    final bridge = await _openBridge();
    final outcome = await bridge.runJsCode(
      'setResult([_base64.encodeToString("hi"), _base64.decodeToString("aGk=")]);',
    );
    expect(outcome.ok, isTrue);
    expect(outcome.setResult, ['aGk=', 'hi']);
  });

  test('md5 vectors', () async {
    final bridge = await _openBridge();
    final outcome = await bridge.runJsCode(
      'setResult([__lxMd5(""), __lxMd5("abc"), __lxMd5("The quick brown fox jumps over the lazy dog")]);',
    );
    expect(outcome.ok, isTrue);
    expect(outcome.setResult, [
      'd41d8cd98f00b204e9800998ecf8427e',
      '900150983cd24fb0d6963f7d28e17f72',
      '9e107d9d372bb6826bd81d3542a419d6',
    ]);
  });

  test('rsa round trip with generated key', () async {
    final random = Random.secure();
    final p = _randomPrime(256, random);
    var q = _randomPrime(256, random);
    while (q == p) {
      q = _randomPrime(256, random);
    }
    final n = p * q;
    final phi = (p - BigInt.one) * (q - BigInt.one);
    final e = BigInt.from(65537);
    final d = e.modInverse(phi);
    final bridge = await _openBridge();
    final outcome = await bridge.runJsCode(
      'var c = __lxRsa("encrypt", "hello-rsa", "${n.toRadixString(16)}", "${e.toRadixString(16)}"); '
      'setResult(__lxRsa("decrypt", c, "${n.toRadixString(16)}", "${d.toRadixString(16)}"));',
    );
    expect(outcome.ok, isTrue, reason: outcome.error);
    expect(outcome.setResult, 'hello-rsa');
  });

  test('aes round trip through crypto-js bundle', () async {
    final bridge = await _openBridge();
    final cryptoJs = await File('assets/js_runtime/crypto-js.js')
        .readAsString();
    await bridge.evalExtra(cryptoJs);
    await bridge.evalExtra(lxAesJs);
    final outcome = await bridge.runJsCode(
      'var c = __lxAes("encrypt", "hello-aes", "secret-key-12345", "iv-1234567890abc"); '
      'setResult([c !== "hello-aes", __lxAes("decrypt", c, "secret-key-12345", "iv-1234567890abc")]);',
    );
    expect(outcome.ok, isTrue, reason: outcome.error);
    expect(outcome.setResult, [true, 'hello-aes']);
  });

  test('fy_bridge_app file fetch through fileReader', () async {
    final bridge = await _openBridge(
      fileReader: (path, isAsset) async => 'file-text:$path',
    );
    final outcome = await bridge.runJsCode(
      'var t = await fy_bridge_app.fetch("hiker://files/s.js"); setResult(t);',
    );
    expect(outcome.ok, isTrue, reason: outcome.error);
    expect(outcome.setResult, 'file-text:/tmp/js_bridge_files/s.js');
  });

  test('downloadFile writes bytes through stub http', () async {
    final dir = await Directory.systemTemp.createTemp('js_bridge_dl');
    addTearDown(() => dir.delete(recursive: true));
    final bridge = await _openBridge(
      bodies: {'http://x/f.bin': 'bin-content'},
      filesDir: dir.path,
    );
    final outcome = await bridge.runJsCode(
      'var p = await downloadFile("http://x/f.bin", "hiker://files/f.bin"); setResult(p);',
    );
    expect(outcome.ok, isTrue, reason: outcome.error);
    final saved = outcome.setResult as String;
    expect(await File(saved).readAsString(), 'bin-content');
  });

  test('rule error surfaces instead of silent empty', () async {
    final bridge = await _openBridge();
    final outcome = await bridge.runJsCode('throw new Error("boom");');
    expect(outcome.ok, isFalse);
    expect(outcome.error, contains('boom'));
  });
}
