import 'package:flutter/material.dart';

import 'content_models.dart';
import 'midnight_zone.dart';
import 'novel_cover.dart';
import 'novel_reader_page.dart';
import 'reading_bookshelf.dart';

class ReadingBookshelfScreen extends StatefulWidget {
  const ReadingBookshelfScreen({super.key, required this.sources});

  final List<ContentSource> sources;

  @override
  State<ReadingBookshelfScreen> createState() =>
      _ReadingBookshelfScreenState();
}

class _ReadingBookshelfScreenState extends State<ReadingBookshelfScreen> {
  List<ReadingShelfEntry> _entries = const [];
  bool _midnightActivated = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    List<ReadingShelfEntry> entries = const [];
    bool activated = false;
    try {
      entries = await loadShelf();
    } catch (_) {}
    try {
      activated = await loadMidnightActivated();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _midnightActivated = activated;
      _loading = false;
    });
  }

  Widget _cover(ReadingShelfEntry entry, ColorScheme colors) {
    if (entry.cover.isNotEmpty) {
      return Image.network(
        entry.cover,
        width: 56,
        height: 76,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => novelCoverFallback(entry.bookId, 56, 76),
      );
    }
    return novelCoverFallback(entry.bookId, 56, 76);
  }

  String _progress(ReadingShelfEntry entry) {
    final total = entry.chapterTotal > 0 ? '共 ${entry.chapterTotal} 章' : '';
    final current = entry.started
        ? '读到第 ${entry.lastChapterIndex + 1} 章'
        : '尚未开始';
    return [current, total].where((part) => part.isNotEmpty).join(' / ');
  }

  Future<void> _open(ReadingShelfEntry entry) async {
    final source = widget.sources
        .where((item) => item.id == entry.sourceId)
        .firstOrNull;
    if (source == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该书的源已不在，请重新导入')),
        );
      }
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NovelReaderPage(
          source: source,
          book: ContentBook(
            id: entry.bookId,
            title: entry.title,
            cover: entry.cover,
            author: entry.author,
          ),
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _remove(ReadingShelfEntry entry) async {
    try {
      await removeShelfEntry(entry.sourceId, entry.bookId);
    } catch (_) {}
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = visibleShelfEntries(_entries, _midnightActivated);
    final hiddenCount = _entries.length - visible.length;
    return Scaffold(
      appBar: AppBar(title: const Text('书架')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : visible.isEmpty
          ? Center(
              child: Text(
                hiddenCount > 0 ? '书架里的成人书因午夜门禁隐藏' : '书架是空的，在阅读页点书签加入',
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hiddenCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      '有 $hiddenCount 本书因午夜门禁隐藏',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final entry = visible[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => _open(entry),
                          borderRadius: BorderRadius.circular(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _cover(entry, colors),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _progress(entry),
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      entry.sourceName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: ValueKey(
                                  'shelf-remove-${entry.sourceId}-${entry.bookId}',
                                ),
                                tooltip: '移出书架',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _remove(entry),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
