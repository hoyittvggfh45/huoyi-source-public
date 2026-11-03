import 'package:duanju_app/builtin_py_sites.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('内置 py 午夜站', () {
    test('河马站注册值：视频分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.hmavSite;
      expect(site.id, 'hmav');
      expect(site.name, '🔞河马AV');
      expect(site.section, SourceSite.sectionVideo);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.hmavAssetPath, 'assets/py_spiders/hmav.py');
    });
    test('河马站进午夜区、不进点播区', () {
      expect(isMidnightZoneSource(BuiltinPySites.hmavSite), isTrue);
      expect(isVodZoneSource(BuiltinPySites.hmavSite), isFalse);
    });
  });
}
