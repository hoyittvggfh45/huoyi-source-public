import 'dart:async';

import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'danmaku_controller.dart';
import 'danmaku_overlay.dart';
import 'local_store.dart';
import 'models.dart';
import 'watchroom/player.dart';

double hongguoVideoAspect(RoomPlayerHandle handle) {
  final state = handle.videoController?.player.state;
  final width = state?.width;
  final height = state?.height;
  if (width != null && height != null && width > 0 && height > 0) {
    return width / height;
  }
  return 9 / 16;
}

class HongguoDanmakuLayer extends StatefulWidget {
  const HongguoDanmakuLayer({
    super.key,
    required this.handle,
    required this.repository,
    required this.store,
    required this.available,
    required this.aspectRatio,
  });

  final RoomPlayerHandle handle;
  final AppRepository repository;
  final LocalStore store;
  final bool available;
  final double aspectRatio;

  @override
  State<HongguoDanmakuLayer> createState() => _HongguoDanmakuLayerState();
}

class _HongguoDanmakuLayerState extends State<HongguoDanmakuLayer> {
  late final DanmakuController _controller;
  StreamSubscription<double>? _positionSub;
  PlaybackPlan? _boundPlan;

  @override
  void initState() {
    super.initState();
    _controller = DanmakuController(widget.repository);
    widget.handle.addListener(_sync);
    _positionSub = widget.handle.positionStream.listen((_) {
      if (mounted) _sync();
    });
    _sync();
  }

  @override
  void didUpdateWidget(HongguoDanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    widget.handle.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final handle = widget.handle;
    if (!identical(_boundPlan, handle.plan)) {
      _boundPlan = handle.plan;
      _controller.setPlan(handle.plan);
    }
    _controller.setEnabled(widget.store.playbackPreferences.danmaku);
    _controller.update(
      position: Duration(milliseconds: (handle.position * 1000).round()),
      duration: Duration(milliseconds: (handle.duration * 1000).round()),
      speed: widget.store.playbackPreferences.speed,
      playing: handle.playing,
      buffering: false,
      foreground: true,
      available: widget.available,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DanmakuOverlay(
      controller: _controller,
      aspectRatio: widget.aspectRatio,
    );
  }
}
