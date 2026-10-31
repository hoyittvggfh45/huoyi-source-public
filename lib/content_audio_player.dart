import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'content_models.dart';
import 'core_bridge.dart';

class ContentAudioPlayerScreen extends StatefulWidget {
  const ContentAudioPlayerScreen({
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
  State<ContentAudioPlayerScreen> createState() =>
      _ContentAudioPlayerScreenState();
}

String _formatAudioTime(Duration value) {
  final total = value.inSeconds;
  if (total < 0) return '00:00';
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$mm:$ss';
  return '$mm:$ss';
}

class _ContentAudioPlayerScreenState extends State<ContentAudioPlayerScreen> {
  late final Player _player = Player();
  late int _index;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _loading = true;
  String _error = '';
  double _rate = 1.0;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.chapters.length - 1);
    _subs.addAll([
      _player.stream.position.listen((value) {
        if (mounted) setState(() => _position = value);
      }),
      _player.stream.duration.listen((value) {
        if (mounted) setState(() => _duration = value);
      }),
      _player.stream.playing.listen((value) {
        if (mounted) setState(() => _playing = value);
      }),
      _player.stream.completed.listen((completed) {
        if (completed == true) _next(auto: true);
      }),
      _player.stream.error.listen((_) {
        if (mounted && _error.isEmpty) {
          setState(() => _error = '音频播放出错');
        }
      }),
    ]);
    _loadTrack(_index);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadTrack(int index) async {
    if (index < 0 || index >= widget.chapters.length) return;
    setState(() {
      _index = index;
      _loading = true;
      _error = '';
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    try {
      final track = await widget.source.audioTrack(
        widget.book.id,
        widget.chapters[index],
      );
      if (!mounted) return;
      await _player.open(Media(track.url));
      await _player.setRate(_rate);
      await _player.play();
      if (mounted) setState(() => _loading = false);
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
          _error = '音频加载失败';
        });
      }
    }
  }

  void _next({bool auto = false}) {
    if (_index + 1 >= widget.chapters.length) return;
    _loadTrack(_index + 1);
  }

  void _prev() {
    if (_index - 1 < 0) return;
    _loadTrack(_index - 1);
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _setRate(double rate) async {
    setState(() => _rate = rate);
    await _player.setRate(rate);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chapter = widget.chapters.isEmpty ? null : widget.chapters[_index];
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs);
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.title, maxLines: 1)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: widget.book.cover.isNotEmpty
                      ? Image.network(
                          widget.book.cover,
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
                          child: const Icon(Icons.headphones_rounded),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.book.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (chapter != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          chapter.title,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                      if (widget.book.author.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.book.author,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        '第 ${_index + 1} 集 / 共 ${widget.chapters.length} 集',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_error, style: TextStyle(color: colors.error)),
                  ),
                  FilledButton(
                    onPressed: () => _loadTrack(_index),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text(_formatAudioTime(_position)),
                Expanded(
                  child: Slider(
                    value: posMs,
                    max: maxMs,
                    onChanged: (value) {
                      _player.seek(Duration(milliseconds: value.toInt()));
                    },
                  ),
                ),
                Text(_formatAudioTime(_duration)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '上一集',
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: _index > 0 ? _prev : null,
                ),
                const SizedBox(width: 16),
                _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      )
                    : IconButton(
                        tooltip: _playing ? '暂停' : '播放',
                        iconSize: 48,
                        icon: Icon(
                          _playing
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_filled_rounded,
                        ),
                        onPressed: _toggle,
                      ),
                const SizedBox(width: 16),
                IconButton(
                  tooltip: '下一集',
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: _index + 1 < widget.chapters.length
                      ? () => _next()
                      : null,
                ),
                const SizedBox(width: 16),
                PopupMenuButton<double>(
                  tooltip: '倍速',
                  initialValue: _rate,
                  onSelected: _setRate,
                  itemBuilder: (_) => [
                    for (final rate in [0.75, 1.0, 1.25, 1.5, 2.0])
                      PopupMenuItem(value: rate, child: Text('${rate}x')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Text('${_rate}x'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: widget.chapters.length,
              itemBuilder: (context, i) {
                final item = widget.chapters[i];
                final selected = i == _index;
                return ListTile(
                  selected: selected,
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(item.title, maxLines: 2),
                  trailing: selected
                      ? const Icon(Icons.volume_up_rounded)
                      : null,
                  onTap: () {
                    if (i != _index) _loadTrack(i);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
