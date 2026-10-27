import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import 'bridge.dart';
import 'manifest.dart';
import 'storage.dart';

class MiniAppScreen extends StatefulWidget {
  const MiniAppScreen({
    super.key,
    required this.manifest,
    required this.directory,
    required this.storage,
  });
  final MiniAppManifest manifest;
  final Directory directory;
  final MiniAppStorage storage;

  @override
  State<MiniAppScreen> createState() => _MiniAppScreenState();
}

class _MiniAppScreenState extends State<MiniAppScreen> {
  WebViewController? _controller;
  HttpServer? _server;
  late final MiniAppBridge _bridge;
  bool _unsupported = false;

  @override
  void initState() {
    super.initState();
    _bridge = MiniAppBridge(
      manifest: widget.manifest,
      storage: widget.storage,
      fetch: _fetch,
      onReply: _reply,
      onEmit: _emit,
    );
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(_start());
    } else {
      _unsupported = true;
    }
  }

  Future<void> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_serve);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'JhMiniapp',
        onMessageReceived: (message) {
          unawaited(_bridge.handleMessage(message.message));
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
            _bridge.emit('ready', {'app': widget.manifest.id});
          },
        ),
      );
    _controller = controller;
    await controller.loadRequest(
      Uri.parse('http://127.0.0.1:${server.port}/${widget.manifest.entry}'),
    );
    if (mounted) setState(() {});
  }

  Future<void> _serve(HttpRequest request) async {
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
      request.response.headers.contentType = _contentType(relative);
      request.response.add(bytes);
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  ContentType _contentType(String path) {
    final extension = p.extension(path).toLowerCase();
    switch (extension) {
      case '.html':
        return ContentType('text', 'html', charset: 'utf-8');
      case '.css':
        return ContentType('text', 'css', charset: 'utf-8');
      case '.js':
        return ContentType('text', 'javascript', charset: 'utf-8');
      case '.json':
        return ContentType('application', 'json', charset: 'utf-8');
      case '.png':
        return ContentType('image', 'png');
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.gif':
        return ContentType('image', 'gif');
      case '.svg':
        return ContentType('image', 'svg+xml');
      case '.webp':
        return ContentType('image', 'webp');
      default:
        return ContentType.binary;
    }
  }

  Future<MiniAppHttpResponse> _fetch(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        [],
        (acc, chunk) => acc..addAll(chunk),
      );
      return MiniAppHttpResponse(status: response.statusCode, bytes: bytes);
    } finally {
      client.close();
    }
  }

  void _reply(int id, Object? result, String? error) {
    final controller = _controller;
    if (controller == null) return;
    if (error != null) {
      unawaited(
        controller.runJavaScript(
          'window.jhminiapp._reject($id, ${jsonEncode(error)})',
        ),
      );
    } else {
      unawaited(
        controller.runJavaScript(
          'window.jhminiapp._resolve($id, ${jsonEncode(result)})',
        ),
      );
    }
  }

  void _emit(String event, String dataJson) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller.runJavaScript(
        'window.jhminiapp._emit(${jsonEncode(event)}, $dataJson)',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupported) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.manifest.name)),
        body: const Center(child: Text('迷你应用 WebView 仅支持 Android 与 iOS')),
      );
    }
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.manifest.name)),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  _bridge.emit('tv.key', {'key': event.logicalKey.keyLabel});
                }
                return KeyEventResult.ignored;
              },
              child: WebViewWidget(controller: controller),
            ),
    );
  }

  @override
  void dispose() {
    unawaited(_server?.close(force: true));
    super.dispose();
  }
}
