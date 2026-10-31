import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hongguoBridgeResolveUrl', () {
    test('assembles the local bridge resolve endpoint', () {
      expect(
        hongguoBridgeResolveUrl('127.0.0.1', 8917),
        'http://127.0.0.1:8917/resolve',
      );
      expect(
        hongguoBridgeResolveUrl('192.168.1.2', 9999),
        'http://192.168.1.2:9999/resolve',
      );
    });
  });

  group('hongguoBridgePlanFromJson', () {
    test('maps a node bridge response with route fields and marker session', () {
      final plan = hongguoBridgePlanFromJson(
        {
          'url': 'https://example.test/play.m3u8',
          'headers': {
            'User-Agent': 'hongguo-test',
            'Referer': 'https://example.test/',
          },
          'referer': 'https://example.test/',
          'quality': 720,
          'qualities': [720, 480, 720],
          'decryptionKey': 'aabbcc',
        },
        routeIndex: 2,
        routeCount: 3,
        session: hongguoBridgeSessionForKey('hongguo:123'),
      );
      expect(plan.url, 'https://example.test/play.m3u8');
      expect(plan.headers['User-Agent'], 'hongguo-test');
      expect(plan.headers['Referer'], 'https://example.test/');
      expect(plan.quality, 720);
      expect(plan.qualities, [720, 480]);
      expect(plan.decryptionKey, 'aabbcc');
      expect(plan.routeIndex, 2);
      expect(plan.routeCount, 3);
      expect(plan.session, 'hongguo-bridge:hongguo:123');
      expect(plan.hasAlternative, isFalse);
    });

    test('falls back to the top-level referer when headers carry none', () {
      final plan = hongguoBridgePlanFromJson(
        {'url': 'https://example.test/play.m3u8', 'referer': 'https://r.test/'},
        routeIndex: 1,
        routeCount: 2,
        session: hongguoBridgeSessionForKey('hongguo:123'),
      );
      expect(plan.headers['Referer'], 'https://r.test/');
    });

    test('an empty url fails as a bridge failure, never as an empty plan', () {
      expect(
        () => hongguoBridgePlanFromJson(
          {'url': ''},
          routeIndex: 1,
          routeCount: 2,
          session: hongguoBridgeSessionForKey('hongguo:123'),
        ),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.message,
            'message',
            contains('桥接线路解析失败'),
          ),
        ),
      );
    });
  });

  group('hongguo bridge route mapping', () {
    test('the bridge index is the direct route count', () {
      const direct = PlaybackPlan(
        url: 'https://example.test/direct.m3u8',
        session: 'go-session-1',
        routeIndex: 0,
        routeCount: 2,
      );
      final bumped = hongguoBridgePlanWithRouteCount(direct, direct.routeCount);
      expect(bumped.routeIndex, 0);
      expect(bumped.routeCount, 3);
      expect(bumped.url, direct.url);
      expect(bumped.session, 'go-session-1');
    });

    test('a single direct route gains the bridge line as route 2', () {
      const direct = PlaybackPlan(
        url: 'https://example.test/direct.m3u8',
        session: 'go-session-1',
        routeIndex: 0,
        routeCount: 1,
      );
      final bumped = hongguoBridgePlanWithRouteCount(direct, direct.routeCount);
      expect(bumped.routeCount, 2);
      expect(hongguoBridgeIsBridgeRoute(1, 1), isTrue);
      expect(hongguoBridgeIsBridgeRoute(1, 0), isFalse);
      expect(hongguoBridgeIsBridgeRoute(null, 0), isFalse);
    });

    test('bridge session markers round-trip to the drama key', () {
      const dramaKey = 'hongguo:123';
      final session = hongguoBridgeSessionForKey(dramaKey);
      expect(session, 'hongguo-bridge:hongguo:123');
      expect(hongguoBridgeKeyFromSession(session), dramaKey);
      expect(hongguoBridgeKeyFromSession('go-session-1'), isNull);
    });
  });

  group('hongguo bridge address settings', () {
    Future<LocalStore> createStore() async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      return store;
    }

    test('defaults are 127.0.0.1 and 8917', () async {
      final store = await createStore();
      expect(store.hongguoBridgeHost, '127.0.0.1');
      expect(store.hongguoBridgePort, 8917);
    });

    test('host and port edits persist across a store restart', () async {
      final store = await createStore();
      await store.setHongguoBridgeHost('192.168.1.2');
      await store.setHongguoBridgePort('9999');
      expect(store.hongguoBridgeHost, '192.168.1.2');
      expect(store.hongguoBridgePort, 9999);
      final restarted = LocalStore(await SharedPreferences.getInstance());
      addTearDown(restarted.dispose);
      expect(restarted.hongguoBridgeHost, '192.168.1.2');
      expect(restarted.hongguoBridgePort, 9999);
    });

    test('an invalid port falls back to 8917', () async {
      final store = await createStore();
      await store.setHongguoBridgePort('not-a-port');
      expect(store.hongguoBridgePort, 8917);
    });
  });
}
