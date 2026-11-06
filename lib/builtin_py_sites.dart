import 'package:flutter/services.dart';

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
      SourceSite.importedSites[tgdramaSiteId] = tgdramaSite;
      SourceSite.importedPyFiles[tgdramaSiteId] = fileName;
    } catch (_) {}
  }
}
