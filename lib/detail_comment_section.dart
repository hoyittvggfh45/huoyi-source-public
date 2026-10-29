import 'package:flutter/material.dart';

import 'comment_models.dart';
import 'comment_service.dart';
import 'comment_sheet.dart';

class DetailCommentSection extends StatefulWidget {
  const DetailCommentSection({super.key, required this.videoKey});

  final String videoKey;

  @override
  State<DetailCommentSection> createState() => _DetailCommentSectionState();
}

class _DetailCommentSectionState extends State<DetailCommentSection> {
  List<VideoComment> _comments = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await CommentService.instance.fetchAll(widget.videoKey);
      final blocked = await CommentService.instance.blockedSenders();
      final visible = all
          .where((comment) => !blocked.contains(comment.senderId))
          .toList()
          .reversed
          .toList();
      if (mounted) {
        setState(() {
          _comments = visible;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '评论加载失败';
        });
      }
    }
  }

  Future<void> _write() async {
    final sent = await showCommentSheet(
      context,
      videoKey: widget.videoKey,
      timeMs: 0,
    );
    if (sent != null) _load();
  }

  Future<void> _block(VideoComment comment) async {
    await CommentService.instance.block(comment.senderId);
    if (mounted) {
      setState(
        () => _comments = _comments
            .where((item) => item.senderId != comment.senderId)
            .toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('评论', style: Theme.of(context).textTheme.titleMedium),
              if (!_loading) ...[
                const SizedBox(width: 8),
                Text(
                  '${_comments.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const Spacer(),
              TextButton(onPressed: _write, child: const Text('写评论')),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator()
          else if (_error != null)
            Row(
              children: [
                Expanded(child: Text(_error!)),
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            )
          else if (_comments.isEmpty)
            const Text('还没有评论，来发第一条吧')
          else
            ..._comments.map(
              (comment) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${commentDisplayName(comment)} · ${commentRelativeTime(comment.createdAt, DateTime.now().millisecondsSinceEpoch)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(comment.text),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _block(comment),
                      child: const Text('屏蔽'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
