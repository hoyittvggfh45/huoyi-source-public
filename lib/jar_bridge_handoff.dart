import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'core_bridge.dart';
import 'jar_import.dart';
import 'tvbox_config.dart';

class JarBridgeHandoff {
  JarBridgeHandoff._();

  static const bool available = true;

  static Future<String> importTvBoxConfig({
    required AppRepository repository,
    required String name,
    required String content,
  }) async {
    final report = await TvBoxImporter(
      repository,
    ).importFromText(content, sourceIdentity: 'file:$name');
    if (report.apiSites + report.jarSites + report.pySites == 0) {
      throw AppFailure(
        'TVBox 配置未注册任何站点'
        '${report.notes.isEmpty ? '' : '：${report.notes.join('；')}'}',
      );
    }
    return '已导入 TVBox 配置「${report.name}」：${report.summary}';
  }

  static Future<String> registerJar({
    required String name,
    required List<int> bytes,
  }) async {
    final digest = md5.convert(bytes).toString();
    final directory = await getApplicationSupportDirectory();
    final jarDir = Directory(path.join(directory.path, 'imported_jars'));
    if (!await jarDir.exists()) await jarDir.create(recursive: true);
    final file = File(path.join(jarDir.path, '$digest.jar'));
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    final classes = await JarImport.scanAndRegister(
      jarId: 'imp${digest.substring(0, 10)}',
      jarUrl: file.path,
      jarMd5: digest,
    );
    final registered = classes.where((info) => info.instantiable).length;
    if (registered == 0) {
      throw AppFailure('jar 内未发现可实例化的 Spider 类（共枚举 ${classes.length} 个类）');
    }
    return 'jar 已注册 $registered 个站点（枚举 ${classes.length} 个类）';
  }
}
