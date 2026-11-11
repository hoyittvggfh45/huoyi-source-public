import 'dart:async';

import 'package:flutter/material.dart';

import 'app_page_route.dart';
import 'core_bridge.dart';
import 'hongguo_account.dart' as hg_account;
import 'hongguo_codec.dart';
import 'hongguo_comment.dart';
import 'hongguo_danmaku.dart';
import 'hongguo_playback_settings.dart';
import 'hongguo_preload.dart';
import 'hongguo_related.dart';
import 'hongguo_resume.dart';
import 'hongguo_sleep_timer.dart';
import 'local_store.dart';
import 'models.dart';
import 'playback_foreground.dart';
import 'playback_preferences.dart';
import 'tvbox_player_bridge.dart';
import 'watchroom/player.dart';
import 'widgets.dart';
import 'moyi_theme.dart';

class HongguoPlaybackPage extends StatefulWidget {
  const HongguoPlaybackPage({
    super.key,
    required this.drama,
    required this.repository,
    required this.store,
    this.detail,
    this.initialEpisode = 0,
    this.startPosition = 0,
    this.accountController,
    this.preferCloud = false,
  });

  final Drama drama;
  final AppRepository repository;
  final LocalStore store;
  final DramaDetail? detail;
  final int initialEpisode;
  final double startPosition;
  final hg_account.HongguoAccountController? accountController;
  final bool preferCloud;

  @override
  State<HongguoPlaybackPage> createState() => _HongguoPlaybackPageState();
}

String _formatSpeed(double value) =>
    value == value.roundToDouble() ? '${value.toInt()}.0' : '$value';

String _formatClock(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '00:00';
  final total = seconds.round();
  final minutes = total ~/ 60;
  final rest = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (minutes >= 60) return '${two(minutes ~/ 60)}:${two(minutes % 60)}:${two(rest)}';
  return '${two(minutes)}:${two(rest)}';
}

class _HongguoPlaybackPageState extends State<HongguoPlaybackPage> {
  final RoomPlayerHandle _player = RoomPlayerHandle();
  late final HongguoPreloadWindow _preloadWindow = HongguoPreloadWindow(
    widget.repository,
    detailOf: (drama) async {
      if (drama.id == widget.drama.id) return _detail;
      try {
        return await widget.repository.detail(drama);
      } catch (_) {
        return null;
      }
    },
  );
  DramaDetail? _detail;
  late int _episode;
  bool _detailLoading = false;
  String? _detailError;
  int _playToken = 0;
  bool _opening = false;
  bool _pendingPlay = false;
  bool _usedStartPosition = false;
  bool _synopsisExpanded = false;
  bool _fullscreen = false;
  bool _playbackServiceHeld = false;
  String? _commentDramaId;
  HongguoCommentPage? _commentPage;
  late HongguoPlaybackSettings _settings;
  late HongguoDecoderLessons _lessons;
  final HongguoSleepTimer _sleepTimer = HongguoSleepTimer();
  Timer? _sleepPoll;
  HongguoCloudProgress? _cloudProgress;
  List<int> _knownQualities = const [];
  String _qualityNoticeFor = '';
  double? _replayStart;
  String _decodeRetriedFor = '';
  Timer? _crossSeasonTimer;
  bool _crossSeasonPending = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.detail;
    _episode = widget.initialEpisode;
    _settings = HongguoPlaybackSettings.load(widget.store.preferences);
    _lessons = HongguoCodecCapabilities.loadLessons(widget.store.preferences);
    _cloudProgress = _resumeProgressOf(
      widget.accountController?.cloudProgress(widget.drama.id),
    );
    _sleepPoll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_sleepTimer.poll()) {
        unawaited(_player.pause());
        _note('定时停止：已暂停播放');
        if (mounted) setState(() {});
      }
    });
    unawaited(_playCurrent());
  }

  HongguoCloudProgress? _resumeProgressOf(
    hg_account.HongguoCloudProgress? progress,
  ) {
    if (progress == null) return null;
    return HongguoCloudProgress(
      seriesId: progress.seriesId,
      episodeId: progress.episodeId,
      episodeIndex: progress.episodeIndex,
      position: progress.position.toDouble(),
      duration: progress.duration.toDouble(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(progress.updatedAt),
    );
  }

  @override
  void dispose() {
    _playToken++;
    _crossSeasonTimer?.cancel();
    _sleepPoll?.cancel();
    unawaited(_saveProgress());
    _player.dispose();
    _preloadWindow.dispose();
    if (_playbackServiceHeld) {
      _playbackServiceHeld = false;
      unawaited(PlaybackForeground.release());
    }
    super.dispose();
  }

  Future<void> _loadCommentCounts(PlaybackPlan plan) async {
    final seriesId = hongguoNumericId(widget.drama.id);
    if (plan.session.isEmpty && seriesId == null) return;
    try {
      final page = plan.session.isEmpty
          ? await widget.repository.commentsBySeries(seriesId!)
          : await widget.repository.comments(plan);
      if (!mounted || _commentDramaId != widget.drama.id) return;
      setState(() => _commentPage = page);
    } catch (_) {}
  }

  Future<void> _openComments() async {
    final plan = _player.plan;
    if (plan == null) {
      _note('本集暂不支持评论');
      return;
    }
    final seriesId = hongguoNumericId(widget.drama.id);
    if (plan.session.isEmpty && seriesId == null) {
      _note('本集暂不支持评论');
      return;
    }
    await showHongguoComments(
      context,
      plan,
      widget.repository,
      initialPage: _commentPage,
      seriesId: plan.session.isEmpty ? seriesId : null,
    );
  }

  Future<void> _playCurrent() async {
    if (!mounted) return;
    if (_opening) {
      _pendingPlay = true;
      return;
    }
    final token = ++_playToken;
    _opening = true;
    try {
      var detail = _detail;
      if (detail == null) {
        setState(() {
          _detailLoading = true;
          _detailError = null;
        });
        try {
          detail = await widget.repository.detail(widget.drama);
        } catch (error) {
          if (!mounted || token != _playToken) return;
          setState(() {
            _detailLoading = false;
            _detailError = error.toString();
          });
          return;
        }
        if (!mounted || token != _playToken) return;
        _detail = detail;
        setState(() => _detailLoading = false);
      }
      if (detail.episodes.isEmpty) {
        if (!mounted || token != _playToken) return;
        setState(() => _detailError = '暂无可播剧集');
        return;
      }
      var start = 0.0;
      if (!_usedStartPosition) {
        _usedStartPosition = true;
        if (widget.startPosition > 0) {
          start = widget.startPosition;
        } else {
          final resume = _localResumeTarget(detail);
          if (resume != null) {
            if (resume.index != _episode) {
              setState(() => _episode = resume.index);
            }
            start = resume.position;
          }
        }
      }
      final replayStart = _replayStart;
      _replayStart = null;
      if (replayStart != null) start = replayStart;
      final episodeIndex = _episode.clamp(0, detail.episodes.length - 1);
      if (episodeIndex != _episode) {
        setState(() => _episode = episodeIndex);
      }
      if (!mounted || token != _playToken) return;
      final preloaded = _preloadWindow.take(
        widget.drama,
        detail.episodes[episodeIndex],
      );
      await _player.open(
        detail: detail,
        episodeIndex: episodeIndex,
        startPosition: start,
        repository: widget.repository,
        store: widget.store,
        preloadedPlan: preloaded,
        quality: _effectiveQuality(),
      );
      if (!mounted || token != _playToken) return;
      final plan = _player.plan;
      if (plan != null) {
        if (plan.qualities.isNotEmpty) {
          _knownQualities = plan.qualities;
        }
        final wanted = widget.store.playbackPreferences.quality;
        final noticeKey = '${widget.drama.id}|$_episode|$wanted';
        if (wanted > 0 &&
            plan.qualities.isNotEmpty &&
            !plan.qualities.contains(wanted) &&
            _qualityNoticeFor != noticeKey) {
          _qualityNoticeFor = noticeKey;
          _note('本集暂无 ${wanted}P，已用最高画质播放');
        }
        if (!_playbackServiceHeld) {
          _playbackServiceHeld = true;
          unawaited(PlaybackForeground.acquire(widget.drama.title));
        }
        if (_commentDramaId != widget.drama.id) {
          _commentDramaId = widget.drama.id;
          unawaited(_loadCommentCounts(plan));
        }
      }
      _preloadWindow.recenter(
        drama: widget.drama,
        episodes: detail.episodes,
        episodeIndex: episodeIndex,
        upcoming: detail.related,
        quality: _effectiveQuality(),
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

  int _effectiveQuality() {
    final wanted = HongguoCodecCapabilities.normalizeQuality(
      widget.store.playbackPreferences.quality,
    );
    final available = _knownQualities.isNotEmpty
        ? _knownQualities
        : HongguoCodecCapabilities.qualityOptions;
    return HongguoCodecCapabilities.effectiveQuality(
      wanted,
      available,
      _lessons,
    );
  }

  HongguoResumeTarget? _localResumeTarget(DramaDetail detail) {
    final watched = widget.store.watched(widget.drama.id);
    if (watched == null) return null;
    final ids = [for (final episode in detail.episodes) episode.id];
    final localIndex = detail.episodes.indexWhere(
      (episode) => episode.number == watched.episode,
    );
    final progress = hongguoResumeProgress(
      episodeIds: ids,
      seriesId: widget.drama.id,
      localIndex: localIndex >= 0 ? localIndex : null,
      localPosition: watched.position,
      localUpdatedAt: watched.updatedAt,
      cloud: _cloudProgress,
      preferCloud: widget.preferCloud,
    );
    if (progress == null) return null;
    final completed = watched.finished && localIndex == progress.index;
    return hongguoResumeTarget(
      episodeIds: ids,
      episodeId: ids[progress.index],
      position: progress.position,
      completed: completed,
    );
  }

  Future<void> _saveProgress() async {
    final detail = _detail;
    if (detail == null || detail.episodes.isEmpty) return;
    if (_episode < 0 || _episode >= detail.episodes.length) return;
    final position = _player.position;
    final duration = _player.duration;
    if (duration <= 0 || position < 0) return;
    await widget.store.saveWatch(
      WatchEntry(
        drama: widget.drama,
        episode: detail.episodes[_episode].number,
        position: position,
        duration: duration,
        updatedAt: DateTime.now(),
      ),
    );
    final accountController = widget.accountController;
    if (accountController != null && accountController.loggedIn) {
      try {
        await accountController.recordPlayback(
          hg_account.HongguoCloudProgress(
            seriesId: widget.drama.id,
            seriesTitle: widget.drama.title,
            seriesCover: widget.drama.cover,
            episodeId: detail.episodes[_episode].id,
            episodeIndex: _episode,
            position: position.toInt(),
            duration: duration.toInt(),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            episodeCount: detail.episodes.length,
          ),
        );
      } catch (_) {}
    }
  }

  void _replayWithQuality() {
    _replayStart = _player.position;
    _preloadWindow.clear();
    unawaited(_playCurrent());
  }

  Future<void> _onPlayerError(String message) async {
    final plan = _player.plan;
    if (plan == null || plan.quality <= 0) return;
    if (!HongguoCodecCapabilities.looksLikeDecodeFailure(message)) return;
    final learned = _lessons.remember(
      HongguoCodecCapabilities.codec,
      plan.quality,
    );
    if (learned == null) return;
    await HongguoCodecCapabilities.saveLessons(
      widget.store.preferences,
      _lessons,
    );
    final retryKey = '${widget.drama.id}|$_episode|${plan.quality}';
    if (_decodeRetriedFor == retryKey) return;
    _decodeRetriedFor = retryKey;
    if (_effectiveQuality() < plan.quality) {
      _note('该画质本机解码失败，已自动降档重试');
      _replayWithQuality();
    }
  }

  void _playEpisode(int index) {
    unawaited(_saveProgress());
    _crossSeasonTimer?.cancel();
    _crossSeasonPending = false;
    _decodeRetriedFor = '';
    setState(() {
      _episode = index;
      _synopsisExpanded = false;
    });
    unawaited(_playCurrent());
  }

  void _onCompleted() {
    final detail = _detail;
    if (detail == null || detail.episodes.isEmpty) return;
    unawaited(_saveProgress());
    if (_sleepTimer.episodeEnded()) {
      unawaited(_player.pause());
      _note('定时停止：已播完设定集数');
      if (mounted) setState(() {});
      return;
    }
    if (_episode + 1 < detail.episodes.length) {
      _playEpisode(_episode + 1);
    } else {
      _maybeCrossSeason();
    }
  }

  void _maybeCrossSeason() {
    if (!_settings.seasonAutoplay) {
      _openEpisodeSheet(initialTab: 1);
      return;
    }
    _crossSeasonPending = true;
    if (mounted) setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('正在加载下一季…'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: '取消本次',
          onPressed: () {
            _crossSeasonTimer?.cancel();
            _crossSeasonPending = false;
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    _crossSeasonTimer?.cancel();
    _crossSeasonTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_crossSeasonPending) return;
      _crossSeasonPending = false;
      final next = _nextSeasonDrama();
      if (next == null) {
        _note('下一季暂时无法加载，请稍后手动选择');
        _openEpisodeSheet(initialTab: 1);
        return;
      }
      unawaited(
        Navigator.of(context).pushReplacement<void, void>(
          appPageRoute<void>(
            builder: (_) => HongguoPlaybackPage(
              drama: next,
              repository: widget.repository,
              store: widget.store,
              accountController: widget.accountController,
              preferCloud: widget.preferCloud,
            ),
          ),
        ),
      );
    });
  }

  Drama? _nextSeasonDrama() {
    final detail = _detail;
    if (detail == null) return null;
    final rows = HongguoRelated.fetchRelatedSeasons(
      current: widget.drama,
      candidates: detail.related,
    );
    return HongguoRelated.nextSeason(
      current: widget.drama,
      rows: rows,
    )?.drama;
  }

  Future<void> _saveSettings() =>
      _settings.save(widget.store.preferences);

  Future<void> _togglePlay() async {
    if (!_player.hasVideo) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _toggleFavorite() async {
    await widget.store.toggleFavorite(widget.drama);
    if (mounted) setState(() {});
  }

  Future<void> _toggleDanmaku() async {
    final prefs = widget.store.playbackPreferences;
    await widget.store.setPlaybackPreferences(
      prefs.copyWith(danmaku: !prefs.danmaku),
    );
    if (mounted) setState(() {});
  }

  void _note(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _releaseStatusLabel() {
    return switch (widget.drama.releaseStatus) {
      'finished' || 'completed' => '已完结',
      'ongoing' => '连载中',
      _ => '',
    };
  }

  Future<void> _openEpisodeSheet({required int initialTab}) async {
    final detail = _detail;
    if (detail == null) {
      if (!_detailLoading) unawaited(_playCurrent());
      return;
    }
    if (detail.episodes.isEmpty) {
      _note('暂无可播剧集');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: moyiSheetFill,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _EpisodeSheet(
        detail: detail,
        drama: widget.drama,
        repository: widget.repository,
        store: widget.store,
        currentEpisode: _episode,
        initialTab: initialTab,
        accountController: widget.accountController,
        onSelect: (index) {
          Navigator.of(context).pop();
          _playEpisode(index);
        },
        onToggleFavorite: () => unawaited(_toggleFavorite()),
        onOpenRelated: (drama) {
          Navigator.of(context).pop();
          unawaited(
            Navigator.of(this.context).push<void>(
              appPageRoute<void>(
                builder: (_) => HongguoPlaybackPage(
                  drama: drama,
                  repository: widget.repository,
                  store: widget.store,
                  accountController: widget.accountController,
                  preferCloud: widget.preferCloud,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openSpeedSheet() async {
    final prefs = widget.store.playbackPreferences;
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: moyiSheetFill,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '倍速',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                children: playbackSpeeds
                    .map(
                      (value) => ChoiceChip(
                        label: Text('${_formatSpeed(value)}x'),
                        selected: value == prefs.speed,
                        onSelected: (_) =>
                            Navigator.of(context).pop(value),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await widget.store.setPlaybackPreferences(
      prefs.copyWith(speed: selected),
    );
    try {
      await _player.videoController?.player.setRate(selected);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _openQualitySheet() async {
    final prefs = widget.store.playbackPreferences;
    final options = {
      0,
      ..._knownQualities.where((value) => value > 0),
      ...HongguoCodecCapabilities.qualityOptions,
    }.toList()..sort((a, b) => b.compareTo(a));
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: moyiSheetFill,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                _player.plan?.quality != null && _player.plan!.quality > 0
                    ? '清晰度 · 当前 ${_player.plan!.quality}P'
                    : '清晰度',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                children: options
                    .map(
                      (value) => ChoiceChip(
                        label: Text(
                          value == 0 ? '自动（优先高清）' : '$value P',
                        ),
                        selected: value == prefs.quality,
                        onSelected: (_) =>
                            Navigator.of(context).pop(value),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (_lessons.size > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextButton(
                  onPressed: () async {
                    _lessons.reset();
                    await HongguoCodecCapabilities.saveLessons(
                      widget.store.preferences,
                      _lessons,
                    );
                    if (context.mounted) Navigator.of(context).pop(-1);
                  },
                  child: const Text('清除解码学习记录'),
                ),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == -1) {
      if (mounted) setState(() {});
      return;
    }
    await widget.store.setPlaybackPreferences(
      prefs.copyWith(quality: selected),
    );
    if (!mounted) return;
    setState(() {});
    _replayWithQuality();
  }

  Future<void> _openFrameSheet() async {
    var frameMode = _settings.frameMode;
    var rotation = _settings.rotationQuarters;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: moyiSheetFill,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '画面模式',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  children: HongguoFrameMode.values
                      .map(
                        (mode) => ChoiceChip(
                          label: Text(mode.label),
                          selected: mode == frameMode,
                          onSelected: (_) =>
                              setSheetState(() => frameMode = mode),
                        ),
                      )
                      .toList(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  '画面旋转',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 8,
                  children: [0, 1, 2, 3]
                      .map(
                        (quarters) => ChoiceChip(
                          label: Text('${quarters * 90}°'),
                          selected: quarters == rotation,
                          onSelected: (_) =>
                              setSheetState(() => rotation = quarters),
                        ),
                      )
                      .toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('确定'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (changed != true || !mounted) return;
    _settings = _settings.copyWith(
      frameMode: frameMode,
      rotationQuarters: rotation,
    );
    await _saveSettings();
    if (mounted) setState(() {});
  }

  Future<void> _openSleepSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: moyiSheetFill,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                _sleepTimer.active
                    ? '定时停止 · ${_sleepTimer.label()}'
                    : '定时停止',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                children: [10, 15, 30, 60, 90, 120, 180]
                    .map(
                      (minutes) => ChoiceChip(
                        label: Text('$minutes 分钟'),
                        selected: false,
                        onSelected: (_) => Navigator.of(
                          context,
                        ).pop('m$minutes'),
                      ),
                    )
                    .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                children: [1, 2, 3, 5, 10]
                    .map(
                      (count) => ChoiceChip(
                        label: Text('再播 $count 集'),
                        selected: false,
                        onSelected: (_) =>
                            Navigator.of(context).pop('e$count'),
                      ),
                    )
                    .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop('off'),
                child: const Text('关闭定时'),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == 'off') {
      _sleepTimer.cancel();
    } else if (selected.startsWith('m')) {
      _sleepTimer.afterMinutes(int.parse(selected.substring(1)));
    } else if (selected.startsWith('e')) {
      _sleepTimer.afterEpisodes(int.parse(selected.substring(1)));
    }
    if (mounted) setState(() {});
  }

  Future<void> _openMoreSheet() async {
    final favorite = widget.store.isFavorite(widget.drama.id);
    final prefs = widget.store.playbackPreferences;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: moyiSheetFill,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                ),
                title: Text(favorite ? '取消收藏' : '收藏'),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_toggleFavorite());
                },
              ),
              ListTile(
                leading: const Icon(Icons.grid_view_rounded),
                title: const Text('选集'),
                onTap: () {
                  Navigator.of(context).pop();
                  Future.microtask(() {
                    if (mounted) _openEpisodeSheet(initialTab: 1);
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.high_quality_rounded),
                title: Text(
                  prefs.quality > 0 ? '清晰度 · ${prefs.quality}P' : '清晰度 · 自动',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Future.microtask(() {
                    if (mounted) unawaited(_openQualitySheet());
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.aspect_ratio_rounded),
                title: Text(
                  '画面模式 · ${_settings.frameMode.label}',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Future.microtask(() {
                    if (mounted) unawaited(_openFrameSheet());
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.bedtime_rounded),
                title: Text(
                  _sleepTimer.active
                      ? '定时停止 · ${_sleepTimer.label()}'
                      : '定时停止',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Future.microtask(() {
                    if (mounted) unawaited(_openSleepSheet());
                  });
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.access_time_rounded),
                title: const Text('常驻播放进度'),
                value: _settings.alwaysShowProgress,
                onChanged: (value) async {
                  _settings = _settings.copyWith(
                    alwaysShowProgress: value,
                  );
                  await _saveSettings();
                  setSheetState(() {});
                  if (mounted) setState(() {});
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.skip_next_rounded),
                title: const Text('跨季自动连播'),
                value: _settings.seasonAutoplay,
                onChanged: (value) async {
                  _settings = _settings.copyWith(seasonAutoplay: value);
                  await _saveSettings();
                  setSheetState(() {});
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.comment_rounded),
                title: Text(
                  widget.store.playbackPreferences.danmaku
                      ? '关闭弹幕'
                      : '开启弹幕',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_toggleDanmaku());
                },
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('关闭'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_fullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _videoArea(),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: _topBar(),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.42,
              child: _videoArea(),
            ),
            Expanded(child: _infoArea()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final prefs = widget.store.playbackPreferences;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: '返回',
          onPressed: () {
            if (_fullscreen) {
              setState(() => _fullscreen = false);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        Text(
          '第${_episode + 1}集',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _openSpeedSheet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_formatSpeed(prefs.speed)}x',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: _openQualitySheet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _player.plan?.quality != null && _player.plan!.quality > 0
                  ? '${_player.plan!.quality}P'
                  : prefs.quality > 0
                  ? '${prefs.quality}P'
                  : '自动',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          tooltip: '更多',
          onPressed: _openMoreSheet,
        ),
      ],
    );
  }

  Widget _videoArea() {
    return GestureDetector(
      onTap: _togglePlay,
      child: ListenableBuilder(
        listenable: _player,
        builder: (context, _) {
          final keyMatches =
              _player.videoKey == '${widget.drama.id}|$_episode';
          if (_player.loading ||
              _player.error != null ||
              (keyMatches && _player.hasVideo)) {
            return Stack(
              fit: StackFit.expand,
              children: [
                RoomPlayerView(
                  handle: _player,
                  viewType: TvboxPlayerController.viewType,
                  onCompleted: _onCompleted,
                  onError: (message) => unawaited(_onPlayerError(message)),
                  onRetry: () => unawaited(_playCurrent()),
                  onFullscreen: _fullscreen
                      ? () => setState(() => _fullscreen = false)
                      : null,
                  isFullscreen: _fullscreen,
                  fit: _settings.frameMode.boxFit,
                  quarterTurns: _settings.rotationQuarters,
                ),
                if (_settings.alwaysShowProgress && !_player.useTvbox)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _persistentProgress(),
                  ),
                HongguoDanmakuLayer(
                  handle: _player,
                  repository: widget.repository,
                  store: widget.store,
                  available: keyMatches && _player.hasVideo,
                  aspectRatio: hongguoVideoAspect(_player),
                  seriesId: hongguoNumericId(widget.drama.id),
                  videoId: _detail != null &&
                          _episode >= 0 &&
                          _episode < _detail!.episodes.length
                      ? hongguoNumericId(_detail!.episodes[_episode].id)
                      : null,
                ),
              ],
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              DramaCover(
                drama: widget.drama,
                repository: widget.repository,
              ),
              if (_detailLoading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (_detailError != null)
                Center(
                  child: StatusPanel(
                    title: '加载失败',
                    message: _detailError!,
                    onRetry: () => unawaited(_playCurrent()),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoArea() {
    final detail = _detail;
    final episodes = detail?.episodes ?? const <Episode>[];
    final episodeTitle =
        detail != null && _episode < episodes.length
            ? episodes[_episode].title
            : null;
    final episodeLine = episodeTitle == null
        ? '第${_episode + 1}集'
        : episodeTitle == '第${_episode + 1}集'
        ? episodeTitle
        : '第${_episode + 1}集 | $episodeTitle';
    final synopsis = detail?.drama.description ?? widget.drama.description;
    final status = _releaseStatusLabel();
    return Container(
      color: moyiSheetFill,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: GestureDetector(
                onTap: () => setState(() => _fullscreen = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '全屏观看',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_episode != 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onTap: () => _playEpisode(0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  Text(
                                    '从第1集开始看',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => _openEpisodeSheet(initialTab: 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.drama.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Text(
                              ' >',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        episodeLine,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (synopsis.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  synopsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                  maxLines: _synopsisExpanded ? null : 2,
                                  overflow: _synopsisExpanded
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                ),
                              ),
                              if (synopsis.length > 80)
                                GestureDetector(
                                  onTap: () => setState(
                                    () => _synopsisExpanded =
                                        !_synopsisExpanded,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      _synopsisExpanded ? '收起' : '展开',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      _progressBar(),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => _openEpisodeSheet(initialTab: 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Text(
                                status.isEmpty
                                    ? '选集 · 全${episodes.length}集'
                                    : '选集 · $status · 全${episodes.length}集',
                                style: const TextStyle(color: Colors.white),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.keyboard_arrow_up_rounded,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    _action(
                      icon: widget.store.isFavorite(widget.drama.id)
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      label: '收藏',
                      count: _commentPage != null &&
                              _commentPage!.collectorsCount > 0
                          ? '${_commentPage!.collectorsCount}'
                          : null,
                      onTap: () => unawaited(_toggleFavorite()),
                    ),
                    const SizedBox(height: 20),
                    _action(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '评论',
                      count: _commentPage != null && _commentPage!.total > 0
                          ? '${_commentPage!.total}'
                          : null,
                      onTap: () => unawaited(_openComments()),
                    ),
                    const SizedBox(height: 20),
                    _action(
                      icon: Icons.favorite_outline_rounded,
                      label: '点赞',
                      onTap: () => _note('该剧暂无点赞数据'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    String? count,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          if (count != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                count,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _persistentProgress() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
        ),
      ),
      child: ListenableBuilder(
        listenable: _player,
        builder: (context, _) {
          final duration = _player.duration;
          return StreamBuilder<double>(
            stream: _player.positionStream,
            initialData: _player.position,
            builder: (context, snapshot) {
              final position = snapshot.data ?? _player.position;
              final fraction = duration > 0
                  ? (position / duration).clamp(0.0, 1.0)
                  : 0.0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        _formatClock(position),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                      const Text(
                        ' / ',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        _formatClock(duration),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      if (_sleepTimer.active)
                        Text(
                          '定时 · ${_sleepTimer.label()}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 3,
                    child: Stack(
                      children: [
                        Container(color: Colors.white24),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: fraction,
                          child: Container(color: moyiPink),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _progressBar() {
    return ListenableBuilder(
      listenable: _player,
      builder: (context, _) {
        final duration = _player.duration;
        return StreamBuilder<double>(
          stream: _player.positionStream,
          initialData: _player.position,
          builder: (context, snapshot) {
            final position = snapshot.data ?? _player.position;
            final fraction = duration > 0
                ? (position / duration).clamp(0.0, 1.0)
                : 0.0;
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final fill = width * fraction;
                return SizedBox(
                  height: 12,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 3,
                          width: width,
                          color: Colors.white24,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 3,
                          width: fill,
                          color: moyiPink,
                        ),
                      ),
                      Positioned(
                        left: (fill - 5).clamp(0.0, width - 10),
                        top: 1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: moyiPink,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _EpisodeSheet extends StatefulWidget {
  const _EpisodeSheet({
    required this.detail,
    required this.drama,
    required this.repository,
    required this.store,
    required this.currentEpisode,
    required this.onSelect,
    required this.onToggleFavorite,
    required this.onOpenRelated,
    this.initialTab = 1,
    this.accountController,
  });

  final DramaDetail detail;
  final Drama drama;
  final AppRepository repository;
  final LocalStore store;
  final int currentEpisode;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggleFavorite;
  final ValueChanged<Drama> onOpenRelated;
  final int initialTab;
  final hg_account.HongguoAccountController? accountController;

  @override
  State<_EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<_EpisodeSheet> {
  late int _tab = widget.initialTab;
  late int _range = widget.currentEpisode ~/ 30;
  late bool _favorite = widget.store.isFavorite(widget.drama.id);

  List<String> get _ranges {
    final count = widget.detail.episodes.length;
    final ranges = <String>[];
    for (var start = 0; start < count; start += 30) {
      final end = (start + 30).clamp(0, count);
      ranges.add('${start + 1}-$end');
    }
    return ranges;
  }

  String get _seasonLine {
    final season = widget.drama.tags.firstWhere(
      (tag) => RegExp(r'第\d+季').hasMatch(tag),
      orElse: () => '',
    );
    final parts = [
      if (season.isNotEmpty) season,
      '全${widget.detail.episodes.length}集',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 64,
                    height: 88,
                    child: DramaCover(
                      drama: widget.drama,
                      repository: widget.repository,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _tab = 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.drama.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Text(
                              ' >',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _seasonLine,
                        style: const TextStyle(color: moyiMutedOnDark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 16),
              _sheetTab(0, '简介'),
              const SizedBox(width: 24),
              _sheetTab(1, '选集'),
              const SizedBox(width: 24),
              _sheetTab(2, '系列剧'),
            ],
          ),
          Container(height: 1, color: Colors.white12),
          Expanded(child: _tabBody()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: MoyiGradientButton(
                label: _favorite ? '已收藏' : '收藏',
                icon: _favorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                onPressed: () {
                  widget.onToggleFavorite();
                  setState(() => _favorite = !_favorite);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetTab(int index, String label) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Colors.white : moyiMutedOnDark,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 20,
            height: 3,
            decoration: BoxDecoration(
              color: selected ? moyiPink : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reserveSeason(HongguoRelatedSeason season) async {
    final controller = widget.accountController;
    if (controller == null) return;
    try {
      await controller.reserveSeries(season.drama.id);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已预约，上线后可在红果账号里查看')),
      );
    } on hg_account.HongguoLoginFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('预约失败，请稍后重试')));
    }
  }

  Widget _tabBody() {
    if (_tab == 0) {
      final description = widget.detail.drama.description;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          description.isEmpty ? '暂无简介' : description,
          style: const TextStyle(height: 1.6, color: moyiBodyOnDark),
        ),
      );
    }
    if (_tab == 2) {
      final related = widget.detail.related;
      if (related.isEmpty) {
        return const Center(
          child: Text(
            '暂无系列剧数据',
            style: TextStyle(color: Colors.white),
          ),
        );
      }
      final seasons = HongguoRelated.fetchRelatedSeasons(
        current: widget.drama,
        candidates: related,
      );
      final byId = <String, HongguoRelatedSeason>{
        for (final season in seasons) season.drama.id: season,
      };
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: related.length,
        itemBuilder: (context, index) {
          final drama = related[index];
          final season = byId[drama.id];
          final upcoming = season?.upcoming ?? false;
          final controller = widget.accountController;
          final reserved =
              controller?.isReserved(drama.id) ?? false;
          return GestureDetector(
            onTap:
                upcoming
                    ? null
                    : () {
                      Navigator.of(context).pop();
                      widget.onOpenRelated(drama);
                    },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 48,
                      height: 64,
                      child: DramaCover(
                        drama: drama,
                        repository: widget.repository,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          drama.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                        if (season != null)
                          Text(
                            season.label,
                            style: const TextStyle(
                              color: moyiMutedOnDark,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (upcoming && controller != null)
                    reserved
                        ? const Text(
                          '已预约',
                          style: TextStyle(color: moyiMutedOnDark),
                        )
                        : FilledButton(
                          onPressed: () => _reserveSeason(season!),
                          child: const Text('预约'),
                        )
                  else
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: moyiMutedOnDark,
                    ),
                ],
              ),
            ),
          );
        },
      );
    }
    final ranges = _ranges;
    final range = _range.clamp(0, ranges.length - 1);
    final start = range * 30;
    final end = (start + 30).clamp(0, widget.detail.episodes.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (var i = 0; i < ranges.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _range = i),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24, top: 12),
                    child: Text(
                      ranges[i],
                      style: TextStyle(
                        fontWeight:
                            i == range ? FontWeight.bold : FontWeight.normal,
                        color: i == range ? Colors.white : moyiMutedOnDark,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.1,
            ),
            itemCount: end - start,
            itemBuilder: (context, offset) {
              final index = start + offset;
              final selected = index == widget.currentEpisode;
              return GestureDetector(
                onTap: () => widget.onSelect(index),
                child: Stack(
                  children: [
                    Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: selected ? moyiSelectedGradient : null,
                        color: selected ? null : moyiDarkCardFill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (selected)
                      const Positioned(
                        top: 4,
                        right: 6,
                        child: Icon(
                          Icons.bar_chart_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
