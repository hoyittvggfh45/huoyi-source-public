import 'dart:io';

import 'package:duanju_app/rfw_theme/rfw_theme_store.dart';
import 'package:flutter_test/flutter_test.dart';

const validTheme = '''
import core.widgets;
import peek.home;

widget root = Container(
  color: 0xFFFAF6EE,
  child: Text(text: "hello"),
);
''';

const missingRootTheme = '''
import core.widgets;

widget other = Container(
  color: 0xFFFAF6EE,
);
''';

const badImportTheme = '''
import core.widgets;
import some.other;

widget root = Container(
  color: 0xFFFAF6EE,
);
''';

void main() {
  test('valid theme passes validation', () {
    expect(validateRfwThemeText(validTheme).ok, true);
  });

  test('empty text is rejected', () {
    final result = validateRfwThemeText('  \n');
    expect(result.ok, false);
    expect(result.reason, contains('为空'));
  });

  test('broken syntax is rejected', () {
    final result = validateRfwThemeText('import core.widgets;\nwidget root = ');
    expect(result.ok, false);
    expect(result.reason, contains('解析失败'));
  });

  test('missing root is rejected', () {
    final result = validateRfwThemeText(missingRootTheme);
    expect(result.ok, false);
    expect(result.reason, contains('root'));
  });

  test('unsupported import is rejected', () {
    final result = validateRfwThemeText(badImportTheme);
    expect(result.ok, false);
    expect(result.reason, contains('some.other'));
  });

  test('import stores, lists, rejects duplicates, deletes', () async {
    final dir = await Directory.systemTemp.createTemp('rfw_theme_test');
    try {
      final first = await importRfwThemeText(
        'my theme.rfwtxt',
        validTheme,
        directory: dir,
      );
      expect(first.ok, true);
      expect(first.entry?.name, 'my theme');
      final entries = await loadRfwThemeEntries(directory: dir);
      final imported = entries.where((entry) => !entry.isBuiltin).toList();
      expect(imported.length, 1);
      expect(imported.first.fileName, 'my theme.rfwtxt');
      final text = await loadRfwThemeText(imported.first, directory: dir);
      expect(text, validTheme);
      final duplicate = await importRfwThemeText(
        'my theme.rfwtxt',
        validTheme,
        directory: dir,
      );
      expect(duplicate.ok, false);
      expect(duplicate.message, contains('已存在'));
      final renamed = await importRfwThemeText(
        'my theme.rfwtxt',
        validTheme.replaceFirst('hello', 'world'),
        directory: dir,
      );
      expect(renamed.ok, true);
      expect(renamed.entry?.fileName, 'my theme-2.rfwtxt');
      final removed = await deleteImportedRfwTheme(
        imported.first,
        directory: dir,
      );
      expect(removed, true);
      final remaining = await loadRfwThemeEntries(directory: dir);
      expect(remaining.where((entry) => !entry.isBuiltin).length, 1);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('builtin entries are never deletable', () async {
    final dir = await Directory.systemTemp.createTemp('rfw_theme_test');
    try {
      expect(
        await deleteImportedRfwTheme(builtinRfwThemes.first, directory: dir),
        false,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('file name keeps readable characters and strips the suffix', () {
    expect(rfwThemeFileName('我的主题.rfwtxt'), '我的主题.rfwtxt');
    expect(rfwThemeFileName('plain'), 'plain.rfwtxt');
    expect(rfwThemeFileName('a/b\\c.rfwtxt'), 'c.rfwtxt');
  });
}
