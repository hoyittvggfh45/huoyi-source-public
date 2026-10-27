import 'package:shared_preferences/shared_preferences.dart';

class MiniAppStorage {
  MiniAppStorage(this._prefs, this.appId);
  final SharedPreferences _prefs;
  final String appId;

  String _key(String key) => 'miniapp:$appId:$key';

  Future<String?> get(String key) async => _prefs.getString(_key(key));

  Future<void> set(String key, String value) =>
      _prefs.setString(_key(key), value);

  Future<void> remove(String key) => _prefs.remove(_key(key));

  List<String> keys() {
    final prefix = 'miniapp:$appId:';
    return _prefs
        .getKeys()
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .toList();
  }
}
