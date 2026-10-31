import 'dart:convert';
import 'dart:typed_data';

import 'package:duanju_app/lab_environment.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List buildAr(Map<String, Uint8List> members) {
  final out = BytesBuilder();
  out.add('!<arch>\n'.codeUnits);
  for (final entry in members.entries) {
    final name = '${entry.key}/'.padRight(16);
    final size = entry.value.length.toString().padRight(10);
    final header =
        '$name${'0'.padRight(12)}${'0'.padRight(6)}${'0'.padRight(6)}100644  $size`\n';
    out.add(header.codeUnits);
    out.add(entry.value);
    if (entry.value.length.isOdd) {
      out.add('\n'.codeUnits);
    }
  }
  return out.takeBytes();
}

Uint8List buildElf(int machine) {
  final bytes = Uint8List(64);
  bytes[0] = 0x7F;
  bytes[1] = 0x45;
  bytes[2] = 0x4C;
  bytes[3] = 0x46;
  bytes[4] = 2;
  bytes[5] = 1;
  bytes[16] = 2;
  bytes[17] = 0;
  bytes[18] = machine & 0xFF;
  bytes[19] = (machine >> 8) & 0xFF;
  return bytes;
}

const String sampleIndex = '''
Package: php
Version: 8.5.12-1
Filename: pool/main/p/php/php_8.5.12-1_aarch64.deb
Size: 11963656
Depends: libxml2, libicu, openssl (>= 3.0), libfoo | libbar
Description: test package
 continued line

Package: libxml2
Version: 2.15.4-1
Filename: pool/main/libx/libxml2/libxml2_2.15.4-1_aarch64.deb
Size: 1000
Depends: libicu

Package: libicu
Version: 78.3
Filename: pool/main/libi/libicu/libicu_78.3_aarch64.deb
Size: 2000

Package: openssl
Version: 1:3.6.5
Filename: pool/main/o/openssl/openssl_3.6.5_aarch64.deb
Size: 3000
Depends: ca-certificates

Package: ca-certificates
Version: 1:2026.10.20-1
Filename: pool/main/c/ca-certificates/ca-certificates_2026.10.20-1_aarch64.deb
Size: 4000

Package: libfoo
Version: 1.0
Filename: pool/main/libf/libfoo/libfoo_1.0_aarch64.deb
Size: 500

Package: libbar
Version: 2.0
Filename: pool/main/libb/libbar/libbar_2.0_aarch64.deb
Size: 600
''';

void main() {
  test('parseTermuxPackages reads fields and skips continuations', () {
    final packages = parseTermuxPackages(sampleIndex);
    expect(packages.length, 7);
    expect(packages['php']!.version, '8.5.12-1');
    expect(
      packages['php']!.filename,
      'pool/main/p/php/php_8.5.12-1_aarch64.deb',
    );
    expect(packages['php']!.size, 11963656);
    expect(packages['php']!.depends, [
      'libxml2',
      'libicu',
      'openssl',
      'libfoo',
    ]);
  });

  test('parseTermuxDepends strips versions and picks first alternative', () {
    expect(
      parseTermuxDepends('a, b (>= 1.0), c | d, e [amd64]'),
      ['a', 'b', 'c', 'e'],
    );
    expect(parseTermuxDepends(''), isEmpty);
  });

  test('resolveTermuxClosure orders deps first and dedupes', () {
    final packages = parseTermuxPackages(sampleIndex);
    final closure = resolveTermuxClosure(packages, 'php');
    final names = closure.map((item) => item.name).toList();
    expect(names.toSet().length, names.length);
    expect(names.last, 'php');
    expect(names.indexOf('libicu') < names.indexOf('libxml2'), isTrue);
    expect(names.indexOf('libxml2') < names.indexOf('php'), isTrue);
    expect(names.indexOf('ca-certificates') < names.indexOf('openssl'), isTrue);
    expect(names, isNot(contains('libbar')));
  });

  test('resolveTermuxClosure throws on missing dependency', () {
    final packages = parseTermuxPackages(sampleIndex);
    packages['php'] = const TermuxPackage(
      name: 'php',
      version: '1',
      filename: 'php.deb',
      depends: ['no-such-package'],
      size: 1,
    );
    expect(
      () => resolveTermuxClosure(packages, 'php'),
      throwsA(isA<LabFailure>()),
    );
  });

  test('parseDebDataMember extracts data member from synthetic ar', () {
    final payload = Uint8List.fromList([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]);
    final deb = buildAr({
      'debian-binary': Uint8List.fromList('2.0\n'.codeUnits),
      'control.tar.xz': Uint8List.fromList([1, 2, 3]),
      'data.tar.xz': payload,
    });
    expect(parseDebDataMember(deb), payload);
  });

  test('parseDebDataMember throws without data member or bad magic', () {
    final noData = buildAr({'control.tar.xz': Uint8List.fromList([1])});
    expect(() => parseDebDataMember(noData), throwsA(isA<LabFailure>()));
    expect(
      () => parseDebDataMember(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<LabFailure>()),
    );
  });

  test('elfMachine reads e_machine and elfMachineName maps it', () {
    expect(elfMachine(buildElf(183)), 183);
    expect(elfMachine(buildElf(62)), 62);
    expect(elfMachine(buildElf(40)), 40);
    expect(elfMachine(Uint8List.fromList([1, 2, 3])), isNull);
    expect(elfMachine(Uint8List(64)), isNull);
    expect(elfMachineName(183), 'aarch64');
    expect(elfMachineName(62), 'x86_64');
    expect(elfMachineName(999), 'unknown');
  });

  test('lab paths and meta roundtrip', () {
    expect(
      labBinaryPath('/root', LabEnvironmentId.php),
      '/root/php/data/data/com.termux/files/usr/bin/php',
    );
    expect(
      labBinaryPath('/root', LabEnvironmentId.node),
      '/root/node/data/data/com.termux/files/usr/bin/node',
    );
    expect(labWwwDir('/root', LabEnvironmentId.php), '/root/php/www');
    const meta = LabMeta(version: '8.5.12-1', port: 18080, pid: 123);
    final restored = LabMeta.fromJson(
      jsonDecode(jsonEncode(meta.toJson())) as Map<String, dynamic>,
    );
    expect(restored.version, '8.5.12-1');
    expect(restored.port, 18080);
    expect(restored.pid, 123);
  });
}
