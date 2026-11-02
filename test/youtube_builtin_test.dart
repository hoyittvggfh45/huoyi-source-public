import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:duanju_app/zakatv_builtin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builtin YouTube points at the rewritten spider class', () {
    final site = zakatvBuiltinSites.firstWhere(
      (site) => site.key == 'ZakaYouTube',
    );
    expect(site.name, '油管');
    expect(site.className, 'com.github.catvod.spider.YtNewAmns');
    expect(site.ext, '{"proxy":""}');
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
