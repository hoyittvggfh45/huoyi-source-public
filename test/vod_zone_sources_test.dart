import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('点播/午夜分区谓词', () {
    test('非 🔞 内置视频站回点播区', () {
      const site = SourceSite(
        'go_hua',
        'Hua',
        '',
        section: SourceSite.sectionVideo,
        origin: SourceSite.originBuiltin,
      );
      expect(isVodZoneSource(site), isTrue);
      expect(isMidnightZoneSource(site), isTrue);
    });
    test('🔞 内置视频站不进点播区、仍在午夜区', () {
      const site = SourceSite(
        'mjv011',
        '🔞mjv011',
        '',
        section: SourceSite.sectionVideo,
        origin: SourceSite.originBuiltin,
      );
      expect(isVodZoneSource(site), isFalse);
      expect(isMidnightZoneSource(site), isTrue);
    });
    test('配置与导入站行为不变', () {
      const config = SourceSite(
        'cfg',
        '配置站',
        '',
        section: SourceSite.sectionVideo,
        origin: SourceSite.originConfig,
      );
      const py = SourceSite(
        'py1',
        '导入py',
        '',
        section: SourceSite.sectionVideo,
        origin: SourceSite.originImport,
        importType: 'py',
      );
      const jar = SourceSite(
        'jar1',
        '导入jar',
        '',
        section: SourceSite.sectionVideo,
        origin: SourceSite.originImport,
        importType: 'jar',
      );
      const other = SourceSite(
        'o1',
        '其他导入',
        '',
        section: SourceSite.sectionVideo,
        origin: SourceSite.originImport,
        importType: 'zip',
      );
      expect(isVodZoneSource(config), isTrue);
      expect(isVodZoneSource(py), isTrue);
      expect(isVodZoneSource(jar), isTrue);
      expect(isVodZoneSource(other), isFalse);
    });
    test('短剧分区内置站不进点播区', () {
      const site = SourceSite(
        'hgtv',
        'HGTV',
        '',
        section: SourceSite.sectionDrama,
        origin: SourceSite.originBuiltin,
      );
      expect(isVodZoneSource(site), isFalse);
    });
  });
}
