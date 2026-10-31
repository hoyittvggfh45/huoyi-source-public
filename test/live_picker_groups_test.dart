import 'package:duanju_app/live_sources.dart';
import 'package:flutter_test/flutter_test.dart';

const _regular = LiveSource(
  id: 'bilibili',
  name: '哔哩哔哩',
  description: '',
  protocol: LiveProtocol.platform,
);

const _movie = LiveSource(
  id: 'yuhuo_live',
  name: '欲火直播',
  description: '',
  protocol: LiveProtocol.list,
  group: '欲火直播',
);

const _adult = LiveSource(
  id: 'xiuguo',
  name: '秀果',
  description: '',
  protocol: LiveProtocol.pingtai,
  adult: true,
);

const _adultSecond = LiveSource(
  id: 'maiyoux',
  name: '欲火聚合',
  description: '',
  protocol: LiveProtocol.pingtai,
  adult: true,
);

const _imported = LiveSource(
  id: 'm3u:t1',
  name: '导入订阅',
  description: '',
  protocol: LiveProtocol.list,
  builtin: false,
);

void main() {
  group('直播切源分组：成人直播间单独成组', () {
    test('常规＋成人＋导入分三组，标题与成员各就其位', () {
      final groups = LiveSource.pickerGroups([
        _regular,
        _adult,
        _imported,
      ]);
      expect(
        groups.map((item) => item.title),
        ['平台源', '成人直播间', '导入源'],
      );
      expect(groups[0].sources.map((item) => item.id), ['bilibili']);
      expect(groups[1].sources.map((item) => item.id), ['xiuguo']);
      expect(groups[2].sources.map((item) => item.id), ['m3u:t1']);
    });

    test('绿色模式可见集里没有成人组，午夜激活后才出现', () {
      final green = LiveSource.pickerGroups(
        LiveSource.visible(true),
      );
      expect(
        green.any((item) => item.title == '成人直播间'),
        isFalse,
      );
      final open = LiveSource.pickerGroups(
        LiveSource.visible(false),
      );
      final adult = open.firstWhere((item) => item.title == '成人直播间');
      expect(
        adult.sources.map((item) => item.id),
        containsAll(['xiuguo', 'maiyoux']),
      );
    });

    test('只有常规源时单组无标题，沿用旧行为', () {
      final groups = LiveSource.pickerGroups([_regular, _movie]);
      expect(groups.length, 1);
      expect(groups.single.title, '');
      expect(
        groups.single.sources.map((item) => item.id),
        ['bilibili', 'yuhuo_live'],
      );
    });

    test('常规＋导入无成人时两组标题沿用旧行为', () {
      final groups = LiveSource.pickerGroups([_regular, _imported]);
      expect(
        groups.map((item) => item.title),
        ['平台源', '导入源'],
      );
    });

    test('只有成人源时单组成人直播间组', () {
      final groups = LiveSource.pickerGroups([_adult, _adultSecond]);
      expect(groups.length, 1);
      expect(groups.single.title, '成人直播间');
      expect(
        groups.single.sources.map((item) => item.id),
        ['xiuguo', 'maiyoux'],
      );
    });

    test('看电影的常规分类留在常规流：电影白名单放行、花名挡掉', () {
      expect(
        LiveSource.hidesCategory('电影频道', greenMode: true),
        isFalse,
      );
      expect(
        LiveSource.hidesCategory('卡哇伊', greenMode: true),
        isTrue,
      );
      expect(
        LiveSource.hidesCategory('卫视直播', greenMode: true),
        isFalse,
      );
    });

    test('内置注册表成人标记与常规源归属如实', () {
      expect(LiveSource.byId('xiuguo')!.adult, isTrue);
      expect(LiveSource.byId('maiyoux')!.adult, isTrue);
      expect(LiveSource.byId('bilibili')!.adult, isFalse);
      expect(LiveSource.byId('yuhuo_live')!.adult, isFalse);
    });
  });
}
