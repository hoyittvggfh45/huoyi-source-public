import 'package:duanju_app/gate_config.dart';
import 'package:duanju_app/gate_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    GateService.instance.resetToDefaults();
  });

  test('defaults enable every known feature module and region', () {
    final config = GateConfig.defaults();
    expect(config.features.values.every((value) => value), isTrue);
    expect(config.modules.values.every((value) => value), isTrue);
    expect(config.regions.values.every((value) => value), isTrue);
    expect(config.features.length, GateFeature.all.length);
    expect(config.modules.length, GateModule.all.length);
    expect(config.regions.length, GateRegion.all.length);
  });

  test('fromJson keeps only known keys and falls back on bad values', () {
    final config = GateConfig.fromJson({
      'version': 'bad',
      'features': {'download': false, 'unknown_key': false, 'danmaku': 'yes'},
      'modules': {'live': false},
      'regions': {'cn': false},
    });
    expect(config.version, 1);
    expect(config.features['download'], isFalse);
    expect(config.features.containsKey('unknown_key'), isFalse);
    expect(config.features['danmaku'], isTrue);
    expect(config.modules['live'], isFalse);
    expect(config.modules['drama'], isTrue);
    expect(config.regions['cn'], isFalse);
    expect(config.regions['overseas'], isTrue);
  });

  test('json round trip preserves disabled switches', () {
    final config = GateConfig.defaults().copyWith(
      features: {'download': false, 'danmaku': true},
      modules: {'live': false},
    );
    final restored = GateConfig.fromJson(config.toJson());
    expect(restored.features['download'], isFalse);
    expect(restored.modules['live'], isFalse);
  });

  test('unknown keys are treated as enabled', () {
    expect(GateService.instance.isFeatureEnabled('no_such_feature'), isTrue);
    expect(GateService.instance.isModuleEnabled('no_such_module'), isTrue);
  });

  test('applyConfig disables a feature and notifies listeners', () {
    var notified = false;
    void listener() {
      notified = true;
    }

    GateService.instance.addListener(listener);
    GateService.instance.applyConfig(
      GateConfig.defaults().copyWith(
        features: Map<String, bool>.from(GateConfig.defaults().features)
          ..['download'] = false,
      ),
    );
    expect(GateService.instance.isFeatureEnabled('download'), isFalse);
    expect(notified, isTrue);
    GateService.instance.removeListener(listener);
  });

  test('refresh restores defaults after a local preview', () {
    GateService.instance.applyConfig(
      GateConfig.defaults().copyWith(
        modules: Map<String, bool>.from(GateConfig.defaults().modules)
          ..['live'] = false,
      ),
    );
    expect(GateService.instance.isModuleEnabled('live'), isFalse);
    GateService.instance.refresh();
    expect(GateService.instance.isModuleEnabled('live'), isTrue);
  });

  test('saveToServer fails without a server endpoint', () async {
    expect(GateService.serverConnected, isFalse);
    await expectLater(
      GateService.instance.saveToServer(GateConfig.defaults()),
      throwsUnsupportedError,
    );
  });
}
