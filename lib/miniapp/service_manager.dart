import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class MiniAppServiceRequest {
  const MiniAppServiceRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.params,
    required this.headers,
    required this.body,
    required this.url,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> params;
  final Map<String, String> headers;
  final List<int> body;
  final String url;

  Map<String, Object?> toJson() => {
    'method': method,
    'path': path,
    'query': query,
    'params': params,
    'headers': headers,
    'body': utf8.decode(body, allowMalformed: true),
    'url': url,
  };
}

class MiniAppServiceResponse {
  const MiniAppServiceResponse({
    required this.status,
    required this.body,
    this.headers = const {},
  });

  final int status;
  final List<int> body;
  final Map<String, String> headers;

  factory MiniAppServiceResponse.text(String text, {int status = 200}) =>
      MiniAppServiceResponse(
        status: status,
        body: utf8.encode(text),
        headers: const {'Content-Type': 'text/plain; charset=utf-8'},
      );

  factory MiniAppServiceResponse.json(Object? data, {int status = 200}) =>
      MiniAppServiceResponse(
        status: status,
        body: utf8.encode(jsonEncode(data)),
        headers: const {'Content-Type': 'application/json; charset=utf-8'},
      );

  factory MiniAppServiceResponse.unavailable() =>
      MiniAppServiceResponse.text('service unavailable', status: 503);

  factory MiniAppServiceResponse.notFound() =>
      MiniAppServiceResponse.text('not found', status: 404);

  factory MiniAppServiceResponse.forbidden() =>
      MiniAppServiceResponse.text('forbidden', status: 403);

  factory MiniAppServiceResponse.tooLarge() =>
      MiniAppServiceResponse.text('response too large', status: 502);

  factory MiniAppServiceResponse.timeout() =>
      MiniAppServiceResponse.text('service timeout', status: 504);

  static MiniAppServiceResponse? fromHandlerResult(Object? result) {
    if (result is MiniAppServiceResponse) return result;
    if (result == null) return MiniAppServiceResponse.unavailable();
    if (result is String) return MiniAppServiceResponse.text(result);
    if (result is Map) {
      final status = result['status'];
      final headers = <String, String>{};
      final rawHeaders = result['headers'];
      if (rawHeaders is Map) {
        rawHeaders.forEach((key, value) {
          if (value != null) headers[key.toString()] = value.toString();
        });
      }
      final base64 = result['bodyBase64'];
      if (base64 is String) {
        try {
          return MiniAppServiceResponse(
            status: status is int ? status : 200,
            body: base64Decode(base64),
            headers: headers,
          );
        } on FormatException {
          return MiniAppServiceResponse.tooLarge();
        }
      }
      final body = result['body'];
      if (body is String) {
        return MiniAppServiceResponse(
          status: status is int ? status : 200,
          body: utf8.encode(body),
          headers: headers,
        );
      }
      if (body == null) {
        return MiniAppServiceResponse(
          status: status is int ? status : 200,
          body: const [],
          headers: headers,
        );
      }
    }
    return MiniAppServiceResponse.tooLarge();
  }
}

typedef MiniAppServiceHandler =
    Future<MiniAppServiceResponse?> Function(MiniAppServiceRequest request);

class MiniAppServiceInstance {
  MiniAppServiceInstance({
    required this.appId,
    required this.token,
    required this.handler,
    required this.registrationId,
  }) : registeredAt = DateTime.now(),
       lastUsed = DateTime.now();

  final String appId;
  final String token;
  final MiniAppServiceHandler handler;
  final int registrationId;
  final DateTime registeredAt;
  DateTime lastUsed;
}

class MiniAppServiceManager {
  MiniAppServiceManager({
    this.maxInstances = 3,
    this.callTimeout = const Duration(seconds: 60),
    this.maxBodyBytes = 1024 * 1024,
  });

  static const servicePathPrefix = 'miniapp';

  final int maxInstances;
  final Duration callTimeout;
  final int maxBodyBytes;

  final _instances = <String, MiniAppServiceInstance>{};
  final _tokens = <String, String>{};
  final _changes = StreamController<List<MiniAppServiceInstance>>.broadcast();
  HttpServer? _server;
  bool _lanEnabled = false;
  int _nextRegistrationId = 1;
  final _random = Random.secure();

  Future<bool> Function(String appId)? onWakeRequest;

  Stream<List<MiniAppServiceInstance>> get changes => _changes.stream;

  List<MiniAppServiceInstance> get instances {
    final list = _instances.values.toList();
    list.sort((a, b) => a.registeredAt.compareTo(b.registeredAt));
    return list;
  }

  bool get isRunning => _server != null;
  bool get lanEnabled => _lanEnabled;
  int? get port => _server?.port;

  MiniAppServiceInstance? instanceFor(String appId) => _instances[appId];

  bool isRegistered(String appId) => _instances.containsKey(appId);

  String? localAddress(String appId) {
    final instance = _instances[appId];
    final server = _server;
    if (instance == null || server == null) return null;
    return 'http://127.0.0.1:${server.port}/$servicePathPrefix/$appId'
        '?token=${instance.token}';
  }

  Future<String?> lanAddress(String appId) async {
    final instance = _instances[appId];
    final server = _server;
    if (instance == null || server == null || !_lanEnabled) return null;
    final address = await _firstPrivateIPv4();
    if (address == null) return null;
    return 'http://$address:${server.port}/$servicePathPrefix/$appId'
        '?token=${instance.token}';
  }

  Future<MiniAppServiceInstance> register(
    String appId,
    MiniAppServiceHandler handler,
  ) async {
    if (_instances.length >= maxInstances && !_instances.containsKey(appId)) {
      MiniAppServiceInstance? oldest;
      for (final instance in _instances.values) {
        if (oldest == null || instance.lastUsed.isBefore(oldest.lastUsed)) {
          oldest = instance;
        }
      }
      if (oldest != null) _instances.remove(oldest.appId);
    }
    final instance = MiniAppServiceInstance(
      appId: appId,
      token: _tokens.putIfAbsent(appId, _newToken),
      handler: handler,
      registrationId: _nextRegistrationId++,
    );
    _instances[appId] = instance;
    _emit();
    try {
      await start();
    } catch (_) {}
    return instance;
  }

  void unregister(int registrationId) {
    var removed = false;
    _instances.removeWhere((_, instance) {
      final match = instance.registrationId == registrationId;
      if (match) removed = true;
      return match;
    });
    if (removed) _emit();
  }

  void unregisterApp(String appId) {
    if (_instances.remove(appId) != null) _emit();
  }

  Future<void> start() async {
    if (_server != null) return;
    final address = _lanEnabled
        ? InternetAddress.anyIPv4
        : InternetAddress.loopbackIPv4;
    final server = await HttpServer.bind(address, 0);
    _server = server;
    server.listen(_handleHttpRequest);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> setLanEnabled(bool enabled) async {
    if (_lanEnabled == enabled) return;
    _lanEnabled = enabled;
    if (_server != null) {
      await stop();
      if (enabled) await start();
    }
  }

  Future<MiniAppServiceResponse?> dispatchLocal(
    String appId,
    MiniAppServiceRequest request,
  ) async {
    final instance = _instances[appId];
    if (instance == null) return null;
    instance.lastUsed = DateTime.now();
    try {
      final result = await instance
          .handler(request)
          .timeout(callTimeout);
      final response = MiniAppServiceResponse.fromHandlerResult(result);
      if (response == null) return MiniAppServiceResponse.unavailable();
      if (response.body.length > maxBodyBytes) {
        return MiniAppServiceResponse.tooLarge();
      }
      return response;
    } on TimeoutException {
      return MiniAppServiceResponse.timeout();
    } catch (_) {
      return MiniAppServiceResponse.unavailable();
    }
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    try {
      final response = await _routeHttp(request);
      await _writeHttp(request.response, response);
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<MiniAppServiceResponse> _routeHttp(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length < 2 || segments[0] != servicePathPrefix) {
      return MiniAppServiceResponse.notFound();
    }
    final appId = segments[1];
    final remote = request.connectionInfo?.remoteAddress;
    if (remote != null && !isLoopbackAddress(remote)) {
      if (!_lanEnabled || !isPrivateOrLoopbackIp(remote)) {
        return MiniAppServiceResponse.forbidden();
      }
    }
    final instance = _instances[appId];
    if (instance == null) return MiniAppServiceResponse.unavailable();
    final token =
        request.uri.queryParameters['token'] ??
        request.headers.value('x-miniapp-token');
    if (token == null || token != instance.token) {
      return MiniAppServiceResponse.forbidden();
    }
    final body = await request.fold<List<int>>(
      [],
      (acc, chunk) => acc..addAll(chunk),
    );
    final headers = <String, String>{};
    request.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    final rest = segments.length > 2
        ? '/${segments.sublist(2).join('/')}'
        : '/';
    final serviceRequest = MiniAppServiceRequest(
      method: request.method,
      path: rest,
      query: request.uri.queryParameters,
      params: request.uri.queryParameters,
      headers: headers,
      body: body,
      url: 'miniapp://$appId$rest',
    );
    final dispatched = await dispatchLocal(appId, serviceRequest);
    return dispatched ?? MiniAppServiceResponse.unavailable();
  }

  Future<void> _writeHttp(
    HttpResponse http,
    MiniAppServiceResponse response,
  ) async {
    http.statusCode = response.status;
    response.headers.forEach((name, value) {
      if (_hopByHop.contains(name.toLowerCase())) return;
      try {
        http.headers.set(name, value);
      } catch (_) {}
    });
    http.headers.contentLength = response.body.length;
    http.add(response.body);
    await http.close();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(instances);
  }

  String _newToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String?> _firstPrivateIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (isPrivateOrLoopbackIp(address)) return address.address;
        }
      }
    } catch (_) {}
    return null;
  }

  static bool isLoopbackAddress(InternetAddress address) =>
      address.isLoopback;

  static bool isPrivateOrLoopbackIp(InternetAddress address) {
    if (address.isLoopback) return true;
    if (address.type != InternetAddressType.IPv4) {
      return address.address == '::1' ||
          address.address.toLowerCase().startsWith('fe80:');
    }
    final parts = address.address.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((octet) => octet == null)) return false;
    final a = octets[0]!;
    final b = octets[1]!;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 169 && b == 254) return true;
    return false;
  }

  static const _hopByHop = {
    'host',
    'content-length',
    'connection',
    'transfer-encoding',
    'keep-alive',
    'proxy-connection',
    'trailer',
    'upgrade',
  };
}
