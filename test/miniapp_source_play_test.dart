import 'package:duanju_app/miniapp/renderer.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_parse.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PlaybackPlan> _neverParse(
  PlaybackPlan plan,
  List<ParseInterface> apis,
) async => throw StateError('resolveParse must not run');

void main() {
  test('direct media flagged needsParse is returned as parse 0', () async {
    var calls = 0;
    final result = await miniappSourcePlayMap(
      const PlaybackPlan(
        url: 'https://cdn.example.com/v/index.m3u8?token=abc',
        headers: {'Referer': 'https://site.example.com/'},
        needsParse: true,
      ),
      flag: '线路1',
      sourceId: 'py_site',
      resolveParse: (plan, apis) async {
        calls++;
        return plan;
      },
    );
    expect(calls, 0);
    expect(result['url'], 'https://cdn.example.com/v/index.m3u8?token=abc');
    expect(result['parse'], '0');
    expect(result['header'], {'Referer': 'https://site.example.com/'});
    expect(result['playUrl'], 'https://cdn.example.com/v/index.m3u8?token=abc');
  });

  test('local py proxy url flagged needsParse is returned as parse 0', () async {
    final result = await miniappSourcePlayMap(
      const PlaybackPlan(
        url: 'http://127.0.0.1:12345/pyproxy?d=abc',
        needsParse: true,
      ),
      flag: '线路1',
      sourceId: 'py_site',
      resolveParse: _neverParse,
    );
    expect(result['url'], 'http://127.0.0.1:12345/pyproxy?d=abc');
    expect(result['parse'], '0');
    expect(result['playUrl'], 'http://127.0.0.1:12345/pyproxy?d=abc');
  });

  test('page url flagged needsParse is resolved before returning', () async {
    final result = await miniappSourcePlayMap(
      const PlaybackPlan(
        url: 'https://site.example.com/play/123',
        headers: {'Referer': 'https://site.example.com/'},
        needsParse: true,
      ),
      flag: '线路1',
      sourceId: 'py_site',
      resolveParse: (plan, apis) async => const PlaybackPlan(
        url: 'https://cdn.example.com/v/index.m3u8',
        headers: {'User-Agent': 'miniapp'},
      ),
      parseApis: const [
        ParseInterface(id: 'jx', name: 'jx', url: 'https://jx.example.com/?url='),
      ],
    );
    expect(result['url'], 'https://cdn.example.com/v/index.m3u8');
    expect(result['parse'], '0');
    expect(result['header'], {'User-Agent': 'miniapp'});
    expect(result['playUrl'], 'https://cdn.example.com/v/index.m3u8');
  });

  test('unresolvable page url keeps parse 1 instead of a fake direct url',
      () async {
    final result = await miniappSourcePlayMap(
      const PlaybackPlan(
        url: 'https://site.example.com/play/123',
        needsParse: true,
      ),
      flag: '线路1',
      sourceId: 'py_site',
      resolveParse: (plan, apis) async => throw StateError('jx failed'),
      parseApis: const [
        ParseInterface(id: 'jx', name: 'jx', url: 'https://jx.example.com/?url='),
      ],
    );
    expect(result['url'], 'https://site.example.com/play/123');
    expect(result['parse'], '1');
  });

  test('page url without parse apis keeps parse 1', () async {
    final result = await miniappSourcePlayMap(
      const PlaybackPlan(
        url: 'https://site.example.com/play/123',
        needsParse: true,
      ),
      flag: '线路1',
      sourceId: 'py_site',
      resolveParse: _neverParse,
    );
    expect(result['parse'], '1');
  });

  test('originalUrl is kept when the plan carries one', () async {
    final result = await miniappSourcePlayMap(
      const PlaybackPlan(
        url: 'https://cdn.example.com/v/index.m3u8',
        originalUrl: 'https://site.example.com/play/123',
      ),
      flag: '线路1',
      sourceId: 'py_site',
      resolveParse: _neverParse,
    );
    expect(result['url'], 'https://cdn.example.com/v/index.m3u8');
    expect(result['playUrl'], 'https://site.example.com/play/123');
  });

  test('player page url settles through resolveParse', () async {
    final settled = await miniappSettlePlayPlan(
      const PlaybackPlan(
        url: 'https://site.example.com/play/123',
        needsParse: true,
      ),
      resolveParse: (plan, apis) async => const PlaybackPlan(
        url: 'https://cdn.example.com/v/index.m3u8',
      ),
      parseApis: const [
        ParseInterface(id: 'jx', name: 'jx', url: 'https://jx.example.com/?url='),
      ],
    );
    expect(settled.url, 'https://cdn.example.com/v/index.m3u8');
    expect(settled.needsParse, isFalse);
  });
}
