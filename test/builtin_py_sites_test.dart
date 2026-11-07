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

  group('内置 py 午夜站', () {
    test('ABJAV 站注册值：视频分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.abjavSite;
      expect(site.id, 'abjav');
      expect(site.name, '🔞ABJAV');
      expect(site.section, SourceSite.sectionVideo);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.abjavAssetPath, 'assets/py_spiders/abjav.py');
    });
    test('ABJAV 站进午夜区、不进点播区', () {
      expect(isMidnightZoneSource(BuiltinPySites.abjavSite), isTrue);
      expect(isVodZoneSource(BuiltinPySites.abjavSite), isFalse);
    });
  });

  group('内置 py 短剧站', () {
    test('2026短剧AI 站注册值：短剧分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.ai2026Site;
      expect(site.id, 'ai2026');
      expect(site.name, '🔞2026短剧AI');
      expect(site.section, SourceSite.sectionDrama);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.ai2026AssetPath, 'assets/py_spiders/ai2026.py');
    });
    test('2026短剧AI 站进短剧区、不进午夜区、不进点播区', () {
      expect(BuiltinPySites.ai2026Site.isDramaSection, isTrue);
      expect(isMidnightZoneSource(BuiltinPySites.ai2026Site), isFalse);
      expect(isVodZoneSource(BuiltinPySites.ai2026Site), isFalse);
      expect(BuiltinPySites.ai2026Site.onlineSearch, isTrue);
      expect(BuiltinPySites.ai2026Site.pagedSearch, isTrue);
    });
  });

  group('内置 py 短剧站', () {
    test('4K.AI短剧 站注册值：短剧分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.ai4kSite;
      expect(site.id, 'ai4k');
      expect(site.name, '🔞4K.AI短剧');
      expect(site.section, SourceSite.sectionDrama);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.ai4kAssetPath, 'assets/py_spiders/ai4k.py');
    });
    test('4K.AI短剧 站进短剧区、不进午夜区、不进点播区', () {
      expect(BuiltinPySites.ai4kSite.isDramaSection, isTrue);
      expect(isMidnightZoneSource(BuiltinPySites.ai4kSite), isFalse);
      expect(isVodZoneSource(BuiltinPySites.ai4kSite), isFalse);
      expect(BuiltinPySites.ai4kSite.onlineSearch, isTrue);
      expect(BuiltinPySites.ai4kSite.pagedSearch, isTrue);
    });
  });

  group('内置 py 短剧站', () {
    test('AI短剧AV 站注册值：短剧分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.aidjSite;
      expect(site.id, 'aidj');
      expect(site.name, '🔞AI短剧AV');
      expect(site.section, SourceSite.sectionDrama);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.aidjAssetPath, 'assets/py_spiders/aidj.py');
    });
    test('AI短剧AV 站进短剧区、不进午夜区、不进点播区', () {
      expect(BuiltinPySites.aidjSite.isDramaSection, isTrue);
      expect(isMidnightZoneSource(BuiltinPySites.aidjSite), isFalse);
      expect(isVodZoneSource(BuiltinPySites.aidjSite), isFalse);
      expect(BuiltinPySites.aidjSite.onlineSearch, isTrue);
      expect(BuiltinPySites.aidjSite.pagedSearch, isTrue);
    });
  });

  group('内置 py 短剧站', () {
    test('AI短剧网 站注册值：短剧分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.aiduanjuSite;
      expect(site.id, 'aiduanju');
      expect(site.name, '🔞AI短剧网');
      expect(site.section, SourceSite.sectionDrama);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.aiduanjuAssetPath, 'assets/py_spiders/aiduanju.py');
    });
    test('AI短剧网 站进短剧区、不进午夜区、不进点播区', () {
      expect(BuiltinPySites.aiduanjuSite.isDramaSection, isTrue);
      expect(isMidnightZoneSource(BuiltinPySites.aiduanjuSite), isFalse);
      expect(isVodZoneSource(BuiltinPySites.aiduanjuSite), isFalse);
      expect(BuiltinPySites.aiduanjuSite.onlineSearch, isTrue);
      expect(BuiltinPySites.aiduanjuSite.pagedSearch, isTrue);
    });
  });

  group('内置 py 短剧站', () {
    test('新黄果短剧 站注册值：短剧分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.aimoveSite;
      expect(site.id, 'aimove');
      expect(site.name, '🔞新黄果短剧');
      expect(site.section, SourceSite.sectionDrama);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.aimoveAssetPath, 'assets/py_spiders/aimove.py');
    });
    test('新黄果短剧 站进短剧区、不进午夜区、不进点播区', () {
      expect(BuiltinPySites.aimoveSite.isDramaSection, isTrue);
      expect(isMidnightZoneSource(BuiltinPySites.aimoveSite), isFalse);
      expect(isVodZoneSource(BuiltinPySites.aimoveSite), isFalse);
      expect(BuiltinPySites.aimoveSite.onlineSearch, isTrue);
      expect(BuiltinPySites.aimoveSite.pagedSearch, isTrue);
    });
  });

  group('内置 py 短剧站', () {
    test('Ai小视频 站注册值：短剧分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.aisxpcSite;
      expect(site.id, 'aisxpc');
      expect(site.name, '🔞Ai小视频');
      expect(site.section, SourceSite.sectionDrama);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.aisxpcAssetPath, 'assets/py_spiders/aisxpc.py');
    });
    test('Ai小视频 站进短剧区、不进午夜区、不进点播区', () {
      expect(BuiltinPySites.aisxpcSite.isDramaSection, isTrue);
      expect(isMidnightZoneSource(BuiltinPySites.aisxpcSite), isFalse);
      expect(isVodZoneSource(BuiltinPySites.aisxpcSite), isFalse);
      expect(BuiltinPySites.aisxpcSite.onlineSearch, isTrue);
      expect(BuiltinPySites.aisxpcSite.pagedSearch, isTrue);
    });
    test('大奶Ai短剧 站注册值：短剧分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.danaiSite;
      expect(site.id, 'danai');
      expect(site.name, '🔞大奶Ai短剧');
      expect(site.section, SourceSite.sectionDrama);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.danaiAssetPath, 'assets/py_spiders/danai.py');
    });
    test('大奶Ai短剧 站进短剧区、不进午夜区、不进点播区', () {
      expect(BuiltinPySites.danaiSite.isDramaSection, isTrue);
      expect(isMidnightZoneSource(BuiltinPySites.danaiSite), isFalse);
      expect(isVodZoneSource(BuiltinPySites.danaiSite), isFalse);
      expect(BuiltinPySites.danaiSite.onlineSearch, isTrue);
      expect(BuiltinPySites.danaiSite.pagedSearch, isTrue);
    });
    test('69短剧 站注册值：短剧分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.dj69Site;
      expect(site.id, 'dj69');
      expect(site.name, '🔞69短剧');
      expect(site.section, SourceSite.sectionDrama);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.dj69AssetPath, 'assets/py_spiders/dj69.py');
    });
    test('69短剧 站进短剧区、不进午夜区、不进点播区', () {
      expect(BuiltinPySites.dj69Site.isDramaSection, isTrue);
      expect(isMidnightZoneSource(BuiltinPySites.dj69Site), isFalse);
      expect(isVodZoneSource(BuiltinPySites.dj69Site), isFalse);
      expect(BuiltinPySites.dj69Site.onlineSearch, isTrue);
      expect(BuiltinPySites.dj69Site.pagedSearch, isTrue);
    });
  });

  group('内置 py 午夜站', () {
    test('A色TV 站注册值：视频分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.asextvSite;
      expect(site.id, 'asextv');
      expect(site.name, '🔞A色TV');
      expect(site.section, SourceSite.sectionVideo);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.asextvAssetPath, 'assets/py_spiders/asextv.py');
    });
    test('A色TV 站进午夜区、不进点播区', () {
      expect(isMidnightZoneSource(BuiltinPySites.asextvSite), isTrue);
      expect(isVodZoneSource(BuiltinPySites.asextvSite), isFalse);
    });
  });

  group('内置 py 午夜站', () {
    test('AVHWA 站注册值：视频分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.avhwaSite;
      expect(site.id, 'avhwa');
      expect(site.name, '🔞AVHWA');
      expect(site.section, SourceSite.sectionVideo);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.avhwaAssetPath, 'assets/py_spiders/avhwa.py');
    });
    test('AVHWA 站进午夜区、不进点播区', () {
      expect(isMidnightZoneSource(BuiltinPySites.avhwaSite), isTrue);
      expect(isVodZoneSource(BuiltinPySites.avhwaSite), isFalse);
    });
  });

  group('内置 py 午夜站', () {
    test('AV Today 站注册值：视频分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.avtodaySite;
      expect(site.id, 'avtoday');
      expect(site.name, '🔞AV Today');
      expect(site.section, SourceSite.sectionVideo);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.avtodayAssetPath, 'assets/py_spiders/avtoday.py');
    });
    test('AV Today 站进午夜区、不进点播区', () {
      expect(isMidnightZoneSource(BuiltinPySites.avtodaySite), isTrue);
      expect(isVodZoneSource(BuiltinPySites.avtodaySite), isFalse);
    });
  });

  group('内置 py 午夜站', () {
    test('AV研究院 站注册值：视频分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.avyanjiuyuanSite;
      expect(site.id, 'avyanjiuyuan');
      expect(site.name, '🔞AV研究院');
      expect(site.section, SourceSite.sectionVideo);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.avyanjiuyuanAssetPath, 'assets/py_spiders/avyanjiuyuan.py');
    });
    test('AV研究院 站进午夜区、不进点播区', () {
      expect(isMidnightZoneSource(BuiltinPySites.avyanjiuyuanSite), isTrue);
      expect(isVodZoneSource(BuiltinPySites.avyanjiuyuanSite), isFalse);
    });
  });

  group('内置 py 午夜站', () {
    test('八度影院 站注册值：视频分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.badyiSite;
      expect(site.id, 'badyi');
      expect(site.name, '🔞八度影院');
      expect(site.section, SourceSite.sectionVideo);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.badyiAssetPath, 'assets/py_spiders/badyi.py');
    });
    test('八度影院 站进午夜区、不进点播区', () {
      expect(isMidnightZoneSource(BuiltinPySites.badyiSite), isTrue);
      expect(isVodZoneSource(BuiltinPySites.badyiSite), isFalse);
    });
  });

  group('内置 py 午夜站', () {
    test('草榴视频 站注册值：视频分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.caoliuSite;
      expect(site.id, 'caoliu');
      expect(site.name, '🔞草榴视频');
      expect(site.section, SourceSite.sectionVideo);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.caoliuAssetPath, 'assets/py_spiders/caoliu.py');
    });
    test('草榴视频 站进午夜区、不进点播区', () {
      expect(isMidnightZoneSource(BuiltinPySites.caoliuSite), isTrue);
      expect(isVodZoneSource(BuiltinPySites.caoliuSite), isFalse);
    });
  });

  group('内置 py 午夜站', () {
    test('中国X站 站注册值：视频分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.chinaxSite;
      expect(site.id, 'chinax');
      expect(site.name, '🔞中国X站');
      expect(site.section, SourceSite.sectionVideo);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.chinaxAssetPath, 'assets/py_spiders/chinax.py');
    });
    test('中国X站 站进午夜区、不进点播区', () {
      expect(isMidnightZoneSource(BuiltinPySites.chinaxSite), isTrue);
      expect(isVodZoneSource(BuiltinPySites.chinaxSite), isFalse);
    });
  });

  group('内置 py 午夜站', () {
    test('顶级AI色库 站注册值：视频分区、内置来源、py 类型、🔞 名', () {
      final site = BuiltinPySites.dingjiasekuSite;
      expect(site.id, 'dingjiaseku');
      expect(site.name, '🔞顶级AI色库');
      expect(site.section, SourceSite.sectionVideo);
      expect(site.origin, SourceSite.originBuiltin);
      expect(site.importType, 'py');
      expect(BuiltinPySites.dingjiasekuAssetPath, 'assets/py_spiders/dingjiaseku.py');
    });
    test('顶级AI色库 站进午夜区、不进点播区', () {
      expect(isMidnightZoneSource(BuiltinPySites.dingjiasekuSite), isTrue);
      expect(isVodZoneSource(BuiltinPySites.dingjiasekuSite), isFalse);
    });
  });
}
