import 'dart:async';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/next_film_preloader.dart';
import 'package:duanju_app/playback_queue.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class _FakeFilmRepository extends FixtureRepository {
  final preloadCalls = <Drama>[];
  final released = <String>[];
  bool failPreload = false;
  PlaybackPlan? preloadResult;
  Completer<void>? detailGate;

  @override
  Future<DramaDetail> detail(Drama drama) async {
    final gate = detailGate;
    if (gate != null) await gate.future;
    return super.detail(drama);
  }

  @override
  Future<PlaybackPlan?> preload(
    Drama drama,
    Episode episode, {
    int quality = 0,
    bool online = false,
    int route = 0,
    bool adBlock = true,
  }) async {
    preloadCalls.add(drama);
    if (failPreload) throw AppFailure('合成预加载失败');
    return preloadResult ??
        PlaybackPlan(
          url: 'https://example.test/next.mp4',
          session: 'next-session',
          prefetchedBytes: 4096,
          expiresAt:
              DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        );
  }

  @override
  Future<void> release(String session) async {
    released.add(session);
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('prepares the next film and hands it over on take', () async {
    final repository = _FakeFilmRepository();
    final preloader = NextFilmPreloader(
      repository,
      (_) => null,
      delay: Duration.zero,
    );
    final queue = PlaybackQueue.around(
      [FixtureRepository.free, FixtureRepository.vip],
      FixtureRepository.free,
    );
    preloader.prepare(queue);
    await _settle();
    final ready = preloader.take(FixtureRepository.vip);
    expect(ready, isNotNull);
    expect(ready!.detail.drama.id, FixtureRepository.vip.id);
    expect(ready.episode.id, '1');
    expect(ready.plan.url, isNotEmpty);
    expect(ready.plan.prefetchedBytes, 4096);
    expect(preloader.take(FixtureRepository.vip), isNull);
  });

  test('does nothing when the queue has no next film', () async {
    final repository = _FakeFilmRepository();
    final preloader = NextFilmPreloader(
      repository,
      (_) => null,
      delay: Duration.zero,
    );
    final queue = PlaybackQueue.around(
      [FixtureRepository.free, FixtureRepository.vip],
      FixtureRepository.vip,
    );
    preloader.prepare(queue);
    await _settle();
    expect(repository.detailCalls, 0);
    expect(repository.preloadCalls, isEmpty);
  });

  test('take with a different film keeps the bundle', () async {
    final repository = _FakeFilmRepository();
    final preloader = NextFilmPreloader(
      repository,
      (_) => null,
      delay: Duration.zero,
    );
    final queue = PlaybackQueue.around(
      [FixtureRepository.free, FixtureRepository.vip],
      FixtureRepository.free,
    );
    preloader.prepare(queue);
    await _settle();
    expect(preloader.take(FixtureRepository.free), isNull);
    expect(preloader.take(FixtureRepository.vip), isNotNull);
  });

  test('preload failure is silent and retried only after the backoff', () async {
    final repository = _FakeFilmRepository()..failPreload = true;
    final preloader = NextFilmPreloader(
      repository,
      (_) => null,
      delay: Duration.zero,
    );
    final queue = PlaybackQueue.around(
      [FixtureRepository.free, FixtureRepository.vip],
      FixtureRepository.free,
    );
    preloader.prepare(queue);
    await _settle();
    expect(preloader.take(FixtureRepository.vip), isNull);
    preloader.prepare(queue);
    await _settle();
    expect(repository.preloadCalls, hasLength(1));
  });

  test('concurrent prepares resolve only once', () async {
    final repository = _FakeFilmRepository()
      ..detailGate = Completer<void>();
    final preloader = NextFilmPreloader(
      repository,
      (_) => null,
      delay: Duration.zero,
    );
    final queue = PlaybackQueue.around(
      [FixtureRepository.free, FixtureRepository.vip],
      FixtureRepository.free,
    );
    preloader.prepare(queue);
    preloader.prepare(queue);
    repository.detailGate!.complete();
    await _settle();
    expect(repository.detailCalls, 1);
    expect(repository.preloadCalls, hasLength(1));
  });

  test('expired plan is released instead of handed over', () async {
    final repository = _FakeFilmRepository()
      ..preloadResult = PlaybackPlan(
        url: 'https://example.test/next.mp4',
        session: 'stale-session',
        expiresAt:
            DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      );
    final preloader = NextFilmPreloader(
      repository,
      (_) => null,
      delay: Duration.zero,
    );
    final queue = PlaybackQueue.around(
      [FixtureRepository.free, FixtureRepository.vip],
      FixtureRepository.free,
    );
    preloader.prepare(queue);
    await _settle();
    expect(preloader.take(FixtureRepository.vip), isNull);
    expect(repository.released, contains('stale-session'));
  });

  test('switching target releases the previous plan', () async {
    final repository = _FakeFilmRepository();
    final preloader = NextFilmPreloader(
      repository,
      (_) => null,
      delay: Duration.zero,
    );
    final third = Drama(
      id: 'test:300',
      source: 'test',
      title: '第三部',
      episodes: 1,
    );
    final firstQueue = PlaybackQueue.around(
      [FixtureRepository.free, FixtureRepository.vip],
      FixtureRepository.free,
    );
    preloader.prepare(firstQueue);
    await _settle();
    final secondQueue = PlaybackQueue.around(
      [FixtureRepository.free, FixtureRepository.vip, third],
      FixtureRepository.vip,
    );
    preloader.prepare(secondQueue);
    await _settle();
    expect(repository.released, contains('next-session'));
    expect(preloader.take(third), isNotNull);
  });
}
