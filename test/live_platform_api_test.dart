import 'package:duanju_app/live_http.dart';
import 'package:duanju_app/live_models.dart';
import 'package:duanju_app/live_platform_api.dart';
import 'package:duanju_app/live_repository.dart';
import 'package:duanju_app/live_sources.dart';
import 'package:flutter_test/flutter_test.dart';

const _bilibiliRooms = '''
{"code":0,"message":"OK","data":{"recommend_room_list":[
{"roomid":12345,"title":"冲分之夜","uname":"主播甲","cover":"https://img.test/cover1.jpg","keyframe":"https://img.test/kf1.jpg","online":987,"area_v2_parent_name":"网游","area_v2_name":"英雄联盟"},
{"roomid":67890,"title":"","uname":"主播乙","cover":"","keyframe":"https://img.test/kf2.jpg","online":0,"area_v2_parent_name":"娱乐","area_v2_name":"颜值"}
]}}
''';

const _bilibiliPlay = '''
{"code":0,"message":"OK","data":{"durl":[
{"url":"https://cdn.test/live_1.flv?sign=a","order":1},
{"url":"https://cdn2.test/live_1.flv?sign=b","order":2}
]}}
''';

const _huyaRooms = '''
{"status":200,"message":"","data":{"page":1,"totalPage":4,"datas":[
{"profileRoom":92059,"introduction":"好运姐冲分","roomName":"","nick":"王炸","screenshot":"https://img.test/shot1.jpg","gameFullName":"星秀","uid":"111"},
{"profileRoom":1001,"introduction":"","roomName":"晚间电台","nick":"小夜","screenshot":"https://img.test/shot2.jpg","gameFullName":"星秀","uid":"222"},
{"profileRoom":0,"introduction":"占位","roomName":"","nick":"无名","screenshot":"","gameFullName":"星秀","uid":"333"}
]}}
''';

const _huyaPage = '''
<html><script>
var hyPlayerConfig = {stream: {"data":[{"gameStreamInfoList":[
{"sCdnType":"AL","iPCPriorityRate":-1,"sStreamName":"111-222-a-0-1","sFlvUrl":"http://al.flv.test/src","sFlvUrlSuffix":"flv","sFlvAntiCode":"wsSecret=aa&wsTime=ff01","sHlsUrl":"http://al.hls.test/src","sHlsUrlSuffix":"m3u8","sHlsAntiCode":"wsSecret=aa&wsTime=ff01"},
{"sCdnType":"TX","iPCPriorityRate":100,"sStreamName":"111-222-a-0-1","sFlvUrl":"http://tx.flv.test/huyalive","sFlvUrlSuffix":"flv","sFlvAntiCode":"wsSecret=bb&wsTime=ff02","sHlsUrl":"http://tx.hls.test/huyalive","sHlsUrlSuffix":"m3u8","sHlsAntiCode":"wsSecret=bb&wsTime=ff02"}
]}]}}
</script></html>
''';

class _FakeHttp extends LiveHttp {
  _FakeHttp(this.responses);

  final Map<String, String> responses;
  final List<String> requested = [];

  @override
  Future<String> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    requested.add(url);
    final body = responses[url];
    if (body == null) throw StateError('unexpected request: $url');
    return body;
  }
}

void main() {
  group('内置平台源注册', () {
    test('哔哩哔哩与虎牙已注册为 platform 源且带 Referer', () {
      final bilibili = LiveSource.byId('bilibili');
      expect(bilibili, isNotNull);
      expect(bilibili!.protocol, LiveProtocol.platform);
      expect(bilibili.paginated, isTrue);
      expect(bilibili.adult, isFalse);
      expect(bilibili.headers['Referer'], 'https://live.bilibili.com/');
      final huya = LiveSource.byId('huya');
      expect(huya, isNotNull);
      expect(huya!.protocol, LiveProtocol.platform);
      expect(huya.headers['Referer'], 'https://www.huya.com/');
      expect(
        LiveSource.visible(true).map((source) => source.id),
        containsAll(['bilibili', 'huya']),
      );
    });

    test('分类表与实测口径一致', () {
      final bilibili = livePlatformCategories('bilibili');
      expect(bilibili.map((item) => item.id), ['rec']);
      final huya = livePlatformCategories('huya');
      expect(huya.length, 15);
      expect(huya.first.name, '全部');
      final byName = {for (final item in huya) item.name: item.id};
      expect(byName['王者荣耀'], '2336');
      expect(byName['英雄联盟'], '1');
      expect(byName['星秀'], '1663');
      expect(livePlatformCategories('unknown'), isEmpty);
    });

    test('房间列表地址按平台拼装', () {
      expect(
        liveRoomsUrl('bilibili', 'rec', 2),
        'https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getMoreRecList?platform=web&page=2',
      );
      expect(
        liveRoomsUrl('huya', '0', 1),
        'https://www.huya.com/cache.php?m=LiveList&do=getLiveListByPage&tagAll=0&page=1',
      );
      expect(
        liveRoomsUrl('huya', '2336', 3),
        'https://www.huya.com/cache.php?m=LiveList&do=getLiveListByPage&tagAll=0&page=3&gameId=2336',
      );
      expect(liveRoomsPagesPerFetch('bilibili'), 3);
      expect(liveRoomsPagesPerFetch('huya'), 1);
    });
  });

  group('哔哩哔哩解析', () {
    test('推荐房间列表映射为频道', () {
      const platform = LivePlatform(id: 'rec', name: '热门推荐');
      final channels = liveParseRooms('bilibili', platform, _bilibiliRooms);
      expect(channels.length, 2);
      final first = channels.first;
      expect(first.name, '冲分之夜');
      expect(first.token, '12345');
      expect(first.url, 'https://live.bilibili.com/12345');
      expect(first.logo, 'https://img.test/cover1.jpg');
      expect(first.group, '热门推荐');
      expect(first.subtitle, contains('主播甲'));
      expect(first.subtitle, contains('网游/英雄联盟'));
      expect(first.subtitle, contains('987 人气'));
      expect(first.number, '001');
      final second = channels[1];
      expect(second.name, '主播乙');
      expect(second.logo, 'https://img.test/kf2.jpg');
      expect(second.number, '002');
    });

    test('编号可续排且坏数据回空', () {
      const platform = LivePlatform(id: 'rec', name: '热门推荐');
      final channels = liveParseRooms(
        'bilibili',
        platform,
        _bilibiliRooms,
        firstNumber: 13,
      );
      expect(channels.first.number, '013');
      expect(liveParseRooms('bilibili', platform, 'not json'), isEmpty);
      expect(liveParseRooms('bilibili', platform, '{"code":-1}'), isEmpty);
    });

    test('播放地址取 durl 顺序', () {
      final urls = liveParsePlaybackUrls('bilibili', _bilibiliPlay);
      expect(urls, [
        'https://cdn.test/live_1.flv?sign=a',
        'https://cdn2.test/live_1.flv?sign=b',
      ]);
      expect(
        liveParsePlaybackUrls('bilibili', '{"code":0,"data":{}}'),
        isEmpty,
      );
    });
  });

  group('虎牙解析', () {
    test('游戏房间列表映射为频道并跳过无效房间', () {
      const platform = LivePlatform(id: '1663', name: '星秀');
      final channels = liveParseRooms('huya', platform, _huyaRooms);
      expect(channels.length, 2);
      final first = channels.first;
      expect(first.name, '好运姐冲分');
      expect(first.token, '92059');
      expect(first.url, 'https://www.huya.com/92059');
      expect(first.logo, 'https://img.test/shot1.jpg');
      expect(first.subtitle, '王炸 · 星秀');
      final second = channels[1];
      expect(second.name, '晚间电台');
      expect(second.token, '1001');
    });

    test('房间页按 PC 优先级取 HLS 在前、FLV 兜底', () {
      final urls = liveParsePlaybackUrls('huya', _huyaPage);
      expect(urls, [
        'http://tx.hls.test/huyalive/111-222-a-0-1.m3u8?wsSecret=bb&wsTime=ff02',
        'http://al.hls.test/src/111-222-a-0-1.m3u8?wsSecret=aa&wsTime=ff01',
        'http://tx.flv.test/huyalive/111-222-a-0-1.flv?wsSecret=bb&wsTime=ff02',
        'http://al.flv.test/src/111-222-a-0-1.flv?wsSecret=aa&wsTime=ff01',
      ]);
      expect(liveParsePlaybackUrls('huya', '<html>no stream</html>'), isEmpty);
    });

    test('播放请求地址按房间号拼装', () {
      final bilibili = LiveChannel(
        key: 'k',
        name: 'n',
        urls: const ['https://live.bilibili.com/12345'],
        token: '12345',
      );
      expect(
        livePlaybackRequestUrl('bilibili', bilibili),
        'https://api.live.bilibili.com/room/v1/Room/playUrl?cid=12345&qn=10000&platform=web',
      );
      final huya = LiveChannel(
        key: 'k',
        name: 'n',
        urls: const ['https://www.huya.com/92059'],
        token: '92059',
      );
      expect(
        livePlaybackRequestUrl('huya', huya),
        'https://www.huya.com/92059',
      );
    });
  });

  group('仓库 platform 分支', () {
    test('虎牙分类、房间与播放全链走适配层', () async {
      final http = _FakeHttp({
        liveRoomsUrl('huya', '1663', 1): _huyaRooms,
        'https://www.huya.com/92059': _huyaPage,
      });
      final repository = LiveRepository(http: http);
      addTearDown(repository.dispose);
      final source = LiveSource.byId('huya')!;
      final platforms = await repository.platforms(source);
      expect(platforms.length, 15);
      final platform = platforms.firstWhere((item) => item.id == '1663');
      final channels = await repository.channels(source, platform);
      expect(channels.length, 2);
      final playback = await repository.playback(source, channels.first);
      expect(
        playback.url,
        'http://tx.hls.test/huyalive/111-222-a-0-1.m3u8?wsSecret=bb&wsTime=ff02',
      );
      expect(playback.headers['Referer'], 'https://www.huya.com/');
    });

    test('哔哩哔哩一页合并三个接口页并去重', () async {
      String roomsUrl(int page) => liveRoomsUrl('bilibili', 'rec', page);
      final http = _FakeHttp({
        roomsUrl(1): _bilibiliRooms,
        roomsUrl(2): _bilibiliRooms,
        roomsUrl(3): '{"code":0,"data":{"recommend_room_list":[]}}',
        'https://api.live.bilibili.com/room/v1/Room/playUrl?cid=12345&qn=10000&platform=web':
            _bilibiliPlay,
      });
      final repository = LiveRepository(http: http);
      addTearDown(repository.dispose);
      final source = LiveSource.byId('bilibili')!;
      final platforms = await repository.platforms(source);
      expect(platforms.single.id, 'rec');
      final channels = await repository.channels(source, platforms.single);
      expect(channels.length, 2);
      expect(channels.map((item) => item.number), ['001', '002']);
      expect(http.requested.sublist(0, 3), [
        roomsUrl(1),
        roomsUrl(2),
        roomsUrl(3),
      ]);
      final playback = await repository.playback(source, channels.first);
      expect(playback.url, 'https://cdn.test/live_1.flv?sign=a');
      expect(playback.headers['Referer'], 'https://live.bilibili.com/');
    });
  });
}
