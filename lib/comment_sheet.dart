import 'package:flutter/material.dart';

import 'comment_api.dart';
import 'comment_identity.dart';
import 'comment_service.dart';
import 'danmaku_models.dart';

Future<DanmakuItem?> showCommentSheet(
  BuildContext context, {
  required String videoKey,
  required int timeMs,
}) {
  return showModalBottomSheet<DanmakuItem>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) =>
        CommentSheet(videoKey: videoKey, timeMs: timeMs),
  );
}

class CommentSheet extends StatefulWidget {
  const CommentSheet({super.key, required this.videoKey, required this.timeMs});

  final String videoKey;
  final int timeMs;

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final identity = CommentIdentity.instance;
    final controller = TextEditingController(text: identity.nickname);
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('改昵称'),
        content: TextField(
          controller: controller,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '1 至 20 字'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null) return;
    final ok = await identity.rename(next);
    if (!ok && mounted) {
      setState(() => _error = '昵称须为 1 至 20 字');
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _text.text;
    if (text.trim().isEmpty) {
      setState(() => _error = '评论不能为空');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final posted = await CommentService.instance.send(
        videoKey: widget.videoKey,
        text: text,
        timeMs: widget.timeMs,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        DanmakuItem(
          id: posted.id,
          text: posted.nickname.isNotEmpty
              ? '${posted.nickname}：${posted.text}'
              : posted.text,
          timeMs: posted.timeMs,
        ),
      );
    } on CommentRateLimited {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = '发得太快了，稍后再试';
        });
      }
    } on CommentApiException catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = '评论发送失败';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CommentIdentity.instance,
      builder: (context, _) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('发弹幕评论'),
                const Spacer(),
                TextButton(
                  onPressed: _rename,
                  child: Text(
                    CommentIdentity.instance.nickname.isEmpty
                        ? '设置昵称'
                        : CommentIdentity.instance.nickname,
                  ),
                ),
              ],
            ),
            TextField(
              controller: _text,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '说点什么…',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _send(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(_sending ? '发送中…' : '发送'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
