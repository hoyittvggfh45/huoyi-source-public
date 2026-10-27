import 'package:duanju_app/drama_style_home.dart';
import 'package:duanju_app/hongguo_account.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/ui_style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('drama style storage round-trips all values', () {
    expect(DramaUiStyle.fullscreen.storageValue, 'fullscreen');
    expect(DramaUiStyle.ant.storageValue, 'ant');
    expect(DramaUiStyle.drama.storageValue, 'drama');
    expect(
      DramaUiStyle.fromStorageValue('fullscreen'),
      DramaUiStyle.fullscreen,
    );
    expect(DramaUiStyle.fromStorageValue('ant'), DramaUiStyle.ant);
    expect(DramaUiStyle.fromStorageValue('drama'), DramaUiStyle.drama);
    expect(DramaUiStyle.fromStorageValue('unknown'), DramaUiStyle.ant);
    expect(DramaUiStyle.fromStorageValue(null), DramaUiStyle.ant);
    expect(DramaUiStyle.fromStorageValue(''), DramaUiStyle.ant);
  });

  test('drama style labels use own descriptive copy', () {
    expect(DramaUiStyle.fullscreen.label, '首页全屏');
    expect(DramaUiStyle.ant.label, '蚂蚁');
    expect(DramaUiStyle.drama.label, '短剧');
    for (final style in DramaUiStyle.values) {
      expect(style.label.contains('MiniReel'), isFalse);
      expect(style.label.contains('短剧之家'), isFalse);
      expect(style.label.contains('蚂蚁影视'), isFalse);
      expect(style.label.contains('蚂蚁TV'), isFalse);
    }
  });

  test('drama style value lives under the drama-zone key', () {
    expect(dramaUiStyleStorageKey, 'dramaUiStyle');
    expect(dramaUiStyleStorageKey.contains('drama'), isTrue);
  });

  test('drama style persists and reloads through the drama key', () async {
    SharedPreferences.setMockInitialValues({});
    await saveDramaUiStyle(DramaUiStyle.drama);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(dramaUiStyleStorageKey), 'drama');
    expect(preferences.getString('uiStyle'), isNull);
    expect(dramaUiStyleNotifier.value, DramaUiStyle.drama);
    await saveDramaUiStyle(DramaUiStyle.ant);
    expect(dramaUiStyleNotifier.value, DramaUiStyle.ant);
  });

  test('groupDramaSections groups by item category in order', () {
    final sections = groupDramaSections([
      const Drama(id: 'a:1', source: 'a', title: '甲', category: '真人剧'),
      const Drama(id: 'a:2', source: 'a', title: '乙', category: '漫剧'),
      const Drama(id: 'a:3', source: 'a', title: '丙', category: '真人剧'),
      const Drama(id: 'a:4', source: 'a', title: '丁', kind: 'folder'),
    ], '全部');
    expect([for (final section in sections) section.title], ['真人剧', '漫剧']);
    expect(sections[0].items.length, 2);
    expect(sections[1].items.length, 1);
  });

  test('groupDramaSections falls back to the given title', () {
    final sections = groupDramaSections([
      const Drama(id: 'a:1', source: 'a', title: '甲'),
      const Drama(id: 'a:2', source: 'a', title: '乙'),
    ], '全部');
    expect(sections.length, 1);
    expect(sections[0].title, '全部');
    expect(sections[0].items.length, 2);
    expect(groupDramaSections([], '全部'), isEmpty);
  });

  test('hongguo account masks phones and round-trips json', () {
    expect(HongguoAccount.maskPhone('13812345678'), '138****5678');
    expect(HongguoAccount.maskPhone(''), '');
    const account = HongguoAccount(
      userId: '123',
      displayName: '测试账号',
      maskedPhone: '138****5678',
      method: 'sms',
    );
    final restored = HongguoAccount.fromJson(account.toJson());
    expect(restored.userId, '123');
    expect(restored.displayName, '测试账号');
    expect(restored.maskedPhone, '138****5678');
    expect(restored.methodLabel, '短信登录');
    expect(account.loggedIn, isTrue);
    expect(
      const HongguoAccount(userId: '', displayName: '', method: 'sms').loggedIn,
      isFalse,
    );
  });

  test('hongguo account persists under an app-level key', () async {
    SharedPreferences.setMockInitialValues({});
    const account = HongguoAccount(
      userId: '123',
      displayName: '测试账号',
      method: 'qr',
    );
    await saveHongguoAccount(account);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(hongguoAccountStorageKey), contains('123'));
    expect(hongguoAccountNotifier.value?.methodLabel, '扫码登录');
    await clearHongguoAccount();
    expect(preferences.getString(hongguoAccountStorageKey), isNull);
    expect(hongguoAccountNotifier.value, isNull);
  });
}
