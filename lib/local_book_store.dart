import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'legado_gbk.dart';

class LocalBook {
  const LocalBook({
    required this.id,
    required this.title,
    required this.fileName,
    required this.size,
    required this.addedAt,
  });

  final String id;
  final String title;
  final String fileName;
  final int size;
  final int addedAt;

  bool get isEpub => fileName.toLowerCase().endsWith('.epub');

  factory LocalBook.fromJson(Map<String, dynamic> json) => LocalBook(
    id: (json['id'] ?? '').toString(),
    title: (json['title'] ?? '').toString(),
    fileName: (json['fileName'] ?? '').toString(),
    size: int.tryParse('${json['size']}') ?? 0,
    addedAt: int.tryParse('${json['addedAt']}') ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'fileName': fileName,
    'size': size,
    'addedAt': addedAt,
  };
}

class LocalBookStore {
  static const _key = 'local_books_v1';

  static Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/local_books');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<LocalBook>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(LocalBook.fromJson)
            .where((b) => b.id.isNotEmpty && b.fileName.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<LocalBook>> add(
    List<int> bytes,
    String originalName,
  ) async {
    final dir = await _directory();
    final ext = originalName.toLowerCase().endsWith('.epub') ? 'epub' : 'txt';
    final title = originalName.replaceAll(
      RegExp(r'\.(txt|epub)$', caseSensitive: false),
      '',
    );
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final fileName = '${id}_local.$ext';
    await File('${dir.path}/$fileName').writeAsBytes(bytes, flush: true);
    final books = await load();
    books.add(
      LocalBook(
        id: id,
        title: title.isEmpty ? fileName : title,
        fileName: fileName,
        size: bytes.length,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(books.map((b) => b.toJson()).toList()),
    );
    return books;
  }

  static Future<List<LocalBook>> remove(LocalBook book) async {
    final dir = await _directory();
    final file = File('${dir.path}/${book.fileName}');
    if (await file.exists()) await file.delete();
    final books = await load();
    books.removeWhere((b) => b.id == book.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(books.map((b) => b.toJson()).toList()),
    );
    return books;
  }

  static Future<List<({String title, String text})>> readChapters(
    LocalBook book,
  ) async {
    final dir = await _directory();
    final bytes = await File('${dir.path}/${book.fileName}').readAsBytes();
    if (book.isEpub) return _epubChapters(bytes);
    return _txtChapters(_decodeText(bytes));
  }

  static String _decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return decodeGbkBytes(bytes);
    }
  }

  static List<({String title, String text})> _txtChapters(String text) {
    final lines = text.split('\n');
    final header = RegExp(
      r'^\s*(第[0-9一二三四五六七八九十百千两]+[章回节篇].{0,30}|Chapter\s+\d+.{0,30}|序章|楔子|前言|引子)\s*$',
    );
    final starts = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (header.hasMatch(lines[i])) starts.add(i);
    }
    if (starts.length < 2) {
      return [(title: '全文', text: text.trim())];
    }
    final out = <({String title, String text})>[];
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1] : lines.length;
      final body = lines.sublist(starts[i] + 1, end).join('\n').trim();
      out.add((title: lines[starts[i]].trim(), text: body));
    }
    return out;
  }

  static List<({String title, String text})> _epubChapters(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? find(String path) {
      for (final file in archive.files) {
        if (file.name == path) return file;
      }
      return null;
    }

    final container = find('META-INF/container.xml');
    if (container == null) throw const FormatException('epub 缺少 container');
    final containerText = utf8.decode(container.content as List<int>);
    final rootMatch = RegExp(
      r'''full-path=["']([^"']+)["']''',
    ).firstMatch(containerText);
    if (rootMatch == null) throw const FormatException('epub 找不到 opf');
    final opfPath = rootMatch.group(1)!;
    final opfFile = find(opfPath);
    if (opfFile == null) throw const FormatException('epub 找不到 opf 文件');
    final opfText = utf8.decode(opfFile.content as List<int>);
    final base = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';
    final hrefById = <String, String>{};
    for (final m in RegExp(
      r'''<item[^>]*id=["']([^"']+)["'][^>]*href=["']([^"']+)["']''',
    ).allMatches(opfText)) {
      hrefById[m.group(1)!] = m.group(2)!;
    }
    for (final m in RegExp(
      r'''<item[^>]*href=["']([^"']+)["'][^>]*id=["']([^"']+)["']''',
    ).allMatches(opfText)) {
      hrefById.putIfAbsent(m.group(2)!, () => m.group(1)!);
    }
    final spine = RegExp(
      r'''<itemref[^>]*idref=["']([^"']+)["']''',
    ).allMatches(opfText).map((m) => m.group(1)!).toList();
    final chapters = <({String title, String text})>[];
    for (final idref in spine) {
      final href = hrefById[idref];
      if (href == null) continue;
      final file = find('$base$href') ?? find(href);
      if (file == null) continue;
      final html = _decodeText(file.content as List<int>);
      final text = _htmlToText(html);
      if (text.trim().isEmpty) continue;
      final titleMatch = RegExp(
        r'<title[^>]*>(.*?)</title>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(html);
      final headingMatch = RegExp(
        r'<h[12][^>]*>(.*?)</h[12]>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(html);
      var title = '';
      if (titleMatch != null) title = _htmlToText(titleMatch.group(1)!).trim();
      if (title.isEmpty && headingMatch != null) {
        title = _htmlToText(headingMatch.group(1)!).trim();
      }
      chapters.add((
        title: title.isEmpty ? '第${chapters.length + 1}章' : title,
        text: text.trim(),
      ));
    }
    if (chapters.isEmpty) throw const FormatException('epub 没有可读章节');
    return chapters;
  }

  static String _htmlToText(String html) {
    var s = html.replaceAll(
      RegExp(
        r'<(script|style)[^>]*>.*?</\1>',
        dotAll: true,
        caseSensitive: false,
      ),
      '',
    );
    s = s.replaceAll(
      RegExp(r'</(p|div|h[1-6]|li|tr)>', caseSensitive: false),
      '\n',
    );
    s = s.replaceAll(RegExp(r'<br[^>]*>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s.replaceAll('&nbsp;', ' ');
    s = s.replaceAll('&lt;', '<');
    s = s.replaceAll('&gt;', '>');
    s = s.replaceAll('&quot;', '"');
    s = s.replaceAll('&apos;', "'");
    s = s.replaceAll('&amp;', '&');
    s = s.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.tryParse(m.group(1)!) ?? 0xFFFD),
    );
    s = s.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) =>
          String.fromCharCode(int.tryParse(m.group(1)!, radix: 16) ?? 0xFFFD),
    );
    final lines = s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    return lines.join('\n');
  }
}
