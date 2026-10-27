import 'package:flutter/material.dart';

import 'content_models.dart';

class ComicReaderScreen extends StatefulWidget {
  const ComicReaderScreen({
    super.key,
    required this.source,
    required this.book,
    required this.chapters,
    required this.initialIndex,
  });

  final ContentSource source;
  final ContentBook book;
  final List<ContentChapter> chapters;
  final int initialIndex;

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late int _index;
  Future<List<String>>? _future;
  final _scroll = ScrollController();
  int _currentPage = 1;
  int _pageCount = 0;

  ContentChapter get _chapter => widget.chapters[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _load();
    _scroll.addListener(_onScroll);
  }

  void _load() {
    _future = widget.source.chapterPages(widget.book.id, _chapter);
    _currentPage = 1;
    _pageCount = 0;
  }

  void _onScroll() {
    if (_pageCount <= 0 || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final ratio = (_scroll.offset / max).clamp(0, 1);
    final page = (ratio * _pageCount).ceil().clamp(1, _pageCount);
    if (page != _currentPage) setState(() => _currentPage = page);
  }

  void _switch(int index) {
    if (index < 0 || index >= widget.chapters.length) return;
    setState(() {
      _index = index;
      _load();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_chapter.title, maxLines: 1),
        actions: [
          if (_pageCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('$_currentPage / $_pageCount'),
              ),
            ),
        ],
      ),
      body: FutureBuilder<List<String>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          final pages = snapshot.data ?? const <String>[];
          if (pages.isEmpty) return const Center(child: Text('本章暂无图片'));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageCount != pages.length) {
              setState(() => _pageCount = pages.length);
            }
          });
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: pages.length,
                  itemBuilder: (context, i) => Image.network(
                    pages[i],
                    fit: BoxFit.fitWidth,
                    headers: widget.source.pageHeaders,
                    errorBuilder: (_, _, _) => Container(
                      height: 200,
                      alignment: Alignment.center,
                      child: Text('第 ${i + 1} 页加载失败'),
                    ),
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : Container(
                            height: 240,
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(),
                          ),
                  ),
                ),
              ),
              SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _index > 0 ? () => _switch(_index - 1) : null,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('上一章'),
                    ),
                    TextButton.icon(
                      onPressed: _index + 1 < widget.chapters.length
                          ? () => _switch(_index + 1)
                          : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('下一章'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 小说阅读页：正文纵向滚动，字号可调，上下章切换。
