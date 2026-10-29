import 'package:duanju_app/hiker_miniapp/hiker_builtin_cloud_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builtin cloud codes keep every user entry', () {
    expect(hikerBuiltinCloudCodes.length, 29);
    for (final entry in hikerBuiltinCloudCodes) {
      expect(entry.name.isNotEmpty, isTrue);
      expect(entry.category.isNotEmpty, isTrue);
      expect(entry.code.isNotEmpty, isTrue);
      expect(entry.code.startsWith('云'), isTrue);
      expect(entry.code.contains('/'), isTrue);
      expect(entry.code.contains(' '), isFalse);
      expect(entry.code.contains('\n'), isFalse);
    }
  });

  test('adult entries are marked', () {
    final adults = [
      for (final entry in hikerBuiltinCloudCodes)
        if (entry.adult) entry.name,
    ];
    expect(adults, ['51视频区', 'MissAV', '蜜桃仙子', '18AV', 'stripchat']);
    for (final entry in hikerBuiltinCloudCodes) {
      if (entry.adult) expect(entry.category, '成人视频');
    }
  });

  test('shared codes keep both names', () {
    final grrb = [
      for (final entry in hikerBuiltinCloudCodes)
        if (entry.code == '云5oooole/grrb') entry.name,
    ];
    expect(grrb, ['魔法影视', '叶子音乐']);
    final dduk = [
      for (final entry in hikerBuiltinCloudCodes)
        if (entry.code == '云5oooole/dduk') entry.name,
    ];
    expect(dduk, ['1234影视', '云朵视频(关梯)']);
    final codes = {for (final entry in hikerBuiltinCloudCodes) entry.code};
    expect(codes.length, 27);
  });

  test('same name different codes are kept apart', () {
    final magic = [
      for (final entry in hikerBuiltinCloudCodes)
        if (entry.name == '魔法影视') entry.code,
    ];
    expect(magic, ['云5oooole/grrb', '云5oooole/8nem']);
    final cloud = [
      for (final entry in hikerBuiltinCloudCodes)
        if (entry.name == '云朵视频(关梯)') entry.code,
    ];
    expect(cloud, ['云5oooole/wxxh', '云5oooole/dduk']);
    final longjiang = [
      for (final entry in hikerBuiltinCloudCodes)
        if (entry.name == '龙江影院(关梯)') entry.code,
    ];
    expect(longjiang, ['云5oooole/cwm5']);
  });

  test('categories and notes are preserved', () {
    String categoryOf(String name) => hikerBuiltinCloudCodes
        .firstWhere((entry) => entry.name == name)
        .category;
    expect(categoryOf('声阅APP'), '听书');
    expect(categoryOf('顶点小说'), '阅读');
    expect(categoryOf('叶子音乐'), '音乐');
    expect(categoryOf('蜜桃仙子'), '成人视频');
    final wolong = hikerBuiltinCloudCodes.firstWhere(
      (entry) => entry.name == '卧龙影院',
    );
    expect(wolong.note, '有广告去不掉');
    final missav = hikerBuiltinCloudCodes.firstWhere(
      (entry) => entry.name == 'MissAV',
    );
    expect(missav.note, '看视频进去之后点封面播放');
    expect(missav.code, '云5oooole/78y7');
  });
}
