import 'dart:io';

import 'package:duanju_app/jar_site_config.dart';
import 'package:duanju_app/zakatv_builtin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builtin jar configs json parses and covers YouTube', () {
    final text = File('assets/jar_site_configs.json').readAsStringSync();
    final configs = parseJarSiteConfigs(text);
    expect(configs.length, greaterThan(100));
    final yt = matchJarSiteConfig(
      'com.github.catvod.spider.YouTube',
      configs,
    );
    expect(yt, isNotNull);
    expect(yt!.key, 'youtube');
    expect(yt.name, 'YouTube');
    expect(yt.ext, '{"proxy":""}');
    final haijiao = matchJarSiteConfig(
      'com.github.catvod.spider.ZakaHaijiaoAmns',
      configs,
    );
    expect(haijiao, isNotNull);
    expect(haijiao!.key, 'ZakaHaijiao');
    expect(
      matchJarSiteConfig('com.github.catvod.spider.NotInJson', configs),
      isNull,
    );
  });

  test('Qinav is built in and auto-configures on import', () {
    final site = zakatvBuiltinSites.firstWhere(
      (site) => site.key == 'Qinav',
    );
    expect(site.className, 'com.github.catvod.spider.Qinav');
    expect(site.name, '🔞Qinav');
    final text = File('assets/jar_site_configs.json').readAsStringSync();
    final configs = parseJarSiteConfigs(text);
    final matched = matchJarSiteConfig(site.className, configs);
    expect(matched, isNotNull);
    expect(matched!.key, 'Qinav');
    expect(matched.name, '🔞Qinav');
  });

  test('rewritten YouTube spider auto-configures on import', () {
    final text = File('assets/jar_site_configs.json').readAsStringSync();
    final configs = parseJarSiteConfigs(text);
    final matched = matchJarSiteConfig(
      'com.github.catvod.spider.YtNewAmns',
      configs,
    );
    expect(matched, isNotNull);
    expect(matched!.key, 'ZakaYouTube');
    expect(matched.name, '油管');
    expect(matched.ext, '{"proxy":""}');
  });

  test('builtin jar configs asset constant points at the json file', () {
    expect(builtinJarConfigsAsset, 'assets/jar_site_configs.json');
    expect(File(builtinJarConfigsAsset).existsSync(), isTrue);
  });
}
