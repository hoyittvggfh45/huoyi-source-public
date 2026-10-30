import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'bridge.dart';
import 'installer.dart';
import 'manifest.dart';
import 'permissions.dart';
import 'renderer.dart';
import 'service_manager.dart';
import 'storage.dart';

const miniappServiceLanPrefKey = 'miniapp_service_lan_enabled';

class _PendingService {
  const _PendingService({required this.manifest, required this.directory});

  final MiniAppManifest manifest;
  final Directory directory;
}

class MiniAppServiceHost extends StatefulWidget {
  const MiniAppServiceHost({super.key});

  @override
  State<MiniAppServiceHost> createState() => _MiniAppServiceHostState();
}

class _MiniAppServiceHostState extends State<MiniAppServiceHost> {
  final _manager = MiniAppBridge.sharedServices;
  final _pending = <String, _PendingService>{};

  @override
  void initState() {
    super.initState();
    _manager.onWakeRequest = _wake;
    unawaited(_restoreLan());
  }

  @override
  void dispose() {
    if (_manager.onWakeRequest == _wake) _manager.onWakeRequest = null;
    super.dispose();
  }

  Future<void> _restoreLan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(miniappServiceLanPrefKey) ?? false;
      if (enabled) await _manager.setLanEnabled(true);
    } catch (_) {}
  }

  Future<bool> _wake(String appId) async {
    if (_manager.isRegistered(appId)) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final installer = MiniAppInstaller(Directory('${docs.path}/miniapps'));
      final manifest = await installer.load(installer.directoryFor(appId));
      if (!manifest.permissions.contains(MiniAppPermissions.service)) {
        return false;
      }
      if (!mounted) return false;
      setState(() {
        _pending[appId] = _PendingService(
          manifest: manifest,
          directory: installer.directoryFor(appId),
        );
      });
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        if (_manager.isRegistered(appId)) return true;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return _manager.isRegistered(appId);
    } catch (_) {
      return false;
    }
  }

  void _removePending(String appId) {
    if (!mounted) return;
    setState(() => _pending.remove(appId));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.shrink(
      child: Stack(
        children: [
          for (final entry in _pending.entries)
            _ServiceInstanceView(
              key: ValueKey('service-${entry.key}'),
              manifest: entry.value.manifest,
              directory: entry.value.directory,
              onGone: () => _removePending(entry.key),
            ),
        ],
      ),
    );
  }
}

class _ServiceInstanceView extends StatefulWidget {
  const _ServiceInstanceView({
    super.key,
    required this.manifest,
    required this.directory,
    required this.onGone,
  });

  final MiniAppManifest manifest;
  final Directory directory;
  final void Function() onGone;

  @override
  State<_ServiceInstanceView> createState() => _ServiceInstanceViewState();
}

class _ServiceInstanceViewState extends State<_ServiceInstanceView> {
  final _manager = MiniAppBridge.sharedServices;
  WebViewController? _controller;
  HttpServer? _server;
  MiniAppBridge? _bridge;
  int? _registrationId;
  bool _disposed = false;
  final _serveCalls = <int, Completer<Object?>>{};
  int _serveSeq = 0;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(_init());
    }
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      _bridge = MiniAppBridge(
        manifest: widget.manifest,
        storage: MiniAppStorage(prefs, widget.manifest.id),
        onReply: _reply,
        onServeRegistered: _registerService,
        onServeReply: _handleServeReply,
      );
      await _start();
    } catch (_) {}
  }

  Future<void> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_disposed) {
      await server.close(force: true);
      return;
    }
    _server = server;
    server.listen(_serveFile);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'JhMiniapp',
        onMessageReceived: (message) {
          unawaited(_bridge?.handleMessage(message.message));
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.startsWith('http://127.0.0.1:${server.port}/')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) async {
            await _controller?.runJavaScript(MiniAppBridge.injectionScript);
          },
        ),
      );
    _controller = controller;
    await controller.loadRequest(
      Uri.parse('http://127.0.0.1:${server.port}/${widget.manifest.entry}'),
    );
    if (mounted) setState(() {});
  }

  Future<void> _serveFile(HttpRequest request) async {
    try {
      final relative = request.uri.path.replaceFirst(RegExp('^/'), '');
      final target = p.normalize(p.join(widget.directory.path, relative));
      final inside = p.isWithin(widget.directory.path, target);
      final file = File(target);
      if (!inside || !await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final bytes = await file.readAsBytes();
      if (p.extension(relative).toLowerCase() == '.html') {
        try {
          final html = utf8.decode(bytes);
          request.response.headers.contentType =
              ContentType('text', 'html', charset: 'utf-8');
          request.response.add(
            utf8.encode(
              injectMiniAppBootstrap(html, MiniAppBridge.injectionScript),
            ),
          );
        } catch (_) {
          request.response.add(bytes);
        }
      } else {
        request.response.add(bytes);
      }
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  void _reply(int id, Object? result, String? error) {
    final controller = _controller;
    if (controller == null) return;
    if (error != null) {
      unawaited(
        controller.runJavaScript(
          'window.ant._reject($id, ${jsonEncode(error)})',
        ),
      );
    } else {
      unawaited(
        controller.runJavaScript(
          'window.ant._resolve($id, ${jsonEncode(result)})',
        ),
      );
    }
  }

  void _registerService() {
    if (_registrationId != null || _disposed) return;
    unawaited(
      _manager
          .register(widget.manifest.id, _callServeHandler)
          .then((instance) {
            if (_disposed) {
              _manager.unregister(instance.registrationId);
              return;
            }
            _registrationId = instance.registrationId;
          }),
    );
  }

  void _handleServeReply(int id, Object? result, String? error) {
    final completer = _serveCalls.remove(id);
    if (completer == null) return;
    if (error != null) {
      completer.completeError(MiniAppDenied(error));
    } else {
      completer.complete(result);
    }
  }

  Future<MiniAppServiceResponse?> _callServeHandler(
    MiniAppServiceRequest request,
  ) async {
    final controller = _controller;
    if (controller == null) return MiniAppServiceResponse.unavailable();
    final id = ++_serveSeq;
    final completer = Completer<Object?>();
    _serveCalls[id] = completer;
    try {
      await controller.runJavaScript(
        'window.__antServeCall($id, ${jsonEncode(request.toJson())})',
      );
      final result = await completer.future.timeout(_manager.callTimeout);
      return MiniAppServiceResponse.fromHandlerResult(result);
    } on TimeoutException {
      _serveCalls.remove(id);
      return MiniAppServiceResponse.timeout();
    } catch (_) {
      _serveCalls.remove(id);
      return MiniAppServiceResponse.unavailable();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final registrationId = _registrationId;
    if (registrationId != null) _manager.unregister(registrationId);
    for (final completer in _serveCalls.values) {
      if (!completer.isCompleted) {
        completer.completeError(const MiniAppDenied('service stopped'));
      }
    }
    _serveCalls.clear();
    unawaited(_server?.close(force: true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Offstage(
      offstage: true,
      child: controller == null
          ? const SizedBox.shrink()
          : WebViewWidget(controller: controller),
    );
  }
}
