import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'import_file_store.dart';
import 'models.dart';

class BuiltinPySites {
  BuiltinPySites._();

  static const hmavSiteId = 'hmav';
  static const hmavAssetPath = 'assets/py_spiders/hmav.py';
  static const hmavFileId = 'builtin_hmav';

  static const hmavSite = SourceSite(
    hmavSiteId,
    '🔞河马AV',
    '内置 py · hmav',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const tgdramaSiteId = 'tgdrama';
  static const tgdramaAssetPath = 'assets/py_spiders/tgdrama.py';
  static const tgdramaFileId = 'builtin_tgdrama';

  static const tgdramaSite = SourceSite(
    tgdramaSiteId,
    'TG影视库',
    '内置 py · tgdrama',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const abjavSiteId = 'abjav';
  static const abjavAssetPath = 'assets/py_spiders/abjav.py';
  static const abjavFileId = 'builtin_abjav';

  static const abjavSite = SourceSite(
    abjavSiteId,
    '🔞ABJAV',
    '内置 py · abjav',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const ai2026SiteId = 'ai2026';
  static const ai2026AssetPath = 'assets/py_spiders/ai2026.py';
  static const ai2026FileId = 'builtin_ai2026';

  static const ai2026Site = SourceSite(
    ai2026SiteId,
    '🔞2026短剧AI',
    '内置 py · ai2026',
    section: SourceSite.sectionDrama,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const ai4kSiteId = 'ai4k';
  static const ai4kAssetPath = 'assets/py_spiders/ai4k.py';
  static const ai4kFileId = 'builtin_ai4k';

  static const ai4kSite = SourceSite(
    ai4kSiteId,
    '🔞4K.AI短剧',
    '内置 py · ai4k',
    section: SourceSite.sectionDrama,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const aidjSiteId = 'aidj';
  static const aidjAssetPath = 'assets/py_spiders/aidj.py';
  static const aidjFileId = 'builtin_aidj';

  static const aidjSite = SourceSite(
    aidjSiteId,
    '🔞AI短剧AV',
    '内置 py · aidj',
    section: SourceSite.sectionDrama,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const aiduanjuSiteId = 'aiduanju';
  static const aiduanjuAssetPath = 'assets/py_spiders/aiduanju.py';
  static const aiduanjuFileId = 'builtin_aiduanju';

  static const aiduanjuSite = SourceSite(
    aiduanjuSiteId,
    '🔞AI短剧网',
    '内置 py · aiduanju',
    section: SourceSite.sectionDrama,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const aimoveSiteId = 'aimove';
  static const aimoveAssetPath = 'assets/py_spiders/aimove.py';
  static const aimoveFileId = 'builtin_aimove';

  static const aimoveSite = SourceSite(
    aimoveSiteId,
    '🔞新黄果短剧',
    '内置 py · aimove',
    section: SourceSite.sectionDrama,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const aisxpcSiteId = 'aisxpc';
  static const aisxpcAssetPath = 'assets/py_spiders/aisxpc.py';
  static const aisxpcFileId = 'builtin_aisxpc';

  static const aisxpcSite = SourceSite(
    aisxpcSiteId,
    '🔞Ai小视频',
    '内置 py · aisxpc',
    section: SourceSite.sectionDrama,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const asextvSiteId = 'asextv';
  static const asextvAssetPath = 'assets/py_spiders/asextv.py';
  static const asextvFileId = 'builtin_asextv';

  static const asextvSite = SourceSite(
    asextvSiteId,
    '🔞A色TV',
    '内置 py · asextv',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const avhwaSiteId = 'avhwa';
  static const avhwaAssetPath = 'assets/py_spiders/avhwa.py';
  static const avhwaFileId = 'builtin_avhwa';

  static const avhwaSite = SourceSite(
    avhwaSiteId,
    '🔞AVHWA',
    '内置 py · avhwa',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const avtodaySiteId = 'avtoday';
  static const avtodayAssetPath = 'assets/py_spiders/avtoday.py';
  static const avtodayFileId = 'builtin_avtoday';

  static const avtodaySite = SourceSite(
    avtodaySiteId,
    '🔞AV Today',
    '内置 py · avtoday',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const avyanjiuyuanSiteId = 'avyanjiuyuan';
  static const avyanjiuyuanAssetPath = 'assets/py_spiders/avyanjiuyuan.py';
  static const avyanjiuyuanFileId = 'builtin_avyanjiuyuan';

  static const avyanjiuyuanSite = SourceSite(
    avyanjiuyuanSiteId,
    '🔞AV研究院',
    '内置 py · avyanjiuyuan',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const badyiSiteId = 'badyi';
  static const badyiAssetPath = 'assets/py_spiders/badyi.py';
  static const badyiFileId = 'builtin_badyi';

  static const badyiSite = SourceSite(
    badyiSiteId,
    '🔞八度影院',
    '内置 py · badyi',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const caoliuSiteId = 'caoliu';
  static const caoliuAssetPath = 'assets/py_spiders/caoliu.py';
  static const caoliuFileId = 'builtin_caoliu';

  static const caoliuSite = SourceSite(
    caoliuSiteId,
    '🔞草榴视频',
    '内置 py · caoliu',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const chinaxSiteId = 'chinax';
  static const chinaxAssetPath = 'assets/py_spiders/chinax.py';
  static const chinaxFileId = 'builtin_chinax';

  static const chinaxSite = SourceSite(
    chinaxSiteId,
    '🔞中国X站',
    '内置 py · chinax',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const danaiSiteId = 'danai';
  static const danaiAssetPath = 'assets/py_spiders/danai.py';
  static const danaiFileId = 'builtin_danai';

  static const danaiSite = SourceSite(
    danaiSiteId,
    '🔞大奶Ai短剧',
    '内置 py · danai',
    section: SourceSite.sectionDrama,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const dingjiasekuSiteId = 'dingjiaseku';
  static const dingjiasekuAssetPath = 'assets/py_spiders/dingjiaseku.py';
  static const dingjiasekuFileId = 'builtin_dingjiaseku';

  static const dingjiasekuSite = SourceSite(
    dingjiasekuSiteId,
    '🔞顶级AI色库',
    '内置 py · dingjiaseku',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static const dj69SiteId = 'dj69';
  static const dj69AssetPath = 'assets/py_spiders/dj69.py';
  static const dj69FileId = 'builtin_dj69';

  static const dj69Site = SourceSite(
    dj69SiteId,
    '🔞69短剧',
    '内置 py · dj69',
    section: SourceSite.sectionDrama,
    origin: SourceSite.originBuiltin,
    importType: 'py',
  );

  static Future<bool> register() async {
    try {
      final bytes = await rootBundle.load(hmavAssetPath);
      final fileName = await ImportFileStore.save(
        hmavFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[hmavSiteId] = hmavSite;
      SourceSite.importedPyFiles[hmavSiteId] = fileName;
      await _registerTgdrama();
      await _registerAbjav();
      await _registerAi2026();
      await _registerAi4k();
      await _registerAidj();
      await _registerAiduanju();
      await _registerAimove();
      await _registerAisxpc();
      await _registerAsextv();
      await _registerAvhwa();
      await _registerAvtoday();
      await _registerAvyanjiuyuan();
      await _registerBadyi();
      await _registerCaoliu();
      await _registerChinax();
      await _registerDanai();
      await _registerDingjiaseku();
      await _registerDj69();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _registerTgdrama() async {
    try {
      final bytes = await rootBundle.load(tgdramaAssetPath);
      final fileName = await ImportFileStore.save(
        tgdramaFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      var site = tgdramaSite;
      try {
        final supportDir = await getApplicationSupportDirectory();
        site = SourceSite(
          tgdramaSiteId,
          'TG影视库',
          '内置 py · tgdrama',
          section: SourceSite.sectionVideo,
          origin: SourceSite.originBuiltin,
          importType: 'py',
          importExt: jsonEncode({
            'db_path': '${supportDir.path}/tgdrama/tgdrama.db',
          }),
        );
      } catch (_) {}
      SourceSite.importedSites[tgdramaSiteId] = site;
      SourceSite.importedPyFiles[tgdramaSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAbjav() async {
    try {
      final bytes = await rootBundle.load(abjavAssetPath);
      final fileName = await ImportFileStore.save(
        abjavFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[abjavSiteId] = abjavSite;
      SourceSite.importedPyFiles[abjavSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAi2026() async {
    try {
      final bytes = await rootBundle.load(ai2026AssetPath);
      final fileName = await ImportFileStore.save(
        ai2026FileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[ai2026SiteId] = ai2026Site;
      SourceSite.importedPyFiles[ai2026SiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAi4k() async {
    try {
      final bytes = await rootBundle.load(ai4kAssetPath);
      final fileName = await ImportFileStore.save(
        ai4kFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[ai4kSiteId] = ai4kSite;
      SourceSite.importedPyFiles[ai4kSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAidj() async {
    try {
      final bytes = await rootBundle.load(aidjAssetPath);
      final fileName = await ImportFileStore.save(
        aidjFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[aidjSiteId] = aidjSite;
      SourceSite.importedPyFiles[aidjSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAiduanju() async {
    try {
      final bytes = await rootBundle.load(aiduanjuAssetPath);
      final fileName = await ImportFileStore.save(
        aiduanjuFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[aiduanjuSiteId] = aiduanjuSite;
      SourceSite.importedPyFiles[aiduanjuSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAimove() async {
    try {
      final bytes = await rootBundle.load(aimoveAssetPath);
      final fileName = await ImportFileStore.save(
        aimoveFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[aimoveSiteId] = aimoveSite;
      SourceSite.importedPyFiles[aimoveSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAisxpc() async {
    try {
      final bytes = await rootBundle.load(aisxpcAssetPath);
      final fileName = await ImportFileStore.save(
        aisxpcFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[aisxpcSiteId] = aisxpcSite;
      SourceSite.importedPyFiles[aisxpcSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAsextv() async {
    try {
      final bytes = await rootBundle.load(asextvAssetPath);
      final fileName = await ImportFileStore.save(
        asextvFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[asextvSiteId] = asextvSite;
      SourceSite.importedPyFiles[asextvSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAvhwa() async {
    try {
      final bytes = await rootBundle.load(avhwaAssetPath);
      final fileName = await ImportFileStore.save(
        avhwaFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[avhwaSiteId] = avhwaSite;
      SourceSite.importedPyFiles[avhwaSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAvtoday() async {
    try {
      final bytes = await rootBundle.load(avtodayAssetPath);
      final fileName = await ImportFileStore.save(
        avtodayFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[avtodaySiteId] = avtodaySite;
      SourceSite.importedPyFiles[avtodaySiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerAvyanjiuyuan() async {
    try {
      final bytes = await rootBundle.load(avyanjiuyuanAssetPath);
      final fileName = await ImportFileStore.save(
        avyanjiuyuanFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[avyanjiuyuanSiteId] = avyanjiuyuanSite;
      SourceSite.importedPyFiles[avyanjiuyuanSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerBadyi() async {
    try {
      final bytes = await rootBundle.load(badyiAssetPath);
      final fileName = await ImportFileStore.save(
        badyiFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[badyiSiteId] = badyiSite;
      SourceSite.importedPyFiles[badyiSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerCaoliu() async {
    try {
      final bytes = await rootBundle.load(caoliuAssetPath);
      final fileName = await ImportFileStore.save(
        caoliuFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[caoliuSiteId] = caoliuSite;
      SourceSite.importedPyFiles[caoliuSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerChinax() async {
    try {
      final bytes = await rootBundle.load(chinaxAssetPath);
      final fileName = await ImportFileStore.save(
        chinaxFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[chinaxSiteId] = chinaxSite;
      SourceSite.importedPyFiles[chinaxSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerDanai() async {
    try {
      final bytes = await rootBundle.load(danaiAssetPath);
      final fileName = await ImportFileStore.save(
        danaiFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[danaiSiteId] = danaiSite;
      SourceSite.importedPyFiles[danaiSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerDingjiaseku() async {
    try {
      final bytes = await rootBundle.load(dingjiasekuAssetPath);
      final fileName = await ImportFileStore.save(
        dingjiasekuFileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[dingjiasekuSiteId] = dingjiasekuSite;
      SourceSite.importedPyFiles[dingjiasekuSiteId] = fileName;
    } catch (_) {}
  }

  static Future<void> _registerDj69() async {
    try {
      final bytes = await rootBundle.load(dj69AssetPath);
      final fileName = await ImportFileStore.save(
        dj69FileId,
        'py',
        bytes.buffer.asUint8List(),
      );
      SourceSite.importedSites[dj69SiteId] = dj69Site;
      SourceSite.importedPyFiles[dj69SiteId] = fileName;
    } catch (_) {}
  }
}
