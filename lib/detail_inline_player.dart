import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'core_bridge.dart';
import 'jar_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'playback_loader.dart';
import 'playback_parse.dart';
import 'player_picker.dart';

double inlineResumePosition({
  required double captured,
  required WatchEntry? saved,
  required int episodeNumber,
}) {
  if (saved != null &&
      saved.episode == episodeNumber &&
      saved.position > captured) {
    return saved.position;
  }
  return captured;
}

class InlinePlayer extends StatefulWidget {
  const InlinePlayer({
    super.key,
    required this.detail,
    required this.index,
    required this.repository,
    required this.store,
    this.initialPosition = 0,
    this.playerFactory,
    this.videoBuilder,
  });

  final DramaDetail detail;
  final int index;
  final AppRepository repository;
  final LocalStore store;
  final double initialPosition;

  @visibleForTesting
  final Player Function()? playerFactory;

  @visibleForTesting
  final Widget Function(Widget controls)? videoBuilder;

  @override
  State<InlinePlayer> createState() => _InlinePlayerState();
}

class _InlinePlayerState extends State<InlinePlayer> {
  late final Player _player;
  VideoController? _video;
  late final PlaybackLoader _loader;
  StreamSubscription<String>? _errorSubscription;
  PlaybackPlan? _plan;
  ParseInterface? _selectedParse;
  bool _loading = true;
  String? _error;
  int _generation = 0;
  bool _closed = false;

  Episode get _episode => widget.detail.episodes[widget.index];

  double get _position => _player.state.position.inMilliseconds / 1000;

  @override
  void initState() {
    super.initState();
    _player =
        widget.playerFactory?.call() ??
        Player(
          configuration: const PlayerConfiguration(
            bufferSize: 32 * 1024 * 1024,
            logLevel: MPVLogLevel.error,
          ),
        );
    _video = widget.videoBuilder == null
        ? VideoController(
            _player,
            configuration: const VideoControllerConfiguration(
              enableHardwareAcceleration: true,
            ),
          )
        : null;
    _loader = PlaybackLoader(widget.repository);
    _errorSubscription = _player.stream.error.listen((error) {
      if (_closed || !mounted || _plan == null || error.trim().isEmpty) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error;
      });
    });
    unawaited(_start());
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    _errorSubscription?.cancel();
    unawaited(_saveProgress());
    final session = _plan?.session;
    if (session != null && session.isNotEmpty) {
      unawaited(widget.repository.release(session));
    }
    unawaited(_loader.close());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    _selectedParse = await ParseInterfaceStore.loadSelected().catchError(
      (Object _) => null,
    );
    if (_closed || !mounted) return;
    await _resolve(widget.initialPosition);
  }

  Future<void> _resolve(double position) async {
    final ticket = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    PlaybackPlan? prepared;
    var installed = false;
    try {
      prepared = await _loader.load(widget.detail.drama, _episode);
      if (_closed || !mounted || ticket != _generation) {
        if (prepared != null) {
          await widget.repository.release(prepared.session);
        }
        return;
      }
      if (prepared == null) return;
      if (!prepared.local && prepared.needsParse) {
        if (JarBridge.isJarSource(widget.detail.drama.source)) {
          final parsed = applySelectedParse(
            url: prepared.url,
            needsParse: true,
            selected: _selectedParse,
          );
          if (parsed != null && parsed != prepared.url) {
            prepared = prepared.withUrl(parsed);
          } else {
            throw AppFailure('需要解析但未配置解析接口');
          }
        } else {
          final apis = await ParseInterfaceStore.loadEnabled();
          if (apis.isEmpty) {
            throw AppFailure('需要解析但未配置解析接口');
          }
          if (prepared.session.isNotEmpty) {
            await widget.repository.release(prepared.session);
          }
          prepared = await widget.repository.resolveParse(prepared, apis);
        }
      } else if (!prepared.local && looksLikeWebPage(prepared.url)) {
        final parsed = applySelectedParse(
          url: prepared.url,
          needsParse: false,
          selected: _selectedParse,
        );
        if (parsed != null && parsed != prepared.url) {
          prepared = prepared.withUrl(parsed);
        }
      }
      if (_closed || !mounted || ticket != _generation) {
        await widget.repository.release(prepared.session);
        return;
      }
      if (prepared.url.isEmpty) {
        throw AppFailure('站源未返回播放地址，请重试');
      }
      final plan = prepared;
      final platform = _player.platform;
      if (plan.decryptionKey.isNotEmpty && platform is NativePlayer) {
        try {
          await platform.setProperty(
            'demuxer-lavf-o',
            [
              'seg_max_retry=3',
              'strict=experimental',
              'allowed_extensions=ALL',
              'protocol_whitelist=[http,https,tcp,tls,crypto,data,file]',
              'decryption_key=${plan.decryptionKey}',
            ].join(','),
          );
        } catch (_) {}
      }
      if (_closed || ticket != _generation) {
        await widget.repository.release(plan.session);
        return;
      }
      await _player.open(
        Media(
          plan.url,
          httpHeaders: plan.headers,
          start: position > 0
              ? Duration(milliseconds: (position * 1000).round())
              : null,
        ),
        play: true,
      );
      if (_closed || !mounted || ticket != _generation) return;
      installed = true;
      setState(() {
        _plan = plan;
        _loading = false;
      });
    } catch (error) {
      if (_closed || !mounted || ticket != _generation) {
        if (!installed && prepared != null) {
          await widget.repository
              .release(prepared.session)
              .catchError((Object _) {});
        }
        return;
      }
      if (!installed && prepared != null) {
        await widget.repository.release(prepared.session);
      }
      setState(() {
        _loading = false;
        _error = error is AppFailure ? error.message : '无法播放这一集，请重试或换一集。';
      });
    }
  }

  Future<void> _retry() => _resolve(_position);

  Future<void> _saveProgress() async {
    final plan = _plan;
    if (plan == null) return;
    final position = _position;
    final duration = _player.state.duration.inMilliseconds / 1000;
    if (position < .1) return;
    final entry = WatchEntry(
      drama: widget.detail.drama,
      episode: _episode.number,
      position: position,
      duration: duration,
      updatedAt: DateTime.now(),
    );
    try {
      await widget.store.saveWatch(entry);
    } catch (_) {}
  }

  Future<void> _openFullscreen() async {
    if (_plan == null) return;
    final captured = _position;
    await _player.pause();
    await _saveProgress();
    if (!mounted || _closed) return;
    await pushPlayer<void>(
      context,
      detail: widget.detail,
      initialIndex: widget.index,
      initialPosition: captured,
      repository: widget.repository,
      store: widget.store,
      startFullscreen: true,
    );
    if (!mounted || _closed) return;
    final resume = inlineResumePosition(
      captured: captured,
      saved: widget.store.watched(widget.detail.drama.id),
      episodeNumber: _episode.number,
    );
    await _player.seek(Duration(milliseconds: (resume * 1000).round()));
    if (!_player.state.playing) {
      await _player.playOrPause();
    }
  }

  Future<void> _openFullscreenFallback() async {
    await pushPlayer<void>(
      context,
      detail: widget.detail,
      initialIndex: widget.index,
      initialPosition: _position,
      repository: widget.repository,
      store: widget.store,
    );
    if (mounted && !_closed && _error != null) {
      await _retry();
    }
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes % 60;
    final seconds = value.inSeconds % 60;
    final tail =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return hours > 0 ? '$hours:$tail' : tail;
  }

  Widget _controls() {
    final episode = _episode;
    if (_loading) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                '正在准备播放 · 第 ${episode.number} 集',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white70,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    key: const ValueKey('inline-retry'),
                    onPressed: _retry,
                    child: const Text('重试'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    key: const ValueKey('inline-error-fullscreen'),
                    onPressed: _openFullscreenFallback,
                    child: const Text('全屏播放'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _player.playOrPause(),
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned(
          top: 8,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '第 ${episode.number} 集',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Row(
              children: [
                StreamBuilder<bool>(
                  stream: _player.stream.playing,
                  initialData: _player.state.playing,
                  builder: (context, snapshot) => IconButton(
                    tooltip: snapshot.data == true ? '暂停' : '播放',
                    onPressed: () => _player.playOrPause(),
                    icon: Icon(
                      snapshot.data == true
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
                StreamBuilder<Duration>(
                  stream: _player.stream.position,
                  initialData: _player.state.position,
                  builder: (context, snapshot) => Text(
                    _formatDuration(snapshot.data ?? Duration.zero),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<Duration>(
                    stream: _player.stream.position,
                    initialData: _player.state.position,
                    builder: (context, positionSnapshot) =>
                        StreamBuilder<Duration>(
                          stream: _player.stream.duration,
                          initialData: _player.state.duration,
                          builder: (context, durationSnapshot) {
                            final position =
                                positionSnapshot.data ?? Duration.zero;
                            final duration =
                                durationSnapshot.data ?? Duration.zero;
                            final max = duration.inMilliseconds.toDouble();
                            return Slider(
                              value: max > 0
                                  ? position.inMilliseconds.toDouble().clamp(
                                      0,
                                      max,
                                    )
                                  : 0,
                              max: max > 0 ? max : 1,
                              onChanged: (value) => _player.seek(
                                Duration(milliseconds: value.round()),
                              ),
                            );
                          },
                        ),
                  ),
                ),
                StreamBuilder<Duration>(
                  stream: _player.stream.duration,
                  initialData: _player.state.duration,
                  builder: (context, snapshot) => Text(
                    _formatDuration(snapshot.data ?? Duration.zero),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                IconButton(
                  key: const ValueKey('inline-fullscreen'),
                  tooltip: '全屏',
                  onPressed: _openFullscreen,
                  icon: const Icon(
                    Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.videoBuilder != null)
              widget.videoBuilder!(_controls())
            else
              Video(
                controller: _video!,
                fit: BoxFit.contain,
                controls: (_) => _controls(),
              ),
          ],
        ),
      ),
    );
  }
}
