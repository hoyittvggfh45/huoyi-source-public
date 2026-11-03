import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'import_file_store.dart';
import 'rss_model.dart';

class RssSourceRecord {
  const RssSourceRecord({
    required this.id,
    required this.name,
    required this.sourceUrl,
    required this.fileName,
  });

  final String id;
  final String name;
  final String sourceUrl;
  final String fileName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sourceUrl': sourceUrl,
    'fileName': fileName,
  };

  static RssSourceRecord? fromJson(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    final fileName = map['fileName']?.toString() ?? '';
    if (id.isEmpty || fileName.isEmpty) return null;
    return RssSourceRecord(
      id: id,
      name: map['name']?.toString() ?? id,
      sourceUrl: map['sourceUrl']?.toString() ?? '',
      fileName: fileName,
    );
  }
}

class RssSourceStore {
  RssSourceStore._();

  static const prefsKey = 'rss_subscriptions';

  static Future<List<RssSourceRecord>> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final records = <RssSourceRecord>[];
      for (final row in decoded) {
        if (row is Map) {
          final record = RssSourceRecord.fromJson(
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

  static Future<void> _saveRecords(List<RssSourceRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
  }

  static Future<List<RssSource>> loadSources() async {
    final records = await loadRecords();
    final sources = <RssSource>[];
    for (final record in records) {
      try {
        final path = await ImportFileStore.pathOf(record.fileName);
        final text = await File(path).readAsString();
        sources.add(parseRssSource(text));
      } catch (_) {
        continue;
      }
    }
    return sources;
  }

  static Future<RssSource> importJson(String jsonText) async {
    final source = parseRssSource(jsonText);
    final fileName = await ImportFileStore.save(
      source.id,
      'json',
      utf8.encode(jsonText),
    );
    final records = await loadRecords();
    final next = [
      for (final record in records)
        if (record.id != source.id) record,
      RssSourceRecord(
        id: source.id,
        name: source.name,
        sourceUrl: source.sourceUrl,
        fileName: fileName,
      ),
    ];
    await _saveRecords(next);
    return source;
  }

  static Future<void> remove(String id) async {
    final records = await loadRecords();
    for (final record in records) {
      if (record.id == id) {
        await ImportFileStore.delete(record.fileName);
      }
    }
    await _saveRecords([
      for (final record in records)
        if (record.id != id) record,
    ]);
  }
}
