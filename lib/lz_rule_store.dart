import 'dart:convert';
import 'dart:io';

import 'core_bridge.dart';

enum LzRuleKind { json, txt, py, js, other, dir }

LzRuleKind lzKindForName(String name) {
  if (name.endsWith('.json')) return LzRuleKind.json;
  if (name.endsWith('.txt')) return LzRuleKind.txt;
  if (name.endsWith('.py')) return LzRuleKind.py;
  if (name.endsWith('.js')) return LzRuleKind.js;
  return LzRuleKind.other;
}

class LzRulePath {
  const LzRulePath(this.relative, this.kind);

  final String relative;
  final LzRuleKind kind;
}

const List<LzRulePath> lzRulePaths = [
  LzRulePath('lz/sources.json', LzRuleKind.json),
  LzRulePath('lz/sourses.json', LzRuleKind.json),
  LzRulePath('lz/source.json', LzRuleKind.json),
  LzRulePath('lz/sourse.json', LzRuleKind.json),
  LzRulePath('lz/youtube.txt', LzRuleKind.txt),
  LzRulePath('lz/cj.txt', LzRuleKind.txt),
  LzRulePath('lz/novel', LzRuleKind.dir),
  LzRulePath('lz/port.txt', LzRuleKind.txt),
  LzRulePath('lz/py/sy', LzRuleKind.dir),
  LzRulePath('lz/js', LzRuleKind.dir),
  LzRulePath('lz/wj/直播', LzRuleKind.dir),
  LzRulePath('lz/ai/模板.txt', LzRuleKind.txt),
  LzRulePath('novel/source.json', LzRuleKind.json),
  LzRulePath('novel/sources.json', LzRuleKind.json),
];

class LzRuleEntry {
  const LzRuleEntry({
    required this.path,
    required this.exists,
    this.sizeBytes,
    this.modified,
    this.count,
  });

  final LzRulePath path;
  final bool exists;
  final int? sizeBytes;
  final DateTime? modified;
  final int? count;
}

class LzRuleStore {
  LzRuleStore({this.root = '/storage/emulated/0'});

  final String root;

  String _full(LzRulePath path) => '$root/${path.relative}';

  Future<bool> get rootReadable async {
    try {
      return await Directory(root).exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureFolders() async {
    try {
      final dirs = <String>{'lz', 'novel'};
      for (final path in lzRulePaths) {
        final parts = path.relative.split('/');
        for (var i = 1; i < parts.length; i++) {
          dirs.add(parts.sublist(0, i).join('/'));
        }
        if (path.kind == LzRuleKind.dir) {
          dirs.add(path.relative);
        }
      }
      for (final dir in dirs) {
        await Directory('$root/$dir').create(recursive: true);
      }
    } catch (_) {}
  }

  Future<List<LzRuleEntry>> scan() async {
    final entries = <LzRuleEntry>[];
    for (final path in lzRulePaths) {
      entries.add(await _scanOne(path));
    }
    return entries;
  }

  Future<List<LzRuleEntry>> scanFolder() async {
    final found = <LzRuleEntry>[];
    try {
      final base = Directory('$root/lz');
      if (!await base.exists()) return const [];
      await _collect(base, 'lz', found, 0);
    } catch (_) {
      return found;
    }
    found.sort((a, b) => a.path.relative.compareTo(b.path.relative));
    return found;
  }

  Future<void> _collect(
    Directory dir,
    String relative,
    List<LzRuleEntry> out,
    int depth,
  ) async {
    if (out.length >= 500 || depth > 4) return;
    List<FileSystemEntity> children;
    try {
      children = await dir.list().toList();
    } catch (_) {
      return;
    }
    for (final child in children) {
      if (out.length >= 500) return;
      final name = child.path.split('/').last;
      if (name.startsWith('.')) continue;
      final childRelative = '$relative/$name';
      if (child is Directory) {
        out.add(await _scanOne(LzRulePath(childRelative, LzRuleKind.dir)));
        await _collect(child, childRelative, out, depth + 1);
      } else if (child is File) {
        out.add(await _scanOne(LzRulePath(childRelative, lzKindForName(name))));
      }
    }
  }

  Future<LzRuleEntry> _scanOne(LzRulePath path) async {
    final full = _full(path);
    try {
      if (path.kind == LzRuleKind.dir) {
        final dir = Directory(full);
        if (!await dir.exists()) {
          return LzRuleEntry(path: path, exists: false);
        }
        final stat = await dir.stat();
        var count = 0;
        try {
          count = await dir.list().length;
        } catch (_) {
          count = 0;
        }
        return LzRuleEntry(
          path: path,
          exists: true,
          modified: stat.modified,
          count: count,
        );
      }
      final file = File(full);
      if (!await file.exists()) {
        return LzRuleEntry(path: path, exists: false);
      }
      final stat = await file.stat();
      int? count;
      try {
        if (path.kind == LzRuleKind.json) {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is List) {
            count = decoded.length;
          } else if (decoded is Map) {
            count = 1;
          }
        } else if (path.kind == LzRuleKind.txt ||
            path.kind == LzRuleKind.py ||
            path.kind == LzRuleKind.js) {
          final lines = await file.readAsLines();
          count = lines.where((line) => line.trim().isNotEmpty).length;
        }
      } catch (_) {
        count = null;
      }
      return LzRuleEntry(
        path: path,
        exists: true,
        sizeBytes: stat.size,
        modified: stat.modified,
        count: count,
      );
    } catch (_) {
      return LzRuleEntry(path: path, exists: false);
    }
  }

  Future<void> importFile(LzRulePath target, File source) async {
    if (target.kind == LzRuleKind.dir) {
      throw AppFailure('目录项不支持单文件导入，请把文件放进该目录');
    }
    final dest = File(_full(target));
    await dest.parent.create(recursive: true);
    await source.copy(dest.path);
  }

  Future<void> deleteEntry(LzRulePath target) async {
    final full = _full(target);
    if (target.kind == LzRuleKind.dir) {
      final dir = Directory(full);
      if (!await dir.exists()) {
        throw AppFailure('目录不存在');
      }
      final children = await dir.list().toList();
      if (children.isNotEmpty) {
        throw AppFailure('目录非空，先清空子文件再删除');
      }
      await dir.delete();
      return;
    }
    final file = File(full);
    if (!await file.exists()) {
      throw AppFailure('文件不存在');
    }
    await file.delete();
  }
}
