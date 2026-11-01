import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:duanju_app/zakatv_builtin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builtin YouTube points at the repaired spider class', () {
    final site = zakatvBuiltinSites.firstWhere(
      (site) => site.key == 'ZakaYouTube',
    );
    expect(site.name, 'YouTube');
    expect(site.className, youtubeSpiderClass);
    expect(site.className, 'com.github.catvod.spider.YouTube');
  });

  test('merged zakatv jar md5 matches the asset on disk', () {
    final bytes = File('assets/jars/zakatv.jar').readAsBytesSync();
    expect(md5.convert(bytes).toString(), zakatvJarMd5);
  });

  test('standalone youtube jar md5 matches the asset on disk', () {
    final bytes = File('assets/jars/youtube.jar').readAsBytesSync();
    expect(md5.convert(bytes).toString(), youtubeJarMd5);
  });
}
