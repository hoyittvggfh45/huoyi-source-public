import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'content_legado.dart';
import 'content_models.dart';
import 'content_py.dart';
import 'content_registry.dart';
import 'content_txt.dart';
import 'import_file_store.dart';

enum NovelImportKind { py, txt, json }

class NovelImportRecord {
  const NovelImportRecord({
    required this.id,
    required this.name,
    required this.fileName,
    this.kind = NovelImportKind.py,
    this.sourceType = 0,
  });

  final String id;
  final String name;
  final String fileName;
  final NovelImportKind kind;
  final int sourceType;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fileName': fileName,
    'kind': kind.name,
    'sourceType': sourceType,
  };

  static NovelImportRecord? fromJson(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    final fileName = map['fileName']?.toString() ?? '';
    if (id.isEmpty || fileName.isEmpty) return null;
    final rawKind = map['kind']?.toString();
    final kind = rawKind == 'txt'
        ? NovelImportKind.txt
        : rawKind == 'json'
        ? NovelImportKind.json
        : rawKind == 'py'
        ? NovelImportKind.py
        : fileName.toLowerCase().endsWith('.txt')
        ? NovelImportKind.txt
        : fileName.toLowerCase().endsWith('.json')
        ? NovelImportKind.json
        : NovelImportKind.py;
    final rawType = map['sourceType'];
    final sourceType = rawType is num
        ? rawType.toInt()
        : int.tryParse(rawType?.toString() ?? '') ?? 0;
    return NovelImportRecord(
      id: id,
      name: map['name']?.toString() ?? id,
      fileName: fileName,
      kind: kind,
      sourceType: sourceType,
    );
  }

  ContentSource toSource() => switch (kind) {
    NovelImportKind.txt => TxtContentSource(
      id: id,
      name: name,
      importedFileName: fileName,
      section: ContentSection.novel,
    ),
    NovelImportKind.json => JsonContentSource(
      id: id,
      name: name,
      importedFileName: fileName,
      section: ContentSection.novel,
      sourceType: sourceType,
    ),
    NovelImportKind.py => PyContentSource(
      id: id,
      name: name,
      importedFileName: fileName,
      section: ContentSection.novel,
    ),
  };
}

class NovelSourceStore {
  NovelSourceStore._();

  static const prefsKey = 'novel_py_imports';

  static bool isNovelComicPyText(String text) =>
      text.contains('novel://') || text.contains('pics://');

  static Future<List<NovelImportRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final records = <NovelImportRecord>[];
      for (final row in decoded) {
        if (row is Map) {
          final record = NovelImportRecord.fromJson(
            Map<String, dynamic>.from(row),
          );
          if (record != null) records.add(record);
        }
      }
      return records;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _save(List<NovelImportRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
  }

  static Future<void> applyToRegistry() async {
    final records = await load();
    ContentRegistry.setNovelImports([
      for (final record in records) record.toSource(),
    ]);
  }

  static Future<NovelImportRecord?> importPicked() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['py', 'txt', 'json'],
      );
    } on PlatformException catch (e) {
      if (e.code != 'unknown_path') rethrow;
      picked = await FilePicker.pickFile(type: FileType.any);
      final ext = picked?.extension?.toLowerCase();
      if (picked != null && ext != 'py' && ext != 'txt' && ext != 'json') {
        throw const FormatException('不是 py、txt 或 json 文件');
      }
    }
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('空文件');
    final isTxt = picked.name.toLowerCase().endsWith('.txt');
    final isJson = picked.name.toLowerCase().endsWith('.json');
    var jsonType = 0;
    if (isJson) {
      jsonType = validateLegadoJson(
        utf8.decode(bytes, allowMalformed: true),
      ).type;
    } else if (!isTxt &&
        !isNovelComicPyText(utf8.decode(bytes, allowMalformed: true))) {
      throw const FormatException('不是小说漫画源');
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = await ImportFileStore.save(
      'novel_$stamp',
      isTxt ? 'txt' : isJson ? 'json' : 'py',
      bytes,
    );
    final base = (picked.name.split('/').last.split('\\').last).replaceAll(
      RegExp(r'\.(py|txt|json)$', caseSensitive: false),
      '',
    );
    final records = await load();
    final record = NovelImportRecord(
      id: 'novel_$stamp',
      name: base.isEmpty ? '小说源$stamp' : base,
      fileName: fileName,
      kind: isTxt
          ? NovelImportKind.txt
          : isJson
          ? NovelImportKind.json
          : NovelImportKind.py,
      sourceType: isJson ? jsonType : 0,
    );
    records.add(record);
    await _save(records);
    return record;
  }

  static Future<void> remove(NovelImportRecord record) async {
    final records = await load();
    records.removeWhere((item) => item.id == record.id);
    await _save(records);
    await ImportFileStore.delete(record.fileName);
  }
}
