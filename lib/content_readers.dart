import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'content_models.dart';

class ComicReadingProgress {
  static const _key = 'comic_progress_v1';

  static String keyFor(String sourceId, String bookId) => '$sourceId::$bookId';

  static Future<({int chapter, int page})?> load(
    String sourceId,
    String bookId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final item = decoded[keyFor(sourceId, bookId)];
      if (item is! Map<String, dynamic>) return null;
      final chapter = int.tryParse('${item['chapter']}');
      final page = int.tryParse('${item['page']}');
      if (chapter == null || page == null) return null;
      return (chapter: chapter, page: page);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    String sourceId,
    String bookId,
    int chapter,
    int page,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    var map = <String, dynamic>{};
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) map = Map.of(decoded);
      } catch (_) {}
    }
    map[keyFor(sourceId, bookId)] = {'chapter': chapter, 'page': page};
    await prefs.setString(_key, jsonEncode(map));
  }
}

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
  final _pageController = PageController();
  final _zoomControllers = <int, TransformationController>{};
  final _retryNonce = <int, int>{};
  var _paged = false;
  var _restored = false;
  var _savedPage = 0;
  List<String> _pages = [];
  int _currentPage = 1;
  int _pageCount = 0;

  ContentChapter get _chapter => widget.chapters[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _scroll.addListener(_onScroll);
    _restoreAndLoad();
  }

  Future<void> _restoreAndLoad() async {
    final saved = await ComicReadingProgress.load(
      widget.source.id,
      widget.book.id,
    );
    if (!mounted) return;
    if (saved != null &&
        saved.chapter >= 0 &&
        saved.chapter < widget.chapters.length) {
      _index = saved.chapter;
      _savedPage = saved.page;
    }
    _load();
  }

  void _load() {
    _future = widget.source.chapterPages(widget.book.id, _chapter);
    _currentPage = 1;
    _pageCount = 0;
    _pages = [];
    _retryNonce.clear();
  }

  void _onScroll() {
    if (_paged || _pageCount <= 0 || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final ratio = (_scroll.offset / max).clamp(0, 1);
    final page = (ratio * _pageCount).ceil().clamp(1, _pageCount);
    if (page != _currentPage) {
      setState(() => _currentPage = page);
      ComicReadingProgress.save(
        widget.source.id,
        widget.book.id,
        _index,
        page - 1,
      );
      _precacheAround(page - 1);
    }
  }

  void _precacheAround(int center) {
    if (!mounted || _pages.isEmpty) return;
    for (var i = center - 3; i <= center + 3; i++) {
      if (i < 0 || i >= _pages.length || i == center) continue;
      precacheImage(
        NetworkImage(_pages[i], headers: widget.source.pageHeaders),
        context,
      );
    }
  }

  void _onPagesReady(List<String> pages) {
    _pages = pages;
    if (_restored) {
      _precacheAround(_currentPage - 1);
      return;
    }
    _restored = true;
    if (_savedPage <= 0) {
      _precacheAround(0);
      return;
    }
    final target = _savedPage.clamp(0, pages.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_paged) {
        if (_pageController.hasClients) _pageController.jumpToPage(target);
      } else if (_scroll.hasClients) {
        final max = _scroll.position.maxScrollExtent;
        if (max > 0) {
          _scroll.jumpTo(max * target / pages.length);
        }
      }
      setState(() => _currentPage = target + 1);
      _precacheAround(target);
    });
  }

  void _switch(int index) {
    if (index < 0 || index >= widget.chapters.length) return;
    setState(() {
      _index = index;
      _restored = true;
      _savedPage = 0;
      _load();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    ComicReadingProgress.save(widget.source.id, widget.book.id, index, 0);
  }

  void _openCatalog() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: widget.chapters.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(widget.chapters[i].title),
          selected: i == _index,
          onTap: () {
            Navigator.of(context).pop();
            _switch(i);
          },
        ),
      ),
    );
  }

  TransformationController _zoomController(int index) {
    return _zoomControllers.putIfAbsent(
      index,
      () => TransformationController(),
    );
  }

  Widget _pageImage(int index, String url) {
    final controller = _zoomController(index);
    return GestureDetector(
      onDoubleTap: () {
        final current = controller.value;
        if (current == Matrix4.identity()) {
          controller.value = Matrix4.diagonal3Values(2, 2, 1);
        } else {
          controller.value = Matrix4.identity();
        }
      },
      child: InteractiveViewer(
        transformationController: controller,
        minScale: 1,
        maxScale: 4,
        child: Image.network(
          url,
          key: ValueKey('$index-${_retryNonce[index] ?? 0}'),
          fit: BoxFit.fitWidth,
          headers: widget.source.pageHeaders,
          errorBuilder: (_, _, _) => Container(
            height: 200,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('第 ${index + 1} 页加载失败'),
                TextButton(
                  onPressed: () => setState(() {
                    _retryNonce[index] = (_retryNonce[index] ?? 0) + 1;
                  }),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : Container(
                  height: 240,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pageController.dispose();
    for (final controller in _zoomControllers.values) {
      controller.dispose();
    }
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
                padding: const EdgeInsets.only(right: 8),
                child: Text('$_currentPage / $_pageCount'),
              ),
            ),
          IconButton(
            icon: Icon(_paged ? Icons.view_list_rounded : Icons.book_rounded),
            tooltip: _paged ? '切换条漫' : '切换分页',
            onPressed: () {
              setState(() {
                _paged = !_paged;
                if (_paged && _pageController.hasClients) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _pageController.hasClients) {
                      _pageController.jumpToPage(
                        (_currentPage - 1).clamp(0, _pageCount - 1),
                      );
                    }
                  });
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.list_rounded),
            tooltip: '目录',
            onPressed: _openCatalog,
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
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${snapshot.error}'),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final pages = snapshot.data ?? const <String>[];
          if (pages.isEmpty) return const Center(child: Text('本章暂无图片'));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (_pageCount != pages.length || _pages.isEmpty)) {
              setState(() => _pageCount = pages.length);
              _onPagesReady(pages);
            }
          });
          return Column(
            children: [
              Expanded(
                child: _paged
                    ? PageView.builder(
                        controller: _pageController,
                        itemCount: pages.length,
                        onPageChanged: (page) {
                          setState(() => _currentPage = page + 1);
                          ComicReadingProgress.save(
                            widget.source.id,
                            widget.book.id,
                            _index,
                            page,
                          );
                          _precacheAround(page);
                        },
                        itemBuilder: (context, i) => SingleChildScrollView(
                          child: _pageImage(i, pages[i]),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        itemCount: pages.length,
                        itemBuilder: (context, i) => _pageImage(i, pages[i]),
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
                    TextButton(
                      onPressed: _openCatalog,
                      child: const Text('目录'),
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

class NovelReadingProgress {
  static const _key = 'novel_progress_v1';

  static String keyFor(String sourceId, String bookId) => '$sourceId::$bookId';

  static Future<({int chapter, int page})?> load(
    String sourceId,
    String bookId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final item = decoded[keyFor(sourceId, bookId)];
      if (item is! Map<String, dynamic>) return null;
      final chapter = int.tryParse('${item['chapter']}');
      final page = int.tryParse('${item['page']}');
      if (chapter == null || page == null) return null;
      return (chapter: chapter, page: page);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    String sourceId,
    String bookId,
    int chapter,
    int page,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    var map = <String, dynamic>{};
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) map = Map.of(decoded);
      } catch (_) {}
    }
    map[keyFor(sourceId, bookId)] = {'chapter': chapter, 'page': page};
    await prefs.setString(_key, jsonEncode(map));
  }
}

List<String> paginateNovelText(String text, double fontSize) {
  final target = fontSize <= 14
      ? 1100
      : fontSize <= 18
      ? 850
      : 650;
  final pages = <String>[];
  var current = StringBuffer();
  for (final paragraph in text.split('\n')) {
    final line = paragraph.trim();
    if (line.isEmpty) continue;
    if (current.length + line.length + 1 > target && current.isNotEmpty) {
      pages.add(current.toString().trim());
      current = StringBuffer();
    }
    if (current.isNotEmpty) current.writeln();
    current.write(line);
  }
  if (current.isNotEmpty) pages.add(current.toString().trim());
  return pages;
}

class NovelReaderScreen extends StatefulWidget {
  const NovelReaderScreen({
    super.key,
    required this.source,
    required this.book,
    required this.chapters,
    required this.initialIndex,
    this.initialPage = 0,
  });

  final ContentSource source;
  final ContentBook book;
  final List<ContentChapter> chapters;
  final int initialIndex;
  final int initialPage;

  @override
  State<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends State<NovelReaderScreen> {
  late int _index;
  late int _pageIndex;
  double _fontSize = 18;
  Future<String>? _future;
  List<String> _pages = [];
  final _pageController = PageController();

  ContentChapter get _chapter => widget.chapters[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.chapters.length - 1);
    _pageIndex = widget.initialPage;
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _load() {
    _future = widget.source.chapterText(widget.book.id, _chapter);
    _future!.then((text) {
      if (!mounted) return;
      final pages = paginateNovelText(text, _fontSize);
      setState(() {
        _pages = pages;
        _pageIndex = _pageIndex.clamp(0, pages.isEmpty ? 0 : pages.length - 1);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients && _pageIndex > 0) {
          _pageController.jumpToPage(_pageIndex);
        }
      });
      NovelReadingProgress.save(
        widget.source.id,
        widget.book.id,
        _index,
        _pageIndex,
      );
    });
  }

  void _switchChapter(int index) {
    if (index < 0 || index >= widget.chapters.length) return;
    setState(() {
      _index = index;
      _pageIndex = 0;
      _pages = [];
      _load();
    });
  }

  void _changeFont(double delta) {
    final next = (_fontSize + delta).clamp(12, 26).toDouble();
    if (next == _fontSize) return;
    setState(() => _fontSize = next);
    _future?.then((text) {
      if (!mounted) return;
      setState(() {
        _pages = paginateNovelText(text, _fontSize);
        _pageIndex = 0;
      });
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    });
  }

  void _openCatalog() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: widget.chapters.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(widget.chapters[i].title),
          selected: i == _index,
          onTap: () {
            Navigator.of(context).pop();
            _switchChapter(i);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_chapter.title, maxLines: 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.format_size_rounded),
            tooltip: '减小字号',
            onPressed: () => _changeFont(-2),
          ),
          IconButton(
            icon: const Icon(Icons.text_increase_rounded),
            tooltip: '增大字号',
            onPressed: () => _changeFont(2),
          ),
          IconButton(
            icon: const Icon(Icons.list_rounded),
            tooltip: '目录',
            onPressed: _openCatalog,
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          final text = snapshot.data ?? '';
          if (text.trim().isEmpty) {
            return const Center(child: Text('本章正文为空'));
          }
          if (_pages.isEmpty) _pages = paginateNovelText(text, _fontSize);
          return Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (page) {
                    setState(() => _pageIndex = page);
                    NovelReadingProgress.save(
                      widget.source.id,
                      widget.book.id,
                      _index,
                      page,
                    );
                  },
                  itemBuilder: (context, i) => SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _pages[i],
                      style: TextStyle(fontSize: _fontSize, height: 1.7),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _index > 0
                            ? () => _switchChapter(_index - 1)
                            : null,
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('上一章'),
                      ),
                      TextButton(
                        onPressed: _pageIndex > 0
                            ? () => _pageController.previousPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              )
                            : null,
                        child: const Text('上一页'),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            _pages.isEmpty
                                ? ''
                                : '${_pageIndex + 1} / ${_pages.length}',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _pageIndex + 1 < _pages.length
                            ? () => _pageController.nextPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              )
                            : null,
                        child: const Text('下一页'),
                      ),
                      TextButton.icon(
                        onPressed: _index + 1 < widget.chapters.length
                            ? () => _switchChapter(_index + 1)
                            : null,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('下一章'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
