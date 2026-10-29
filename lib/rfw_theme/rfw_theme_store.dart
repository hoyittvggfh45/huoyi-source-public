import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RfwThemeEntry {
  const RfwThemeEntry({
    required this.id,
    required this.name,
    required this.isBuiltin,
    this.asset,
    this.fileName,
  });

  final String id;
  final String name;
  final bool isBuiltin;
  final String? asset;
  final String? fileName;
}

const List<RfwThemeEntry> builtinRfwThemes = [
  RfwThemeEntry(
    id: 'chenguang',
    name: '晨光网格',
    isBuiltin: true,
    asset: 'assets/rfw_themes/chenguang_grid.rfwtxt',
  ),
  RfwThemeEntry(
    id: 'suyu',
    name: '素影列表',
    isBuiltin: true,
    asset: 'assets/rfw_themes/suyu_list.rfwtxt',
  ),
  RfwThemeEntry(
    id: 'xinghe',
    name: '星河横幅',
    isBuiltin: true,
    asset: 'assets/rfw_themes/xinghe_banner.rfwtxt',
  ),
];

const String rfwThemeModeKey = 'rfwThemeMode';
const String rfwThemeIdKey = 'rfwThemeId';
const String rfwDisplayStyleKey = 'rfwDisplayStyle';

final ValueNotifier<bool> rfwThemeModeNotifier = ValueNotifier(false);
final ValueNotifier<String?> rfwThemeIdNotifier = ValueNotifier(null);
final ValueNotifier<String> rfwDisplayStyleNotifier = ValueNotifier('grid');

Future<void> loadRfwThemePreferences() async {
  final prefs = await SharedPreferences.getInstance();
  rfwThemeModeNotifier.value = prefs.getBool(rfwThemeModeKey) ?? false;
  rfwThemeIdNotifier.value = prefs.getString(rfwThemeIdKey);
  rfwDisplayStyleNotifier.value = prefs.getString(rfwDisplayStyleKey) ?? 'grid';
}

Future<void> saveRfwThemeMode(bool enabled) async {
  rfwThemeModeNotifier.value = enabled;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(rfwThemeModeKey, enabled);
}

Future<void> saveRfwThemeId(String? id) async {
  rfwThemeIdNotifier.value = id;
  final prefs = await SharedPreferences.getInstance();
  if (id == null) {
    await prefs.remove(rfwThemeIdKey);
  } else {
    await prefs.setString(rfwThemeIdKey, id);
  }
}

Future<void> saveRfwDisplayStyle(String style) async {
  rfwDisplayStyleNotifier.value = style;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(rfwDisplayStyleKey, style);
}

class RfwThemeValidation {
  const RfwThemeValidation({required this.ok, this.reason = ''});

  final bool ok;
  final String reason;
}

RfwThemeValidation validateRfwThemeText(String text) {
  if (text.trim().isEmpty) {
    return const RfwThemeValidation(ok: false, reason: '主题文件为空');
  }
  late final RemoteWidgetLibrary library;
  try {
    library = parseLibraryFile(text);
  } on ParserException catch (error) {
    return RfwThemeValidation(ok: false, reason: '主题解析失败：$error');
  } catch (error) {
    return RfwThemeValidation(ok: false, reason: '主题解析失败：$error');
  }
  if (!library.widgets.any((widget) => widget.name == 'root')) {
    return const RfwThemeValidation(ok: false, reason: '主题缺少 root 定义');
  }
  const allowedImports = {'core.widgets', 'peek.home'};
  for (final import in library.imports) {
    final name = import.name.parts.join('.');
    if (!allowedImports.contains(name)) {
      return RfwThemeValidation(ok: false, reason: '主题引用了不支持的库：$name');
    }
  }
  return const RfwThemeValidation(ok: true);
}

Future<Directory> rfwThemeDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/rfw_themes');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

String rfwThemeFileName(String originalName) {
  final base = originalName.split('/').last.split('\\').last;
  final withoutExtension = base.toLowerCase().endsWith('.rfwtxt')
      ? base.substring(0, base.length - 7)
      : base;
  final cleaned = withoutExtension
      .replaceAll(RegExp('[\\x00-\\x1F]'), '')
      .trim();
  return '${cleaned.isEmpty ? 'theme' : cleaned}.rfwtxt';
}

Future<List<RfwThemeEntry>> loadRfwThemeEntries({Directory? directory}) async {
  final dir = directory ?? await rfwThemeDirectory();
  final entries = <RfwThemeEntry>[...builtinRfwThemes];
  if (await dir.exists()) {
    final files = await dir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final fileName = file.path.split('/').last;
      if (!fileName.toLowerCase().endsWith('.rfwtxt')) continue;
      entries.add(
        RfwThemeEntry(
          id: 'imported:$fileName',
          name: fileName.substring(0, fileName.length - 7),
          isBuiltin: false,
          fileName: fileName,
        ),
      );
    }
  }
  return entries;
}

Future<String?> loadRfwThemeText(
  RfwThemeEntry entry, {
  Directory? directory,
}) async {
  if (entry.isBuiltin) {
    final asset = entry.asset;
    if (asset == null) return null;
    try {
      return await rootBundle.loadString(asset);
    } catch (_) {
      return null;
    }
  }
  final fileName = entry.fileName;
  if (fileName == null) return null;
  final dir = directory ?? await rfwThemeDirectory();
  final file = File('${dir.path}/$fileName');
  if (!await file.exists()) return null;
  return file.readAsString();
}

class RfwThemeImportResult {
  const RfwThemeImportResult({
    required this.ok,
    required this.message,
    this.entry,
  });

  final bool ok;
  final String message;
  final RfwThemeEntry? entry;
}

Future<RfwThemeImportResult> importRfwThemeText(
  String originalName,
  String text, {
  Directory? directory,
}) async {
  final validation = validateRfwThemeText(text);
  if (!validation.ok) {
    return RfwThemeImportResult(ok: false, message: validation.reason);
  }
  final dir = directory ?? await rfwThemeDirectory();
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final fileName = rfwThemeFileName(originalName);
  var target = File('${dir.path}/$fileName');
  if (await target.exists()) {
    final existing = await target.readAsString();
    if (existing == text) {
      return RfwThemeImportResult(
        ok: false,
        message: '主题已存在：${fileName.substring(0, fileName.length - 7)}',
      );
    }
    var suffix = 2;
    while (await target.exists()) {
      final stem = fileName.substring(0, fileName.length - 7);
      target = File('${dir.path}/$stem-$suffix.rfwtxt');
      suffix += 1;
    }
  }
  await target.writeAsString(text);
  final savedName = target.path.split('/').last;
  return RfwThemeImportResult(
    ok: true,
    message: '主题已导入：${savedName.substring(0, savedName.length - 7)}',
    entry: RfwThemeEntry(
      id: 'imported:$savedName',
      name: savedName.substring(0, savedName.length - 7),
      isBuiltin: false,
      fileName: savedName,
    ),
  );
}

Future<bool> deleteImportedRfwTheme(
  RfwThemeEntry entry, {
  Directory? directory,
}) async {
  if (entry.isBuiltin) return false;
  final fileName = entry.fileName;
  if (fileName == null) return false;
  final dir = directory ?? await rfwThemeDirectory();
  final file = File('${dir.path}/$fileName');
  if (!await file.exists()) return false;
  await file.delete();
  return true;
}

Future<RfwThemeImportResult?> pickAndImportRfwTheme() async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['rfwtxt'],
  );
  if (picked == null) return null;
  final pickedLength = await picked.length();
  if (pickedLength != null && pickedLength > 1024 * 1024) {
    return const RfwThemeImportResult(ok: false, message: '主题文件过大（超过 1MB）');
  }
  late final String text;
  try {
    final bytes = await picked.readAsBytes();
    text = utf8.decode(bytes);
  } catch (_) {
    return const RfwThemeImportResult(ok: false, message: '主题文件不是有效 UTF-8 文本');
  }
  return importRfwThemeText(picked.name, text);
}
