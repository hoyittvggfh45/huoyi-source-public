import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/theme_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pure light mode forces white surfaces', () {
    final themed = applyThemePreferences(
      AppTheme.platformLight,
      modeStyle: 'pureLight',
    );
    expect(themed.brightness, Brightness.light);
    expect(themed.scaffoldBackgroundColor, Colors.white);
    expect(themed.colorScheme.surface, Colors.white);
    expect(themed.drawerTheme.backgroundColor, Colors.white);
  });

  test('pure dark mode forces black surfaces', () {
    final themed = applyThemePreferences(
      AppTheme.platformDark,
      modeStyle: 'pureDark',
    );
    expect(themed.brightness, Brightness.dark);
    expect(themed.scaffoldBackgroundColor, Colors.black);
    expect(themed.colorScheme.surface, Colors.black);
    expect(themed.drawerTheme.backgroundColor, Colors.black);
  });

  test('accent overrides primary and mode selects theme', () {
    final themed = applyThemePreferences(
      AppTheme.platformLight,
      accent: 'green',
    );
    expect(themed.colorScheme.primary, const Color(0xFF2E7D32));
    expect(themeModeFor('pureLight', 'system'), ThemeMode.light);
    expect(themeModeFor('pureDark', 'system'), ThemeMode.dark);
    expect(themeModeFor('', 'dark'), ThemeMode.dark);
    expect(themeModeFor('', 'system'), ThemeMode.system);
  });

  test('paper style uses serif titles, candy uses stadium buttons', () {
    final paper = applyThemePreferences(AppTheme.light, style: 'paper');
    expect(paper.textTheme.titleMedium?.fontFamily, 'serif');
    final candy = applyThemePreferences(AppTheme.light, style: 'candy');
    expect(candy.filledButtonTheme.style?.shape?.resolve({}), isA<StadiumBorder>());
  });

  test('theme prefs roundtrip through LocalStore', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(store.themeModeStyle, '');
    expect(store.themeBackground, 'theme');
    await store.setThemeModeStyle('pureDark');
    await store.setThemeStyle('glass');
    await store.setThemeAccent('blue');
    await store.setThemeBackground('gradient');
    expect(store.themeModeStyle, 'pureDark');
    expect(store.themeStyle, 'glass');
    expect(store.themeAccent, 'blue');
    expect(store.themeBackground, 'gradient');
    await store.resetThemeSettings();
    expect(store.themeModeStyle, '');
    expect(store.themeStyle, '');
    expect(store.themeAccent, '');
    expect(store.themeBackground, 'theme');
    store.dispose();
  });
}
