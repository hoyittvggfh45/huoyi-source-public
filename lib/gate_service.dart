import 'package:flutter/foundation.dart';

import 'gate_config.dart';

class GateService extends ChangeNotifier {
  GateService._();

  static final GateService instance = GateService._();

  static const serverConnected = false;

  GateConfig _config = GateConfig.defaults();

  GateConfig get config => _config;

  String? get detectedRegion {
    final country = PlatformDispatcher.instance.locale.countryCode;
    if (country == null || country.isEmpty) return null;
    return country.toUpperCase() == 'CN' ? GateRegion.cn : GateRegion.overseas;
  }

  bool get regionAllowed {
    final region = detectedRegion;
    if (region == null) return true;
    return _config.regions[region] ?? true;
  }

  bool isFeatureEnabled(String key) => _config.features[key] ?? true;

  bool isModuleEnabled(String key) => _config.modules[key] ?? true;

  void refresh() {
    final next = GateConfig.defaults();
    if (next != _config) {
      _config = next;
      notifyListeners();
    }
  }

  void applyConfig(GateConfig next) {
    if (next != _config) {
      _config = next;
      notifyListeners();
    }
  }

  void resetToDefaults() => applyConfig(GateConfig.defaults());

  Future<void> saveToServer(GateConfig draft) async {
    throw UnsupportedError('服务端管理接口未接通');
  }
}
