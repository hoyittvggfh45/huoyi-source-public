import 'package:duanju_app/danmaku_loader.dart';
import 'package:duanju_app/danmaku_models.dart';
import 'package:duanju_app/hongguo_codec.dart';
import 'package:duanju_app/hongguo_comment.dart';
import 'package:duanju_app/hongguo_playback_settings.dart';
import 'package:duanju_app/hongguo_resume.dart';
import 'package:duanju_app/hongguo_sleep_timer.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HongguoSleepTimer', () {
    test('afterMinutes counts down with the clock and stops once', () {
      var now = 1000000;
      final timer = HongguoSleepTimer(now: () => now);
      timer.afterMinutes(30);
      expect(timer.active, isTrue);
      expect(timer.label(), '30 分钟后');
      expect(timer.poll(), isFalse);
      now += 29 * 60000;
      expect(timer.label(), '1 分钟后');
      expect(timer.poll(), isFalse);
      now += 60000;
      expect(timer.poll(), isTrue);
      expect(timer.active, isFalse);
      expect(timer.label(), '关闭');
      expect(timer.poll(), isFalse);
    });

    test('afterEpisodes counts episode ends and stops at zero', () {
      final timer = HongguoSleepTimer(now: () => 0);
      timer.afterEpisodes(2);
      expect(timer.label(), '再播完 2 集');
      expect(timer.episodeEnded(), isFalse);
      expect(timer.episodesLeft, 1);
      expect(timer.episodeEnded(), isTrue);
      expect(timer.active, isFalse);
    });

    test('minute deadline also fires through episodeEnded', () {
      var now = 0;
      final timer = HongguoSleepTimer(now: () => now);
      timer.afterMinutes(1);
      expect(timer.episodeEnded(), isFalse);
      now += 60000;
      expect(timer.episodeEnded(), isTrue);
    });

    test('out of range values are rejected', () {
      final timer = HongguoSleepTimer(now: () => 0);
      expect(() => timer.afterMinutes(0), throwsArgumentError);
      expect(() => timer.afterMinutes(181), throwsArgumentError);
      expect(() => timer.afterEpisodes(0), throwsArgumentError);
      expect(() => timer.afterEpisodes(11), throwsArgumentError);
      expect(timer.active, isFalse);
    });
  });

  group('hongguoResumeTarget', () {
    const ids = ['a', 'b', 'c'];

    test('completed episode moves to the next one at zero', () {
      final target = hongguoResumeTarget(
        episodeIds: ids,
        episodeId: 'a',
        position: 55,
        completed: true,
      );
      expect(target.index, 1);
      expect(target.position, 0);
    });

    test('completed last episode stays on the last one at zero', () {
      final target = hongguoResumeTarget(
        episodeIds: ids,
        episodeId: 'c',
        position: 55,
        completed: true,
      );
      expect(target.index, 2);
      expect(target.position, 0);
    });

    test('unfinished episode resumes in place', () {
      final target = hongguoResumeTarget(
        episodeIds: ids,
        episodeId: 'b',
        position: 42,
      );
      expect(target.index, 1);
      expect(target.position, 42);
    });

    test('unknown episode falls back to the first one', () {
      final target = hongguoResumeTarget(
        episodeIds: ids,
        episodeId: 'zzz',
        position: 10,
      );
      expect(target.index, 0);
      expect(target.position, 0);
    });
  });

  group('hongguoResumeProgress', () {
    const ids = ['a', 'b', 'c'];
    final localTime = DateTime(2026, 11, 11, 10);
    final cloudTime = DateTime(2026, 11, 11, 12);

    test('local only returns the local episode', () {
      final target = hongguoResumeProgress(
        episodeIds: ids,
        seriesId: 's1',
        localIndex: 1,
        localPosition: 30,
        localUpdatedAt: localTime,
      );
      expect(target?.index, 1);
      expect(target?.position, 30);
    });

    test('newer cloud progress wins, same time prefers local', () {
      final cloud = HongguoCloudProgress(
        seriesId: 's1',
        episodeId: 'c',
        episodeIndex: 2,
        position: 5,
        duration: 60,
        updatedAt: cloudTime,
      );
      final newer = hongguoResumeProgress(
        episodeIds: ids,
        seriesId: 's1',
        localIndex: 1,
        localPosition: 30,
        localUpdatedAt: localTime,
        cloud: cloud,
      );
      expect(newer?.index, 2);
      final tie = hongguoResumeProgress(
        episodeIds: ids,
        seriesId: 's1',
        localIndex: 1,
        localPosition: 30,
        localUpdatedAt: cloudTime,
        cloud: cloud,
      );
      expect(tie?.index, 1);
    });

    test('preferCloud takes the cloud record', () {
      final cloud = HongguoCloudProgress(
        seriesId: 's1',
        episodeId: 'c',
        episodeIndex: 2,
        position: 5,
        duration: 60,
        updatedAt: localTime,
      );
      final target = hongguoResumeProgress(
        episodeIds: ids,
        seriesId: 's1',
        localIndex: 1,
        localPosition: 30,
        localUpdatedAt: cloudTime,
        cloud: cloud,
        preferCloud: true,
      );
      expect(target?.index, 2);
    });

    test('cloud episode id miss falls back to its episode index', () {
      final cloud = HongguoCloudProgress(
        seriesId: 's1',
        episodeId: 'missing',
        episodeIndex: 2,
        position: 7,
        duration: 60,
        updatedAt: cloudTime,
      );
      final target = hongguoResumeProgress(
        episodeIds: ids,
        seriesId: 's1',
        cloud: cloud,
      );
      expect(target?.index, 2);
      expect(target?.position, 7);
    });

    test('cloud record for another series is ignored', () {
      final cloud = HongguoCloudProgress(
        seriesId: 'other',
        episodeId: 'c',
        episodeIndex: 2,
        position: 7,
        duration: 60,
        updatedAt: cloudTime,
      );
      final target = hongguoResumeProgress(
        episodeIds: ids,
        seriesId: 's1',
        localIndex: 0,
        localPosition: 3,
        localUpdatedAt: localTime,
        cloud: cloud,
      );
      expect(target?.index, 0);
    });
  });

  group('HongguoDecoderLessons', () {
    test('remembered failures block that quality only', () {
      final lessons = HongguoDecoderLessons();
      expect(lessons.fails('h264', 1080), isFalse);
      lessons.remember('h264', 1080);
      expect(lessons.fails('h264', 1080), isTrue);
      expect(lessons.fails('h264', 720), isFalse);
      expect(lessons.fails('hevc', 1080), isFalse);
      expect(lessons.size, 1);
    });

    test('sizeless verdict covers the whole codec', () {
      final lessons = HongguoDecoderLessons();
      lessons.remember('h264', null);
      expect(lessons.fails('h264', 720), isTrue);
    });

    test('restore and reset round trip', () {
      final lessons = HongguoDecoderLessons();
      lessons.restore({'h264|720', 'hevc'});
      expect(lessons.fails('h264', 720), isTrue);
      expect(lessons.fails('hevc', 1080), isTrue);
      expect(lessons.keys(), {'h264|720', 'hevc'});
      lessons.reset();
      expect(lessons.size, 0);
    });
  });

  group('HongguoCodecCapabilities', () {
    test('effectiveQuality drops to the highest supported at or below', () {
      final lessons = HongguoDecoderLessons();
      lessons.remember('h264', 1080);
      expect(
        HongguoCodecCapabilities.effectiveQuality(
          1080,
          [1080, 720, 480],
          lessons,
        ),
        720,
      );
      expect(
        HongguoCodecCapabilities.effectiveQuality(
          0,
          [1080, 720, 480],
          lessons,
        ),
        720,
      );
      expect(
        HongguoCodecCapabilities.effectiveQuality(
          480,
          [1080, 720, 480],
          lessons,
        ),
        480,
      );
    });

    test('no supported quality falls back to auto', () {
      final lessons = HongguoDecoderLessons();
      for (final quality in [1080, 720, 480]) {
        lessons.remember('h264', quality);
      }
      expect(
        HongguoCodecCapabilities.effectiveQuality(
          1080,
          [1080, 720, 480],
          lessons,
        ),
        0,
      );
    });

    test('normalizeQuality keeps known options and maps the rest to auto', () {
      expect(HongguoCodecCapabilities.normalizeQuality(720), 720);
      expect(HongguoCodecCapabilities.normalizeQuality(1440), 0);
      expect(HongguoCodecCapabilities.normalizeQuality(0), 0);
    });

    test('low end cap drops to 720 once 1080 has failed', () {
      final lessons = HongguoDecoderLessons();
      expect(HongguoCodecCapabilities.lowEndCap(lessons), 1080);
      lessons.remember('h264', 1080);
      expect(HongguoCodecCapabilities.lowEndCap(lessons), 720);
    });

    test('decode failure classifier only matches decoder wording', () {
      expect(
        HongguoCodecCapabilities.looksLikeDecodeFailure(
          'Failed to initialize decoder',
        ),
        isTrue,
      );
      expect(
        HongguoCodecCapabilities.looksLikeDecodeFailure('codec not supported'),
        isTrue,
      );
      expect(
        HongguoCodecCapabilities.looksLikeDecodeFailure(
          'HTTP 403: request failed',
        ),
        isFalse,
      );
      expect(
        HongguoCodecCapabilities.looksLikeDecodeFailure('connection timeout'),
        isFalse,
      );
    });
  });

  group('HongguoPlaybackSettings', () {
    test('json round trip keeps every field', () {
      const settings = HongguoPlaybackSettings(
        frameMode: HongguoFrameMode.fill,
        rotationQuarters: 1,
        alwaysShowProgress: true,
        seasonAutoplay: true,
      );
      final restored = HongguoPlaybackSettings.fromJson(settings.toJson());
      expect(restored.frameMode, HongguoFrameMode.fill);
      expect(restored.rotationQuarters, 1);
      expect(restored.alwaysShowProgress, isTrue);
      expect(restored.seasonAutoplay, isTrue);
    });

    test('unknown stored values fall back to defaults', () {
      final restored = HongguoPlaybackSettings.fromJson({
        'frameMode': 'sideways',
        'rotationQuarters': 7,
        'alwaysShowProgress': 'yes',
      });
      expect(restored.frameMode, HongguoFrameMode.fit);
      expect(restored.rotationQuarters, 3);
      expect(restored.alwaysShowProgress, isFalse);
      expect(restored.seasonAutoplay, isFalse);
    });

    test('frame modes map to the matching box fit', () {
      expect(HongguoFrameMode.fit.boxFit, BoxFit.contain);
      expect(HongguoFrameMode.zoom.boxFit, BoxFit.cover);
      expect(HongguoFrameMode.fill.boxFit, BoxFit.fill);
      expect(HongguoFrameMode.fit.label, '完整画面');
      expect(HongguoFrameMode.zoom.label, '等比铺满');
      expect(HongguoFrameMode.fill.label, '拉伸铺满');
    });
  });

  group('HongguoCommentPage', () {
    test('fromJson maps counts and score fields', () {
      final page = HongguoCommentPage.fromJson({
        'items': [
          {
            'id': 'c1',
            'text': '好看',
            'userName': '道友',
            'avatar': '',
            'timeSec': 1700000000,
          },
        ],
        'cursor': 'next',
        'hasMore': true,
        'total': 12,
        'collectorsCount': 34,
        'score': 8.6,
        'scoreCount': 56,
      });
      expect(page.items.length, 1);
      expect(page.items.first.text, '好看');
      expect(page.cursor, 'next');
      expect(page.hasMore, isTrue);
      expect(page.total, 12);
      expect(page.collectorsCount, 34);
      expect(page.score, 8.6);
      expect(page.scoreCount, 56);
    });
  });

  group('DanmakuLoader window advance', () {
    const plan = PlaybackPlan(
      url: 'https://media.example.test/synthetic.mp4',
      session: 'current',
      danmakuId: '1001',
    );

    Future<DanmakuPage> pageFor(int start) async {
      return DanmakuPage.fromJson(
        {
          'episodeId': '1001',
          'startMs': start,
          'nextMs': start + 30000,
          'items': [
            {'id': 'd$start', 'text': '弹幕', 'timeMs': start + 1000},
          ],
        },
        episodeId: '1001',
        startMs: start,
        durationMs: 180000,
      );
    }

    test('advances to the next window near the end of the current one', () async {
      var positionMs = 0;
      var moving = true;
      final requested = <int>[];
      final loader = DanmakuLoader(
        state: () => DanmakuWindowState(
          visible: true,
          buffering: false,
          positionMs: positionMs,
          moving: moving,
          durationMs: 180000,
          plan: plan,
        ),
        loadPage: (loadedPlan, start, duration) async {
          requested.add(start);
          return pageFor(start);
        },
        cancelLoad: () async {},
        onItems: (_) {},
        onChanged: () {},
      );
      loader.ensureWindow();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(requested, [0]);
      positionMs = 25000;
      loader.ensureWindow();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(requested, [0, 30000]);
      expect(moving, isTrue);
    });

    test('jump into an uncovered gap loads the gap window', () async {
      var positionMs = 0;
      final requested = <int>[];
      final loader = DanmakuLoader(
        state: () => DanmakuWindowState(
          visible: true,
          buffering: false,
          positionMs: positionMs,
          moving: true,
          durationMs: 180000,
          plan: plan,
        ),
        loadPage: (loadedPlan, start, duration) async {
          requested.add(start);
          return pageFor(start);
        },
        cancelLoad: () async {},
        onItems: (_) {},
        onChanged: () {},
      );
      loader.ensureWindow();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(requested, [0]);
      positionMs = 45000;
      loader.ensureWindow();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(requested, [0, 30000]);
    });
  });
}
