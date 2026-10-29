import 'package:flutter/foundation.dart';

import 'core_bridge.dart';
import 'danmaku_loader.dart';
import 'danmaku_models.dart';
import 'danmaku_time_sync.dart';
import 'models.dart';

class DanmakuController extends ChangeNotifier {
  DanmakuController(
    this.repository, {
    DateTime Function()? now,
    this.commentPage,
  }) : _now = now ?? DateTime.now {
    _loader = DanmakuLoader(
      now: _now,
      state: () => DanmakuWindowState(
        visible: _sourceVisible,
        buffering: _buffering,
        positionMs: positionMs,
        moving: moving,
        durationMs: durationMs,
        plan: _plan,
      ),
      loadPage: (plan, start, duration) =>
          repository.danmaku(plan, startMs: start, durationMs: duration),
      cancelLoad: () => repository.cancelDanmaku(),
      onItems: (list) {
        _sourceItems = list;
        dataRevision++;
      },
      onChanged: notifyListeners,
    );
    _sync = DanmakuTimeSync(now: _now);
  }

  final AppRepository repository;
  final DateTime Function() _now;
  final DanmakuLoadPage? commentPage;
  late final DanmakuLoader _loader;
  late final DanmakuTimeSync _sync;
  DanmakuLoader? _commentLoader;
  String? _commentVideoKey;
  PlaybackPlan? _plan;
  bool _closed = false;
  bool _enabled = true;
  bool _available = false;
  bool _foreground = true;
  bool _playing = false;
  bool _buffering = false;
  bool _seeking = false;
  DateTime _lastPositionNotification = DateTime.fromMillisecondsSinceEpoch(0);
  int positionMs = 0;
  int durationMs = 0;
  double rate = 1;
  int motionRevision = 0;
  int dataRevision = 0;
  List<DanmakuItem> _sourceItems = const [];
  List<DanmakuItem> _commentItems = const [];
  List<DanmakuItem> _liveCommentItems = const [];

  List<DanmakuItem> get items => [
    ..._sourceItems,
    ..._commentItems,
    ..._liveCommentItems,
  ];

  bool get supported =>
      _plan != null &&
      !_plan!.local &&
      _plan!.session.isNotEmpty &&
      _plan!.danmakuId.isNotEmpty;
  bool get _sourceVisible =>
      !_closed &&
      supported &&
      _enabled &&
      _available &&
      _foreground &&
      !_seeking &&
      durationMs > 0 &&
      positionMs < durationMs;

  bool get _commentVisible =>
      !_closed &&
      _commentVideoKey != null &&
      commentPage != null &&
      _enabled &&
      _available &&
      _foreground &&
      !_seeking &&
      durationMs > 0 &&
      positionMs < durationMs;

  bool get visible => _sourceVisible || _commentVisible;
  bool get moving => visible && _playing && !_buffering;
  bool get loading => _loader.loading;
  bool get canRetry =>
      visible && (_loader.hasFailures || (_commentLoader?.hasFailures ?? false));
  String get status {
    if (!_enabled) return '弹幕已关闭';
    if (_plan?.local == true) return '本地播放不加载弹幕';
    if (_commentVideoKey != null && !supported) {
      if (canRetry) return '评论暂不可用，可重试';
      final commentLoader = _commentLoader;
      if ((commentLoader?.loading ?? false) &&
          !(commentLoader?.hasPages ?? false)) {
        return '正在加载评论';
      }
      if (commentLoader?.hasPages ?? false) {
        return items.isEmpty ? '这段暂无评论' : '已载入 ${items.length} 条评论';
      }
      return '等待播放';
    }
    if (_plan != null && !supported) return '本集暂不支持弹幕';
    if (canRetry) return '弹幕暂不可用，可重试';
    if (loading && !_loader.hasPages) return '正在加载弹幕';
    if (_loader.hasPages) {
      return items.isEmpty ? '这段暂无弹幕' : '已载入 ${items.length} 条弹幕';
    }
    return '等待播放';
  }

  void setPlan(PlaybackPlan? plan) {
    if (_closed || identical(_plan, plan)) return;
    _cancel();
    _plan = plan;
    _loader.clearPages();
    _seeking = false;
    _available = false;
    positionMs = durationMs = 0;
    _resetMotion();
    notifyListeners();
  }

  void setCommentVideoKey(String? videoKey) {
    if (_closed || _commentVideoKey == videoKey) return;
    _commentLoader?.cancel();
    _commentLoader = null;
    _commentItems = const [];
    _commentVideoKey = videoKey;
    final page = commentPage;
    if (videoKey != null && page != null) {
      _commentLoader = DanmakuLoader(
        state: () => DanmakuWindowState(
          visible: _commentVisible,
          buffering: _buffering,
          positionMs: positionMs,
          moving: moving,
          durationMs: durationMs,
          plan: PlaybackPlan(url: '', danmakuId: videoKey),
        ),
        loadPage: page,
        cancelLoad: () async {},
        onItems: (list) {
          _commentItems = list;
          dataRevision++;
        },
        onChanged: notifyListeners,
      );
    }
    dataRevision++;
    notifyListeners();
    _ensureWindow();
  }

  void addCommentItem(DanmakuItem item) {
    if (_closed) return;
    if (_liveCommentItems.any((entry) => entry.id == item.id)) return;
    _liveCommentItems = [..._liveCommentItems, item];
    dataRevision++;
    notifyListeners();
  }

  void setEnabled(bool enabled) {
    if (_closed || _enabled == enabled) return;
    _enabled = enabled;
    _cancel();
    _loader.clearPages();
    _commentLoader?.clearPages();
    _resetMotion();
    notifyListeners();
    _ensureWindow();
  }

  void update({
    required Duration position,
    required Duration duration,
    required double speed,
    required bool playing,
    required bool buffering,
    required bool foreground,
    required bool available,
    bool discontinuity = false,
  }) {
    if (_closed) return;
    final wasVisible = visible, wasMoving = moving;
    final previousRate = rate;
    final nextPosition = position.inMilliseconds.clamp(0, danmakuMaxDurationMs);
    final nextDuration = duration.inMilliseconds;
    final expected = _sync.expectedPosition();
    final drift = !_seeking && (nextPosition - expected).abs() > 600;
    final durationChanged = nextDuration != durationMs && durationMs > 0;
    final jumped =
        !_seeking &&
        (discontinuity ||
            nextPosition < positionMs ||
            nextPosition - positionMs > 2000);
    if (durationChanged) {
      _cancel();
      _loader.clearPages();
    } else if (jumped) {
      _cancel();
    }
    if (!_seeking) positionMs = nextPosition;
    durationMs = nextDuration > 0 && nextDuration <= danmakuMaxDurationMs
        ? nextDuration
        : 0;
    rate = speed.isFinite && speed > 0 ? speed : 1;
    _playing = playing;
    _buffering = buffering;
    _foreground = foreground;
    _available = available;
    if (wasVisible && !visible) _cancel();
    final motionChanged =
        drift ||
        jumped ||
        durationChanged ||
        wasVisible != visible ||
        wasMoving != moving ||
        previousRate != rate;
    if (motionChanged) {
      _resetMotion();
    }
    final now = _now();
    if (motionChanged ||
        moving &&
            items.isNotEmpty &&
            now.difference(_lastPositionNotification).inMilliseconds >= 250) {
      _lastPositionNotification = now;
      notifyListeners();
    }
    _ensureWindow();
  }

  void beginSeek() {
    if (_closed) return;
    _cancel();
    _seeking = true;
    _resetMotion();
    notifyListeners();
  }

  void endSeek(Duration position) {
    if (_closed) return;
    _seeking = false;
    positionMs = position.inMilliseconds.clamp(0, danmakuMaxDurationMs);
    _resetMotion();
    notifyListeners();
    _ensureWindow();
  }

  void retry() {
    if (_closed || !visible) return;
    _loader.clearFailures();
    _commentLoader?.clearFailures();
    _ensureWindow();
    notifyListeners();
  }

  void _resetMotion() {
    motionRevision++;
    _sync.reset(positionMs: positionMs, rate: rate, moving: moving);
  }

  void _cancel() {
    _loader.cancel();
    _commentLoader?.cancel();
  }

  void _ensureWindow() {
    _loader.ensureWindow();
    _commentLoader?.ensureWindow();
  }

  @override
  void dispose() {
    _closed = true;
    _cancel();
    super.dispose();
  }
}
