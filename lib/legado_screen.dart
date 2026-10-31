import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'content_http.dart';
import 'content_readers.dart';
import 'core_bridge.dart';
import 'legado_builtin_data.dart';
import 'legado_source.dart';
import 'local_book_store.dart';

class LegadoScreen extends StatefulWidget {
  const LegadoScreen({super.key, required this.repository, this.initialComic = false});

  final AppRepository repository;
  final bool initialComic;

  @override
  State<LegadoScreen> createState() => _LegadoScreenState();
}

enum _LegadoFilter { novel, comic, all }

class _LegadoScreenState extends State<LegadoScreen> {
  List<LegadoSource> _sources = [];
  LegadoSource? _selected;
  _LegadoFilter _filter = _LegadoFilter.novel;
  late final _builtinCount = parseLegadoSources(builtinLegadoRulesJson).length;
  final _query = TextEditingController();
  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _chapters = [];
  Map<String, dynamic>? _currentBook;
  int _chapterIndex = -1;
  int? _resumeChapter;
  String _content = '';
  List<String> _pages = [];
  int _pageIndex = 0;
  double _fontSize = 16;
  final _readPageController = PageController();
  int _searchPage = 1;
  List<Map<String, dynamic>> _contentImages = [];
  int _imageIndex = 1;
  final _imageRetry = <String, int>{};
  List<Map<String, dynamic>> _exploreCategories = [];
  String _exploreUrl = '';
  int _explorePage = 1;
  bool _explored = false;
  String _mode = 'books';
  bool _busy = false;
  bool _searched = false;
  bool _searchUnsupported = false;
  final Set<String> _unsupportedIds = {};
  String _error = '';
  bool _localView = false;
  List<LocalBook> _localBooks = [];
  List<({String title, String text})> _localChapters = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialComic) _filter = _LegadoFilter.comic;
    _refresh();
  }

  @override
  void dispose() {
    _query.dispose();
    _readPageController.dispose();
    super.dispose();
  }

  List<LegadoSource> get _visibleSources => switch (_filter) {
    _LegadoFilter.novel =>
      _sources.where((s) => s.type == '0' || s.type.isEmpty).toList(),
    _LegadoFilter.comic => _sources.where((s) => s.type == '2').toList(),
    _LegadoFilter.all => _sources,
  };

  void _ensureVisibleSelection() {
    final visible = _visibleSources;
    if (_selected == null || !visible.any((s) => s.id == _selected!.id)) {
      _selected = visible.isNotEmpty ? visible.first : null;
    }
  }

  Future<void> _deleteSource(LegadoSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书源'),
        content: Text('确定删除「${source.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final sources = await LegadoStore.remove(source);
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _unsupportedIds.remove(source.id);
      if (_selected?.id == source.id) _selected = null;
      _ensureVisibleSelection();
      _books = [];
      _chapters = [];
      _content = '';
      _contentImages = [];
      _mode = 'books';
      _searched = false;
      _exploreCategories = [];
      _exploreUrl = '';
      _explored = false;
    });
  }

  Future<void> _restoreBuiltin() async {
    await LegadoStore.restoreBuiltin();
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _refresh() async {
    await LegadoStore.seedBuiltin();
    final sources = await LegadoStore.load();
    final localBooks = await LocalBookStore.load();
    if (mounted) {
      setState(() {
        _sources = sources;
        _localBooks = localBooks;
        _ensureVisibleSelection();
      });
    }
    if (sources.isNotEmpty) unawaited(_checkSources(sources));
  }

  String _searchUnsupportedReason = '';

  bool _legadoCheckUnsupported(dynamic result) {
    return _legadoCheckMap(result)?['supported'] == false;
  }

  Map<String, dynamic>? _legadoCheckMap(dynamic result) {
    Map<String, dynamic>? map;
    if (result is Map<String, dynamic>) {
      map = result;
    } else if (result is String) {
      try {
        final decoded = jsonDecode(result);
        if (decoded is Map<String, dynamic>) map = decoded;
      } catch (_) {}
    }
    return map;
  }

  Future<void> _checkSources(List<LegadoSource> sources) async {
    for (final source in sources) {
      var unsupported = false;
      try {
        final result = await widget.repository.legadoRun(
          source.rawJson,
          'check',
          '',
        );
        unsupported = _legadoCheckUnsupported(result);
      } catch (_) {}
      if (unsupported && mounted) {
        setState(() => _unsupportedIds.add(source.id));
      }
    }
  }

  String _importMessage(int added, LegadoParseReport report, int duplicates) {
    final counts = <String, int>{};
    void bump(String reason) => counts[reason] = (counts[reason] ?? 0) + 1;
    for (var i = 0; i < duplicates; i++) {
      bump('重名');
    }
    for (final drop in report.dropped) {
      bump(drop.reason);
    }
    final skipped = counts.values.fold(0, (a, b) => a + b);
    if (added == 0 && skipped == 0) return '导入 0 条（未解析出书源）';
    if (skipped == 0) return '导入 $added 条开源阅读书源';
    final detail = counts.entries.map((e) => '${e.key} ${e.value}').join('、');
    return '导入 $added 条，跳过 $skipped 条（$detail）';
  }

  Future<void> _applyImport(LegadoParseReport report) async {
    final beforeIds = _sources.map((s) => s.id).toSet();
    final merged = await LegadoStore.addAll(report.sources);
    final addedSources = merged
        .where((s) => !beforeIds.contains(s.id))
        .toList();
    final duplicates = report.sources.length - addedSources.length;
    if (mounted) {
      setState(() {
        _sources = merged;
        _ensureVisibleSelection();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _importMessage(addedSources.length, report, duplicates),
          ),
        ),
      );
    }
    if (addedSources.isNotEmpty) unawaited(_checkSources(addedSources));
  }

  Future<void> _importLocalBook() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'epub'],
    );
    if (picked.isEmpty) return;
    final file = picked.first;
    try {
      final bytes = await file.readAsBytes();
      final books = await LocalBookStore.add(bytes, file.name);
      if (mounted) {
        setState(() => _localBooks = books);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本地书导入成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('本地书导入失败：$e')));
      }
    }
  }

  Future<void> _removeLocalBook(LocalBook book) async {
    final books = await LocalBookStore.remove(book);
    if (mounted) setState(() => _localBooks = books);
  }

  Future<void> _openLocalBook(LocalBook book) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final chapters = await LocalBookStore.readChapters(book);
      if (mounted) {
        setState(() {
          _localChapters = chapters;
          _mode = 'localToc';
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  void _openLocalChapter(({String title, String text}) chapter) {
    setState(() {
      _content = chapter.text;
      _mode = 'localRead';
    });
  }

  Widget _buildLocalView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() {
                  if (_mode == 'localRead') {
                    _mode = 'localToc';
                  } else if (_mode == 'localToc') {
                    _mode = 'local';
                  } else {
                    _localView = false;
                    _mode = 'books';
                  }
                }),
              ),
              const Expanded(
                child: Text(
                  '本地书架',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.file_open_rounded),
                tooltip: '导入本地书（txt / epub）',
                onPressed: _importLocalBook,
              ),
            ],
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: switch (_mode) {
            'localToc' => ListView.builder(
              itemCount: _localChapters.length,
              itemBuilder: (_, i) {
                final chapter = _localChapters[i];
                return ListTile(
                  title: Text(chapter.title),
                  onTap: () => _openLocalChapter(chapter),
                );
              },
            ),
            'localRead' => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _content.isEmpty ? '正文为空' : _content,
                style: const TextStyle(fontSize: 12, height: 1.7),
              ),
            ),
            _ =>
              _localBooks.isEmpty && !_busy
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无本地书：点右上角导入 txt 或 epub 文件。'),
                    )
                  : ListView.builder(
                      itemCount: _localBooks.length,
                      itemBuilder: (_, i) {
                        final book = _localBooks[i];
                        return ListTile(
                          title: Text(book.title),
                          subtitle: Text(
                            '${book.isEpub ? 'epub' : 'txt'} · ${(book.size / 1024).round()} KB',
                          ),
                          onTap: () => _openLocalBook(book),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => _removeLocalBook(book),
                          ),
                        );
                      },
                    ),
          },
        ),
      ],
    );
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked.isEmpty) return;
    final file = picked.first;
    try {
      final bytes = await file.readAsBytes();
      final report = parseLegadoSourcesReport(decodeLegadoImportBytes(bytes));
      await _applyImport(report);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  Future<void> _importUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入书源地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '粘贴书源 JSON 地址（填地址，不是规则原文）',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;
    try {
      final text = await ContentHttp().get(url);
      final report = parseLegadoSourcesReport(text);
      await _applyImport(report);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  List<Map<String, dynamic>> _toMaps(dynamic result) {
    if (result is List) {
      return result.whereType<Map<String, dynamic>>().toList();
    }
    if (result is Map<String, dynamic>) {
      final data = result['data'];
      if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    }
    if (result is String) {
      try {
        final decoded = jsonDecode(result);
        if (decoded is List) {
          return decoded.whereType<Map<String, dynamic>>().toList();
        }
      } catch (_) {}
    }
    return [];
  }

  List<Map<String, dynamic>> _parseContentImages(dynamic raw) {
    final items = <dynamic>[];
    if (raw is List) {
      items.addAll(raw);
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) items.addAll(decoded);
      } catch (_) {}
    }
    final out = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        out.add(item);
      } else if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }

  Map<String, String> _stringHeaders(dynamic value) {
    if (value is! Map) return const {};
    final out = <String, String>{};
    value.forEach((key, item) {
      out[key.toString()] = item.toString();
    });
    return out;
  }

  Future<void> _search([int page = 1]) async {
    final source = _selected;
    final keyword = _query.text.trim();
    if (source == null || keyword.isEmpty) return;
    if (source.searchUrl.isEmpty) {
      setState(() {
        _error = '该书源搜索地址待用户定夺（签名类材料未还原），可先点发现浏览分类。';
        _mode = 'books';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
      _mode = 'books';
      _searchUnsupported = false;
      _searchUnsupportedReason = '';
      _explored = false;
      _searchPage = page;
    });
    try {
      final result = await widget.repository.legadoRun(
        source.rawJson,
        'search',
        '$keyword\x01$page',
      );
      final books = _toMaps(result);
      var unsupported = false;
      var reason = '';
      if (books.isEmpty) {
        try {
          final check = await widget.repository.legadoRun(
            source.rawJson,
            'check',
            '',
          );
          final map = _legadoCheckMap(check);
          unsupported = map?['supported'] == false;
          if (unsupported && map != null) {
            reason = legadoCheckReasonText(map);
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _books = books;
          _busy = false;
          _searched = true;
          _searchPage = page;
          _searchUnsupported = unsupported;
          _searchUnsupportedReason = reason;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _explore() async {
    final source = _selected;
    if (source == null) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final result = await widget.repository.legadoRun(
        source.rawJson,
        'exploreCategories',
        '',
      );
      final categories = _toMaps(result);
      if (mounted) {
        setState(() {
          _exploreCategories = categories;
          _busy = false;
        });
      }
      if (categories.isNotEmpty) {
        final url = (categories.first['url'] ?? '').toString();
        if (url.isNotEmpty) await _loadExplore(url, 1);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _loadExplore(String url, int page) async {
    final source = _selected;
    if (source == null || url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
      _mode = 'books';
    });
    try {
      final result = await widget.repository.legadoRun(
        source.rawJson,
        'explore',
        '$url\x01$page',
      );
      if (mounted) {
        setState(() {
          _books = _toMaps(result);
          _busy = false;
          _searched = true;
          _explored = true;
          _exploreUrl = url;
          _explorePage = page;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _openBook(Map<String, dynamic> book) async {
    final source = _selected;
    final url = (book['url'] ?? '').toString();
    if (source == null || url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
      _currentBook = book;
      _chapterIndex = -1;
      _resumeChapter = null;
      _pages = [];
      _pageIndex = 0;
    });
    try {
      final result = await widget.repository.legadoRun(
        source.rawJson,
        'toc',
        url,
      );
      final chapters = _toMaps(result);
      if (mounted) {
        setState(() {
          _chapters = chapters;
          _mode = 'toc';
          _busy = false;
        });
      }
      final progress = await NovelReadingProgress.load(source.id, url);
      if (mounted &&
          progress != null &&
          progress.chapter >= 0 &&
          progress.chapter < chapters.length) {
        setState(() => _resumeChapter = progress.chapter);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _openChapter(Map<String, dynamic> chapter, [int? index]) async {
    final source = _selected;
    final url = (chapter['url'] ?? '').toString();
    final bookUrl = (_currentBook?['url'] ?? '').toString();
    if (source == null || url.isEmpty) return;
    final chapterIndex = index ??
        _chapters.indexWhere((c) => (c['url'] ?? '').toString() == url);
    setState(() {
      _busy = true;
      _error = '';
      _contentImages = [];
      _imageIndex = 1;
      _chapterIndex = chapterIndex;
      _pageIndex = 0;
      _pages = [];
    });
    if (bookUrl.isNotEmpty && chapterIndex >= 0) {
      await NovelReadingProgress.save(source.id, bookUrl, chapterIndex, 0);
    }
    try {
      final result = await widget.repository.legadoRun(
        source.rawJson,
        'content',
        url,
      );
      var text = '';
      var images = <Map<String, dynamic>>[];
      if (result is Map<String, dynamic>) {
        text = (result['content'] ?? '').toString();
        images = _parseContentImages(result['images']);
      } else if (result is String) {
        try {
          final decoded = jsonDecode(result);
          if (decoded is Map<String, dynamic>) {
            text = (decoded['content'] ?? '').toString();
            images = _parseContentImages(decoded['images']);
          }
        } catch (_) {
          text = result;
        }
      }
      final pages = paginateNovelText(text, _fontSize);
      if (mounted) {
        setState(() {
          _content = text;
          _contentImages = images;
          _pages = pages;
          _pageIndex = 0;
          _mode = 'read';
          _busy = false;
        });
        if (pages.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _readPageController.hasClients) {
              _readPageController.jumpToPage(0);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  void _changeLegadoFont(double delta) {
    final next = (_fontSize + delta).clamp(12, 26).toDouble();
    if (next == _fontSize) return;
    setState(() {
      _fontSize = next;
      _pages = paginateNovelText(_content, _fontSize);
      _pageIndex = 0;
    });
    if (_readPageController.hasClients) _readPageController.jumpToPage(0);
  }

  void _switchLegadoChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    _openChapter(_chapters[index], index);
  }

  @override
  Widget build(BuildContext context) {
    if (_localView) return _buildLocalView();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              if (_mode != 'books')
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () =>
                      setState(() => _mode = _mode == 'read' ? 'toc' : 'books'),
                ),
              IconButton(
                icon: const Icon(Icons.menu_book_rounded),
                tooltip: '本地书架',
                onPressed: () => setState(() => _localView = true),
              ),
              Expanded(
                child: TextField(
                  controller: _query,
                  decoration: const InputDecoration(
                    hintText: '搜索书名或作者',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => _search(), child: const Text('搜索')),
              IconButton(
                icon: const Icon(Icons.explore_rounded),
                tooltip: '发现',
                onPressed: _explore,
              ),
              IconButton(
                icon: const Icon(Icons.file_open_rounded),
                tooltip: '导入书源文件',
                onPressed: _importFile,
              ),
              IconButton(
                icon: const Icon(Icons.link_rounded),
                tooltip: '导入书源地址',
                onPressed: _importUrl,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              ChoiceChip(
                label: Text(widget.initialComic ? '漫画' : '小说'),
                selected: _filter != _LegadoFilter.all,
                onSelected: (_) => setState(() {
                  _filter = widget.initialComic
                      ? _LegadoFilter.comic
                      : _LegadoFilter.novel;
                  _ensureVisibleSelection();
                  _books = [];
                  _searched = false;
                }),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('全部书源'),
                selected: _filter == _LegadoFilter.all,
                onSelected: (_) => setState(() {
                  _filter = _LegadoFilter.all;
                  _ensureVisibleSelection();
                  _books = [];
                  _searched = false;
                }),
              ),
              const Spacer(),
              if (_sources.length < _builtinCount)
                TextButton(
                  onPressed: _restoreBuiltin,
                  child: const Text('恢复默认'),
                ),
            ],
          ),
        ),
        if (_sources.isNotEmpty && _visibleSources.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _filter == _LegadoFilter.comic
                  ? '漫画分类下暂无书源，可切到全部书源查看。'
                  : '小说分类下暂无书源，可切到全部书源查看。',
            ),
          ),
        if (_visibleSources.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final source in _visibleSources)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    child: GestureDetector(
                      onLongPress: () => _deleteSource(source),
                      child: ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(source.name),
                            if (_unsupportedIds.contains(source.id))
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Text(
                                  '规则暂不支持',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        selected: _selected?.id == source.id,
                        onSelected: (_) => setState(() {
                          _selected = source;
                          _books = [];
                          _searched = false;
                          _searchUnsupported = false;
                          _searchUnsupportedReason = '';
                          _exploreCategories = [];
                          _exploreUrl = '';
                          _explored = false;
                          _contentImages = [];
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error, style: const TextStyle(color: Colors.red)),
          ),
        if (_sources.isEmpty && !_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('暂无开源阅读书源：点右上角文件或链接按钮导入 Legado 书源 JSON。'),
          ),
        if (_exploreCategories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final category in _exploreCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    child: ChoiceChip(
                      label: Text((category['title'] ?? '').toString()),
                      selected:
                          _exploreUrl == (category['url'] ?? '').toString(),
                      onSelected: (_) {
                        final url = (category['url'] ?? '').toString();
                        if (url.isNotEmpty) _loadExplore(url, 1);
                      },
                    ),
                  ),
              ],
            ),
          ),
        if (!_explored && _searched && _mode == 'books')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Text('第 $_searchPage 页'),
                const Spacer(),
                TextButton(
                  onPressed: _searchPage > 1
                      ? () => _search(_searchPage - 1)
                      : null,
                  child: const Text('上一页'),
                ),
                TextButton(
                  onPressed: () => _search(_searchPage + 1),
                  child: const Text('下一页'),
                ),
              ],
            ),
          ),
        if (_explored && _mode == 'books')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Text('第 $_explorePage 页'),
                const Spacer(),
                TextButton(
                  onPressed: _explorePage > 1
                      ? () => _loadExplore(_exploreUrl, _explorePage - 1)
                      : null,
                  child: const Text('上一页'),
                ),
                TextButton(
                  onPressed: () => _loadExplore(_exploreUrl, _explorePage + 1),
                  child: const Text('下一页'),
                ),
              ],
            ),
          ),
        Expanded(
          child: switch (_mode) {
            'toc' =>
              _chapters.isEmpty && !_busy && _error.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('没有读到目录，可能是目录规则暂不支持，换个书源试试'),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_resumeChapter != null &&
                            _resumeChapter! < _chapters.length)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: FilledButton.icon(
                              onPressed: () => _openChapter(
                                _chapters[_resumeChapter!],
                                _resumeChapter,
                              ),
                              icon: const Icon(Icons.bookmark_rounded),
                              label: Text(
                                '续读：${(_chapters[_resumeChapter!]['title'] ?? '').toString()}',
                              ),
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _chapters.length,
                            itemBuilder: (_, i) {
                              final chapter = _chapters[i];
                              return ListTile(
                                title: Text(
                                  (chapter['title'] ?? '').toString(),
                                ),
                                selected: i == _chapterIndex,
                                onTap: () => _openChapter(chapter, i),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            'read' => Column(
              children: [
                Expanded(
                  child: _contentImages.isNotEmpty
                      ? Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Row(
                                children: [
                                  Text(
                                    '第 $_imageIndex / ${_contentImages.length} 张',
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _mode = 'toc';
                                    }),
                                    child: const Text('目录'),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  if (notification.metrics.maxScrollExtent <=
                                      0) {
                                    return false;
                                  }
                                  final ratio =
                                      (notification.metrics.pixels /
                                              notification
                                                  .metrics.maxScrollExtent)
                                          .clamp(0, 1);
                                  final index =
                                      (ratio * _contentImages.length)
                                          .ceil()
                                          .clamp(1, _contentImages.length);
                                  if (index != _imageIndex) {
                                    setState(() => _imageIndex = index);
                                  }
                                  return false;
                                },
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (_content.isNotEmpty)
                                        SelectableText(
                                          _content,
                                          style: TextStyle(
                                            fontSize: _fontSize,
                                            height: 1.7,
                                          ),
                                        ),
                                      for (var i = 0;
                                          i < _contentImages.length;
                                          i++)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: InteractiveViewer(
                                            minScale: 1,
                                            maxScale: 4,
                                            child: Image.network(
                                              (_contentImages[i]['url'] ?? '')
                                                  .toString(),
                                              key: ValueKey(
                                                '${(_contentImages[i]['url'] ?? '').toString()}-${_imageRetry[(_contentImages[i]['url'] ?? '').toString()] ?? 0}',
                                              ),
                                              headers: _stringHeaders(
                                                _contentImages[i]['headers'],
                                              ),
                                              errorBuilder: (_, _, _) =>
                                                  Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        '第 ${i + 1} 张加载失败',
                                                      ),
                                                      TextButton(
                                                        onPressed: () =>
                                                            setState(() {
                                                              final url =
                                                                  (_contentImages[i]['url'] ??
                                                                          '')
                                                                      .toString();
                                                              _imageRetry[url] =
                                                                  (_imageRetry[url] ??
                                                                          0) +
                                                                      1;
                                                            }),
                                                        child: const Text(
                                                          '重试',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : _pages.isEmpty
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            _content.isEmpty ? '正文为空' : _content,
                            style: TextStyle(
                              fontSize: _fontSize,
                              height: 1.7,
                            ),
                          ),
                        )
                      : PageView.builder(
                          controller: _readPageController,
                          itemCount: _pages.length,
                          onPageChanged: (page) async {
                            setState(() => _pageIndex = page);
                            final bookUrl =
                                (_currentBook?['url'] ?? '').toString();
                            final source = _selected;
                            if (bookUrl.isNotEmpty &&
                                source != null &&
                                _chapterIndex >= 0) {
                              await NovelReadingProgress.save(
                                source.id,
                                bookUrl,
                                _chapterIndex,
                                page,
                              );
                            }
                          },
                          itemBuilder: (context, i) =>
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: SelectableText(
                                  _pages[i],
                                  style: TextStyle(
                                    fontSize: _fontSize,
                                    height: 1.7,
                                  ),
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
                          onPressed: _chapterIndex > 0
                              ? () => _switchLegadoChapter(_chapterIndex - 1)
                              : null,
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('上一章'),
                        ),
                        TextButton(
                          onPressed: _pages.isNotEmpty && _pageIndex > 0
                              ? () => _readPageController.previousPage(
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
                        IconButton(
                          icon: const Icon(Icons.text_decrease_rounded),
                          tooltip: '减小字号',
                          onPressed: () => _changeLegadoFont(-2),
                        ),
                        IconButton(
                          icon: const Icon(Icons.text_increase_rounded),
                          tooltip: '增大字号',
                          onPressed: () => _changeLegadoFont(2),
                        ),
                        TextButton(
                          onPressed:
                              _pages.isNotEmpty &&
                                  _pageIndex + 1 < _pages.length
                              ? () => _readPageController.nextPage(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                )
                              : null,
                          child: const Text('下一页'),
                        ),
                        TextButton.icon(
                          onPressed: _chapterIndex >= 0 &&
                                  _chapterIndex + 1 < _chapters.length
                              ? () =>
                                  _switchLegadoChapter(_chapterIndex + 1)
                              : null,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('下一章'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            _ =>
              _books.isEmpty && _searched && !_busy && _error.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searchUnsupported
                              ? (_searchUnsupportedReason.isNotEmpty
                                    ? '该书源含本版引擎暂不支持的规则（$_searchUnsupportedReason），换个书源试试'
                                    : '该书源含本版引擎暂不支持的规则，换个书源试试')
                              : _explored
                              ? '该分类下没有内容，换个分类或书源试试'
                              : '没有搜到相关书籍，换个书名或换个书源试试',
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _books.length,
                      itemBuilder: (_, i) {
                        final book = _books[i];
                        return ListTile(
                          title: Text((book['title'] ?? '').toString()),
                          subtitle: Text((book['author'] ?? '').toString()),
                          onTap: () => _openBook(book),
                        );
                      },
                    ),
          },
        ),
      ],
    );
  }
}
