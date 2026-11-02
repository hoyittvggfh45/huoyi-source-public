import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:duanju_app/zakatv_builtin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('油管内置站用另一个修复版 jar，与已内置的 YouTube jar 不同', () {
    expect(youtubeFixSiteName, '油管');
    expect(youtubeFixJarId, isNot('zakatv'));
    expect(youtubeFixJarId, isNotEmpty);
    final fixBytes = File('assets/jars/youtube2.jar').readAsBytesSync();
    final youtubeBytes = File('assets/jars/youtube.jar').readAsBytesSync();
    expect(md5.convert(fixBytes).toString(), youtubeFixJarMd5);
    expect(md5.convert(fixBytes).toString(), isNot(youtubeJarMd5));
    expect(fixBytes, isNot(youtubeBytes));
    expect(fixBytes.length, 175229);
  });

  test('油管修复版 jar 内含 classes.dex', () {
    final bytes = File('assets/jars/youtube2.jar').readAsBytesSync();
    expect(bytes.sublist(0, 2), [0x50, 0x4b]);
    final decoded = String.fromCharCodes(bytes);
    expect(decoded, contains('classes.dex'));
  });
}
