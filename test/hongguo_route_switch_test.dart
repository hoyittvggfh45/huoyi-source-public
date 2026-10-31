import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

PlaybackPlan planForRoute(int route, {String danmakuId = ''}) =>
    PlaybackPlan(
      url: 'https://example.test/route$route.m3u8',
      session: 'session-$route',
      routeIndex: route,
      routeCount: hongguoTotalRoutes,
      danmakuId: danmakuId,
    );

void main() {
  group('hongguoRouteTrialOrder', () {
    test('mainland default follows the fixed route table', () {
      expect(
        hongguoRouteTrialOrder(start: 0, oversea: false),
        [0, 1, 2, 3, 4, 5, 6],
      );
    });

    test('oversea default starts on the oversea line', () {
      expect(
        hongguoRouteTrialOrder(start: 0, oversea: true),
        [1, 0, 2, 3, 4, 5, 6],
      );
    });

    test('trial starts at the requested route and wraps to untried routes', () {
      expect(
        hongguoRouteTrialOrder(start: 3, oversea: false),
        [3, 4, 5, 6, 0, 1, 2],
      );
    });

    test('fast routes go first and failed routes sink to the bottom', () {
      final order = hongguoRouteTrialOrder(
        start: 0,
        oversea: false,
        latencies: {
          4: const Duration(milliseconds: 900),
          0: const Duration(milliseconds: 300),
          2: const Duration(milliseconds: 600),
        },
        failed: {1, 5},
      );
      expect(order.sublist(0, 3), [0, 2, 4]);
      expect(order.sublist(3, 5), [3, 6]);
      expect(order.sublist(5), [1, 5]);
    });

    test('tracker records success latency and failure sink', () {
      final tracker = HongguoRouteSpeedTracker();
      tracker.recordSuccess(3, const Duration(milliseconds: 200));
      tracker.recordSuccess(0, const Duration(milliseconds: 800));
      tracker.recordFailure(1);
      expect(tracker.order(start: 3, oversea: false).first, 3);
      expect(tracker.order(start: 3, oversea: false).last, 1);
      expect(tracker.order(start: 0, oversea: false).first, 0);
      tracker.recordSuccess(1, const Duration(milliseconds: 100));
      expect(tracker.order(start: 1, oversea: false).first, 1);
      expect(tracker.failed, isEmpty);
    });
  });

  group('hongguoRoutePlanMatches', () {
    test('accepts the requested episode on the requested route', () {
      expect(
        hongguoRoutePlanMatches(planForRoute(2, danmakuId: '456'), '456', 2),
        isTrue,
      );
    });

    test('rejects a plan for another episode', () {
      expect(
        hongguoRoutePlanMatches(planForRoute(2, danmakuId: '999'), '456', 2),
        isFalse,
      );
    });

    test('rejects a plan from another route and an empty url', () {
      expect(
        hongguoRoutePlanMatches(planForRoute(3, danmakuId: '456'), '456', 2),
        isFalse,
      );
      expect(
        hongguoRoutePlanMatches(
          const PlaybackPlan(url: '', routeIndex: 2, routeCount: 7),
          '456',
          2,
        ),
        isFalse,
      );
    });
  });

  group('hongguoTryRoutesSequentially', () {
    test('first failure moves to the next route and stops at success', () async {
      final tracker = HongguoRouteSpeedTracker();
      final attempted = <int>[];
      final result = await hongguoTryRoutesSequentially(
        [0, 1, 2],
        (route) async {
          attempted.add(route);
          if (route == 0) throw AppFailure('大陆线无地址');
          return planForRoute(route);
        },
        tracker,
      );
      expect(attempted, [0, 1]);
      expect(result.plan?.routeIndex, 1);
      expect(result.failures, {0: '大陆线无地址'});
      expect(tracker.failed, {0});
      expect(tracker.latencies.containsKey(1), isTrue);
    });

    test('empty url counts as a failure and the next route is tried', () async {
      final tracker = HongguoRouteSpeedTracker();
      final result = await hongguoTryRoutesSequentially(
        [0, 1],
        (route) async => route == 0
            ? const PlaybackPlan(url: '', routeIndex: 0, routeCount: 7)
            : planForRoute(1),
        tracker,
      );
      expect(result.plan?.routeIndex, 1);
      expect(result.failures[0], contains('未返回可播放地址'));
    });

    test('all failures report every route once and never loop', () async {
      final tracker = HongguoRouteSpeedTracker();
      final attempted = <int>[];
      final result = await hongguoTryRoutesSequentially(
        [0, 1, 2, 3, 4, 5, 6],
        (route) async {
          attempted.add(route);
          if (route == 6) {
            throw AppFailure('桥接线路解析失败：桥接服务不可达');
          }
          throw AppFailure('线路$route失败');
        },
        tracker,
      );
      expect(result.plan, isNull);
      expect(attempted, [0, 1, 2, 3, 4, 5, 6]);
      expect(result.failures.length, 7);
      final text = hongguoRouteFailuresText(result.failures, attempted);
      expect(text, contains('线路1 App大陆线失败'));
      expect(text, contains('线路7 桥接线失败：桥接线路解析失败'));
    });

    test('attempts never run in parallel', () async {
      final tracker = HongguoRouteSpeedTracker();
      var running = 0;
      var peak = 0;
      final result = await hongguoTryRoutesSequentially(
        [0, 1, 2, 3],
        (route) async {
          running++;
          peak = peak < running ? running : peak;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
          if (route < 3) throw AppFailure('fail $route');
          return planForRoute(route);
        },
        tracker,
      );
      expect(peak, 1);
      expect(result.plan?.routeIndex, 3);
    });
  });
}
