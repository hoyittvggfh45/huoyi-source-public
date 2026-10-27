import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class MediaSniffer {
  static final RegExp mediaUrlPattern = RegExp(
    r'''https?://[^\s"'<>\\]+?\.(?:m3u8|mpd|mp4|m4v|mov|flv|m4s)(?:\?[^\s"'<>\\]*)?''',
    caseSensitive: false,
  );

  static final RegExp _hlsAssignmentPattern = RegExp(
    r'''(?:hlsUrl|source|videoUrl|playUrl|url)\s*[:=]\s*["'](https?://[^"']+)["']''',
    caseSensitive: false,
  );

  static bool isMediaUrl(String url) => mediaUrlPattern.hasMatch(url);

  static List<String> extractFromText(String text) {
    final found = <String>{};
    for (final match in mediaUrlPattern.allMatches(text)) {
      found.add(match.group(0)!);
    }
    for (final match in _hlsAssignmentPattern.allMatches(text)) {
      final candidate = match.group(1);
      if (candidate != null && isMediaUrl(candidate)) found.add(candidate);
    }
    return found.toList();
  }

  static const String probeScript = r'''
(function () {
  if (window.__snifferInstalled) return;
  window.__snifferInstalled = true;
  window.__sniffedMedia = [];
  var pattern = /\.(m3u8|mpd|mp4|m4v|mov|flv|m4s)(\?|#|$)/i;
  function report(url) {
    if (typeof url !== 'string' || !pattern.test(url)) return;
    if (window.__sniffedMedia.indexOf(url) < 0) window.__sniffedMedia.push(url);
  }
  var open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    report(url);
    return open.apply(this, arguments);
  };
  var fetchOriginal = window.fetch;
  if (fetchOriginal) {
    window.fetch = function (input) {
      report(typeof input === 'string' ? input : input && input.url);
      return fetchOriginal.apply(this, arguments);
    };
  }
  function scanDom() {
    document.querySelectorAll('video, source').forEach(function (node) {
      report(node.currentSrc || node.src);
    });
    if (window.performance && performance.getEntriesByType) {
      performance.getEntriesByType('resource').forEach(function (entry) {
        report(entry.name);
      });
    }
  }
  new MutationObserver(scanDom).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['src'],
  });
  scanDom();
})();
''';
}

class SnifferService {
  SnifferService({List<String> initialCandidates = const []}) {
    addAll(initialCandidates);
  }

  final _candidates = <String>[];

  List<String> get candidates => List.unmodifiable(_candidates);

  bool add(String url) {
    final trimmed = url.trim();
    if (!MediaSniffer.isMediaUrl(trimmed) || _candidates.contains(trimmed)) {
      return false;
    }
    _candidates.add(trimmed);
    return true;
  }

  void addAll(Iterable<String> urls) {
    for (final url in urls) {
      add(url);
    }
  }

  static int _score(String url) {
    final path = url.toLowerCase().split('?').first.split('#').first;
    if (path.endsWith('.m3u8')) return 0;
    if (path.endsWith('.mpd')) return 1;
    if (path.endsWith('.mp4')) return 2;
    return 3;
  }

  String? get preferred {
    if (_candidates.isEmpty) return null;
    final ordered = [..._candidates]
      ..sort((a, b) => _score(a).compareTo(_score(b)));
    return ordered.first;
  }

  static List<String> parseSniffedResult(Object? result) {
    if (result is List) return result.whereType<String>().toList();
    if (result is String) {
      try {
        final decoded = jsonDecode(result);
        if (decoded is List) return decoded.whereType<String>().toList();
      } catch (_) {}
    }
    return const [];
  }
}

class SniffWebViewPage extends StatefulWidget {
  const SniffWebViewPage({
    super.key,
    required this.pageUrl,
    required this.onMediaFound,
    this.headers = const {},
    this.initialCandidates = const [],
  });

  final String pageUrl;
  final Map<String, String> headers;
  final List<String> initialCandidates;
  final ValueChanged<String> onMediaFound;

  @override
  State<SniffWebViewPage> createState() => _SniffWebViewPageState();
}

class _SniffWebViewPageState extends State<SniffWebViewPage> {
  late final SnifferService _service;
  WebViewController? _controller;
  Timer? _timer;
  bool _polling = false;

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _service = SnifferService(initialCandidates: widget.initialCandidates);
    if (!_supported) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => unawaited(_injectAndPoll())),
      );
    _controller = controller;
    unawaited(
      controller.loadRequest(
        Uri.parse(widget.pageUrl),
        headers: widget.headers,
      ),
    );
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_poll()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _injectAndPoll() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.runJavaScript(MediaSniffer.probeScript);
    } catch (_) {}
    await _poll();
  }

  Future<void> _poll() async {
    final controller = _controller;
    if (controller == null || _polling) return;
    _polling = true;
    try {
      final result = await controller.runJavaScriptReturningResult(
        'JSON.stringify(window.__sniffedMedia || [])',
      );
      final found = SnifferService.parseSniffedResult(result);
      var changed = false;
      for (final url in found) {
        if (_service.add(url)) changed = true;
      }
      if (changed && mounted) setState(() {});
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final candidates = _service.candidates;
    final preferred = _service.preferred;
    return Scaffold(
      appBar: AppBar(title: const Text('网页嗅探')),
      body: Column(
        children: [
          if (_controller != null)
            Expanded(child: WebViewWidget(controller: _controller!))
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.radar_rounded, size: 40, color: colors.primary),
                  const SizedBox(height: 12),
                  Text(
                    '当前平台不支持 WebView 嗅探',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '目标播放页：\n${widget.pageUrl}',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          if (preferred != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: FilledButton.icon(
                onPressed: () => widget.onMediaFound(preferred),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('播放推荐地址'),
              ),
            ),
          if (candidates.isNotEmpty)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '已提取的候选媒体地址',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final candidate in candidates)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_circle_outline_rounded),
                      title: Text(
                        candidate,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => widget.onMediaFound(candidate),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
