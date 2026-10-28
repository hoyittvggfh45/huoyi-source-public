import 'dart:io';

import 'package:archive/archive.dart';
import 'package:duanju_app/miniapp/installer.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _encode(Archive archive) => ZipEncoder().encode(archive);

void main() {
  test('installer installs two-level nested zip', () async {
    final root = await Directory.systemTemp.createTemp('jhminiapp_root_');
    try {
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'outer/app/manifest.json',
            '{"id":"deep","name":"深嵌套","entry":"index.html"}',
          ),
        )
        ..add(ArchiveFile.string('outer/app/index.html', '<h1>deep</h1>'));
      final manifest = await MiniAppInstaller(
        root,
      ).installFromZip(_encode(archive));
      expect(manifest.id, 'deep');
      expect(
        await File('${root.path}/deep/index.html').readAsString(),
        '<h1>deep</h1>',
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('installer skips macosx junk', () async {
    final root = await Directory.systemTemp.createTemp('jhminiapp_root_');
    try {
      final archive = Archive()
        ..add(ArchiveFile.string('__MACOSX/manifest.json', 'not json{{'))
        ..add(
          ArchiveFile.string(
            'pkg/manifest.json',
            '{"id":"pkg","name":"包","entry":"index.html"}',
          ),
        )
        ..add(ArchiveFile.string('pkg/index.html', '<h1>pkg</h1>'));
      final manifest = await MiniAppInstaller(
        root,
      ).installFromZip(_encode(archive));
      expect(manifest.id, 'pkg');
      expect(
        await File('${root.path}/pkg/index.html').readAsString(),
        '<h1>pkg</h1>',
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'installer skips candidates missing entry and fails when none qualify',
    () async {
      final root = await Directory.systemTemp.createTemp('jhminiapp_root_');
      try {
        final installer = MiniAppInstaller(root);
        final archive = Archive()
          ..add(ArchiveFile.string('manifest.json', 'not json{{'))
          ..add(
            ArchiveFile.string(
              'bad/manifest.json',
              '{"id":"bad","name":"坏候选","entry":"missing.html"}',
            ),
          )
          ..add(
            ArchiveFile.string(
              'good/manifest.json',
              '{"id":"good","name":"好候选","entry":"index.html"}',
            ),
          )
          ..add(ArchiveFile.string('good/index.html', '<h1>good</h1>'));
        final manifest = await installer.installFromZip(_encode(archive));
        expect(manifest.id, 'good');
        final onlyBad = Archive()
          ..add(
            ArchiveFile.string(
              'bad/manifest.json',
              '{"id":"bad","name":"坏候选","entry":"missing.html"}',
            ),
          );
        expect(
          installer.installFromZip(_encode(onlyBad)),
          throwsFormatException,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
