import 'package:shared_preferences/shared_preferences.dart';

class TdlibRoute {
  TdlibRoute._();

  static const key = 'tgdrama_route';
  static const plugin = 'plugin';
  static const tdlib = 'tdlib';

  static Future<String> current() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key);
    return value == tdlib ? tdlib : plugin;
  }

  static Future<bool> get isTdlib async => await current() == tdlib;

  static Future<void> set(String route) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, route == tdlib ? tdlib : plugin);
  }
}
