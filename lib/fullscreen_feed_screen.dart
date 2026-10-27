import 'dart:async';

import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'playback_preferences.dart';
import 'player_picker.dart';
import 'tvbox_player_bridge.dart';
import 'video_enhancement_preferences.dart';
import 'watchroom/player.dart';
import 'widgets.dart';

String feedResumeKey(Drama drama) => '${drama.source}|${drama.id}';

List<Drama> feedPlayableDramas(List<Drama> items) =>
    items.where((drama) => drama.kind == 'video').toList();

int clampFeedEpisodeIndex(int index, int count) {
  if (count <= 0) return 0;
  if (index < 0) return 0;
  if (index >= count) return count - 1;
  return index;
}

class FullscreenFeedScreen extends StatefulWidget {
  const FullscreenFeedScreen({
    super.key,
    required this.dramas,
    required this.repository,
    required this.store,
    this.onMenuPressed,
    this.categories = const [],
    this.selectedCategory = '',
    this.onCategorySelected,
  });

  final List<Drama> dramas;
  final AppRepository repository;
  final LocalStore store;
  final VoidCallback? onMenuPressed;
  final List<CatalogCategory> categories;
  final String selectedCategory;
  final ValueChanged<String>? onCategorySelected;

  @override
  State<FullscreenFeedScreen> createState() => _FullscreenFeedScreenState();
}

class _FullscreenFeedScreenState extends State<FullscreenFeedScreen> {
  late List<Drama> _items = feedPlayableDramas(widget.dramas);
  late final PageController _pages = PageController();
  final RoomPlayerHandle _player = RoomPlayerHandle();
  final Map<String, DramaDetail> _details = {};
  final Map<String, int> _episodeByKey = {};
  final Map<String, double> _positionByKey = {};
  int _index = 0;
  int _episode = 0;
  bool _detailLoading = false;
  String? _detailError;
  int _playToken = 0;
  bool _opening = false;
  bool _pendingPlay = false;

  @override
  void initState() {
    super.initState();
    if (_items.isNotEmpty) {
      unawaited(_playCurrent());
      _prefetch(1);
    }
  }

  @override
  void didUpdateWidget(FullscreenFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = feedPlayableDramas(widget.dramas);
    final nextKeys = [for (final drama in next) _keyFor(drama)].join('|');
    final currentKeys = [for (final drama in _items) _keyFor(drama)].join('|');
    if (nextKeys == currentKeys) return;
    _savePosition();
    _playToken++;
    setState(() {
      _items = next;
      _index = 0;
      _episode = 0;
      _detailError = null;
    });
    if (next.isEmpty) return;
    if (_pages.hasClients && (_pages.page ?? 0) != 0) {
      _pages.jumpToPage(0);
    } else {
      unawaited(_playCurrent());
      _prefetch(1);
    }
  }

  @override
  void dispose() {
    _playToken++;
    _pages.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final categories = widget.categories;
    final onSelected = widget.onCategorySelected;
    if (categories.isEmpty || onSelected == null) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in categories)
                ChoiceChip(
                  label: Text(category.name),
                  selected: category.id == widget.selectedCategory,
                  onSelected: (_) => Navigator.pop(context, category.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != widget.selectedCategory) {
      onSelected(selected);
    }
  }

  Future<void> _openFeedSettings() async {
    var prefs = widget.store.playbackPreferences;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> save(PlaybackPreferences next) async {
            await saveUserChange(
              sheetContext,
              () => widget.store.setPlaybackPreferences(next),
            );
            prefs = widget.store.playbackPreferences;
            setSheetState(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '流内设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  ListTile(
                    leading: const Icon(Icons.video_settings_outlined),
                    title: const Text('播放器'),
                    subtitle: Text(widget.store.player),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      sheetContext,
                      MaterialPageRoute<void>(
                        builder: (_) => PlayerPickerScreen(store: widget.store),
                      ),
                    ),
                  ),
                  const ListTile(title: Text('播放倍速')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final value in playbackSpeeds)
                          ChoiceChip(
                            label: Text('${speedLabel(value)}x'),
                            selected: prefs.speed == value,
                            onSelected: (selected) {
                              if (selected) {
                                unawaited(save(prefs.copyWith(speed: value)));
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('显示弹幕'),
                    value: prefs.danmaku,
                    onChanged: (value) =>
                        unawaited(save(prefs.copyWith(danmaku: value))),
                  ),
                  SwitchListTile(
                    title: const Text('自动连播'),
                    value: prefs.autoAdvance,
                    onChanged: (value) =>
                        unawaited(save(prefs.copyWith(autoAdvance: value))),
                  ),
                  const ListTile(title: Text('画质增强')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final mode in VideoEnhancementMode.values)
                          ChoiceChip(
                            label: Text(mode.label),
                            selected: prefs.enhancement.mode == mode,
                            onSelected: (selected) {
                              if (selected) {
                                unawaited(
                                  save(
                                    prefs.copyWith(
                                      enhancement: prefs.enhancement.copyWith(
                                        mode: mode,
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text('倍速与弹幕偏好保存后供播放器使用，当前流内播放暂不实时切换。'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _keyFor(Drama drama) => feedResumeKey(drama);

  String _resumeKeyFor(Drama drama, int episode) =>
      '${_keyFor(drama)}|$episode';

  void _savePosition() {
    if (_items.isEmpty || !_player.hasVideo) return;
    final drama = _items[_index];
    _episodeByKey[_keyFor(drama)] = _episode;
    _positionByKey[_resumeKeyFor(drama, _episode)] = _player.position;
  }

  Future<void> _prefetch(int index) async {
    if (index < 0 || index >= _items.length) return;
    final drama = _items[index];
    if (_details.containsKey(_keyFor(drama))) return;
    try {
      final detail = await widget.repository.detail(drama);
      if (!mounted) return;
      _details[_keyFor(drama)] = detail;
    } catch (_) {}
  }

  Future<void> _playCurrent() async {
    if (_items.isEmpty || !mounted) return;
    if (_opening) {
      _pendingPlay = true;
      return;
    }
    final token = ++_playToken;
    _opening = true;
    try {
      final drama = _items[_index];
      var detail = _details[_keyFor(drama)];
      if (detail == null) {
        setState(() {
          _detailLoading = true;
          _detailError = null;
        });
        try {
          detail = await widget.repository.detail(drama);
        } catch (error) {
          if (!mounted || token != _playToken) return;
          setState(() {
            _detailLoading = false;
            _detailError = error.toString();
          });
          return;
        }
        if (!mounted || token != _playToken) return;
        _details[_keyFor(drama)] = detail;
        setState(() => _detailLoading = false);
      }
      if (detail.episodes.isEmpty) {
        if (!mounted || token != _playToken) return;
        setState(() => _detailError = '暂无可播剧集');
        return;
      }
      final episode = clampFeedEpisodeIndex(
        _episodeByKey[_keyFor(drama)] ?? _episode,
        detail.episodes.length,
      );
      final start = _positionByKey[_resumeKeyFor(drama, episode)] ?? 0;
      if (!mounted || token != _playToken) return;
      setState(() => _episode = episode);
      await _player.open(
        detail: detail,
        episodeIndex: episode,
        startPosition: start,
        repository: widget.repository,
        store: widget.store,
      );
      if (mounted) setState(() {});
    } finally {
      _opening = false;
      if (_pendingPlay) {
        _pendingPlay = false;
        if (mounted) unawaited(_playCurrent());
      }
    }
  }

  void _onPageChanged(int index) {
    _savePosition();
    setState(() {
      _index = index;
      _episode = _episodeByKey[_keyFor(_items[index])] ?? 0;
      _detailError = null;
    });
    unawaited(_playCurrent());
    _prefetch(index + 1);
  }

  void _switchEpisode(int delta) {
    if (_items.isEmpty) return;
    final detail = _details[_keyFor(_items[_index])];
    if (detail == null || detail.episodes.isEmpty) return;
    final next = clampFeedEpisodeIndex(
      _episode + delta,
      detail.episodes.length,
    );
    if (next == _episode) return;
    _savePosition();
    setState(() => _episode = next);
    unawaited(_playCurrent());
  }

  Future<void> _togglePlay() async {
    if (!_player.hasVideo) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    if (mounted) setState(() {});
  }

  void _onCompleted() {
    if (_items.isEmpty) return;
    final detail = _details[_keyFor(_items[_index])];
    if (detail != null && _episode < detail.episodes.length - 1) {
      _switchEpisode(1);
      return;
    }
    if (_index < _items.length - 1) {
      unawaited(
        _pages.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  String _formatTime(double seconds) {
    final total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
    final minutes = total ~/ 60;
    final secs = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _coverPlaceholder(Drama drama) {
    if (drama.cover.isEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              drama.title,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Image.network(
      drama.cover,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              drama.title,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    final drama = _items[index];
    final isCurrent = index == _index;
    final detail = _details[_keyFor(drama)];
    final episodeCount = detail?.episodes.length ?? drama.episodes;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: isCurrent ? _togglePlay : null,
          child: isCurrent
              ? RoomPlayerView(
                  handle: _player,
                  viewType: widget.store.player == 'fongmi'
                      ? TvboxPlayerController.fongmiViewType
                      : TvboxPlayerController.viewType,
                  onCompleted: _onCompleted,
                  onError: (_) {},
                  onRetry: () => unawaited(_playCurrent()),
                )
              : _coverPlaceholder(drama),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  tooltip: widget.onMenuPressed == null ? '返回列表' : '导航',
                  onPressed:
                      widget.onMenuPressed ?? () => Navigator.of(context).pop(),
                  icon: Icon(
                    widget.onMenuPressed == null
                        ? Icons.arrow_back_rounded
                        : Icons.menu_rounded,
                    color: Colors.white,
                  ),
                ),
                Expanded(
                  child: Text(
                    drama.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.categories.isNotEmpty &&
                    widget.onCategorySelected != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: InkWell(
                      onTap: _pickCategory,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white54),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.categories
                                      .where(
                                        (category) =>
                                            category.id ==
                                            widget.selectedCategory,
                                      )
                                      .firstOrNull
                                      ?.name ??
                                  '全部',
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (drama.description.isNotEmpty)
                    Text(
                      drama.description,
                      style: const TextStyle(color: Colors.white70),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        episodeCount > 0
                            ? '第${_episode + 1}集 / 共$episodeCount集'
                            : '第${_episode + 1}集',
                        style: const TextStyle(color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '上一集',
                        onPressed: isCurrent && _episode > 0
                            ? () => _switchEpisode(-1)
                            : null,
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: Colors.white,
                        ),
                      ),
                      ListenableBuilder(
                        listenable: _player,
                        builder: (context, _) => IconButton(
                          tooltip: _player.playing ? '暂停' : '播放',
                          onPressed: isCurrent && _player.hasVideo
                              ? _togglePlay
                              : null,
                          icon: Icon(
                            _player.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '下一集',
                        onPressed:
                            isCurrent &&
                                episodeCount > 0 &&
                                _episode < episodeCount - 1
                            ? () => _switchEpisode(1)
                            : null,
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        tooltip: '流内设置',
                        onPressed: _openFeedSettings,
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  ListenableBuilder(
                    listenable: _player,
                    builder: (context, _) => StreamBuilder<double>(
                      stream: _player.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? _player.position;
                        final duration = _player.duration;
                        final max = duration > 0 ? duration : 1.0;
                        return Row(
                          children: [
                            Text(
                              _formatTime(position),
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Expanded(
                              child: Slider(
                                value: position.clamp(0.0, max),
                                max: max,
                                onChanged: isCurrent && _player.hasVideo
                                    ? (value) => unawaited(_player.seek(value))
                                    : null,
                              ),
                            ),
                            Text(
                              _formatTime(duration),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (isCurrent && _detailLoading)
                    const LinearProgressIndicator(),
                  if (isCurrent && _detailError != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _detailError!,
                            style: const TextStyle(color: Colors.white70),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () => unawaited(_playCurrent()),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('全屏流'),
        ),
        body: const Center(
          child: Text('暂无可播短剧', style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        controller: _pages,
        onPageChanged: _onPageChanged,
        itemCount: _items.length,
        itemBuilder: _buildPage,
      ),
    );
  }
}
