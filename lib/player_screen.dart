import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'app_layout.dart';
import 'app_orientation.dart';
import 'app_theme.dart';
import 'home_screen.dart';
import 'player_back.dart';
import 'atmosphere_background.dart';
import 'tv_theme.dart';
import 'core_bridge.dart';
import 'jar_bridge.dart';
import 'danmaku_controller.dart';
import 'danmaku_overlay.dart';
import 'download_picker.dart';
import 'downloads_screen.dart';
import 'follow_state.dart';
import 'local_store.dart';
import 'models.dart';
import 'playback_loader.dart';
import 'playback_parse.dart';
import 'playback_preloader.dart';
import 'playback_queue.dart';
import 'playback_sniffer.dart';
import 'playback_recovery.dart';
import 'playback_error.dart';
import 'player_backend.dart';
import 'playback_preferences.dart';
import 'player_controls.dart';
import 'player_route.dart';
import 'tvbox_video_pane.dart';
import 'tvbox_player_bridge.dart';
import 'player_interactions.dart';
import 'player_menu.dart';
import 'television_controls.dart';
import 'widgets.dart';
import 'sources_screen.dart';
import 'lan_controller.dart';
import 'lan_screen.dart';
import 'video_enhancement.dart';
import 'picture_quality_applier.dart';
import 'video_output_size.dart';
import 'windows_playback_tuning.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.detail,
    required this.initialIndex,
    required this.repository,
    required this.store,
    this.initialPosition = 0,
    this.localOnly = false,
    this.allowOnlineFallback = true,
    this.mediaId,
    this.playerFactory,
    this.videoBuilder,
    this.handoff,
    this.queue,
  });
  final DramaDetail detail;
  final int initialIndex;
  final double initialPosition;
  final bool localOnly;
  final bool allowOnlineFallback;
  final String? mediaId;
  final AppRepository repository;
  final LocalStore store;
  final LanIncomingPlayback? handoff;
  final PlaybackQueue? queue;
  @visibleForTesting
  final Player Function()? playerFactory;
  @visibleForTesting
  final Widget Function(Widget controls)? videoBuilder;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController? _video;
  late final VideoEnhancementController _enhancement;
  late final PictureQualityApplier _pictureQuality;
  late final PlaybackLoader _loader;
  late final PlaybackPreloader _preloader;
  bool _preloadEnabled = true;
  late final DanmakuController _danmaku;
  int _seekSequence = 0;
  bool _danmakuEnabled = true;
  late final PlayerInteractions _interactions;
  final _playerFocus = FocusNode(debugLabel: 'player-surface');
  final _videoPaneKey = GlobalKey();
  final _tvboxPaneKey = GlobalKey();
  final _tvboxHandle = TvboxPlaybackHandle();
  PlaybackBackendManager? _backendManager;
  PlaybackPlan? _tvboxPlan;
  double _tvboxStartPosition = 0;
  bool _tvboxAutoplay = true;
  final _menuRevision = ValueNotifier<int>(0);
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _recovery = PlaybackRecovery();
  Object _lanIdentity = Object();
  bool _handoffOwned = true;
  double? _lanFirstPosition;
  String? _savedProgressKey;
  final _health = PlaybackHealth();
  Timer? _saveTimer;
  Timer? _healthTimer;
  Timer? _errorTimer;
  Timer? _pictureInPictureExitTimer;
  Future<void> _operations = Future<void>.value();
  late int _index;
  late final int _profileEpoch;
  int _openedIndex = -1;
  int _generation = 0;
  int _requestedQuality = 0;
  int _routeIndex = 0;
  bool _loading = true;
  bool _forceOnline = false;
  bool _localFailure = false;
  bool _fullscreen = false;
  bool _pageFullscreen = false;
  bool _windowFullscreen = false;
  bool _automaticFullscreenSuppressed = true;
  bool _panelOpen = false;
  bool _episodePanelVisible = true;
  bool _episodesReversed = false;
  bool _synopsisExpanded = false;
  final ScrollController _episodeStripController = ScrollController();
  bool _autoAdvance = true;
  bool _adBlock = true;
  bool? _systemFullscreen;
  Orientation? _lastOrientation;
  bool _closed = false;
  bool _acceptErrors = false;
  bool _foreground = true;
  bool _playIntent = true;
  bool _showControlsOnPlaybackReady = true;
  bool _pendingError = false;
  bool _pictureInPictureSupported = false;
  bool _pictureInPictureActive = false;
  bool _pictureInPictureRequested = false;
  bool _pictureInPictureHandlerInstalled = false;
  bool _brightnessAdjusted = false;
  double? _cachedBrightness;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  String _loadingMessage = '正在准备播放';
  String? _error;
  String? _saveWarning;
  PlaybackPlan? _plan;
  double _speed = 1;
  double _aspectRatio = 9 / 16;
  double _resumePosition = 0;
  bool _rotating = false;
  bool _backPending = false;
  bool _television = false;
  TelevisionDecoder _televisionDecoder = TelevisionDecoder.optimized;
  PlaybackOrientationMode _orientationMode = PlaybackOrientationMode.auto;
  ParseInterface? _selectedParse;
  String _lastPageUrl = '';
  bool get _televisionDecoderApplies => _television && Platform.isAndroid;
  AppOrientationController? _orientationController;
  bool get _pictureInPictureVisible =>
      _pictureInPictureActive || _pictureInPictureRequested;
  bool get _canUsePictureInPicture =>
      !_television &&
      defaultTargetPlatform == TargetPlatform.android &&
      _pictureInPictureSupported;
  bool get _mobile =>
      !_television &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _useTvbox =>
      !_television &&
      Platform.isAndroid &&
      (widget.store.player == 'tvbox' || widget.store.player == 'fongmi') &&
      (_plan?.decryptionKey.isEmpty ?? true) &&
      _backendManager?.current != PlaybackBackend.main;
  VideoEnhancementController? get _enhancementForUi =>
      _enhancement.supported ? _enhancement : null;
  PlaybackPreferences get _preferences => PlaybackPreferences(
    speed: _useTvbox ? _tvboxHandle.speed : _speed,
    quality: _requestedQuality,
    autoAdvance: _autoAdvance,
    danmaku: _danmakuEnabled,
    preload: _preloadEnabled,
    adBlock: _adBlock,
    enhancement: _enhancement.preferences,
    televisionDecoder: _televisionDecoder,
    orientationMode: _orientationMode,
  );
  String get _qualityLabel => _plan?.local == true
      ? '本地原画'
      : _requestedQuality == 0
      ? '自动'
      : '${_requestedQuality}P';
  int get _routeCount => _plan?.local == true ? 1 : (_plan?.routeCount ?? 1);
  int get _currentRoute =>
      (_plan?.routeIndex ?? 0).clamp(0, _routeCount > 0 ? _routeCount - 1 : 0);
  String get _routeLabel => '线路 ${_currentRoute + 1}';
  String get _session => _plan?.session ?? '';
  double get _currentPosition =>
      _useTvbox &&
          _openedIndex == _index &&
          _tvboxHandle.position > Duration.zero
      ? _tvboxHandle.positionSeconds
      : _openedIndex == _index && _player.state.position.inMilliseconds > 0
      ? _player.state.position.inMilliseconds / 1000
      : _resumePosition;
  Duration get _seekFallbackPosition =>
      _useTvbox ? _tvboxHandle.position : _player.state.position;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialIndex;
    _profileEpoch = widget.handoff?.profileEpoch ?? widget.store.profileEpoch;
    final preferences = widget.store.playbackPreferences;
    _speed = preferences.speed;
    _tvboxHandle.speed = preferences.speed;
    _requestedQuality = preferences.quality;
    _autoAdvance = true;
    _danmakuEnabled = preferences.danmaku;
    _adBlock = preferences.adBlock;
    _preloadEnabled = true;
    _televisionDecoder = preferences.televisionDecoder;
    _orientationMode = preferences.orientationMode;
    _loader = PlaybackLoader(widget.repository);
    _preloader = PlaybackPreloader(widget.repository);
    unawaited(_loadParseSelection());
    _danmaku = DanmakuController(widget.repository)
      ..setEnabled(_danmakuEnabled);
    widget.store.addListener(_accessChanged);
    _player =
        widget.playerFactory?.call() ??
        Player(
          // Windows 曾经开 verbose 日志（为了从日志里嗅探 GL 渲染器名），
          // 但 mpv 每行日志都要跨 FFI 生成一个 PlayerLog 事件回到 Dart，
          // 播放时每秒上千行，本身就是抖动的来源。渲染环境改由
          // VideoEnhancementController 按 vo/vo-passes 判定后，这里只留 error。
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
    _enhancement = VideoEnhancementController(
      player: _player,
      video: _video,
      preferences: preferences.enhancement,
      category: widget.detail.drama.category,
      tags: widget.detail.drama.tags,
    );
    _pictureQuality = PictureQualityApplier(_player)
      ..apply(preferences.pictureQuality);
    _interactions = PlayerInteractions(
      player: _player,
      available: () =>
          !_closed &&
          widget.store.profileEpoch == _profileEpoch &&
          !_loading &&
          _error == null &&
          _foreground &&
          !_panelOpen,
      baseSpeed: () => _speed,
      onTogglePlayback: _togglePlayback,
      onSeek: _seekTo,
      onFullscreen: _rotate,
      onEpisode: (direction) {
        if (widget.detail.episodes.length > 1) {
          final next = _index + direction;
          if (next < 0) return '已经是第一集';
          if (next >= widget.detail.episodes.length) return '已经是最后一集';
          unawaited(_play(next, showControlsOnReady: false));
          return '第 ${widget.detail.episodes[next].number} 集';
        }
        return _queueSwipe(direction);
      },
      onBrightness: _androidBrightness ? _setScreenBrightness : null,
      currentBrightness: _androidBrightness ? _currentBrightness : null,
    );
    _playerFocus.addListener(() {
      if (!_playerFocus.hasPrimaryFocus && !_closed) _interactions.cancel();
    });
    _configurePictureInPicture();
    unawaited(_readSystemBrightness());
    _subscriptions.add(
      _player.stream.error.listen((error) {
        if (_enhancement.handlePlaybackError(error)) return;
        if (!_closed && _acceptErrors && mounted && error.trim().isNotEmpty) {
          _queueRecovery();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (completed &&
            !_loading &&
            !_closed &&
            _acceptErrors &&
            _error == null) {
          final duration = _player.state.duration;
          if (duration <= Duration.zero ||
              _player.state.position < duration - const Duration(seconds: 2)) {
            _queueRecovery();
          } else if (_autoAdvance &&
              _foreground &&
              !_panelOpen &&
              _index + 1 < widget.detail.episodes.length) {
            _play(_index + 1, showControlsOnReady: false);
          } else {
            _playIntent = false;
            _interactions.cancel();
            unawaited(_player.pause());
            unawaited(_saveProgress(flush: true));
          }
        }
      }),
    );
    _subscriptions.add(
      _player.stream.position.listen((position) {
        if (!_closed && _openedIndex == _index && position > Duration.zero) {
          _resumePosition = position.inMilliseconds / 1000;
        }
        _syncDanmaku();
        _syncPreload();
        _acknowledgeHandoff();
      }),
    );
    for (final stream in [
      _player.stream.duration,
      _player.stream.buffer,
      _player.stream.playing,
      _player.stream.buffering,
      _player.stream.rate,
      _player.stream.completed,
    ]) {
      _subscriptions.add(
        stream.listen((_) {
          _syncDanmaku();
          _syncPreload();
          _acknowledgeHandoff();
        }),
      );
    }
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        final plan = _plan;
        if (!playing || plan == null || plan.routeIndex == _routeIndex) {
          return;
        }
        if (mounted && !_closed) {
          setState(() => _routeIndex = plan.routeIndex);
        }
      }),
    );
    _subscriptions.add(
      _player.stream.videoParams.listen((parameters) {
        final size = videoDisplaySize(parameters);
        if (size != null && mounted && !_closed) {
          final previousRatio = _aspectRatio;
          setState(() {
            _aspectRatio = size.width / size.height;
          });
          _scheduleSystemUi();
          if ((previousRatio >= 1) != (_aspectRatio >= 1)) {
            unawaited(_applyOrientation());
          }
        }
      }),
    );
    _saveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveProgress(),
    );
    _healthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_closed &&
          _acceptErrors &&
          !_loading &&
          _error == null &&
          _health.stalled(
            position: _useTvbox
                ? _tvboxHandle.position
                : _player.state.position,
            playing:
                (_useTvbox ? _tvboxHandle.playing : _player.state.playing) &&
                _playIntent,
            foreground: _foreground,
            now: DateTime.now(),
          )) {
        unawaited(_recover());
      }
    });
    final handoff = widget.handoff;
    if (handoff != null) {
      handoff.consumed = true;
      handoff.stop = () async {
        if (_handoffOwned && !_closed) await _stopForLan();
      };
    }
    if (_profileEpoch != widget.store.profileEpoch ||
        handoff?.cancelled == true) {
      handoff?.fail('接收用户已变更，推送已取消');
      if (handoff != null)
        unawaited(widget.repository.release(handoff.plan.session));
      _loading = false;
      _error = '播放接收已取消';
    } else {
      _play(
        _index,
        position: widget.initialPosition,
        handoffPlan: handoff?.plan,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closed) {
        widget.repository.catalogUpdates.publish(
          widget.repository.catalogUpdates.current(widget.detail.drama),
          retryCover: true,
        );
        unawaited(_applyOrientation());
      }
    });
  }

  void _accessChanged() {
    if (!_closed &&
        (widget.store.profileEpoch != _profileEpoch || widget.store.locked)) {
      _preloader.clear();
      _enhancement.suspend();
      _handoffOwned = false;
      _playIntent = false;
      widget.handoff?.fail('接收端用户已变更');
      unawaited(_player.pause());
    }
    if (!_closed &&
        (widget.store.profileEpoch != _profileEpoch ||
            widget.store.locked ||
            !widget.store.allowsSource('hongguo'))) {
      _danmaku.setPlan(null);
    }
  }

  void _configurePictureInPicture() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _pictureInPictureHandlerInstalled = true;
    AppDevice.channel.setMethodCallHandler((call) async {
      if (call.method == 'pictureInPictureChanged') {
        final arguments = call.arguments;
        final active = arguments is Map && arguments['active'] == true;
        _setPictureInPictureStatus(active: active, delayHiddenPause: !active);
      }
    });
    unawaited(_refreshPictureInPictureStatus());
  }

  Future<void> _refreshPictureInPictureStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'pictureInPictureStatus',
      );
      if (!mounted || _closed) return;
      _setPictureInPictureStatus(
        supported: status?['supported'] == true,
        active: status?['active'] == true,
      );
    } on PlatformException {
      if (mounted && !_closed) {
        _setPictureInPictureStatus(supported: false, active: false);
      }
    } on MissingPluginException {
      if (mounted && !_closed) {
        _setPictureInPictureStatus(supported: false, active: false);
      }
    }
  }

  void _setPictureInPictureStatus({
    bool? supported,
    bool? active,
    bool? requested,
    bool delayHiddenPause = false,
  }) {
    final nextSupported = supported ?? _pictureInPictureSupported;
    final nextActive = active ?? _pictureInPictureActive;
    final nextRequested =
        requested ?? (nextActive ? false : _pictureInPictureRequested);
    void assign() {
      _pictureInPictureSupported = nextSupported;
      _pictureInPictureActive = nextActive;
      _pictureInPictureRequested = nextRequested;
    }

    if (mounted && !_closed) {
      setState(assign);
    } else {
      assign();
    }
    if (_pictureInPictureVisible ||
        _lifecycleState == AppLifecycleState.resumed) {
      _pictureInPictureExitTimer?.cancel();
      _applyLifecycleVisibility(pauseWhenHidden: false);
      return;
    }
    _pictureInPictureExitTimer?.cancel();
    _applyLifecycleVisibility(pauseWhenHidden: !delayHiddenPause);
    if (delayHiddenPause) {
      _pictureInPictureExitTimer = Timer(const Duration(milliseconds: 700), () {
        if (!_closed &&
            !_pictureInPictureVisible &&
            _lifecycleState != AppLifecycleState.resumed) {
          _applyLifecycleVisibility();
        }
      });
    }
  }

  void _applyLifecycleVisibility({bool pauseWhenHidden = true}) {
    final windowsInactive =
        Platform.isWindows && _lifecycleState == AppLifecycleState.inactive;
    final visible =
        _lifecycleState == AppLifecycleState.resumed ||
        windowsInactive ||
        _pictureInPictureVisible;
    _foreground = visible;
    _enhancement.setForeground(_foreground);
    _syncDanmaku();
    _syncPreload();
    _health.reset();
    if (!visible) _interactions.cancel();
    if (pauseWhenHidden &&
        !visible &&
        (_lifecycleState == AppLifecycleState.paused ||
            _lifecycleState == AppLifecycleState.hidden)) {
      _playIntent = false;
      unawaited(_player.pause());
      unawaited(_saveProgress(flush: true));
    }
    if (visible && _pendingError) {
      _queueRecovery();
    }
  }

  Future<void> _enterPictureInPicture() async {
    if (!_canUsePictureInPicture ||
        _closed ||
        _loading ||
        _error != null ||
        _panelOpen) {
      return;
    }
    _interactions.cancel();
    final rawRatio = _aspectRatio.isFinite && _aspectRatio > 0
        ? _aspectRatio
        : 16 / 9;
    final ratio = rawRatio.clamp(1 / 2.39, 2.39).toDouble();
    final width = ratio >= 1 ? (1000 * ratio).round() : 1000;
    final height = ratio >= 1 ? 1000 : (1000 / ratio).round();
    _setPictureInPictureStatus(requested: true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _closed) return;
    final sourceRect = _pictureInPictureSourceRect();
    final arguments = <String, int>{'width': width, 'height': height};
    if (sourceRect != null) arguments.addAll(sourceRect);
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'enterPictureInPicture',
        arguments,
      );
      if (!mounted || _closed) return;
      final supported = status?['supported'] == true;
      final active = status?['active'] == true;
      final requested = status?['requested'] == true;
      _setPictureInPictureStatus(
        supported: supported,
        active: active,
        requested: requested && !active,
      );
      if (!supported || (!active && !requested)) {
        _notice('当前设备不支持画中画');
      } else if (requested && !active) {
        _pictureInPictureExitTimer?.cancel();
        _pictureInPictureExitTimer = Timer(const Duration(seconds: 2), () {
          if (!_closed &&
              _pictureInPictureRequested &&
              !_pictureInPictureActive) {
            _setPictureInPictureStatus(requested: false);
          }
        });
      }
    } on PlatformException {
      _setPictureInPictureStatus(requested: false);
      _notice('无法进入画中画，请检查系统权限');
    } on MissingPluginException {
      _setPictureInPictureStatus(supported: false, requested: false);
      _notice('当前平台不支持画中画');
    }
  }

  Map<String, int>? _pictureInPictureSourceRect() {
    final paneContext = _videoPaneKey.currentContext;
    final renderObject = paneContext?.findRenderObject();
    if (paneContext == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final ratio =
        MediaQuery.maybeOf(paneContext)?.devicePixelRatio ??
        View.of(paneContext).devicePixelRatio;
    final left = (topLeft.dx * ratio).round().clamp(0, 100000);
    final top = (topLeft.dy * ratio).round().clamp(0, 100000);
    final right = ((topLeft.dx + size.width) * ratio).round().clamp(0, 100000);
    final bottom = ((topLeft.dy + size.height) * ratio).round().clamp(
      0,
      100000,
    );
    if (right <= left || bottom <= top) return null;
    return {'left': left, 'top': top, 'right': right, 'bottom': bottom};
  }

  void _attachLanPlayback() {
    LanController.current?.attachPlayback(
      LanPlaybackHost(
        identity: _lanIdentity,
        title:
            widget.detail.drama.title +
            ' · 第 ' +
            widget.detail.episodes[_index].number.toString() +
            ' 集',
        stop: _stopForLan,
      ),
    );
  }

  void _acknowledgeHandoff() {
    final handoff = widget.handoff;
    if (!_handoffOwned ||
        handoff == null ||
        handoff.cancelled ||
        handoff.started.isCompleted ||
        _closed ||
        _loading ||
        _error != null ||
        _openedIndex != _index ||
        _index != widget.initialIndex ||
        widget.store.profileEpoch != _profileEpoch)
      return;
    final state = _player.state;
    final position = state.position.inMilliseconds / 1000;
    final duration = state.duration.inMilliseconds / 1000;
    if (duration > 0 && handoff.position > duration + 2) {
      handoff.fail('续播位置超过接收端分集时长');
      return;
    }
    if (!state.playing ||
        state.buffering ||
        (state.width ?? 0) <= 0 ||
        position < handoff.position - .5 ||
        position > handoff.position + 20)
      return;
    _lanFirstPosition ??= position;
    if (position >= _lanFirstPosition! + .15) handoff.acknowledge(position);
  }

  Future<void> _stopForLan() async {
    final generation = _generation;
    await _serialize(() async {
      if (_closed ||
          generation != _generation ||
          widget.store.profileEpoch != _profileEpoch)
        return;
      _playIntent = false;
      _interactions.cancel();
      _enhancement.suspend();
      _health.reset();
      await _player.pause();
      await _saveProgress(flush: true);
    });
  }

  Future<void> _pushToDevice() async {
    final link = LanController.current;
    if (link == null ||
        _panelOpen ||
        _closed ||
        _loading ||
        _error != null ||
        widget.mediaId != null)
      return;
    final generation = _generation;
    final index = _index;
    bool current() =>
        mounted &&
        !_closed &&
        generation == _generation &&
        index == _index &&
        widget.store.profileEpoch == _profileEpoch;
    _interactions.cancel();
    setState(() => _panelOpen = true);
    try {
      await showLanPush(
        context,
        link,
        snapshot: () => LanPlaybackIntent(
          drama: widget.detail.drama,
          episodeID: widget.detail.episodes[index].id,
          episode: widget.detail.episodes[index].number,
          position: _currentPosition,
        ),
        stillCurrent: current,
        onAccepted: () async {
          if (!current()) throw StateError('本机播放内容已变更');
          await _stopForLan();
          if (!current()) throw StateError('本机播放内容已变更');
        },
      );
    } catch (error) {
      if (mounted && !_closed) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted && !_closed) setState(() => _panelOpen = false);
    }
  }

  void _syncPreload() {
    if (_closed) return;
    if (!_preloadEnabled ||
        !_foreground ||
        widget.localOnly ||
        _plan?.local == true ||
        _loading ||
        _error != null ||
        _openedIndex != _index ||
        widget.store.profileEpoch != _profileEpoch ||
        widget.store.locked ||
        _index + 1 >= widget.detail.episodes.length) {
      _preloader.clear();
      return;
    }
    final state = _player.state;
    if (!state.playing || state.buffering || !_playIntent) {
      _preloader.pause();
      return;
    }
    final duration = state.duration.inMilliseconds;
    final position = state.position.inMilliseconds;
    if (duration <= 0 ||
        position < 2000 ||
        (position < duration ~/ 2 && duration - position > 45000) ||
        state.buffer.inMilliseconds - position < 5000) {
      return;
    }
    _preloader.prepare(
      widget.detail.drama,
      widget.detail.episodes[_index + 1],
      quality: _requestedQuality,
      route: _routeIndex,
      adBlock: _adBlock,
    );
  }

  void _syncDanmaku({bool discontinuity = false}) {
    if (_closed) return;
    final state = _player.state;
    _danmaku.update(
      position: state.position,
      duration: state.duration,
      speed: state.rate,
      playing: state.playing && _playIntent && !state.completed,
      buffering: state.buffering,
      foreground: _foreground,
      available:
          !_loading &&
          _error == null &&
          _openedIndex == _index &&
          widget.store.profileEpoch == _profileEpoch &&
          !widget.store.locked &&
          widget.store.allowsSource('hongguo'),
      discontinuity: discontinuity,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final television = AppLayout.isTelevision(context);
    if (_television != television) {
      _fullscreen = false;
      _automaticFullscreenSuppressed = false;
      _interactions.cancel();
    }
    _television = television;
    _orientationController = AppOrientationScope.maybeOf(context);
    final orientation = MediaQuery.orientationOf(context);
    if (_lastOrientation != null && _lastOrientation != orientation) {
      _automaticFullscreenSuppressed = false;
      _interactions.cancel();
      // 退出全屏回到竖屏合一页后，选集横排滚回当前集（FongMi 同款语义）
      if (!_showFullscreen) _scrollEpisodeStripToCurrent();
    }
    _lastOrientation = orientation;
    _scheduleSystemUi();
  }

  void _scheduleSystemUi() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed || (!_mobile && !_television)) return;
      final fullscreen = _showFullscreen;
      if (_systemFullscreen == fullscreen) return;
      _systemFullscreen = fullscreen;
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _applyLifecycleVisibility();
  }

  void _queueRecovery() {
    if (_closed || !_acceptErrors || _error != null) {
      return;
    }
    _pendingError = true;
    if (!_foreground || (_errorTimer?.isActive ?? false)) {
      return;
    }
    final ticket = _generation;
    final position = _player.state.position;
    _errorTimer = Timer(const Duration(milliseconds: 900), () {
      if (_closed || ticket != _generation || !_foreground || !_acceptErrors) {
        return;
      }
      _pendingError = false;
      final state = _player.state;
      if (state.playing &&
          !state.buffering &&
          (state.width ?? 0) > 0 &&
          state.position > position + const Duration(milliseconds: 300)) {
        // 已经自愈：撤销"原线路重试"的消耗。否则这条失败链会带着旧状态，
        // 之后偶发一次网络抖动就直接跳线，而不是先重试当前线路。
        _recovery.reset();
        return;
      }
      unawaited(_recover());
    });
  }

  Future<void> _recover() async {
    final current = _plan;
    if (_closed ||
        !_acceptErrors ||
        !_foreground ||
        current == null ||
        _error != null) {
      return;
    }
    _acceptErrors = false;
    _danmaku.setPlan(null);
    _errorTimer?.cancel();
    _pendingError = false;
    final position = _currentPosition;
    final action = current.local
        ? PlaybackRecoveryAction.stop
        : _recovery.next(current);
    if (action == PlaybackRecoveryAction.stop) {
      if (!current.local) {
        final next = _backendManager?.nextBackend();
        if (next != null) {
          _recovery.reset();
          await _play(_index, position: position, continueChain: true);
          return;
        }
      }
      _resumePosition = position;
      final ticket = _generation;
      try {
        await _serialize(() async {
          if (_closed || ticket != _generation) {
            return;
          }
          try {
            await _saveProgress();
            _openedIndex = -1;
            await _player.stop();
          } finally {
            await widget.repository.release(current.session);
          }
        });
      } catch (_) {}
      if (mounted && !_closed && ticket == _generation) {
        setState(() {
          _loading = false;
          _localFailure = current.local;
          _error = current.local
              ? widget.allowOnlineFallback
                    ? '本地视频读取失败，请重试或重新下载；也可以手动改为在线播放。'
                    : '本地成品读取失败，请重试或重新生成。'
              : '自动恢复未成功，请检查网络后重试，也可换一集或选择其他清晰度。';
        });
      }
      return;
    }
    await _play(
      _index,
      position: position,
      recoveryAction: action,
      continueChain: true,
    );
  }

  void _onTvboxCompleted() {
    if (_loading || _closed || !_acceptErrors || _error != null) return;
    final duration = _tvboxHandle.duration;
    if (duration <= Duration.zero ||
        _tvboxHandle.position < duration - const Duration(seconds: 2)) {
      _queueRecovery();
    } else if (_autoAdvance &&
        _foreground &&
        !_panelOpen &&
        _index + 1 < widget.detail.episodes.length) {
      unawaited(_play(_index + 1, showControlsOnReady: false));
    } else {
      _playIntent = false;
      _interactions.cancel();
      unawaited(_tvboxHandle.pause());
      unawaited(_saveProgress(flush: true));
    }
  }

  void _onTvboxError(String message) {
    if (_closed || _loading || _error != null) return;
    final next = _backendManager?.nextBackend();
    if (next == PlaybackBackend.main) {
      final position = _tvboxHandle.positionSeconds > 0
          ? _tvboxHandle.positionSeconds
          : _tvboxStartPosition;
      unawaited(_play(_index, position: position, continueChain: true));
      return;
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _error = message.isEmpty ? '播放失败' : message;
      });
    }
  }

  void _togglePlayback() {
    if (_closed || _loading || _error != null) return;
    _handoffOwned = false;
    widget.handoff?.fail('接收端已操作播放');
    _interactions.cancel();
    if (_useTvbox) {
      _playIntent = !_tvboxHandle.playing;
      _health.reset();
      if (_playIntent && _tvboxHandle.completed) {
        unawaited(_play(_index));
        return;
      }
      if (_playIntent) {
        unawaited(_tvboxHandle.play());
      } else {
        unawaited(_tvboxHandle.pause());
      }
      if (!_playIntent) unawaited(_saveProgress(flush: true));
      _syncDanmaku();
      return;
    }
    _playIntent = !_player.state.playing;
    if (_playIntent) _enhancement.mediaReady();
    _health.reset();
    if (_playIntent && _player.state.completed) {
      unawaited(_play(_index));
      return;
    }
    unawaited(_player.playOrPause());
    if (!_playIntent) unawaited(_saveProgress(flush: true));
    _syncDanmaku();
  }

  Future<void> _saveProgress({bool flush = false}) async {
    if (_openedIndex < 0 || widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    final position = _useTvbox
        ? _tvboxHandle.positionSeconds
        : _player.state.position.inMilliseconds / 1000;
    final duration = _useTvbox
        ? _tvboxHandle.durationSeconds
        : _player.state.duration.inMilliseconds / 1000;
    if (position < .1) {
      return;
    }
    final store = widget.store;
    final progressKey =
        '${widget.mediaId ?? widget.detail.drama.id}:$_openedIndex:$position:$duration';
    if (_savedProgressKey == progressKey && _saveWarning == null) {
      if (flush && widget.mediaId == null) LanController.current?.flush();
      return;
    }
    final entry = WatchEntry(
      drama: widget.repository.catalogUpdates.current(widget.detail.drama),
      episode: widget.detail.episodes[_openedIndex].number,
      position: position,
      duration: duration,
      updatedAt: DateTime.now(),
    );
    try {
      await Future<void>.value();
      if (store.profileEpoch != _profileEpoch) return;
      if (widget.mediaId == null) {
        await store.saveWatch(entry);
        if (flush) LanController.current?.flush();
      } else {
        await store.saveMediaWatch(widget.mediaId!, entry);
      }
      _savedProgressKey = progressKey;
      if (mounted && !_closed && _saveWarning != null) {
        setState(() => _saveWarning = null);
      }
    } catch (_) {
      if (mounted && !_closed && _saveWarning == null) {
        setState(() => _saveWarning = '观看进度尚未保存，请检查存储空间后重试。');
      }
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _operations.catchError((Object _) {}).then((_) => operation());
    _operations = next;
    return next;
  }

  Future<void> _play(
    int index, {
    double position = 0,
    PlaybackRecoveryAction? recoveryAction,
    int? routeSelection,
    bool playWhenReady = true,
    PlaybackPlan? handoffPlan,
    bool showControlsOnReady = true,
    bool continueChain = false,
  }) async {
    if (_closed ||
        widget.store.profileEpoch != _profileEpoch ||
        index < 0 ||
        index >= widget.detail.episodes.length) {
      return;
    }
    _interactions.cancel();
    if (widget.handoff != null &&
        handoffPlan == null &&
        recoveryAction == null &&
        routeSelection == null &&
        !continueChain) {
      _handoffOwned = false;
      widget.handoff?.fail('接收端已更换播放内容');
    }
    if (index != _index) _forceOnline = false;
    final canPreload =
        recoveryAction == null &&
        routeSelection == null &&
        _preloadEnabled &&
        !widget.localOnly;
    final warmed =
        handoffPlan ??
        (canPreload
            ? _preloader.take(
                widget.detail.drama,
                widget.detail.episodes[index],
                quality: _requestedQuality,
                route: _routeIndex,
                online: _forceOnline,
                adBlock: _adBlock,
              )
            : null);
    _preloader.clear();
    final ticket = ++_generation;
    _enhancement.suspend();
    _seekSequence++;
    _danmaku.setPlan(null);
    _acceptErrors = false;
    _pendingError = false;
    _errorTimer?.cancel();
    _health.reset();
    if (recoveryAction == null || routeSelection != null) {
      _recovery.reset();
      _playIntent = playWhenReady;
    }
    _resumePosition = position;
    _showControlsOnPlaybackReady = showControlsOnReady;
    var loadingMessage = switch (recoveryAction) {
      PlaybackRecoveryAction.alternative => '正在切换备用线路',
      PlaybackRecoveryAction.refresh => '正在重新获取播放地址',
      _ => '正在准备播放',
    };
    if (routeSelection != null) loadingMessage = '正在切换播放线路';
    setState(() {
      _index = index;
      _loading = true;
      _error = null;
      _localFailure = false;
      _loadingMessage = loadingMessage;
    });
    LanController.current?.detachPlayback(_lanIdentity);
    _lanIdentity = Object();
    _attachLanPlayback();
    PlaybackPlan? prepared;
    PlaybackPlan? retained;
    bool installed = false;
    try {
      await _serialize(() async {
        if (_closed || ticket != _generation) {
          return;
        }
        await _saveProgress(flush: true);
        await _enhancement.beforeMedia();
        if (_closed || ticket != _generation) return;
        _openedIndex = -1;
        await _player.stop();
        final previous = _plan;
        _plan = null;
        if (recoveryAction == PlaybackRecoveryAction.alternative ||
            routeSelection != null) {
          retained = previous;
        } else if (previous != null) {
          await widget.repository.release(previous.session);
        }
      });
      if (_closed || ticket != _generation) {
        return;
      }
      if (retained != null) {
        if (routeSelection != null) {
          prepared = await _loader.selectRoute(retained!, routeSelection);
        } else {
          prepared = await _loader.fallback(retained!);
        }
      } else if (warmed != null) {
        prepared = await _loader.use(warmed);
      } else {
        prepared = await _loader.load(
          widget.detail.drama,
          widget.detail.episodes[index],
          quality: _requestedQuality,
          route: routeSelection ?? _routeIndex,
          localOnly: widget.localOnly,
          online: _forceOnline,
          adBlock: _adBlock,
        );
      }
      if (prepared == null) {
        return;
      }
      if (!prepared.local && prepared.needsParse) {
        _lastPageUrl = prepared.url;
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
        _lastPageUrl = prepared.url;
        final parsed = applySelectedParse(
          url: prepared.url,
          needsParse: false,
          selected: _selectedParse,
        );
        if (parsed != null && parsed != prepared.url) {
          prepared = prepared.withUrl(parsed);
        }
      }
      final plan = prepared;
      await _serialize(() async {
        if (_closed || ticket != _generation) {
          await widget.repository.release(plan.session);
          return;
        }
        if (plan.url.isEmpty) {
          throw AppFailure('站源未返回播放地址，请重试');
        }
        final platform = _player.platform;
        if (!continueChain) {
          _backendManager = null;
        }
        final useTvboxForPlan = _useTvbox && plan.decryptionKey.isEmpty;
        _backendManager ??= PlaybackBackendManager(
          initial: useTvboxForPlan
              ? PlaybackBackend.tvbox
              : PlaybackBackend.main,
        );
        if (!useTvboxForPlan && platform is NativePlayer) {
          if (Platform.isAndroid) {
            if (_televisionDecoderApplies) {
              final optimized =
                  _televisionDecoder == TelevisionDecoder.optimized;
              await platform.setProperty(
                'hwdec',
                _televisionDecoder == TelevisionDecoder.software
                    ? 'no'
                    : 'mediacodec-copy',
              );
              await platform.setProperty('hwdec-codecs', 'all');
              await platform.setProperty(
                'opengl-pbo',
                optimized ? 'yes' : 'no',
              );
              await platform.setProperty(
                'video-latency-hacks',
                optimized ? 'yes' : 'no',
              );
              await platform.setProperty('scale', 'bilinear');
              await platform.setProperty('cscale', 'bilinear');
              await platform.setProperty('dscale', 'bilinear');
              await platform.setProperty('correct-downscaling', 'no');
              await platform.setProperty(
                'vd-lavc-skiploopfilter',
                optimized ? 'all' : 'default',
              );
              await platform.setProperty(
                'vd-lavc-skipidct',
                optimized ? 'all' : 'default',
              );
              await platform.setProperty('vd-lavc-threads', '2');
              await platform.setProperty(
                'demuxer-max-bytes',
                '${4 * 1024 * 1024}',
              );
              await platform.setProperty(
                'demuxer-max-back-bytes',
                '${1 * 1024 * 1024}',
              );
              await platform.setProperty('demuxer-readahead-secs', '5');
            } else {
              await platform.setProperty('hwdec', 'auto-safe');
              await platform.setProperty('hwdec-codecs', 'all');
              await platform.setProperty('vd-lavc-skiploopfilter', 'nonkey');
              await platform.setProperty('vd-lavc-threads', '4');
            }
            await platform.setProperty('vd-lavc-fast', 'yes');
            await platform.setProperty('video-sync', 'audio');
            await platform.setProperty('framedrop', 'vo');
          } else if (Platform.isWindows) {
            await WindowsPlaybackTuning.apply(platform, local: plan.local);
          }
          if (plan.local || plan.decryptionKey.isNotEmpty) {
            await platform.setProperty(
              'demuxer-lavf-o',
              [
                'seg_max_retry=3',
                'strict=experimental',
                'allowed_extensions=ALL',
                plan.local
                    ? 'protocol_whitelist=[file,crypto,data]'
                    : 'protocol_whitelist=[http,https,tcp,tls,crypto,data,file]',
                if (plan.decryptionKey.isNotEmpty)
                  'decryption_key=${plan.decryptionKey}',
              ].join(','),
            );
            await platform.setProperty('network-timeout', '20');
          }
        }
        _plan = plan;
        installed = true;
        _acceptErrors = true;
        if (useTvboxForPlan) {
          _tvboxPlan = plan;
          _tvboxStartPosition = position;
          _tvboxAutoplay = _foreground && _playIntent;
        } else {
          await _player.open(
            Media(
              plan.url,
              httpHeaders: plan.headers,
              start: position > 0
                  ? Duration(milliseconds: (position * 1000).round())
                  : null,
            ),
            play: _foreground && _playIntent,
          );
        }
        if (_closed || ticket != _generation) {
          return;
        }
        _openedIndex = index;
        if (!_useTvbox) _enhancement.mediaReady();
        _attachLanPlayback();
        _health.reset();
        if (!_useTvbox) await _interactions.applySpeed();
        if (mounted && !_closed && ticket == _generation) {
          setState(() {
            _loading = false;
          });
          _danmaku.setPlan(plan);
          _syncDanmaku();
          _acknowledgeHandoff();
          _menuRevision.value++;
        }
      });
    } catch (error) {
      if (!_closed && mounted && ticket == _generation) {
        if (prepared != null && identical(_plan, prepared)) {
          _acceptErrors = true;
          _queueRecovery();
        } else {
          if (prepared != null) {
            await widget.repository.release(prepared.session);
          }
          if (mounted && !_closed && ticket == _generation) {
            setState(() {
              _loading = false;
              _localFailure =
                  (error is AppFailure && error.code == 'local_media') ||
                  (widget.localOnly && !_forceOnline);
              _error = error is AppFailure ? error.message : '无法播放这一集，请重试或换一集。';
              widget.handoff?.fail(_error!);
            });
          }
        }
      } else if (prepared != null && !installed) {
        await widget.repository.release(prepared.session);
      }
    } finally {
      if (warmed != null && !installed) {
        await widget.repository.release(warmed.session);
      }
      if (retained != null) {
        await widget.repository.release(retained!.session);
      }
    }
  }

  Future<void> _switchOnline() async {
    _forceOnline = true;
    await _retry();
  }

  Future<void> _retry({int? quality}) async {
    final position = _currentPosition;
    if (quality != null) {
      _requestedQuality = quality;
    }
    await _play(
      _index,
      position: position,
      playWhenReady: quality == null || _error != null || _player.state.playing,
    );
  }

  Future<void> _selectRoute(int route) async {
    if (_closed || _plan == null || _plan!.local) return;
    if (route < 0 || route >= _routeCount || route == _currentRoute) return;
    final previous = _routeIndex;
    final position = _currentPosition;
    final playing =
        _playIntent &&
        (_useTvbox ? _tvboxHandle.playing : _player.state.playing);
    await _saveProgress(flush: true);
    setState(() => _routeIndex = route);
    await _play(
      _index,
      position: position,
      routeSelection: route,
      playWhenReady: playing,
    );
    if (_closed || !mounted || _plan?.routeIndex == route) return;
    if (_routeIndex == route) setState(() => _routeIndex = previous);
  }

  bool get _showFullscreen {
    if (_television || _fullscreen || _pageFullscreen || _windowFullscreen) {
      return true;
    }
    if (!_mobile || _automaticFullscreenSuppressed) return false;
    final orientation = MediaQuery.orientationOf(context);
    return switch (_orientationMode) {
      PlaybackOrientationMode.portrait => orientation == Orientation.portrait,
      PlaybackOrientationMode.landscape => orientation == Orientation.landscape,
      PlaybackOrientationMode.auto =>
        (_aspectRatio >= 1 && orientation == Orientation.landscape) ||
            (_aspectRatio < 1 && orientation == Orientation.portrait),
    };
  }

  Future<void> _rotate() async {
    if (_rotating || _television) {
      return;
    }
    final windows = Platform.isWindows;
    final fullscreen = windows ? !_windowFullscreen : !_showFullscreen;
    final previous = _fullscreen;
    final previousPageFullscreen = _pageFullscreen;
    final previousWindowFullscreen = _windowFullscreen;
    final previousSuppressed = _automaticFullscreenSuppressed;
    _interactions.cancel();
    _rotating = true;
    setState(() {
      if (windows) {
        _windowFullscreen = fullscreen;
      } else {
        _fullscreen = fullscreen;
        _automaticFullscreenSuppressed = !fullscreen;
      }
    });
    try {
      if (windows) {
        await windowManager.setFullScreen(fullscreen);
      } else if (_mobile) {
        await (_orientationController?.setPlayback(
                  this,
                  fullscreen: fullscreen,
                  aspectRatio: _aspectRatio,
                  mode: _orientationMode,
                ) ??
                SystemChrome.setPreferredOrientations(
                  AppOrientationController.orientations(
                    television: _television,
                    fullscreen: fullscreen,
                    aspectRatio: _aspectRatio,
                    mode: _orientationMode,
                  ),
                ))
            .timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      if (mounted && !_closed) {
        setState(() {
          _fullscreen = previous;
          _pageFullscreen = previousPageFullscreen;
          _windowFullscreen = previousWindowFullscreen;
          _automaticFullscreenSuppressed = previousSuppressed;
        });
        _notice('无法切换全屏，请重试');
      }
    } finally {
      _rotating = false;
      if (_backPending) {
        _backPending = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_closed) _backToList();
        });
      }
      if (mounted && !_closed) _scheduleSystemUi();
      if (!fullscreen && mounted && !_closed) {
        _scrollEpisodeStripToCurrent();
      }
    }
  }

  /// 退出全屏后把选集横排滚回当前集（每枚 chip 约 84px 估宽，
  /// 精确位置由 ListView 的可视钳制兜底）。
  void _scrollEpisodeStripToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed || !_episodeStripController.hasClients) return;
      final displayIndex = _episodesReversed
          ? widget.detail.episodes.length - 1 - _index
          : _index;
      final target = (displayIndex * 84.0).clamp(
        0.0,
        _episodeStripController.position.maxScrollExtent,
      );
      _episodeStripController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _applyOrientation() async {
    if (_television || !_mobile || _closed) return;
    final fullscreen = _orientationMode != PlaybackOrientationMode.auto
        ? true
        : _showFullscreen;
    try {
      await (_orientationController?.setPlayback(
            this,
            fullscreen: fullscreen,
            aspectRatio: _aspectRatio,
            mode: _orientationMode,
          ) ??
          SystemChrome.setPreferredOrientations(
            AppOrientationController.orientations(
              television: _television,
              fullscreen: fullscreen,
              aspectRatio: _aspectRatio,
              mode: _orientationMode,
            ),
          ));
    } catch (_) {}
    if (mounted && !_closed) _scheduleSystemUi();
  }

  Future<void> _loadParseSelection() async {
    try {
      final selected = await ParseInterfaceStore.loadSelected();
      if (!_closed && mounted) _selectedParse = selected;
    } catch (_) {}
  }

  Future<void> _openSniffer() async {
    final pageUrl = _lastPageUrl;
    if (pageUrl.isEmpty || !mounted || _closed) return;
    final found = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (routeContext) => SniffWebViewPage(
          pageUrl: pageUrl,
          headers: _plan?.headers ?? const {},
          onMediaFound: (url) => Navigator.of(routeContext).pop(url),
        ),
      ),
    );
    if (found == null || found.isEmpty || _closed || !mounted) return;
    await _play(
      _index,
      handoffPlan: PlaybackPlan(
        url: found,
        headers: _plan?.headers ?? const {},
      ),
    );
  }

  String _queueSwipe(int direction) {
    final queue = widget.queue;
    if (queue == null || queue.isEmpty) {
      return direction > 0 ? '已经是最后一集' : '已经是第一集';
    }
    final target = queue.neighbor(direction);
    if (target == null) {
      _notice(direction > 0 ? '已经是列表最后一部' : '已经是列表第一部');
      return '';
    }
    unawaited(_openQueueDrama(queue, direction, target));
    return target.title;
  }

  Future<void> _openQueueDrama(
    PlaybackQueue queue,
    int direction,
    Drama target,
  ) async {
    if (_closed || !mounted) return;
    try {
      final detail = await widget.repository.detail(target);
      if (_closed || !mounted) return;
      if (detail.episodes.isEmpty) {
        _notice('《${target.title}》暂时没有可播放的集数');
        return;
      }
      final watched = widget.store.watched(detail.drama.id);
      final index = resumeEpisodeIndex(detail.episodes, watched);
      final position =
          watched?.episode == detail.episodes[index].number &&
              watched?.finished == false
          ? watched!.position
          : 0.0;
      await Navigator.of(context).pushReplacement(
        playerRoute(
          PlayerScreen(
            detail: detail,
            initialIndex: index,
            initialPosition: position,
            repository: widget.repository,
            store: widget.store,
            queue: queue.moved(direction),
          ),
        ),
      );
    } catch (_) {
      if (mounted && !_closed) _notice('切换失败，请重试');
    }
  }

  Future<void> _setOrientationMode(PlaybackOrientationMode mode) async {
    if (mode == _orientationMode || _closed) return;
    try {
      await _setPreferences(_preferences.copyWith(orientationMode: mode));
    } catch (_) {
      _notice('方向偏好未能保存，请重试');
    }
  }

  void _notice(String message) {
    if (!mounted || _closed) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setPreferences(PlaybackPreferences preferences) async {
    if (_closed || widget.store.profileEpoch != _profileEpoch) {
      throw StateError('当前用户已变更');
    }
    _interactions.cancel();
    final adBlockChanged = preferences.adBlock != _adBlock;
    final nextPreferences = preferences.copyWith(
      autoAdvance: true,
      preload: true,
    );
    await widget.store.setPlaybackPreferences(nextPreferences);
    if (!mounted || _closed || widget.store.profileEpoch != _profileEpoch)
      return;
    final qualityChanged = nextPreferences.quality != _requestedQuality;
    final decoderChanged =
        nextPreferences.televisionDecoder != _televisionDecoder;
    final orientationChanged =
        nextPreferences.orientationMode != _orientationMode;
    _enhancement.setPreferences(nextPreferences.enhancement);
    unawaited(_pictureQuality.apply(nextPreferences.pictureQuality));
    setState(() {
      _speed = nextPreferences.speed;
      _requestedQuality = nextPreferences.quality;
      _autoAdvance = true;
      _danmakuEnabled = nextPreferences.danmaku;
      _adBlock = nextPreferences.adBlock;
      _preloadEnabled = true;
      _televisionDecoder = nextPreferences.televisionDecoder;
      _orientationMode = nextPreferences.orientationMode;
    });
    if (orientationChanged) unawaited(_applyOrientation());
    _danmaku.setEnabled(_danmakuEnabled);
    _syncDanmaku();
    if (qualityChanged || adBlockChanged) _preloader.clear();
    _syncPreload();
    _menuRevision.value++;
    await _interactions.applySpeed();
    if (_useTvbox) unawaited(_tvboxHandle.setSpeed(_speed));
    if (qualityChanged && _plan?.local != true) {
      await _retry(quality: nextPreferences.quality);
    } else if (adBlockChanged && _plan?.local != true) {
      // 去广告开关按会话生效：重建播放会话让核心按新标志清洗或放行原画。
      await _retry();
    } else if (decoderChanged && _televisionDecoderApplies) {
      await _retry();
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      await widget.store.toggleFavorite(widget.detail.drama);
      if (mounted && !_closed) setState(() {});
    } catch (_) {
      _notice('追剧记录未能保存，请检查存储空间后重试');
    }
  }

  Future<void> _toggleDanmaku() async {
    if (widget.detail.drama.source != 'hongguo') return;
    try {
      await _setPreferences(_preferences.copyWith(danmaku: !_danmakuEnabled));
    } catch (_) {
      _notice('弹幕偏好未能保存，请重试');
    }
  }

  Future<void> _retryDanmakuFromControls() async {
    try {
      _danmaku.retry();
      _menuRevision.value++;
    } catch (_) {
      _notice('弹幕重试失败，请稍后再试');
    }
  }

  Future<void> _submitDownloadSelection(DownloadSelection selection) async {
    if (!widget.repository.supportsDownloads ||
        !widget.store.canDownload ||
        widget.store.profileEpoch != _profileEpoch ||
        widget.mediaId != null) {
      return;
    }
    final added = await widget.repository.enqueueDownloads(
      widget.detail,
      selection.episodes,
      quality: selection.quality,
    );
    if (!mounted || _closed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added == 0 ? '所选集数已在下载列表中' : '已加入 $added 集，已有任务自动跳过'),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DownloadsScreen(
                  repository: widget.repository,
                  store: widget.store,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPanel(PlayerMenuSection section) async {
    if (_panelOpen || _closed) return;
    _interactions.cancel();
    setState(() => _panelOpen = true);
    final menuTheme = _showFullscreen ? AppTheme.dark : Theme.of(context);
    try {
      final index = await showDialog<int>(
        context: context,
        builder: (menuContext) => AnimatedBuilder(
          animation: Listenable.merge([
            _menuRevision,
            widget.store,
            _danmaku,
            _preloader,
          ]),
          builder: (_, _) => Theme(
            data: menuTheme,
            child: PlayerMenu(
              section: section,
              episodes: widget.detail.episodes,
              currentIndex: _index,
              preferences: _preferences,
              qualities: _plan?.qualities ?? [],
              actualQuality: _plan?.quality ?? 0,
              local: _plan?.local == true,
              favorite: widget.store.isFavorite(widget.detail.drama.id),
              mobile: _mobile,
              routeIndex: _currentRoute,
              routeCount: _routeCount,
              onRoute: (route) => Navigator.pop(menuContext, route),
              onEpisode: (index) => Navigator.pop(menuContext, index),
              onPreferences: _setPreferences,
              showDanmaku: widget.detail.drama.source == 'hongguo',
              danmakuStatus: _danmaku.status,
              onRetryDanmaku: _danmaku.canRetry ? _danmaku.retry : null,
              preloadStatus: _preloader.status,
              enhancement: _enhancementForUi,
              onCompareEnhancement: () {
                unawaited(_enhancement.toggleCompare());
                Navigator.pop(menuContext);
              },
              onFavorite: () =>
                  widget.store.toggleFavorite(widget.detail.drama),
            ),
          ),
        ),
      );
      if (!mounted || _closed || index == null) return;
      if (section == PlayerMenuSection.route) {
        await _selectRoute(index);
      } else if (index != _index) {
        await _play(index, showControlsOnReady: false);
      }
    } finally {
      if (mounted && !_closed) {
        setState(() => _panelOpen = false);
        _playerFocus.requestFocus();
      }
    }
  }

  Future<void> _seekTo(Duration target) async {
    if (_closed || _loading || _error != null) return;
    _handoffOwned = false;
    widget.handoff?.fail('接收端已调整播放位置');
    final ticket = ++_seekSequence;
    final generation = _generation;
    _danmaku.beginSeek();
    _enhancement.ignorePerformance();
    var succeeded = false;
    try {
      if (_useTvbox) {
        await _tvboxHandle.seek(target);
      } else {
        await _player.seek(target);
      }
      succeeded = true;
    } catch (_) {
      _notice('跳转失败，请重试');
    } finally {
      if (!_closed && ticket == _seekSequence && generation == _generation) {
        _danmaku.endSeek(succeeded ? target : _seekFallbackPosition);
      }
    }
  }

  void _seek(int seconds) {
    final desired =
        (_useTvbox ? _tvboxHandle.position : _player.state.position) +
        Duration(seconds: seconds);
    final maxDuration = _useTvbox
        ? _tvboxHandle.duration
        : _player.state.duration;
    final target = desired < Duration.zero
        ? Duration.zero
        : maxDuration > Duration.zero && desired > maxDuration
        ? maxDuration
        : desired;
    unawaited(_seekTo(target));
  }

  bool get _androidBrightness =>
      defaultTargetPlatform == TargetPlatform.android;

  double? _currentBrightness() {
    return _cachedBrightness;
  }

  Future<void> _setScreenBrightness(double value) async {
    if (_closed) return;
    _cachedBrightness = value;
    _brightnessAdjusted = true;
    try {
      await AppDevice.channel.invokeMethod<void>('setScreenBrightness', {
        'value': value,
      });
    } on PlatformException {
      _notice('亮度调整失败');
    } on MissingPluginException {
      _notice('亮度调整失败');
    }
  }

  Future<void> _resetScreenBrightness() async {
    if (!_brightnessAdjusted) return;
    _brightnessAdjusted = false;
    _cachedBrightness = null;
    try {
      await AppDevice.channel.invokeMethod<void>('resetScreenBrightness');
    } on PlatformException {
      // 恢复失败不打扰用户：窗口亮度覆盖只在本 Activity 存续，返回即失效。
    } on MissingPluginException {
      // 同上。
    }
  }

  Future<void> _readSystemBrightness() async {
    if (!_androidBrightness || _brightnessAdjusted) return;
    try {
      final value = await AppDevice.channel.invokeMethod<double>(
        'screenBrightness',
      );
      _cachedBrightness = value;
    } on PlatformException {
      _cachedBrightness = null;
    } on MissingPluginException {
      _cachedBrightness = null;
    }
  }

  Future<void> _televisionEpisodes(BuildContext context) async {
    if (_panelOpen || _closed) return;
    setState(() => _panelOpen = true);
    int? index;
    try {
      index = await showDialog<int>(
        context: context,
        builder: (_) => Theme(
          data: televisionTheme(AppTheme.dark),
          child: TelevisionEpisodeDialog(
            episodes: widget.detail.episodes,
            currentIndex: _index,
          ),
        ),
      );
    } finally {
      if (mounted && !_closed) setState(() => _panelOpen = false);
    }
    if (index != null && mounted && !_closed && index != _index) {
      await _play(index, showControlsOnReady: false);
    }
  }

  Future<void> _televisionSettings(BuildContext context) async {
    if (_panelOpen || _closed) return;
    setState(() => _panelOpen = true);
    TelevisionPlaybackSetting? selection;
    try {
      final compatibleRendering = _televisionDecoderApplies
          ? await AppDevice.compatibleRendering()
          : null;
      if (!mounted || _closed) return;
      selection = await showDialog<TelevisionPlaybackSetting>(
        context: context,
        builder: (menuContext) => AnimatedBuilder(
          animation: Listenable.merge([_danmaku, _preloader]),
          builder: (_, _) => Theme(
            data: televisionTheme(AppTheme.dark),
            child: TelevisionSettingsDialog(
              speed: _speed,
              quality: _requestedQuality,
              qualities: _plan?.qualities ?? [],
              favorite: widget.store.isFavorite(widget.detail.drama.id),
              onFavorite: _toggleFavorite,
              autoAdvance: _autoAdvance,
              danmaku: _danmakuEnabled,
              showDanmaku: widget.detail.drama.source == 'hongguo',
              danmakuStatus: _danmaku.status,
              onRetryDanmaku: _danmaku.canRetry ? _danmaku.retry : null,
              preload: _preloadEnabled,
              preloadStatus: _preloader.status,
              enhancement: _enhancementForUi,
              onCompareEnhancement: () {
                unawaited(_enhancement.toggleCompare());
                Navigator.pop(menuContext);
              },
              route: _currentRoute,
              routeCount: _routeCount,
              decoder: _televisionDecoderApplies ? _televisionDecoder : null,
              compatibleRendering: compatibleRendering,
            ),
          ),
        ),
      );
    } finally {
      if (mounted && !_closed) setState(() => _panelOpen = false);
    }
    if (selection == null || !mounted || _closed) return;
    if (selection.compatibleRendering != null) {
      await _switchCompatibleRendering(selection.compatibleRendering!);
      return;
    }
    if (selection.route != null && selection.route != _currentRoute) {
      await _selectRoute(selection.route!);
      return;
    }
    try {
      await _setPreferences(
        _preferences.copyWith(
          speed: selection.speed,
          quality: selection.quality,
          autoAdvance: true,
          danmaku: selection.danmaku,
          preload: true,
          enhancement: selection.enhancement,
          televisionDecoder: selection.decoder,
        ),
      );
    } catch (_) {
      _notice('播放偏好未能保存，请重试');
    }
  }

  Future<void> _switchCompatibleRendering(bool enabled) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: televisionTheme(AppTheme.dark),
        child: AlertDialog(
          title: Text(enabled ? '开启兼容渲染模式？' : '关闭兼容渲染模式？'),
          content: const Text('需要重启应用才能生效，正在进行的下载会中断。'),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('立即重启'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await AppDevice.setCompatibleRendering(enabled);
    }
  }

  void _backToList() {
    if (_closed) return;
    if (_episodePanelVisible && !_mobile) {
      _toggleEpisodePanel();
      return;
    }
    final action = resolvePlayerBackAction(
      panelOpen: _panelOpen,
      pageFullscreen: _pageFullscreen,
      fullscreen: _showFullscreen,
      television: _television,
      isFirstRoute: ModalRoute.of(context)?.isFirst ?? false,
    );
    switch (action) {
      case PlayerBackAction.closePanel:
        Navigator.of(context).pop();
      case PlayerBackAction.backOnce:
        Navigator.of(context).pop();
      case PlayerBackAction.exitPageFullscreen:
        _togglePageFullscreen();
      case PlayerBackAction.exitFullscreen:
        if (_rotating) {
          _backPending = true;
          return;
        }
        unawaited(_rotate());
      case PlayerBackAction.backToList:
        Navigator.of(context).popUntil(isBackToListStop);
      case PlayerBackAction.toHome:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                HomeScreen(repository: widget.repository, store: widget.store),
          ),
        );
    }
  }

  void _togglePageFullscreen() {
    if (_television || _closed) return;
    _interactions.cancel();
    setState(() => _pageFullscreen = !_pageFullscreen);
    _scheduleSystemUi();
  }

  void _toggleEpisodePanel() {
    if (_closed || _showFullscreen || _mobile) return;
    _interactions.cancel();
    setState(() => _episodePanelVisible = !_episodePanelVisible);
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_resetScreenBrightness());
    final enhancementClosed = _enhancement.close();
    LanController.current?.detachPlayback(_lanIdentity);
    widget.handoff?.fail('接收端已退出播放');
    widget.store.removeListener(_accessChanged);
    _danmaku.dispose();
    _preloader.dispose();
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _healthTimer?.cancel();
    _errorTimer?.cancel();
    _pictureInPictureExitTimer?.cancel();
    if (_pictureInPictureHandlerInstalled) {
      AppDevice.channel.setMethodCallHandler(null);
    }
    _interactions.dispose();
    _playerFocus.dispose();
    _episodeStripController.dispose();
    _menuRevision.dispose();
    unawaited(_saveProgress(flush: true));
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    unawaited(widget.repository.release(_session));
    unawaited(_loader.close().catchError((Object _) {}));
    unawaited(
      _operations.catchError((Object _) {}).then((_) async {
        await _interactions.pendingRates.catchError((Object _) {});
        await enhancementClosed.catchError((Object _) {});
        await _pictureQuality.dispose().catchError((Object _) {});
        await _player.dispose();
      }),
    );
    if (Platform.isWindows) {
      unawaited(windowManager.setFullScreen(false));
    } else if (_mobile || _television && Platform.isAndroid) {
      unawaited(
        (_orientationController?.releasePlayback(this) ??
                SystemChrome.setPreferredOrientations(
                  AppOrientationController.orientations(
                    television: _television,
                  ),
                ))
            .catchError((Object _) {}),
      );
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inherited = Theme.of(context);
    final theme = _television ? televisionTheme(inherited) : inherited;
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final fullscreen = _showFullscreen;
          final overlayBrightness = fullscreen
              ? Brightness.dark
              : Theme.of(context).brightness;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppTheme.systemBars(overlayBrightness),
            child: _buildPlayer(context),
          );
        },
      ),
    );
  }

  Widget _buildPlayer(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.detail.drama.title;
    final fullscreen = _showFullscreen;
    final pictureInPicture = _pictureInPictureVisible;
    return PopScope(
      canPop: _television,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_television) {
          _backToList();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _backToList,
          const SingleActivator(LogicalKeyboardKey.goBack): _backToList,
        },
        child: Focus(
          focusNode: _playerFocus,
          onKeyEvent: (_, event) {
            if (_television ||
                _panelOpen ||
                !_playerFocus.hasPrimaryFocus ||
                !(ModalRoute.of(context)?.isCurrent ?? true)) {
              return KeyEventResult.ignored;
            }
            return _interactions.key(event);
          },
          autofocus: !_television,
          canRequestFocus: !_television,
          skipTraversal: _television,
          child: Scaffold(
            backgroundColor: fullscreen || pictureInPicture
                ? Colors.black
                : theme.scaffoldBackgroundColor,
            appBar: pictureInPicture || fullscreen || _mobile
                ? null
                : AppBar(
                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    actions: [
                      IconButton(
                        tooltip: '旋转与全屏',
                        onPressed: _rotate,
                        icon: const Icon(Icons.screen_rotation_alt_rounded),
                      ),
                    ],
                  ),
            body: pictureInPicture
                ? _videoPane(context)
                : SafeArea(
                    top: !_television && (fullscreen || _mobile),
                    bottom: !fullscreen,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final desktop = constraints.maxWidth >= 840;
                        if (fullscreen) {
                          return _videoPane(context);
                        }
                        if (desktop ||
                            constraints.maxWidth >
                                constraints.maxHeight * 1.3) {
                          return Row(
                            children: [
                              Expanded(child: _videoPane(context)),
                              if (_episodePanelVisible)
                                SizedBox(
                                  width: desktop ? 312 : 210,
                                  child: _episodePanel(
                                    onClose: _toggleEpisodePanel,
                                  ),
                                ),
                            ],
                          );
                        }
                        if (_mobile) {
                          final height = (constraints.maxWidth / _aspectRatio)
                              .clamp(0.0, constraints.maxHeight * .56);
                          return Column(
                            children: [
                              SizedBox(
                                height: height,
                                width: double.infinity,
                                child: _videoPane(context),
                              ),
                              Expanded(child: _mobilePlaybackPanel()),
                            ],
                          );
                        }
                        final height = (constraints.maxWidth / _aspectRatio)
                            .clamp(0.0, constraints.maxHeight * .64);
                        return Column(
                          children: [
                            SizedBox(
                              height: height,
                              width: double.infinity,
                              child: _videoPane(context),
                            ),
                            Expanded(child: _mobilePlaybackPanel()),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _videoBackdrop() {
    final drama = widget.detail.drama;
    var url = widget.detail.backdrop;
    if (url.isEmpty) {
      for (final still in widget.detail.stills) {
        if (still.isNotEmpty) {
          url = still;
          break;
        }
      }
    }
    if (url.isEmpty) url = drama.cover;
    if (url.isEmpty) return const SizedBox.shrink();
    final backdropDrama = Drama(
      id: '${drama.id}#player-backdrop',
      source: drama.source,
      title: drama.title,
      cover: url,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        AtmosphereBackground(
          url: url,
          repository: widget.repository,
          drama: backdropDrama,
        ),
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DramaCover(
            drama: backdropDrama,
            repository: widget.repository,
            radius: 0,
          ),
        ),
      ],
    );
  }

  Widget _videoPane(BuildContext context) {
    final videoTheme = _television
        ? televisionTheme(AppTheme.dark)
        : AppTheme.dark;
    final title =
        '${widget.detail.drama.title} · 第 ${widget.detail.episodes[_index].number} 集${_plan?.local == true ? ' · 本地' : ''}${widget.detail.episodes[_index].vip ? ' · VIP 试看' : ''}${(_plan?.routeIndex ?? 0) > 0 ? ' · 线路 ${_plan!.routeIndex + 1}' : ''}';
    final hideOverlayForPictureInPicture = _pictureInPictureVisible;
    final errorKind = _error == null ? null : classifyPlaybackError(_error!);
    final Widget controls = hideOverlayForPictureInPicture
        ? const SizedBox.shrink()
        : _television
        ? TelevisionControls(
            player: _player,
            title: title,
            enabled: !_loading && _error == null,
            showOnPlaybackReady: _showControlsOnPlaybackReady,
            enhancement: _enhancementForUi,
            onTogglePlayback: _togglePlayback,
            onSeek: _seek,
            onPrevious: _index > 0
                ? () => _play(_index - 1, showControlsOnReady: false)
                : null,
            onNext: _index + 1 < widget.detail.episodes.length
                ? () => _play(_index + 1, showControlsOnReady: false)
                : null,
            onEpisodes: () => _televisionEpisodes(context),
            onSettings: () => _televisionSettings(context),
            onBack: _backToList,
          )
        : PlayerControls(
            player: _player,
            interactions: _interactions,
            enabled: !_loading && _error == null,
            enhancement: _enhancementForUi,
            panelOpen: _panelOpen,
            fullscreen: _showFullscreen,
            pageFullscreen: _pageFullscreen,
            windowFullscreen: _windowFullscreen,
            showOnPlaybackReady: _showControlsOnPlaybackReady,
            title: title,
            onTogglePlayback: _togglePlayback,
            swipeEnabled: _mobile,
            onFullscreen: _rotate,
            onPageFullscreen: Platform.isWindows ? _togglePageFullscreen : null,
            onExitFullscreen: _backToList,
            onBack: _backToList,
            onFocusSurface: _playerFocus.requestFocus,
            onSeek: _seekTo,
            speed: _speed,
            qualityLabel: _qualityLabel,
            routeLabel: _routeLabel,
            routeCount: _routeCount,
            onRoute: () => _openPanel(PlayerMenuSection.route),
            showDanmaku: widget.detail.drama.source == 'hongguo',
            danmakuEnabled: _danmakuEnabled,
            danmakuStatus: _danmaku.status,
            onEpisodes: () async {
              if (!_mobile && !_showFullscreen) {
                _toggleEpisodePanel();
              } else {
                await _openPanel(PlayerMenuSection.episodes);
              }
            },
            onSpeed: () => _openPanel(PlayerMenuSection.speed),
            onQuality: () => _openPanel(PlayerMenuSection.quality),
            onDanmaku: widget.detail.drama.source == 'hongguo'
                ? _toggleDanmaku
                : null,
            onRetryDanmaku: _danmaku.canRetry
                ? _retryDanmakuFromControls
                : null,
            onPush: widget.mediaId == null ? _pushToDevice : null,
            onPictureInPicture: _canUsePictureInPicture
                ? _enterPictureInPicture
                : null,
            onPrevious: _index > 0
                ? () => _play(_index - 1, showControlsOnReady: false)
                : widget.detail.episodes.length <= 1 &&
                      widget.queue?.neighbor(-1) != null
                ? () => _queueSwipe(-1)
                : null,
            onNext: _index + 1 < widget.detail.episodes.length
                ? () => _play(_index + 1, showControlsOnReady: false)
                : widget.detail.episodes.length <= 1 &&
                      widget.queue?.neighbor(1) != null
                ? () => _queueSwipe(1)
                : null,
            orientationMode: _orientationMode,
            onOrientationMode: _mobile ? _setOrientationMode : null,
          );
    final layeredControls = Stack(
      fit: StackFit.expand,
      children: [
        if (!hideOverlayForPictureInPicture)
          DanmakuOverlay(controller: _danmaku, aspectRatio: _aspectRatio),
        controls,
      ],
    );
    return Theme(
      data: videoTheme,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final pixels = Size(
            constraints.maxWidth * ratio,
            constraints.maxHeight * ratio,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_closed) {
              _enhancement.setViewport(pixels, television: _television);
            }
          });
          return Stack(
            key: _videoPaneKey,
            fit: StackFit.expand,
            children: [
              if (widget.videoBuilder != null)
                widget.videoBuilder!(layeredControls)
              else if (_useTvbox)
                TvboxVideoPane(
                  key: _tvboxPaneKey,
                  viewType: widget.store.player == 'fongmi'
                      ? TvboxPlayerController.fongmiViewType
                      : TvboxPlayerController.viewType,
                  plan: _tvboxPlan,
                  startPosition: _tvboxStartPosition,
                  autoplay: _tvboxAutoplay,
                  decoderMode: _televisionDecoder,
                  handle: _tvboxHandle,
                  onCompleted: _onTvboxCompleted,
                  onError: _onTvboxError,
                  onBack: _television ? null : _backToList,
                  onFullscreen: _television ? null : _rotate,
                  isFullscreen: _showFullscreen,
                )
              else
                Video(
                  controller: _video!,
                  fit: BoxFit.contain,
                  controls: (_) => layeredControls,
                ),
              if ((_loading || _error != null) &&
                  !hideOverlayForPictureInPicture)
                _videoBackdrop(),
              if (_loading && !hideOverlayForPictureInPicture)
                ColoredBox(
                  color: Colors.black.withValues(alpha: .55),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_loadingMessage),
                      ],
                    ),
                  ),
                ),
              if (_error != null && !hideOverlayForPictureInPicture)
                ColoredBox(
                  color: Colors.black.withValues(alpha: .55),
                  child: Column(
                    children: [
                      Expanded(
                        child: StatusPanel(
                          title:
                              errorKind == null ||
                                  errorKind == PlaybackErrorKind.other
                              ? '暂时无法播放'
                              : '暂时无法播放 · ${errorKind.label}',
                          message: errorKind?.suggestion ?? '',
                          detail: _error!,
                          onRetry: () => _retry(),
                          action: _localFailure ? '重试本地播放' : '重试播放',
                          secondaryAction:
                              _localFailure && widget.allowOnlineFallback
                              ? TextButton.icon(
                                  onPressed: _switchOnline,
                                  icon: const Icon(Icons.cloud_outlined),
                                  label: const Text('改为在线播放'),
                                )
                              : !_localFailure &&
                                    !widget.localOnly &&
                                    widget.repository.supportsSourceManagement
                              ? SourceDiagnosticsButton(
                                  repository: widget.repository,
                                  store: widget.store,
                                  drama: widget.detail.drama,
                                )
                              : null,
                          icon: Icons.play_disabled_rounded,
                        ),
                      ),
                      if (errorKind != null &&
                          errorKind.suggestRoute &&
                          _routeCount > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextButton.icon(
                            onPressed: () =>
                                _openPanel(PlayerMenuSection.route),
                            icon: const Icon(Icons.route_outlined),
                            label: const Text('换线路'),
                          ),
                        ),
                      if (_lastPageUrl.isNotEmpty && !_localFailure)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: TextButton.icon(
                            onPressed: _openSniffer,
                            icon: const Icon(Icons.radar_rounded),
                            label: const Text('网页嗅探播放页'),
                          ),
                        ),
                    ],
                  ),
                ),
              if ((_loading || _error != null) &&
                  !hideOverlayForPictureInPicture &&
                  _showFullscreen &&
                  !_television)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '退出全屏',
                          onPressed: _rotate,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              _openPanel(PlayerMenuSection.episodes),
                          child: const Text('选集'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_saveWarning != null && !hideOverlayForPictureInPicture)
                Positioned(
                  top: 52,
                  left: 12,
                  right: 12,
                  child: SafeArea(
                    bottom: false,
                    child: Material(
                      color: const Color(0xE6322424),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _saveWarning!,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            TextButton(
                              onPressed: _saveProgress,
                              child: const Text('重试保存'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_mobile &&
                  !_television &&
                  !_useTvbox &&
                  !hideOverlayForPictureInPicture &&
                  !((_loading || _error != null) && _showFullscreen))
                Positioned(
                  top: 0,
                  left: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .36),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: IconButton(
                          key: const ValueKey('player-permanent-back'),
                          tooltip: '返回',
                          constraints: const BoxConstraints.tightFor(
                            width: 42,
                            height: 42,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: _backToList,
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 竖屏合一页（照 FongMi 手机版骨架）：播放器固定在上方，
  /// 下方单列滚动——片名→备注→站源→年份·类型→线路（同名跨站）→
  /// 选集横排→简介（3 行折叠）→相关推荐（站内 + 同名跨站双轨）。
  /// 选集永远在简介之前。
  Widget _mobilePlaybackPanel() {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const ValueKey('player-info-scroll'),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _playerInfoHeader(),
              _playerSourceRoutes(),
              _playerRouteQualityRow(),
              _playerEpisodeSection(),
              _playerSynopsisSection(),
              _playerDownloadRow(),
              _playerRelatedSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playerInfoHeader() {
    final drama = widget.detail.drama;
    final colors = Theme.of(context).colorScheme;
    final remark = [
      if (drama.releaseStatus.isNotEmpty && drama.releaseStatus != 'unknown')
        drama.releaseLabel,
      if (drama.episodes > 0) '共 ${drama.episodes} 集',
      '当前第 ${widget.detail.episodes[_index].number} 集',
    ].join(' · ');
    final meta = [
      if (drama.onlineDate.isNotEmpty) drama.onlineDate,
      if (drama.category.isNotEmpty) drama.category,
      if (drama.heat.isNotEmpty) '热度 ${drama.heat}',
      if (drama.views.isNotEmpty) '播放 ${drama.views}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          drama.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(remark, style: TextStyle(color: colors.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          '站源：${SourceSite.byId(drama.source).name}',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            meta.join(' · '),
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 10),
        _mobileFollowControl(drama),
        if (drama.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in drama.tags.take(12))
                Chip(label: Text(tag), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
      ],
    );
  }

  /// 线路区：同名跨站副本即换源 chips（有多站时才出现），
  /// 点一条在本页换到那个站的同片续播（集数对齐）。
  Widget _playerSourceRoutes() {
    final drama = widget.detail.drama;
    if (drama.peers.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '换源',
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final peer in drama.peers)
                ActionChip(
                  key: ValueKey('player-peer-${peer.source}'),
                  avatar: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text(
                    peer.episodes > 0
                        ? '${SourceSite.byId(peer.source).name} · ${peer.episodes} 集'
                        : SourceSite.byId(peer.source).name,
                  ),
                  onPressed: () =>
                      _openDramaInPlayer(peer, episodeIndex: _index),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _playerRouteQualityRow() {
    final routeCount = _routeCount;
    final qualities = _plan?.qualities ?? const <int>[];
    if (routeCount <= 1 && qualities.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (routeCount > 1)
            ActionChip(
              key: const ValueKey('player-info-route'),
              avatar: const Icon(Icons.alt_route_rounded, size: 16),
              label: Text(_routeLabel),
              onPressed: () => _openPanel(PlayerMenuSection.route),
            ),
          if (qualities.isNotEmpty)
            ActionChip(
              key: const ValueKey('player-info-quality'),
              avatar: const Icon(Icons.high_quality_rounded, size: 16),
              label: Text(_qualityLabel),
              onPressed: () => _openPanel(PlayerMenuSection.quality),
            ),
        ],
      ),
    );
  }

  Widget _playerEpisodeSection() {
    final episodes = widget.detail.episodes;
    final colors = Theme.of(context).colorScheme;
    final display = _episodesReversed ? episodes.reversed.toList() : episodes;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '选集',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                key: const ValueKey('episode-reverse'),
                tooltip: _episodesReversed ? '正序' : '倒序',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    setState(() => _episodesReversed = !_episodesReversed),
                icon: Icon(
                  _episodesReversed
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 18,
                ),
              ),
              if (episodes.length >= 10)
                TextButton(
                  key: const ValueKey('episode-more'),
                  onPressed: _showEpisodeGridSheet,
                  child: const Text('更多'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 42,
            child: ListView.separated(
              controller: _episodeStripController,
              scrollDirection: Axis.horizontal,
              itemCount: display.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final episode = display[i];
                final realIndex = episodes.indexOf(episode);
                final selected = realIndex == _index;
                return ChoiceChip(
                  key: ValueKey('episode-chip-$realIndex'),
                  label: Text(episode.title),
                  selected: selected,
                  onSelected: (_) {
                    if (selected) {
                      // 再点当前集 = 进全屏（FongMi 语义）
                      unawaited(_rotate());
                    } else {
                      _play(realIndex, showControlsOnReady: false);
                    }
                  },
                );
              },
            ),
          ),
          if (episodes[_index].vip)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '当前集为 VIP 试看',
                style: TextStyle(color: colors.error, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }

  void _showEpisodeGridSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.7,
        child: PlayerEpisodeGrid(
          episodes: widget.detail.episodes,
          currentIndex: _index,
          compact: true,
          title: '全部选集',
          onSelected: (index) {
            Navigator.of(sheetContext).pop();
            _play(index, showControlsOnReady: false);
          },
        ),
      ),
    );
  }

  Widget _playerSynopsisSection() {
    final drama = widget.detail.drama;
    final colors = Theme.of(context).colorScheme;
    final body = drama.description.trim().isEmpty
        ? '暂无简介'
        : drama.description.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '简介',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            key: const ValueKey('player-synopsis'),
            onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
            child: Text(
              body,
              maxLines: _synopsisExpanded ? null : 3,
              overflow: _synopsisExpanded ? null : TextOverflow.ellipsis,
              style: const TextStyle(height: 1.55),
            ),
          ),
          if (widget.detail.warning.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(widget.detail.warning, style: TextStyle(color: colors.error)),
          ],
        ],
      ),
    );
  }

  Widget _playerDownloadRow() {
    if (!widget.repository.supportsDownloads || !widget.store.canDownload) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: OutlinedButton.icon(
        key: const ValueKey('player-download-entry'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: _mobileDownload(),
          ),
        ),
        icon: const Icon(Icons.download_rounded, size: 18),
        label: const Text('下载本剧'),
      ),
    );
  }

  /// 相关区双轨：站内 related 图片卡打底 + 同名跨站卡片网格；
  /// 两轨都为空时整区不渲染。
  Widget _playerRelatedSection() {
    final related = widget.detail.related;
    final peers = widget.detail.drama.peers;
    if (related.isEmpty && peers.isEmpty) return const SizedBox.shrink();
    Widget grid(List<Drama> items, String keyPrefix, int episodeIndex) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 150).floor().clamp(2, 6);
          final tileWidth =
              (constraints.maxWidth - (columns - 1) * 10) / columns;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: DramaTile.extentFor(context, tileWidth),
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => DramaTile(
              key: ValueKey('$keyPrefix-${items[index].id}'),
              drama: items[index],
              repository: widget.repository,
              onTap: () =>
                  _openDramaInPlayer(items[index], episodeIndex: episodeIndex),
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (related.isNotEmpty) ...[
            Text(
              '相关推荐',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            grid(related, 'player-related', 0),
          ],
          if (peers.isNotEmpty) ...[
            if (related.isNotEmpty) const SizedBox(height: 18),
            Text(
              '同名跨站',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            grid(peers, 'player-peer-card', _index),
          ],
        ],
      ),
    );
  }

  /// 在本页换片：取目标详情后以新 PlayerScreen 替换当前路由，
  /// 播放器位置不变（同 FongMi selectSource / 点 quick 的体感）。
  Future<void> _openDramaInPlayer(
    Drama target, {
    required int episodeIndex,
  }) async {
    if (_closed) return;
    try {
      final detail = await widget.repository.detail(target);
      if (!mounted || _closed) return;
      final index = detail.episodes.isEmpty
          ? 0
          : episodeIndex.clamp(0, detail.episodes.length - 1);
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            detail: detail,
            initialIndex: index,
            repository: widget.repository,
            store: widget.store,
            playerFactory: widget.playerFactory,
            videoBuilder: widget.videoBuilder,
          ),
        ),
      );
    } on AppFailure catch (error) {
      if (mounted && !_closed) _notice(error.message);
    } catch (_) {
      if (mounted && !_closed) _notice('打开失败，请重试');
    }
  }

  Widget _mobileFollowControl(Drama drama) {
    final state = widget.store.following(drama.id);
    return PopupMenuButton<String>(
      key: const ValueKey('player-follow-status'),
      tooltip: '追剧与观看状态',
      onSelected: (value) async {
        if (_profileEpoch != widget.store.profileEpoch) return;
        if (value == 'remove') {
          await saveUserChange(
            context,
            () => widget.store.toggleFavorite(drama),
          );
        } else {
          final status = FollowStatus.values.firstWhere(
            (status) => status.name == value,
          );
          await saveUserChange(
            context,
            () => widget.store.setFollowStatus(drama, status),
          );
        }
        if (mounted && !_closed) setState(() {});
      },
      itemBuilder: (_) => [
        for (final status in FollowStatus.values)
          CheckedPopupMenuItem(
            value: status.name,
            checked: state?.status == status,
            child: Text(status.label),
          ),
        if (state != null)
          const PopupMenuItem(value: 'remove', child: Text('取消追剧')),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: state == null
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state == null
                  ? Icons.bookmark_add_outlined
                  : Icons.bookmark_rounded,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(state?.label ?? '加入追剧'),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _mobileDownload() {
    final colors = Theme.of(context).colorScheme;
    if (!widget.repository.supportsDownloads || !widget.store.canDownload) {
      return ColoredBox(
        color: colors.surface,
        child: const StatusPanel(
          title: '下载不可用',
          message: '当前用户或当前环境未开放本地下载。',
          icon: Icons.download_outlined,
        ),
      );
    }
    return DownloadPicker(
      detail: widget.detail,
      preferences: widget.store.downloadPreferences,
      embedded: true,
      onSubmit: _submitDownloadSelection,
    );
  }

  Widget _episodePanel({bool compact = false, VoidCallback? onClose}) {
    final panel = ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: PlayerEpisodeGrid(
        episodes: widget.detail.episodes,
        currentIndex: _index,
        compact: compact,
        title: compact ? '剧集' : '选集',
        onSelected: (index) => _play(index, showControlsOnReady: false),
      ),
    );
    if (compact || onClose == null) return panel;
    return Stack(
      fit: StackFit.expand,
      children: [
        panel,
        Positioned(
          top: 2,
          right: 4,
          child: IconButton(
            tooltip: '关闭选集',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
  }
}
