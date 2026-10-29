import 'dart:io';

import 'package:duanju_app/splash_selection.dart';
import 'package:duanju_app/splash_sets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('registry holds exactly ten animated sets', () {
    expect(splashSets.length, 10);
    final ids = splashSets.map((set) => set.id).toSet();
    expect(ids.length, 10);
    expect(ids, splashSetIds);
    for (final set in splashSets) {
      expect(set.name.isNotEmpty, isTrue);
      expect(set.effect.isNotEmpty, isTrue);
      expect(set.name.contains('火蚁TV'), isFalse);
      expect(set.effect.contains('火蚁TV'), isFalse);
    }
  });

  test('registry lookup and display names', () {
    expect(splashSetById(splashSetNeonAnt)?.name, '霓虹火蚁');
    expect(splashSetById(splashSetLaserAnt)?.name, '激光电影');
    expect(splashSetById(splashSetIos)?.name, 'iOS 风格');
    expect(splashSetById(splashSetHuawei)?.name, '华为鸿蒙风格');
    expect(splashSetById('bogus'), isNull);
    expect(splashSelectionDisplayName(splashSelectionDefault), '默认启动图');
    expect(splashSelectionDisplayName(splashSelectionCustom), '自定义图片');
    expect(splashSelectionDisplayName(splashSetFilm), '胶片放映');
    expect(splashSelectionDisplayName('bogus'), '默认启动图');
  });

  test('selection normalization keeps only known ids', () {
    expect(normalizeSplashSelection(null), splashSelectionDefault);
    expect(normalizeSplashSelection(''), splashSelectionDefault);
    expect(normalizeSplashSelection('bogus'), splashSelectionDefault);
    expect(
      normalizeSplashSelection(splashSelectionCustom),
      splashSelectionCustom,
    );
    expect(normalizeSplashSelection(splashSetLaserAnt), splashSetLaserAnt);
  });

  test('custom image validation rejects bad format, empty and oversize', () {
    expect(validateCustomImage(extension: 'gif', bytes: 100), isNotNull);
    expect(validateCustomImage(extension: 'bmp', bytes: 100), isNotNull);
    expect(validateCustomImage(extension: 'png', bytes: 0), isNotNull);
    expect(
      validateCustomImage(extension: 'png', bytes: splashCustomMaxBytes + 1),
      isNotNull,
    );
    expect(validateCustomImage(extension: 'png', bytes: 100), isNull);
    expect(validateCustomImage(extension: 'JPG', bytes: 100), isNull);
    expect(validateCustomImage(extension: 'webp', bytes: 100), isNull);
  });

  test('custom file helpers round trip in a temp dir', () async {
    final dir = await Directory.systemTemp.createTemp('splash_test_');
    try {
      expect(findCustomSplashFile(dir.path), isNull);
      final target = File(customSplashPath(dir.path, 'png'));
      await target.parent.create(recursive: true);
      await target.writeAsBytes([1, 2, 3]);
      expect(findCustomSplashFile(dir.path)?.path, target.path);
      await deleteCustomSplashFiles(dir.path);
      expect(findCustomSplashFile(dir.path), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('selection persists through shared preferences', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    expect(await loadSplashSelection(), splashSelectionDefault);
    await saveSplashSelection(splashSetNeonAnt);
    expect(await loadSplashSelection(), splashSetNeonAnt);
    await saveSplashSelection('bogus');
    expect(await loadSplashSelection(), splashSelectionDefault);
  });
}
