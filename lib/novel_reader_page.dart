import 'package:flutter/material.dart';

import 'content_models.dart';
import 'nonvideo_content.dart';

class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({super.key, required this.source, required this.book});

  final ContentSource source;
  final ContentBook book;

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  List<ContentChapter> _chapters = const [];
  int _index = 0;
  NonVideoContent? _content;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await widget.source.detail(widget.book.id);
      if (!mounted) return;
      if (detail.chapters.isEmpty) {
        setState(() {
          _loading = false;
          _error = '该书暂无章节';
        });
        return;
      }
      _chapters = detail.chapters;
      await _loadChapter(0);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载章节失败';
        });
      }
    }
  }

  Future<void> _loadChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _loading = true;
      _error = '';
      _index = index;
    });
    try {
      final track = await widget.source.audioTrack(
        widget.book.id,
        _chapters[index],
      );
      final parsed = parseNonVideoUrl(track.url);
      if (!mounted) return;
      if (parsed == null || !parsed.isNovel) {
        setState(() {
          _loading = false;
          _error = '该章不是小说文本';
        });
        return;
      }
      setState(() {
        _loading = false;
        _content = parsed;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载章节失败';
        });
      }
    }
  }

  Future<void> _pickChapter() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择章节'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: _chapters.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(_chapters[i].title),
              selected: i == _index,
              onTap: () => Navigator.of(context).pop(i),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (picked != null && picked != _index) _loadChapter(picked);
  }

  @override
  Widget build(BuildContext context) {
    final chapterTitle = _chapters.isEmpty ? '' : _chapters[_index].title;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          IconButton(
            key: const ValueKey('novel-prev-chapter'),
            tooltip: '上一章',
            onPressed: _index > 0 ? () => _loadChapter(_index - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            key: const ValueKey('novel-next-chapter'),
            tooltip: '下一章',
            onPressed: _index + 1 < _chapters.length
                ? () => _loadChapter(_index + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            key: const ValueKey('novel-chapter-list'),
            tooltip: '章节列表',
            onPressed: _chapters.isEmpty ? null : _pickChapter,
            icon: const Icon(Icons.list_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _index < _chapters.length
                        ? _loadChapter(_index)
                        : _loadDetail(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : _content == null
          ? const Center(child: Text('暂无内容'))
          : NovelReaderView(content: _content!, title: chapterTitle),
    );
  }
}
