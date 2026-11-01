import 'dart:convert';

import 'package:flutter/material.dart';

import 'models.dart';

enum NonVideoKind { novel, pics }

class NonVideoContent {
  const NonVideoContent.novel({required this.title, required this.text})
    : kind = NonVideoKind.novel,
      urls = const [];
  const NonVideoContent.pics({required this.title, required this.urls})
    : kind = NonVideoKind.pics,
      text = '';
  final NonVideoKind kind;
  final String title;
  final String text;
  final List<String> urls;
  bool get isNovel => kind == NonVideoKind.novel;
  bool get isPics => kind == NonVideoKind.pics;
}

String? _findPayload(String value, String scheme) {
  final start = value.indexOf(scheme);
  if (start < 0) return null;
  return value.substring(start);
}

NonVideoContent? parseNonVideoUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final novel = _findPayload(value, 'novel://');
  if (novel != null) {
    final jsonText = novel.substring('novel://'.length).trim();
    if (!jsonText.startsWith('{')) {
      return null;
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) {
        final title = decoded['title']?.toString() ?? '';
        final text = decoded['content']?.toString() ?? '';
        if (text.isNotEmpty) {
          return NonVideoContent.novel(title: title, text: text);
        }
      }
    } catch (_) {}
    return null;
  }
  final pics = _findPayload(value, 'pics://');
  if (pics != null) {
    final payload = pics.substring('pics://'.length);
    final urls = [
      for (final part in payload.split('&&'))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    if (urls.isEmpty) return null;
    return NonVideoContent.pics(title: '', urls: urls);
  }
  return null;
}

NonVideoContent? nonVideoFromEpisode(Episode episode) {
  final candidates = <String>[];
  for (final key in const ['videoUrl', 'episodeId', 'id', 'url']) {
    final value = episode.raw[key];
    if (value is String && value.isNotEmpty) candidates.add(value);
  }
  if (episode.id.isNotEmpty) candidates.add(episode.id);
  for (final candidate in candidates) {
    final parsed = parseNonVideoUrl(candidate);
    if (parsed != null) return parsed;
  }
  return null;
}

bool isNonVideoEpisode(Episode episode) => nonVideoFromEpisode(episode) != null;

NonVideoKind? nonVideoKindOfEpisode(Episode episode) {
  final candidates = <String>[];
  for (final key in const ['videoUrl', 'episodeId', 'id', 'url']) {
    final value = episode.raw[key];
    if (value is String && value.isNotEmpty) candidates.add(value);
  }
  if (episode.id.isNotEmpty) candidates.add(episode.id);
  for (final candidate in candidates) {
    if (_findPayload(candidate, 'novel://') != null) return NonVideoKind.novel;
    if (_findPayload(candidate, 'pics://') != null) return NonVideoKind.pics;
  }
  return null;
}

Map<String, String> _imageHeaders(String url) {
  if (url.startsWith('http://127.0.0.1') ||
      url.startsWith('http://localhost')) {
    return const {};
  }
  return const {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://mjv011.com/',
  };
}

class NovelReaderView extends StatefulWidget {
  const NovelReaderView({super.key, required this.content, required this.title});
  final NonVideoContent content;
  final String title;
  @override
  State<NovelReaderView> createState() => _NovelReaderViewState();
}

class _NovelReaderViewState extends State<NovelReaderView> {
  double _fontSize = 17;
  @override
  Widget build(BuildContext context) {
    final title = widget.content.title.isNotEmpty
        ? widget.content.title
        : widget.title;
    return Container(
      color: const Color(0xFFF7F1E3),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '减小字号',
                  onPressed: _fontSize > 13
                      ? () => setState(() => _fontSize -= 1)
                      : null,
                  icon: const Icon(Icons.text_decrease),
                ),
                Text(
                  '${_fontSize.toInt()}',
                  style: const TextStyle(color: Colors.black54),
                ),
                IconButton(
                  tooltip: '增大字号',
                  onPressed: _fontSize < 26
                      ? () => setState(() => _fontSize += 1)
                      : null,
                  icon: const Icon(Icons.text_increase),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              child: SelectableText(
                widget.content.text,
                style: TextStyle(
                  fontSize: _fontSize,
                  height: 1.7,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PicsViewerView extends StatefulWidget {
  const PicsViewerView({super.key, required this.content, required this.title});
  final NonVideoContent content;
  final String title;
  @override
  State<PicsViewerView> createState() => _PicsViewerViewState();
}

class _PicsViewerViewState extends State<PicsViewerView> {
  late final PageController _controller;
  int _index = 0;
  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PicsViewerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.urls != widget.content.urls) {
      _index = 0;
      _controller.jumpToPage(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.content.urls;
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: urls.length,
            onPageChanged: (value) {
              setState(() => _index = value);
              for (final next in [value - 1, value + 1]) {
                if (next >= 0 && next < urls.length) {
                  precacheImage(
                    NetworkImage(urls[next], headers: _imageHeaders(urls[next])),
                    context,
                  );
                }
              }
            },
            itemBuilder: (context, i) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    urls[i],
                    headers: _imageHeaders(urls[i]),
                    fit: BoxFit.contain,
                    errorBuilder: (context, _, _) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '图片加载失败\n${urls[i]}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '上一张',
                  onPressed: _index > 0
                      ? () => _controller.previousPage(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                ),
                Text(
                  '${_index + 1} / ${urls.length}',
                  style: const TextStyle(color: Colors.white),
                ),
                IconButton(
                  tooltip: '下一张',
                  onPressed: _index + 1 < urls.length
                      ? () => _controller.nextPage(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
