import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'content_audio_history.dart';
import 'content_models.dart';
import 'core_bridge.dart';

enum AudioPlayMode { sequence, loopAll, loopOne, shuffle }

extension AudioPlayModeValue on AudioPlayMode {
  String get storageValue => name;
  static AudioPlayMode fromStorage(String? value) =>
      AudioPlayMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => AudioPlayMode.sequence,
      );
}

int? audioNextIndex(
  AudioPlayMode mode,
  int index,
  int length,
  int Function() shufflePick,
) {
  if (length <= 0 || index < 0 || index >= length) return null;
  if (mode == AudioPlayMode.loopOne) return index;
  if (mode == AudioPlayMode.shuffle) return shufflePick();
  if (index + 1 < length) return index + 1;
  if (mode == AudioPlayMode.loopAll) return 0;
  return null;
}

int? audioPrevIndex(
  AudioPlayMode mode,
  int index,
  int length,
  int Function() shufflePick,
) {
  if (length <= 0 || index < 0 || index >= length) return null;
  if (mode == AudioPlayMode.shuffle) return shufflePick();
  if (index - 1 >= 0) return index - 1;
  if (mode == AudioPlayMode.loopAll) return length - 1;
  return null;
}

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
  AudioPlayMode _mode = AudioPlayMode.sequence;
  final _random = Random();
  final _store = AudioProgressStore();
  int? _pendingSeekMs;
  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _sleepTimer;
  int _sleepMinutesLeft = 0;
  bool _favorite = false;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.chapters.length - 1);
    _subs.addAll([
      _player.stream.position.listen((value) {
        if (mounted) setState(() => _position = value);
        _saveProgressThrottled();
      }),
      _player.stream.duration.listen((value) {
        if (mounted) setState(() => _duration = value);
        final pending = _pendingSeekMs;
        if (pending != null && pending > 0 && value > Duration.zero) {
          _pendingSeekMs = null;
          unawaited(_player.seek(Duration(milliseconds: pending)));
        }
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
    _loadPrefs();
    _loadTrack(_index);
  }

  Future<void> _loadPrefs() async {
    final mode = await _store.loadPlayMode();
    final favorite = await _store.isFavorite(_bookKey);
    if (mounted) {
      setState(() {
        _mode = AudioPlayModeValue.fromStorage(mode);
        _favorite = favorite;
      });
    }
  }

  String get _bookKey => '${widget.source.id}::${widget.book.id}';

  void _saveProgressThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastSavedAt) < const Duration(seconds: 15)) return;
    if (_position <= Duration.zero) return;
    _lastSavedAt = now;
    unawaited(
      _store.saveResume(
        widget.source.id,
        widget.book.id,
        _index,
        _position.inMilliseconds,
      ),
    );
  }

  void _saveProgressNow() {
    if (_position <= Duration.zero) return;
    unawaited(
      _store.saveResume(
        widget.source.id,
        widget.book.id,
        _index,
        _position.inMilliseconds,
      ),
    );
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _saveProgressNow();
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadTrack(int index) async {
    if (index < 0 || index >= widget.chapters.length) return;
    _saveProgressNow();
    setState(() {
      _index = index;
      _loading = true;
      _error = '';
      _position = Duration.zero;
      _duration = Duration.zero;
      _pendingSeekMs = null;
    });
    try {
      final resume = await _store.loadResume(widget.source.id, widget.book.id);
      final track = await widget.source.audioTrack(
        widget.book.id,
        widget.chapters[index],
      );
      if (!mounted) return;
      if (resume != null && resume.chapterIndex == index) {
        _pendingSeekMs = resume.positionMs;
      }
      await _player.open(
        Media(
          track.url,
          httpHeaders: track.headers.isEmpty ? null : track.headers,
        ),
      );
      await _player.setRate(_rate);
      await _player.play();
      unawaited(
        _store.recordHistory(
          AudioHistoryEntry(
            sourceId: widget.source.id,
            bookId: widget.book.id,
            title: widget.book.title,
            cover: widget.book.cover,
            chapterIndex: index,
            chapterTitle: widget.chapters[index].title,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
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

  int _shuffleNext() {
    if (widget.chapters.length <= 1) return _index;
    var next = _random.nextInt(widget.chapters.length);
    while (next == _index) {
      next = _random.nextInt(widget.chapters.length);
    }
    return next;
  }

  void _next({bool auto = false}) {
    if (widget.chapters.isEmpty) return;
    final next = audioNextIndex(
      _mode,
      _index,
      widget.chapters.length,
      _shuffleNext,
    );
    if (next != null) _loadTrack(next);
  }

  void _prev() {
    if (widget.chapters.isEmpty) return;
    final prev = audioPrevIndex(
      _mode,
      _index,
      widget.chapters.length,
      _shuffleNext,
    );
    if (prev != null) _loadTrack(prev);
  }

  Future<void> _cycleMode() async {
    final next = switch (_mode) {
      AudioPlayMode.sequence => AudioPlayMode.loopAll,
      AudioPlayMode.loopAll => AudioPlayMode.loopOne,
      AudioPlayMode.loopOne => AudioPlayMode.shuffle,
      AudioPlayMode.shuffle => AudioPlayMode.sequence,
    };
    setState(() => _mode = next);
    await _store.savePlayMode(next.storageValue);
  }

  IconData get _modeIcon => switch (_mode) {
    AudioPlayMode.sequence => Icons.arrow_forward_rounded,
    AudioPlayMode.loopAll => Icons.repeat_rounded,
    AudioPlayMode.loopOne => Icons.repeat_one_rounded,
    AudioPlayMode.shuffle => Icons.shuffle_rounded,
  };

  String get _modeLabel => switch (_mode) {
    AudioPlayMode.sequence => '顺序播放',
    AudioPlayMode.loopAll => '循环全部',
    AudioPlayMode.loopOne => '单集循环',
    AudioPlayMode.shuffle => '随机播放',
  };

  void _setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (minutes == null || minutes <= 0) {
      setState(() => _sleepMinutesLeft = 0);
      return;
    }
    setState(() => _sleepMinutesLeft = minutes);
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = _sleepMinutesLeft - 1;
      if (left <= 0) {
        timer.cancel();
        setState(() => _sleepMinutesLeft = 0);
        unawaited(_player.pause());
        return;
      }
      setState(() => _sleepMinutesLeft = left);
    });
  }

  Future<void> _toggleFavorite() async {
    final next = !_favorite;
    setState(() => _favorite = next);
    await _store.setFavorite(_bookKey, next);
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
      appBar: AppBar(
        title: Text(widget.book.title, maxLines: 1),
        actions: [
          IconButton(
            tooltip: _favorite ? '取消收藏' : '收藏',
            icon: Icon(
              _favorite ? Icons.star_rounded : Icons.star_border_rounded,
            ),
            onPressed: _toggleFavorite,
          ),
        ],
      ),
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
                  onPressed: widget.chapters.length > 1 ? _prev : null,
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
                  onPressed: widget.chapters.length > 1 ? () => _next() : null,
                ),
                const SizedBox(width: 16),
                IconButton(
                  tooltip: _modeLabel,
                  icon: Icon(_modeIcon),
                  onPressed: _cycleMode,
                ),
                const SizedBox(width: 16),
                PopupMenuButton<int?>(
                  tooltip: '睡眠定时',
                  onSelected: _setSleepTimer,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: null, child: Text('关闭定时')),
                    const PopupMenuItem(value: 15, child: Text('15 分钟后暂停')),
                    const PopupMenuItem(value: 30, child: Text('30 分钟后暂停')),
                    const PopupMenuItem(value: 60, child: Text('60 分钟后暂停')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Text(
                      _sleepMinutesLeft > 0 ? '$_sleepMinutesLeft 分钟' : '定时',
                    ),
                  ),
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
