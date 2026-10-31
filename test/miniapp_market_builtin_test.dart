import 'dart:convert';

import 'package:duanju_app/miniapp/market.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builtin market asset parses to the full market list', () async {
    final text = await rootBundle.loadString(
      'assets/miniapps/market/market.json',
    );
    final items = parseMarketJson(jsonDecode(text));
    expect(items.length, 15);
    expect(
      items.map((item) => item.appId),
      containsAll([
        'com.logvar.danmu',
        'com.leospring.emby',
        'com.leospring.demo',
        'com.leospring.migu_video.node',
      ]),
    );
    for (final item in items) {
      expect(item.name, isNotEmpty);
      expect(item.url, startsWith('https://'));
    }
    expect(
      items.where((item) => item.isZip).length,
      14,
    );
  });

}
