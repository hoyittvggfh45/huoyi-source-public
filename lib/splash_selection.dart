import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

const splashPrefsKey = 'splash_selection_v1';
const splashSelectionDefault = 'default';
const splashSelectionCustom = 'custom';
const splashCustomMaxBytes = 10 * 1024 * 1024;
const splashCustomExtensions = {'png', 'jpg', 'jpeg', 'webp'};

const splashSetAntCinema = 'ant_cinema';
const splashSetWindows = 'windows';
const splashSetIos = 'ios';
const splashSetHuawei = 'huawei';
const splashSetNeonAnt = 'neon_ant';
const splashSetStarryAnt = 'starry_ant';
const splashSetFilm = 'film';
const splashSetMinimalLines = 'minimal_lines';
const splashSetMidnightCinema = 'midnight_cinema';
const splashSetLaserAnt = 'laser_ant';

const splashSetIds = {
  splashSetAntCinema,
  splashSetWindows,
  splashSetIos,
  splashSetHuawei,
  splashSetNeonAnt,
  splashSetStarryAnt,
  splashSetFilm,
  splashSetMinimalLines,
  splashSetMidnightCinema,
  splashSetLaserAnt,
};

bool isBuiltinSplashSetId(String id) => splashSetIds.contains(id);

String normalizeSplashSelection(String? raw) {
  if (raw == null || raw.isEmpty) return splashSelectionDefault;
  if (raw == splashSelectionDefault ||
      raw == splashSelectionCustom ||
      isBuiltinSplashSetId(raw)) {
    return raw;
  }
  return splashSelectionDefault;
}

Future<String> loadSplashSelection() async {
  final prefs = await SharedPreferences.getInstance();
  return normalizeSplashSelection(prefs.getString(splashPrefsKey));
}

Future<void> saveSplashSelection(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(splashPrefsKey, normalizeSplashSelection(id));
}

String? validateCustomImage({required String extension, required int bytes}) {
  if (!splashCustomExtensions.contains(extension.toLowerCase())) {
    return '不支持的图片格式，仅支持 PNG、JPG、JPEG、WEBP';
  }
  if (bytes <= 0) return '图片文件为空';
  if (bytes > splashCustomMaxBytes) return '图片过大，须小于 10MB';
  return null;
}

String customSplashFileName(String extension) =>
    'custom_splash.${extension.toLowerCase()}';

String customSplashPath(String dirPath, String extension) =>
    '$dirPath/splash/${customSplashFileName(extension)}';

File? findCustomSplashFile(String dirPath) {
  for (final ext in splashCustomExtensions) {
    final file = File(customSplashPath(dirPath, ext));
    if (file.existsSync()) return file;
  }
  return null;
}

Future<void> deleteCustomSplashFiles(String dirPath) async {
  for (final ext in splashCustomExtensions) {
    final file = File(customSplashPath(dirPath, ext));
    if (file.existsSync()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
