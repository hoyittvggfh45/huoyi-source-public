import 'package:flutter/material.dart';

import 'content_models.dart';
import 'content_readers.dart';
import 'core_bridge.dart';

/// 三区共用详情页：封面/简介/说明 + 章节（集数）列表，
/// 点章节按分区进音频播放器 / 漫画阅读器 / 小说阅读器。
class ContentDetailScreen extends StatefulWidget {
  const ContentDetailScreen({
    super.key,
    required this.source,
    required this.book,
  });

  final ContentSource source;
  final ContentBook book;

  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  ContentBookDetail? _detail;
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fetched = await widget.source.detail(widget.book.id);
      final detail = fetched.book.title.isEmpty
          ? ContentBookDetail(
              book: widget.book,
              chapters: fetched.chapters,
              note: fetched.note,
            )
          : fetched;
      if (mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '详情加载失败';
          _loading = false;
        });
      }
    }
  }

  void _openChapter(int index) {
    final detail = _detail;
    if (detail == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComicReaderScreen(
          source: widget.source,
          book: detail.book,
          chapters: detail.chapters,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final book = _detail?.book ?? widget.book;
    return Scaffold(
      appBar: AppBar(title: Text(book.title, maxLines: 1)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error, style: TextStyle(color: colors.error)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = '';
                      });
                      _load();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: book.cover.isNotEmpty
                          ? Image.network(
                              book.cover,
                              width: 96,
                              height: 128,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 96,
                                height: 128,
                                color: colors.surfaceContainerHighest,
                              ),
                            )
                          : Container(
                              width: 96,
                              height: 128,
                              color: colors.surfaceContainerHighest,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (book.author.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              book.author,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ],
                          if (book.remarks.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              book.remarks,
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            '${widget.source.name} · '
                            '${_detail?.chapters.length ?? 0} '
                            '${widget.source.section == ContentSection.audio ? '集' : '章'}',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (book.intro.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(book.intro, style: const TextStyle(height: 1.5)),
                ],
                if (_detail != null && _detail!.note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _detail!.note,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  widget.source.section == ContentSection.audio ? '集数' : '章节',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                if (_detail != null && _detail!.chapters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('暂无章节'),
                  ),
                for (var i = 0; i < (_detail?.chapters.length ?? 0); i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(
                      _detail!.chapters[i].title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: _detail!.chapters[i].meta.isNotEmpty
                        ? Text(_detail!.chapters[i].meta)
                        : null,
                    trailing: Icon(
                      widget.source.section == ContentSection.audio
                          ? Icons.play_circle_outline_rounded
                          : Icons.chevron_right_rounded,
                    ),
                    onTap: () => _openChapter(i),
                  ),
              ],
            ),
    );
  }
}
