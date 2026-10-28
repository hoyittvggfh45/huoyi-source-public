import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'content_http.dart';
import 'core_bridge.dart';
import 'legado_source.dart';
import 'local_book_store.dart';

class LegadoScreen extends StatefulWidget {
  const LegadoScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<LegadoScreen> createState() => _LegadoScreenState();
}

class _LegadoScreenState extends State<LegadoScreen> {
  List<LegadoSource> _sources = [];
  LegadoSource? _selected;
  final _query = TextEditingController();
  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _chapters = [];
  String _content = '';
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
    _refresh();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await LegadoStore.seedBuiltin();
    final sources = await LegadoStore.load();
    final localBooks = await LocalBookStore.load();
    if (mounted) {
      setState(() {
        _sources = sources;
        _localBooks = localBooks;
        if (_selected == null && sources.isNotEmpty) _selected = sources.first;
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
        _selected ??= merged.isNotEmpty ? merged.first : null;
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

  Future<void> _search() async {
    final source = _selected;
    final keyword = _query.text.trim();
    if (source == null || keyword.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
      _mode = 'books';
      _searchUnsupported = false;
      _searchUnsupportedReason = '';
    });
    try {
      final result = await widget.repository.legadoRun(
        source.rawJson,
        'search',
        keyword,
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

  Future<void> _openBook(Map<String, dynamic> book) async {
    final source = _selected;
    final url = (book['url'] ?? '').toString();
    if (source == null || url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final result = await widget.repository.legadoRun(
        source.rawJson,
        'toc',
        url,
      );
      if (mounted) {
        setState(() {
          _chapters = _toMaps(result);
          _mode = 'toc';
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

  Future<void> _openChapter(Map<String, dynamic> chapter) async {
    final source = _selected;
    final url = (chapter['url'] ?? '').toString();
    if (source == null || url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final result = await widget.repository.legadoRun(
        source.rawJson,
        'content',
        url,
      );
      var text = '';
      if (result is Map<String, dynamic>) {
        text = (result['content'] ?? '').toString();
      } else if (result is String) {
        try {
          final decoded = jsonDecode(result);
          if (decoded is Map<String, dynamic>) {
            text = (decoded['content'] ?? '').toString();
          }
        } catch (_) {
          text = result;
        }
      }
      if (mounted) {
        setState(() {
          _content = text;
          _mode = 'read';
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
              FilledButton(onPressed: _search, child: const Text('搜索')),
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
        if (_sources.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final source in _sources)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
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
                      }),
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
                  : ListView.builder(
                      itemCount: _chapters.length,
                      itemBuilder: (_, i) {
                        final chapter = _chapters[i];
                        return ListTile(
                          title: Text((chapter['title'] ?? '').toString()),
                          onTap: () => _openChapter(chapter),
                        );
                      },
                    ),
            'read' => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _content.isEmpty ? '正文为空' : _content,
                style: const TextStyle(fontSize: 12, height: 1.7),
              ),
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
