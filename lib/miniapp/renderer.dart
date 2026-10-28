import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../app_update.dart';
import '../core_bridge.dart';
import '../hiker_player_screen.dart';
import '../local_store.dart';
import '../models.dart';
import '../playback_launch_screen.dart';
import 'bridge.dart';
import 'manifest.dart';
import 'permissions.dart';
import 'storage.dart';

String injectMiniAppBootstrap(String html, String script) {
  final tag = '<script>$script</script>';
  final lower = html.toLowerCase();
  final head = lower.indexOf('<head');
  if (head >= 0) {
    final close = html.indexOf('>', head);
    if (close >= 0) {
      return '${html.substring(0, close + 1)}$tag${html.substring(close + 1)}';
    }
  }
  final document = lower.indexOf('<html');
  if (document >= 0) {
    final close = html.indexOf('>', document);
    if (close >= 0) {
      return '${html.substring(0, close + 1)}$tag${html.substring(close + 1)}';
    }
  }
  return '$tag$html';
}

class MiniAppScreen extends StatefulWidget {
  const MiniAppScreen({
    super.key,
    required this.manifest,
    required this.directory,
    required this.storage,
    this.store,
    this.repository,
  });
  final MiniAppManifest manifest;
  final Directory directory;
  final MiniAppStorage storage;
  final LocalStore? store;
  final AppRepository? repository;

  @override
  State<MiniAppScreen> createState() => _MiniAppScreenState();
}

class _MiniAppScreenState extends State<MiniAppScreen> {
  WebViewController? _controller;
  HttpServer? _server;
  late final MiniAppBridge _bridge;
  late final MiniAppHost _host;
  bool _unsupported = false;
  String? _loadingMessage;

  @override
  void initState() {
    super.initState();
    _host = _MiniAppHostImpl(this);
    _bridge = MiniAppBridge(
      manifest: widget.manifest,
      storage: widget.storage,
      fetch: _fetch,
      onReply: _reply,
      onEmit: _emit,
      host: _host,
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
            _bridge.emit('show', {'app': widget.manifest.id});
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
      if (_contentType(relative).mimeType == 'text/html') {
        try {
          final html = utf8.decode(bytes);
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

  void _emit(String event, String dataJson) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller.runJavaScript(
        'window.ant._emit(${jsonEncode(event)}, $dataJson)',
      ),
    );
  }

  void _setLoadingMessage(String? message) {
    if (mounted) setState(() => _loadingMessage = message);
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
    final loadingMessage = _loadingMessage;
    final body = controller == null
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
          );
    return Scaffold(
      appBar: AppBar(title: Text(widget.manifest.name)),
      body: loadingMessage == null
          ? body
          : Stack(
              children: [
                body,
                ModalBarrier(
                  color: Colors.black.withValues(alpha: 0.35),
                  dismissible: false,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        loadingMessage,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    unawaited(_server?.close(force: true));
    super.dispose();
  }
}

class _MiniAppHostImpl extends MiniAppHost {
  _MiniAppHostImpl(this._state);
  final _MiniAppScreenState _state;

  BuildContext get _context => _state.context;
  LocalStore? get _store => _state.widget.store;
  AppRepository? get _repository => _state.widget.repository;

  List<SourceSite> get _vodSources {
    final store = _store;
    if (store == null) return [];
    return [
      for (final site in store.visibleSources)
        if (isVodZoneSource(site)) site,
    ];
  }

  String _sourceId(Map<String, Object?> params) {
    for (final key in ['source', 'key', 'site', 'id']) {
      final value = params[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return '';
  }

  @override
  Future<List<Map<String, Object?>>> sourceList() async {
    final sources = _vodSources;
    if (_store == null || _repository == null) {
      throw const MiniAppDenied('采集源不可用');
    }
    return [
      for (final site in sources)
        {
          'key': site.id,
          'id': site.id,
          'name': site.name,
          'type': 1,
          'searchable': site.onlineSearch ? 1 : 0,
        },
    ];
  }

  @override
  Future<Map<String, Object?>> sourceHome(Map<String, Object?> params) async {
    final repository = _repository;
    if (_store == null || repository == null) {
      throw const MiniAppDenied('采集源不可用');
    }
    var sourceId = _sourceId(params);
    final sources = _vodSources;
    if (sourceId.isEmpty) {
      if (sources.isEmpty) throw const MiniAppDenied('暂无可用采集源');
      sourceId = sources.first.id;
    }
    final categories = await repository.categories(sourceId);
    final category = categories
        .where((entry) => entry.id.isNotEmpty)
        .firstOrNull;
    final page = await repository.catalog(
      sourceId,
      category: category?.id ?? '',
    );
    return {
      'class': [
        for (final entry in categories) {'id': entry.id, 'name': entry.name},
      ],
      'list': [for (final drama in page.items) drama.toJson()],
    };
  }

  @override
  Future<Map<String, Object?>> sourceDetail(Map<String, Object?> params) async {
    final repository = _repository;
    if (_store == null || repository == null) {
      throw const MiniAppDenied('采集源不可用');
    }
    final sourceId = _sourceId(params);
    final dramaId = [params['vodId'], params['vod_id'], params['dramaId']]
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (sourceId.isEmpty || dramaId.isEmpty) {
      throw const MiniAppDenied('source.detail 需要站源与剧集 id');
    }
    final detail = await repository.detail(
      Drama(id: dramaId, source: sourceId, title: ''),
    );
    return {
      'id': detail.drama.id,
      'source': detail.drama.source,
      'title': detail.drama.title,
      'cover': detail.drama.cover,
      'description': detail.drama.description,
      'episodes': [
        for (final episode in detail.episodes)
          {
            'id': episode.id,
            'title': episode.title,
            'number': episode.number,
            'vip': episode.vip,
          },
      ],
    };
  }

  @override
  Future<Map<String, Object?>> playerOpen(Map<String, Object?> params) async {
    final url = params['url']?.toString() ?? '';
    final title = params['title']?.toString() ?? '';
    if (url.isNotEmpty) {
      final headers = <String, String>{};
      final rawHeaders = params['headers'] ?? params['header'];
      if (rawHeaders is Map) {
        rawHeaders.forEach(
          (key, value) => headers[key.toString()] = value.toString(),
        );
      }
      await Navigator.of(_context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => HikerPlayerScreen(
            title: title,
            episodes: [HikerEpisode(title: title, url: url, headers: headers)],
          ),
        ),
      );
      return {'route': '/player', 'url': url};
    }
    final repository = _repository;
    final store = _store;
    if (repository == null || store == null) {
      throw const MiniAppDenied('播放器不可用');
    }
    final sourceId = _sourceId(params);
    final dramaId = [params['vodId'], params['vod_id'], params['dramaId']]
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (sourceId.isEmpty || dramaId.isEmpty) {
      throw const MiniAppDenied('player.open 需要 url 或站源剧集参数');
    }
    await openPlaybackDirectly(
      _context,
      drama: Drama(id: dramaId, source: sourceId, title: title),
      repository: repository,
      store: store,
    );
    return {'route': '/detail', 'source': sourceId, 'id': dramaId};
  }

  @override
  void toast(String message) {
    ScaffoldMessenger.of(
      _context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void showLoading(String message) {
    _state._setLoadingMessage(message);
  }

  @override
  void hideLoading() {
    _state._setLoadingMessage(null);
  }

  @override
  Future<int> actionSheet(List<String> options) async {
    final picked = await showModalBottomSheet<int>(
      context: _context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(options[index]),
            onTap: () => Navigator.pop(context, index),
          ),
        ),
      ),
    );
    return picked ?? -1;
  }

  @override
  Future<Object?> navigateTo(String url) async {
    final controller = _state._controller;
    final port = _state._server?.port;
    if (controller == null || port == null) {
      throw const MiniAppDenied('页面尚未就绪');
    }
    final origin = 'http://127.0.0.1:$port/';
    final target = url.startsWith(origin)
        ? url
        : url.startsWith('/')
        ? '$origin${url.substring(1)}'
        : Uri.tryParse(url)?.hasScheme == true
        ? url
        : '$origin$url';
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.hasScheme) {
      throw MiniAppDenied('无法打开的地址：$url');
    }
    if (uri.toString().startsWith(origin)) {
      await controller.loadRequest(uri);
      return {'url': uri.toString()};
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw MiniAppDenied('无法打开的地址：$url');
    }
    final confirmed = await showDialog<bool>(
      context: _context,
      builder: (context) => AlertDialog(
        title: const Text('是否用浏览器打开？'),
        content: Text(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (confirmed != true) return {'url': url, 'opened': false};
    final opened = await AppUpdateChannel.openUrl(url);
    return {'url': url, 'opened': opened};
  }

  @override
  Future<bool> navigateBack() async {
    final controller = _state._controller;
    if (controller == null) return false;
    if (await controller.canGoBack()) {
      await controller.goBack();
      return true;
    }
    return false;
  }
}
