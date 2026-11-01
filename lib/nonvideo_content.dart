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
  late final PageController _controller = PageController();
  int _page = 0;
  List<String> _pages = const [];
  double _pageWidth = 0;
  double _pageHeight = 0;
  double _pageFont = 0;
  String _pageText = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NovelReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.text != widget.content.text) {
      _pages = const [];
      _page = 0;
      _controller.jumpToPage(0);
    }
  }

  List<String> _paginate(double width, double height) {
    final text = widget.content.text;
    final style = TextStyle(fontSize: _fontSize, height: 1.7);
    final lines = <String>[];
    for (final para in text.split('\n')) {
      final trimmed = para.trim();
      if (trimmed.isEmpty) {
        lines.add('');
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(text: trimmed, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      final metrics = painter.computeLineMetrics();
      var start = 0;
      for (var i = 0; i < metrics.length; i++) {
        final boundary = painter.getLineBoundary(
          TextPosition(offset: start),
        );
        lines.add(trimmed.substring(boundary.start, boundary.end));
        start = boundary.end;
        if (start >= trimmed.length) break;
      }
    }
    final lineHeight = _fontSize * 1.7;
    final perPage = (height / lineHeight).floor().clamp(1, 1000);
    final pages = <String>[];
    for (var i = 0; i < lines.length; i += perPage) {
      final end = (i + perPage).clamp(0, lines.length);
      pages.add(lines.sublist(i, end).join('\n'));
    }
    return pages.isEmpty ? const [''] : pages;
  }

  void _go(int next) {
    if (_pages.isEmpty) return;
    final target = next.clamp(0, _pages.length - 1);
    if (target == _page) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth - 36;
                final height = constraints.maxHeight - 48;
                if (_pages.isEmpty ||
                    _pageWidth != width ||
                    _pageHeight != height ||
                    _pageFont != _fontSize ||
                    _pageText != widget.content.text) {
                  _pages = _paginate(width, height);
                  _pageWidth = width;
                  _pageHeight = height;
                  _pageFont = _fontSize;
                  _pageText = widget.content.text;
                  if (_page >= _pages.length) _page = _pages.length - 1;
                }
                return Stack(
                  children: [
                    PageView.builder(
                      controller: _controller,
                      itemCount: _pages.length,
                      onPageChanged: (value) => setState(() => _page = value),
                      itemBuilder: (context, index) {
                        return AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) {
                            var delta = 0.0;
                            if (_controller.position.hasContentDimensions) {
                              delta = (_controller.page ?? _page.toDouble()) - index;
                            }
                            final turn = delta.clamp(-1.0, 1.0);
                            return Transform(
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..rotateY(-0.35 * turn),
                              alignment: turn > 0
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                              child: Container(
                                color: const Color(0xFFF7F1E3),
                                child: Stack(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        18,
                                        14,
                                        18,
                                        24,
                                      ),
                                      child: SelectableText(
                                        _pages[index],
                                        style: TextStyle(
                                          fontSize: _fontSize,
                                          height: 1.7,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (turn.abs() > 0.01)
                                      Positioned.fill(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: turn > 0
                                                  ? Alignment.centerLeft
                                                  : Alignment.centerRight,
                                              end: turn > 0
                                                  ? Alignment.centerRight
                                                  : Alignment.centerLeft,
                                              colors: [
                                                Colors.black.withValues(
                                                  alpha: 0.22 * turn.abs(),
                                                ),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 48,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _go(_page - 1),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 48,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _go(_page + 1),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 6,
                      child: Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: _pages.isEmpty
                                  ? 0
                                  : (_page + 1) / _pages.length,
                              backgroundColor: Colors.black12,
                              color: Colors.brown,
                              minHeight: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_page + 1} / ${_pages.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
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
