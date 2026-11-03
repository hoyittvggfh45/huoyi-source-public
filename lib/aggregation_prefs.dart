import 'package:shared_preferences/shared_preferences.dart';

class AggregationPrefs {
  static const String experimentEnabledKey =
      'aggregation_experiment_enabled';

  static Future<bool> experimentEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(experimentEnabledKey) ?? true;
  }

  static Future<void> setExperimentEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(experimentEnabledKey, value);
  }
}
