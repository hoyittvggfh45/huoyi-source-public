import 'package:duanju_app/miniapp_center.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ciliSample = '''
// 磁力君.简 数据文件（重构件）
// 来源：潇洒哥 2026-10-03 导出的规则整包备份
var version = 223;
var rrules = [];
''';

const _hikerUrlSample = '''
/**
 * @name 海阔url点击事件生成工具
 * @Author LoyDgIk
 * @version 6
 */
!(function(windows) {});
''';

void main() {
  test('parse cili rule meta', () {
    final meta = parseMiniAppMeta(_ciliSample, '磁力君.简.js');
    expect(meta.name, '磁力君.简');
    expect(meta.version, '223');
    expect(meta.description.contains('磁力君.简 数据文件'), isTrue);
  });

  test('parse hikerurl doc meta', () {
    final meta = parseMiniAppMeta(_hikerUrlSample, 'Hikerurl.js');
    expect(meta.name, '海阔url点击事件生成工具');
    expect(meta.version, '6');
  });

  test('import store round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await MiniAppStore.addImport(prefs, 'test.js', _ciliSample);
    var loaded = MiniAppStore.loadImports(prefs);
    expect(loaded.length, 1);
    expect(loaded.first.name, 'test');
    expect(loaded.first.version, '223');
    await MiniAppStore.addImport(prefs, 'test.js', _hikerUrlSample);
    loaded = MiniAppStore.loadImports(prefs);
    expect(loaded.length, 1);
    expect(loaded.first.name, '海阔url点击事件生成工具');
    await MiniAppStore.removeImport(prefs, 'test.js');
    expect(MiniAppStore.loadImports(prefs), isEmpty);
  });
}
