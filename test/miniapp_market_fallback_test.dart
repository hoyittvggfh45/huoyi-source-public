import 'dart:io';

import 'package:duanju_app/miniapp/installer.dart';
import 'package:duanju_app/miniapp/market.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ghfast market url falls back to direct raw url', () {
    expect(
      MarketClient.directFallbackUrl(
        'https://ghfast.top/https://raw.githubusercontent.com/a/b/main/market.json',
      ),
      'https://raw.githubusercontent.com/a/b/main/market.json',
    );
    expect(
      MarketClient.directFallbackUrl(
        'https://raw.githubusercontent.com/a/b/main/market.json',
      ),
      isNull,
    );
  });

  test('installer installs manifest-only online site and lists it', () async {
    final root = await Directory.systemTemp.createTemp('jhminiapp_root_');
    try {
      final manifest = await MiniAppInstaller(root).installManifest(
        '{"appId":"com.leospring.online_site","name":"在线站点示例","entry":"https://example.com/","renderer":"webview"}',
      );
      expect(manifest.id, 'com.leospring.online_site');
      expect(
        await File('${root.path}/com.leospring.online_site/manifest.json')
            .exists(),
        isTrue,
      );
      final listed = await MiniAppInstaller(root).list();
      expect(
        listed.map((item) => item.id),
        contains('com.leospring.online_site'),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
