import 'package:duanju_app/live_parser.dart';
import 'package:duanju_app/live_sources.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

// 欲火移植注册表锁定（fix3）：senlin 进点播、huangdou 进短剧、
// maiyoux + 欲火直播进直播，三区清单在此逐项写死，注册漏挂/归属写错即红。
// 欲火直播频道表为移植批全量保留版（2,578 条 EXTINF / 29 分组），
// 探活未验通是已知状态（见批次报告_fix3），本测试只锁表本身不锁存活。
void main() {
  group('点播区：森林资源', () {
    test('videoValues 含 v_senlin 且槽位映射正确，删站后共 78 项', () {
      expect(SourceSite.videoValues, hasLength(78));
      final senlin = SourceSite.byId('v_senlin');
      expect(senlin.name, '🔞森林资源');
      expect(senlin.section, SourceSite.sectionVideo);
      expect(senlin.slotId, 'yh_senlin');
      expect(senlin.coreSlotId, 'yh_senlin');
      expect(SourceSite.byId('v_senlin').slotId, 'yh_senlin');
      expect(
        SourceSite.knownValues.map((s) => s.id),
        containsAll(['v_ikun', 'v_senlin']),
      );
    });

    test('videoValues 尾项为黄果 v_huangguo（v_hg 已删）', () {
      final hg = SourceSite.videoValues.last;
      expect(hg.id, 'v_huangguo');
      expect(hg.slotId, 'yh_huangguo');
      expect(hg.section, SourceSite.sectionVideo);
      expect(
        SourceSite.videoValues.map((s) => s.slotId),
        containsAll(['yh_km', 'yh_lxs', 'yh_km2', 'yh_cucumber', 'yh_avbobo']),
      );
    });
  });

  group('短剧区：黄豆短剧', () {
    test('duanjuValues 尾项为 huangdou_yh 且能力位齐', () {
      expect(SourceSite.duanjuValues, hasLength(12));
      final huangdou = SourceSite.duanjuValues.last;
      expect(huangdou.id, 'huangdou_yh');
      expect(huangdou.name, '黄豆短剧');
      expect(huangdou.isDramaSection, isTrue);
      expect(huangdou.onlineSearch, isTrue);
      expect(huangdou.pagedSearch, isTrue);
      expect(SourceSite.byId('huangdou_yh').name, '黄豆短剧');
      expect(SourceSite.defaultHiddenSiteIds, isNot(contains('huangdou_yh')));
    });
  });

  group('直播区：欲火两源', () {
    test('内置直播源清单与协议/端点锁定', () {
      expect(LiveSource.values.map((s) => s.id), [
        'xiuguo',
        'bilibili',
        'huya',
        'maiyoux',
        'yuhuo_live',
      ]);
      final maiyoux = LiveSource.byId('maiyoux')!;
      expect(maiyoux.protocol, LiveProtocol.pingtai);
      expect(maiyoux.endpoints, [
        'http://api.maiyoux.com:81/mf',
        'http://api.vipmisss.com:81/xcdsw',
      ]);
      expect(maiyoux.adult, isTrue);

      final yuhuoLive = LiveSource.byId('yuhuo_live')!;
      expect(yuhuoLive.protocol, LiveProtocol.list);
      expect(yuhuoLive.endpoint, 'asset://assets/live/yuhuo_live.m3u');
      expect(yuhuoLive.adult, isFalse);
    });

    test('绿色模式只整源隐藏 maiyoux，欲火直播保留', () {
      final green = LiveSource.visible(true).map((s) => s.id);
      expect(green, isNot(contains('maiyoux')));
      expect(green, contains('yuhuo_live'));
      expect(
        LiveSource.visible(false).map((s) => s.id),
        containsAll(['maiyoux', 'yuhuo_live']),
      );
    });
  });

  group('欲火直播频道表资产', () {
    test('打包 m3u 可加载并解析出全量分组与频道', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final text = await rootBundle.loadString('assets/live/yuhuo_live.m3u');
      expect(text, startsWith('#EXTM3U'));
      final parsed = LiveParser.parse(
        text,
        source: 'yuhuo_live',
        defaultGroup: '欲火直播',
      );
      expect(parsed.format, LiveFormat.m3u);
      expect(parsed.groups, hasLength(29));
      // 原始 2,578 条 EXTINF；解析器按（分组,台名）合并多线路后为 1,656 个频道。
      expect(parsed.channelCount, 1656);
      final cctv = parsed.groups.first.channels.firstWhere(
        (c) => c.name == 'CCTV-1',
      );
      expect(cctv.urls.length, greaterThan(1));
    });

    test('m3u 小样解析：分组与多线路合并', () {
      const sample = '''
#EXTM3U
#EXTINF:-1 group-title="卫视频道",湖南卫视
http://example.com/hunan.m3u8
#EXTINF:-1 group-title="卫视频道",湖南卫视
http://example.com/hunan2.m3u8
#EXTINF:-1 group-title="电影频道",CCTV-6
http://example.com/cctv6.m3u8
''';
      final parsed = LiveParser.parse(sample, source: 'yuhuo_live');
      expect(parsed.groups, hasLength(2));
      expect(parsed.channelCount, 2);
      expect(parsed.groups.first.channels.single.urls, hasLength(2));
    });
  });
}
