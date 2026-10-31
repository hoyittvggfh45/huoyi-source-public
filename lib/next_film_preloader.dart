import 'dart:async';

import 'core_bridge.dart';
import 'follow_state.dart';
import 'models.dart';
import 'playback_queue.dart';

class NextFilmReady {
  const NextFilmReady({
    required this.detail,
    required this.episode,
    required this.plan,
  });

  final DramaDetail detail;
  final Episode episode;
  final PlaybackPlan plan;
}

class NextFilmPreloader {
  NextFilmPreloader(
    this.repository,
    this.watched, {
    DateTime Function()? now,
    Duration delay = const Duration(milliseconds: 600),
  }) : _now = now ?? DateTime.now,
       _delayDuration = delay;

  final AppRepository repository;
  final WatchEntry? Function(String dramaId) watched;
  final DateTime Function() _now;
  final Duration _delayDuration;
  NextFilmReady? _ready;
  String? _identity;
  Timer? _delay;
  DateTime _expires = DateTime(2000), _retryAt = DateTime(2000);
  int _generation = 0;
  bool _closed = false, loading = false;

  bool get busy => loading || _delay != null;

  void _release(PlaybackPlan plan) =>
      unawaited(repository.release(plan.session).catchError((Object _) {}));

  String _key(Drama drama, int quality, int route, bool adBlock) =>
      '${drama.source}\u0000${drama.id}\u0000$quality\u0000$route\u0000$adBlock';

  void prepare(
    PlaybackQueue queue, {
    int quality = 0,
    int route = 0,
    bool adBlock = true,
  }) {
    if (_closed) return;
    final target = queue.neighbor(1);
    if (target == null) {
      clear();
      return;
    }
    final identity = _key(target, quality, route, adBlock);
    if (_identity != identity) {
      clear();
      _identity = identity;
    }
    if (_ready != null && !_now().isBefore(_expires)) {
      final expired = _ready!;
      _ready = null;
      _release(expired.plan);
    }
    if (_ready != null ||
        loading ||
        _delay != null ||
        _now().isBefore(_retryAt)) {
      return;
    }
    final ticket = _generation;
    _delay = Timer(_delayDuration, () async {
      _delay = null;
      loading = true;
      try {
        final detail = await repository.detail(target);
        if (_closed || ticket != _generation) return;
        if (detail.episodes.isEmpty) {
          throw AppFailure('下一部暂无可播放集数');
        }
        final index = resumeEpisodeIndex(
          detail.episodes,
          watched(target.id),
        );
        final episode = detail.episodes[index];
        final plan = await repository.preload(
          target,
          episode,
          quality: quality,
          route: route,
          adBlock: adBlock,
        );
        if (_closed || ticket != _generation) {
          if (plan != null) _release(plan);
          return;
        }
        if (plan == null || plan.url.isEmpty) {
          throw AppFailure('未取得下一部播放地址');
        }
        var expires = _now().add(const Duration(minutes: 2));
        if (plan.expiresAt > 0) {
          final authorizationExpiry =
              DateTime.fromMillisecondsSinceEpoch(
                plan.expiresAt,
              ).subtract(const Duration(seconds: 5));
          if (authorizationExpiry.isBefore(expires)) {
            expires = authorizationExpiry;
          }
        }
        if (!expires.isAfter(_now())) {
          _release(plan);
          throw AppFailure('下一部播放凭证即将过期');
        }
        _ready = NextFilmReady(detail: detail, episode: episode, plan: plan);
        _expires = expires;
      } catch (_) {
        if (_closed || ticket != _generation) return;
        _retryAt = _now().add(const Duration(seconds: 30));
      } finally {
        if (!_closed && ticket == _generation) loading = false;
      }
    });
  }

  NextFilmReady? take(Drama target) {
    final ready = _ready;
    if (ready == null) return null;
    if (ready.detail.drama.id != target.id ||
        ready.detail.drama.source != target.source ||
        !_now().isBefore(_expires)) {
      if (ready.detail.drama.id == target.id &&
          ready.detail.drama.source == target.source) {
        _ready = null;
        _release(ready.plan);
        _identity = null;
      }
      return null;
    }
    _ready = null;
    clear();
    return ready;
  }

  void pause() {
    _generation++;
    _delay?.cancel();
    _delay = null;
    loading = false;
  }

  void clear() {
    pause();
    final old = _ready;
    _ready = null;
    _identity = null;
    _retryAt = DateTime(2000);
    if (old != null) _release(old.plan);
  }

  void dispose() {
    _closed = true;
    clear();
  }
}
