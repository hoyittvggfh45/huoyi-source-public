import 'dart:io';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/lz_rule_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('空目录扫描全部未找到', () async {
    final root = await Directory.systemTemp.createTemp('lz_empty_');
    addTearDown(() => root.delete(recursive: true));
    final store = LzRuleStore(root: root.path);
    expect(await store.rootReadable, isTrue);
    final entries = await store.scan();
    expect(entries.length, lzRulePaths.length);
    expect(entries.every((entry) => !entry.exists), isTrue);
  });

  test('不存在的根目录扫描全部未找到且可读为假', () async {
    final root = await Directory.systemTemp.createTemp('lz_missing_');
    final missing = '${root.path}/gone';
    addTearDown(() => root.delete(recursive: true));
    final store = LzRuleStore(root: missing);
    expect(await store.rootReadable, isFalse);
    final entries = await store.scan();
    expect(entries.every((entry) => !entry.exists), isTrue);
  });

  test('有规则文件时扫描出条数与导入删除', () async {
    final root = await Directory.systemTemp.createTemp('lz_rules_');
    addTearDown(() => root.delete(recursive: true));
    final lzDir = Directory('${root.path}/lz')..createSync(recursive: true);
    final jsonFile = File('${lzDir.path}/sources.json');
    await jsonFile.writeAsString('[{"a":1},{"a":2},{"a":3}]');
    final txtFile = File('${lzDir.path}/cj.txt');
    await txtFile.writeAsString('第一行\n\n第二行\n');
    Directory('${lzDir.path}/novel').createSync();
    final store = LzRuleStore(root: root.path);
    final entries = await store.scan();
    final byPath = {for (final entry in entries) entry.path.relative: entry};
    expect(byPath['lz/sources.json']!.exists, isTrue);
    expect(byPath['lz/sources.json']!.count, 3);
    expect(byPath['lz/cj.txt']!.exists, isTrue);
    expect(byPath['lz/cj.txt']!.count, 2);
    expect(byPath['lz/novel']!.exists, isTrue);
    expect(byPath['lz/novel']!.count, 0);
    expect(byPath['lz/port.txt']!.exists, isFalse);

    final imported = File('${root.path}/imported.json');
    await imported.writeAsString('[{"a":9}]');
    final dirTarget = lzRulePaths.firstWhere(
      (path) => path.relative == 'lz/novel',
    );
    await expectLater(
      () => store.importFile(dirTarget, imported),
      throwsA(isA<AppFailure>()),
    );
    final txtTarget = lzRulePaths.firstWhere(
      (path) => path.relative == 'lz/port.txt',
    );
    await store.importFile(txtTarget, imported);
    final jsonTarget = lzRulePaths.firstWhere(
      (path) => path.relative == 'lz/source.json',
    );
    await store.importFile(jsonTarget, imported);
    final rescanned = await store.scan();
    final rescannedByPath = {
      for (final entry in rescanned) entry.path.relative: entry,
    };
    expect(rescannedByPath['lz/port.txt']!.exists, isTrue);
    expect(rescannedByPath['lz/port.txt']!.count, 1);
    expect(rescannedByPath['lz/source.json']!.exists, isTrue);
    expect(rescannedByPath['lz/source.json']!.count, 1);
    await store.deleteEntry(jsonTarget);
    final deleted = await store.scan();
    expect(
      deleted
          .firstWhere((entry) => entry.path.relative == 'lz/source.json')
          .exists,
      isFalse,
    );
    await store.deleteEntry(dirTarget);
    expect(
      (await store.scan())
          .firstWhere((entry) => entry.path.relative == 'lz/novel')
          .exists,
      isFalse,
    );
  });

  test('非空目录删除被拒绝', () async {
    final root = await Directory.systemTemp.createTemp('lz_nonempty_');
    addTearDown(() => root.delete(recursive: true));
    final dir = Directory('${root.path}/lz/novel')..createSync(recursive: true);
    File('${dir.path}/x.json').writeAsStringSync('[]');
    final store = LzRuleStore(root: root.path);
    final target = lzRulePaths.firstWhere(
      (path) => path.relative == 'lz/novel',
    );
    await expectLater(
      () => store.deleteEntry(target),
      throwsA(isA<AppFailure>()),
    );
  });

  test('文件夹扫描识别实际文件与类型', () async {
    final root = await Directory.systemTemp.createTemp('lz_found_');
    addTearDown(() => root.delete(recursive: true));
    final lzDir = Directory('${root.path}/lz')..createSync(recursive: true);
    await File('${lzDir.path}/myrules.json').writeAsString('[1,2]');
    await File('${lzDir.path}/notes.txt').writeAsString('a\n\nb\n');
    await File('${lzDir.path}/rule.py').writeAsString('x = 1\n');
    await File('${lzDir.path}/helper.js').writeAsString('let a;\n');
    await File('${lzDir.path}/blob.bin').writeAsString('raw');
    final sub = Directory('${lzDir.path}/py/sy')..createSync(recursive: true);
    await File('${sub.path}/one.py').writeAsString('print(1)\n');
    final store = LzRuleStore(root: root.path);
    final found = await store.scanFolder();
    final byPath = {for (final entry in found) entry.path.relative: entry};
    expect(byPath['lz/myrules.json']!.path.kind, LzRuleKind.json);
    expect(byPath['lz/myrules.json']!.count, 2);
    expect(byPath['lz/notes.txt']!.path.kind, LzRuleKind.txt);
    expect(byPath['lz/notes.txt']!.count, 2);
    expect(byPath['lz/rule.py']!.path.kind, LzRuleKind.py);
    expect(byPath['lz/rule.py']!.count, 1);
    expect(byPath['lz/helper.js']!.path.kind, LzRuleKind.js);
    expect(byPath['lz/blob.bin']!.path.kind, LzRuleKind.other);
    expect(byPath['lz/blob.bin']!.count, isNull);
    expect(byPath['lz/py/sy/one.py']!.path.kind, LzRuleKind.py);
    expect(byPath['lz/py']!.path.kind, LzRuleKind.dir);
    expect(byPath['lz/py']!.count, 1);
    expect(found.every((entry) => entry.exists), isTrue);
  });

  test('自动新建文件夹和子文件夹路径', () async {
    final root = await Directory.systemTemp.createTemp('lz_ensure_');
    addTearDown(() => root.delete(recursive: true));
    final store = LzRuleStore(root: root.path);
    await store.ensureFolders();
    await store.ensureFolders();
    for (final dir in [
      'lz',
      'lz/novel',
      'lz/py',
      'lz/py/sy',
      'lz/js',
      'lz/wj',
      'lz/wj/直播',
      'lz/ai',
      'novel',
    ]) {
      expect(await Directory('${root.path}/$dir').exists(), isTrue);
    }
    final entries = await store.scan();
    final byPath = {for (final entry in entries) entry.path.relative: entry};
    expect(byPath['lz/novel']!.exists, isTrue);
    expect(byPath['lz/novel']!.count, 0);
    expect(byPath['lz/py/sy']!.exists, isTrue);
    expect(byPath['lz/sources.json']!.exists, isFalse);
  });

  test('没有 lz 文件夹时文件夹扫描为空', () async {
    final root = await Directory.systemTemp.createTemp('lz_nofolder_');
    addTearDown(() => root.delete(recursive: true));
    final store = LzRuleStore(root: root.path);
    expect(await store.scanFolder(), isEmpty);
  });
}
