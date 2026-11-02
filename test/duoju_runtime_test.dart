import 'dart:io';

import 'package:archive/archive.dart';
import 'package:duanju_app/duoju_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('node flags keep only -- options', () {
    expect(
      duojuNodeFlags(
        'interval=2000 --incremental-marking --concurrent-marking '
        '--parallel-scavenge __sdcard__dslayer/server/node/duoju-node/index.js',
      ),
      ['--incremental-marking', '--concurrent-marking', '--parallel-scavenge'],
    );
    expect(duojuNodeFlags('__sdcard__dslayer/server/node/duoju-node/index.js'), isEmpty);
    expect(duojuNodeFlags(''), isEmpty);
  });

  test('tar.gz extraction restores files and symlinks', () async {
    final archive = Archive();
    archive.addFile(
      ArchiveFile('bin/tool', 4, [1, 2, 3, 4]),
    );
    final link = ArchiveFile('lib/libx.so.1', 0, [])
      ..symbolicLink = 'libx.so.1.2.3';
    archive.addFile(link);
    archive.addFile(
      ArchiveFile('lib/libx.so.1.2.3', 2, [5, 6]),
    );
    final gzBytes = GZipEncoder().encode(
      TarEncoder().encode(archive),
    )!;
    final dir = await Directory.systemTemp.createTemp('duoju_runtime_test');
    try {
      await extractTarGz(gzBytes, dir);
      final tool = File(path.join(dir.path, 'bin', 'tool'));
      expect(await tool.exists(), isTrue);
      expect(await tool.readAsBytes(), [1, 2, 3, 4]);
      final linkFile = Link(path.join(dir.path, 'lib', 'libx.so.1'));
      expect(await linkFile.exists(), isTrue);
      expect(await linkFile.target(), 'libx.so.1.2.3');
      final target = File(path.join(dir.path, 'lib', 'libx.so.1.2.3'));
      expect(await target.readAsBytes(), [5, 6]);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('tar.gz extraction rejects escaping entries', () async {
    final archive = Archive();
    archive.addFile(ArchiveFile('../escape.txt', 1, [9]));
    archive.addFile(ArchiveFile('ok.txt', 1, [8]));
    final gzBytes = GZipEncoder().encode(
      TarEncoder().encode(archive),
    )!;
    final dir = await Directory.systemTemp.createTemp('duoju_runtime_test');
    try {
      await extractTarGz(gzBytes, dir);
      expect(await File(path.join(dir.path, 'ok.txt')).exists(), isTrue);
      expect(
        await File(path.join(dir.parent.path, 'escape.txt')).exists(),
        isFalse,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('port file parses and tolerates garbage', () async {
    final dir = await Directory.systemTemp.createTemp('duoju_port_test');
    try {
      final dataDir = Directory(path.join(dir.path, 'jdd-data'));
      await dataDir.create();
      expect(readPortFile(dataDir), isNull);
      await File(path.join(dataDir.path, 'port.txt')).writeAsString('5690\n');
      expect(readPortFile(dataDir), 5690);
      await File(path.join(dataDir.path, 'port.txt')).writeAsString('junk');
      expect(readPortFile(dataDir), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
