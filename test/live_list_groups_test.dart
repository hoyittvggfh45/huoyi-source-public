import 'package:duanju_app/live_http.dart';
import 'package:duanju_app/live_models.dart';
import 'package:duanju_app/live_repository.dart';
import 'package:duanju_app/live_sources.dart';
import 'package:flutter_test/flutter_test.dart';

const _m3u = '''
#EXTM3U
#EXTINF:-1 group-title="央视频道",CCTV-1
https://cdn.test/cctv1.m3u8
#EXTINF:-1 group-title="央视频道",CCTV-1
https://cdn2.test/cctv1.m3u8
#EXTINF:-1 group-title="卫视频道",湖南卫视
https://cdn.test/hunan.m3u8
#EXTINF:-1 group-title="浙江综合",浙江卫视
https://cdn.test/zhejiang.m3u8
#EXTINF:-1,无分组频道
https://cdn.test/plain.m3u8
''';

class _FakeHttp extends LiveHttp {
  _FakeHttp(this.responses);

  final Map<String, String> responses;

  @override
  Future<String> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final body = responses[url];
    if (body == null) throw StateError('unexpected request: $url');
    return body;
  }
}

void main() {
  group('列表型直播源按内嵌分组出平台', () {
    late LiveRepository repository;
    const source = LiveSource(
      id: 'test-list',
      name: '测试列表',
      description: '',
      protocol: LiveProtocol.list,
      endpoints: ['https://list.test/channels.m3u'],
    );

    setUp(() {
      repository = LiveRepository(
        http: _FakeHttp({'https://list.test/channels.m3u': _m3u}),
      );
      addTearDown(repository.dispose);
    });

    test('platforms 返回全部频道在前、随后每组一个平台且带计数', () async {
      final platforms = await repository.platforms(source);
      expect(
        platforms.map((item) => item.name),
        ['全部频道', '央视频道', '卫视频道', '浙江综合', '其他'],
      );
      expect(platforms.first.id, 'all');
      expect(platforms[1].count, 1);
    });

    test('按分组取频道只返回该组，同名频道合并多线路', () async {
      final platforms = await repository.platforms(source);
      final cctv = platforms.firstWhere((item) => item.id == '央视频道');
      final channels = await repository.channels(source, cctv);
      expect(channels.length, 1);
      expect(channels.single.name, 'CCTV-1');
      expect(channels.single.urls.length, 2);
    });

    test('全部频道返回全量，单组过滤不串组', () async {
      final platforms = await repository.platforms(source);
      final all = await repository.channels(source, platforms.first);
      expect(all.length, 4);
      final zhejiang = platforms.firstWhere((item) => item.id == '浙江综合');
      final channels = await repository.channels(source, zhejiang);
      expect(channels.map((item) => item.name), ['浙江卫视']);
    });

    test('列表源不分页、平台源分页', () {
      expect(source.paginated, isFalse);
      expect(LiveSource.byId('bilibili')!.paginated, isTrue);
    });
  });

  group('导入 m3u 源同样按频道 group 出平台', () {
    const source = LiveSource(
      id: 'm3u:t1',
      name: '导入订阅',
      description: '',
      protocol: LiveProtocol.list,
      builtin: false,
    );

    setUp(() {
      importedLiveChannels['m3u:t1'] = [
        const LiveChannel(
          key: 'k1',
          name: 'CCTV-1',
          urls: ['https://cdn.test/cctv1.m3u8'],
          group: '央视频道',
        ),
        const LiveChannel(
          key: 'k2',
          name: '湖南卫视',
          urls: ['https://cdn.test/hunan.m3u8'],
          group: '卫视频道',
        ),
      ];
      addTearDown(() => importedLiveChannels.remove('m3u:t1'));
    });

    test('导入源平台含分组，取分组不走网络', () async {
      final repository = LiveRepository(http: _FakeHttp({}));
      addTearDown(repository.dispose);
      final platforms = await repository.platforms(source);
      expect(
        platforms.map((item) => item.name),
        ['全部频道', '央视频道', '卫视频道'],
      );
      final channels = await repository.channels(
        source,
        platforms.firstWhere((item) => item.id == '卫视频道'),
      );
      expect(channels.map((item) => item.name), ['湖南卫视']);
    });
  });
}
