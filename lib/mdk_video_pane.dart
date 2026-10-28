import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'player_core.dart';

class MdkPlayerController {
  MdkPlayerController(this._controller);

  final VideoPlayerController _controller;

  Future<void> play() => _controller.play();

  Future<void> pause() => _controller.pause();

  Future<void> seekTo(Duration target) => _controller.seekTo(target);

  Future<void> setSpeed(double value) => _controller.setPlaybackSpeed(value);
}

class MdkPlaybackHandle {
  MdkPlayerController? _controller;
  double speed = 1.0;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  bool completed = false;

  void attach(MdkPlayerController controller) {
    _controller = controller;
  }

  void detach() {
    _controller = null;
  }

  Future<void> play() async => _controller?.play();

  Future<void> pause() async => _controller?.pause();

  Future<void> seek(Duration target) async => _controller?.seekTo(target);

  Future<void> setSpeed(double value) {
    speed = value;
    return _controller?.setSpeed(value) ?? Future.value();
  }

  double get positionSeconds => position.inMilliseconds / 1000;

  double get durationSeconds => duration.inMilliseconds / 1000;
}

class MdkVideoPane extends StatefulWidget {
  const MdkVideoPane({
    super.key,
    required this.plan,
    required this.startPosition,
    required this.autoplay,
    required this.handle,
    required this.onCompleted,
    required this.onError,
    required this.core,
    required this.onCoreTap,
    required this.title,
    this.onBack,
    this.onFullscreen,
    this.isFullscreen = false,
  });

  final PlaybackPlan? plan;
  final double startPosition;
  final bool autoplay;
  final MdkPlaybackHandle handle;
  final VoidCallback onCompleted;
  final ValueChanged<String> onError;
  final PlayerCore core;
  final VoidCallback onCoreTap;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onFullscreen;
  final bool isFullscreen;

  @override
  State<MdkVideoPane> createState() => _MdkVideoPaneState();
}

class _MdkVideoPaneState extends State<MdkVideoPane> {
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
  static bool _fvpRegistered = false;

  VideoPlayerController? _controller;
  String? _openedSession;
  bool _openedAutoplay = true;
  bool _dragging = false;
  double _dragValue = 0;
  bool _completedFired = false;
  bool _errorFired = false;
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    if (!_fvpRegistered) {
      _fvpRegistered = true;
      fvp.registerWith();
    }
    final plan = widget.plan;
    if (plan != null) {
      _openedAutoplay = widget.autoplay;
      unawaited(_open(plan, widget.startPosition));
    }
  }

  @override
  void didUpdateWidget(MdkVideoPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final plan = widget.plan;
    if (plan != null && plan.session != _openedSession) {
      _openedAutoplay = widget.autoplay;
      unawaited(_open(plan, widget.startPosition));
    }
  }

  @override
  void dispose() {
    _disposeController();
    widget.handle.detach();
    super.dispose();
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onValue);
      unawaited(controller.dispose());
    }
  }

  Future<void> _open(PlaybackPlan plan, double startPosition) async {
    _disposeController();
    _completedFired = false;
    _errorFired = false;
    widget.handle.completed = false;
    final controller = plan.local
        ? VideoPlayerController.file(File(plan.url))
        : VideoPlayerController.networkUrl(
            Uri.parse(plan.url),
            httpHeaders: plan.headers,
          );
    _controller = controller;
    widget.handle.attach(MdkPlayerController(controller));
    controller.addListener(_onValue);
    setState(() => _initializing = true);
    try {
      await controller.initialize();
    } catch (error) {
      if (!mounted || _controller != controller) return;
      setState(() => _initializing = false);
      if (!_errorFired) {
        _errorFired = true;
        widget.onError('MDK 播放器初始化失败');
      }
      return;
    }
    if (!mounted || _controller != controller) return;
    _openedSession = plan.session;
    setState(() => _initializing = false);
    if (startPosition > 0) {
      await controller.seekTo(
        Duration(milliseconds: (startPosition * 1000).round()),
      );
    }
    await controller.setPlaybackSpeed(widget.handle.speed);
    if (_openedAutoplay) {
      await controller.play();
    } else {
      await controller.pause();
    }
  }

  void _onValue() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    widget.handle.position = value.position;
    widget.handle.duration = value.duration;
    widget.handle.playing = value.isPlaying;
    if (value.hasError && !_errorFired) {
      _errorFired = true;
      widget.onError(value.errorDescription ?? '播放失败');
    }
    if (value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying &&
        !_completedFired) {
      _completedFired = true;
      widget.handle.completed = true;
      widget.onCompleted();
    }
    setState(() {});
  }

  String _formatTime(Duration value) {
    final total = value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller != null && controller.value.isInitialized;
    final position = widget.handle.position;
    final duration = widget.handle.duration;
    final maxMs = duration.inMilliseconds.toDouble();
    final sliderValue = maxMs > 0
        ? (_dragging
              ? _dragValue
              : position.inMilliseconds.toDouble().clamp(0, maxMs).toDouble())
        : 0.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (initialized)
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          )
        else
          const ColoredBox(color: Colors.black),
        if (_initializing)
          const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Row(
              children: [
                if (widget.onBack != null)
                  IconButton(
                    tooltip: '返回',
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: widget.onBack,
                  ),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                PlayerCoreBadge(core: widget.core, onTap: widget.onCoreTap),
                if (widget.onFullscreen != null)
                  IconButton(
                    tooltip: widget.isFullscreen ? '退出全屏' : '全屏',
                    icon: Icon(
                      widget.isFullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: Colors.white,
                    ),
                    onPressed: widget.onFullscreen,
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    widget.handle.playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (widget.handle.playing) {
                      unawaited(widget.handle.pause());
                    } else {
                      unawaited(widget.handle.play());
                    }
                  },
                ),
                Text(
                  _formatTime(position),
                  style: const TextStyle(color: Colors.white),
                ),
                Expanded(
                  child: Slider(
                    value: sliderValue,
                    max: maxMs > 0 ? maxMs : 1,
                    onChangeStart: (_) => setState(() => _dragging = true),
                    onChanged: (value) => setState(() => _dragValue = value),
                    onChangeEnd: (value) {
                      setState(() => _dragging = false);
                      unawaited(
                        widget.handle.seek(
                          Duration(milliseconds: value.round()),
                        ),
                      );
                    },
                  ),
                ),
                Text(
                  _formatTime(duration),
                  style: const TextStyle(color: Colors.white),
                ),
                PopupMenuButton<double>(
                  icon: Text(
                    '${widget.handle.speed}x',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onSelected: (value) {
                    unawaited(widget.handle.setSpeed(value));
                  },
                  itemBuilder: (context) => _speeds
                      .map(
                        (speed) => PopupMenuItem<double>(
                          value: speed,
                          child: Text('${speed}x'),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
