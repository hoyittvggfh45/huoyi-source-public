import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'playback_foreground.dart';

class HikerEpisode {
  const HikerEpisode({
    required this.title,
    required this.url,
    this.headers = const {},
  });

  final String title;
  final String url;
  final Map<String, String> headers;
}

String stripHikerPlayFragment(String url) => url.split('#').first;

class HikerPlayerScreen extends StatefulWidget {
  const HikerPlayerScreen({
    super.key,
    required this.title,
    required this.episodes,
    this.initialIndex = 0,
  });

  final String title;
  final List<HikerEpisode> episodes;
  final int initialIndex;

  @override
  State<HikerPlayerScreen> createState() => _HikerPlayerScreenState();
}

class _HikerPlayerScreenState extends State<HikerPlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  late int _index;
  StreamSubscription<String>? _errorSubscription;
  String? _error;
  bool _playbackServiceHeld = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.episodes.length - 1);
    _player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
    );
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _errorSubscription = _player.stream.error.listen((message) {
      if (mounted) setState(() => _error = message);
    });
    WidgetsBinding.instance.addObserver(this);
    _open(_index);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_playbackServiceHeld && _player.state.playing) {
        _playbackServiceHeld = true;
        final title = widget.title.isEmpty
            ? widget.episodes[_index].title
            : widget.title;
        unawaited(PlaybackForeground.acquire(title));
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_playbackServiceHeld) {
        _playbackServiceHeld = false;
        unawaited(PlaybackForeground.release());
      }
    }
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_playbackServiceHeld) {
      _playbackServiceHeld = false;
      unawaited(PlaybackForeground.release());
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _open(int index) async {
    setState(() {
      _index = index;
      _error = null;
    });
    final episode = widget.episodes[index];
    final playUrl = stripHikerPlayFragment(episode.url);
    try {
      await _player.open(Media(playUrl, httpHeaders: episode.headers));
      await _player.play();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.episodes[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title.isEmpty ? episode.title : widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(controller: _controller, fit: BoxFit.contain),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              episode.title,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                '播放失败：$_error',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.episodes.length,
              itemBuilder: (context, index) {
                final item = widget.episodes[index];
                return ListTile(
                  selected: index == _index,
                  title: Text(
                    item.title.isEmpty ? '第${index + 1}集' : item.title,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: index == _index
                      ? const Icon(Icons.play_arrow, color: Colors.white)
                      : null,
                  onTap: () => _open(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
