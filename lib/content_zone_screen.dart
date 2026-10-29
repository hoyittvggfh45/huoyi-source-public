import 'package:flutter/material.dart';

import 'app_page_route.dart';

import 'content_detail_screen.dart';
import 'content_models.dart';
import 'content_zone_binding.dart';
import 'core_bridge.dart';
import 'source_picker_sheet.dart';

/// 听书 / 漫画 / 小说共用的分区页：源切换 + 分类 + 搜索 + 卡片列表，
/// 文件夹卡走下钻栈（与影视区文件夹通道同一交互口径）。
class ContentZoneScreen extends StatefulWidget {
  const ContentZoneScreen({super.key, required this.section, this.binding});

  final ContentSection section;
  final ContentZoneBinding? binding;

  @override
  State<ContentZoneScreen> createState() => _ContentZoneScreenState();
}

class _ContentZoneScreenState extends State<ContentZoneScreen> {
  late final ContentZoneBinding _binding;
  late List<ContentSource> _sources;
  ContentSource? _source;
  List<ContentCategory> _categories = const [];
  String _categoryId = '';
  String _categoryName = '';
  final List<({String id, String name})> _drill = [];
  List<ContentBook> _items = const [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  String _error = '';
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _binding = widget.binding ?? ContentZoneBinding();
    _bindSection();
  }

  @override
  void didUpdateWidget(ContentZoneScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) _bindSection();
  }

  void _bindSection() {
    _sources = _binding.sourcesFor(widget.section);
    _source = _binding.sourceFor(widget.section);
    _categories = const [];
    _categoryId = '';
    _categoryName = '';
    _drill.clear();
    _items = const [];
    _page = 1;
    _hasMore = false;
    _loading = false;
    _loadingMore = false;
    _error = '';
    _query = '';
    _searchController.clear();
    if (_source != null) _loadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final cats = await source.categories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _categoryId = cats.isNotEmpty ? cats.first.id : '';
        _categoryName = cats.isNotEmpty ? cats.first.name : '';
        _drill.clear();
      });
      await _loadPage(reset: true);
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载分类失败';
        });
      }
    }
  }

  Future<void> _loadPage({required bool reset}) async {
    final source = _source;
    if (source == null) return;
    if (reset) {
      setState(() {
        _loading = true;
        _error = '';
        _page = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final page = reset ? 1 : _page + 1;
      final result = _query.isNotEmpty
          ? await source.search(_query, page)
          : await source.catalog(_categoryId, page);
      if (!mounted) return;
      setState(() {
        _items = reset ? result.items : [..._items, ...result.items];
        _page = page;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          if (reset) _error = e.message;
        });
        if (!reset) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          if (reset) _error = '加载失败';
        });
      }
    }
  }

  Future<void> _pickSource() async {
    final picked = await showSitePickerDialog(
      context,
      sectionName: widget.section.title,
      currentId: _source?.id ?? '',
      groups: [
        SourcePickerGroup(
          title: '',
          entries: [
            for (final source in _sources)
              SourcePickerEntry(id: source.id, name: source.name),
          ],
        ),
      ],
    );
    if (picked == null || !mounted) return;
    final source = _sources.where((source) => source.id == picked).firstOrNull;
    if (source != null) _selectSource(source);
  }

  void _selectSource(ContentSource source) {
    if (identical(source, _source)) return;
    _binding.select(widget.section, source);
    setState(() {
      _source = source;
      _query = '';
      _searchController.clear();
      _items = const [];
      _categories = const [];
    });
    _loadCategories();
  }

  void _selectCategory(ContentCategory category) {
    setState(() {
      _categoryId = category.id;
      _categoryName = category.name;
      _drill.clear();
      _query = '';
      _searchController.clear();
    });
    _loadPage(reset: true);
  }

  void _openBook(ContentBook book) {
    final source = _source;
    if (source == null) return;
    if (book.isFolder) {
      setState(() {
        _drill.add((id: _categoryId, name: _categoryName));
        _categoryId = book.drillId;
        _categoryName = book.title;
      });
      _loadPage(reset: true);
      return;
    }
    Navigator.of(context).push(
      appPageRoute(
        builder: (_) => ContentDetailScreen(source: source, book: book),
      ),
    );
  }

  void _drillBack() {
    if (_drill.isEmpty) return;
    final prev = _drill.removeLast();
    setState(() {
      _categoryId = prev.id;
      _categoryName = prev.name;
    });
    _loadPage(reset: true);
  }

  void _submitSearch() {
    setState(() {
      _query = _searchController.text.trim();
      _drill.clear();
    });
    _loadPage(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_sources.isEmpty) {
      return Center(child: Text('${widget.section.title}暂无可用源'));
    }
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              InkWell(
                key: const ValueKey('content-source-switch'),
                onTap: _pickSource,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _source?.name ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              if (_source != null && _source!.note.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _source!.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索${widget.section.title}',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                        _loadPage(reset: true);
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _submitSearch(),
          ),
        ),
        if (_drill.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回上一级',
                  onPressed: _drillBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    _categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        else if (_categories.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                for (final category in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(category.name),
                      selected: _query.isEmpty && category.id == _categoryId,
                      onSelected: (_) => _selectCategory(category),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(child: _body(colors)),
      ],
    );
  }

  Widget _body(ColorScheme colors) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error, style: TextStyle(color: colors.error)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _loadPage(reset: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('暂无内容'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) => _card(_items[index]),
        ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: () => _loadPage(reset: false),
                      child: const Text('加载更多'),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _card(ContentBook book) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openBook(book),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: book.cover.isNotEmpty
                  ? Image.network(
                      book.cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _coverFallback(colors, book),
                    )
                  : _coverFallback(colors, book),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (book.isFolder)
                Icon(Icons.folder_rounded, size: 14, color: colors.primary),
              Expanded(
                child: Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (book.remarks.isNotEmpty)
            Text(
              book.remarks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _coverFallback(ColorScheme colors, ContentBook book) => Container(
    color: colors.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Icon(
      book.isFolder ? Icons.folder_rounded : Icons.image_not_supported,
      color: colors.onSurfaceVariant,
    ),
  );
}
