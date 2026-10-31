import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duanju_app/app_gradient.dart';
import 'package:duanju_app/atmosphere_background.dart';
import 'package:duanju_app/episode_browser.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/remote_widgets.dart';

void main() {
  test('darkenForGradient mixes toward black', () {
    expect(
      darkenForGradient(const Color(0xFFFFFFFF), 0.5),
      const Color(0xFF808080),
    );
    expect(
      darkenForGradient(const Color(0xFF000000), 0.5),
      const Color(0xFF000000),
    );
    expect(
      darkenForGradient(const Color(0xFF123456), 1.5),
      const Color(0xFF000000),
    );
    expect(
      darkenForGradient(const Color(0xFF123456), -0.5),
      const Color(0xFF123456),
    );
  });

  test('gradientColorsForPalette falls back to the unified pair', () {
    expect(gradientColorsForPalette(null), const [
      AppGradientColors.fixedTop,
      AppGradientColors.fixedBottom,
    ]);
  });

  test('gradientColorsForPalette darkens poster colors for white text', () {
    final colors = gradientColorsForPalette(
      const AtmospherePalette(Color(0xFFFFFFFF), Color(0xFFFFFFFF)),
    );
    expect(colors.length, 2);
    expect(colors[1].computeLuminance(), lessThanOrEqualTo(0.15));
    expect(colors[0], darkenForGradient(const Color(0xFFFFFFFF), 0.3));
  });

  test('gradientDarkThemeData keeps text readable on the gradient', () {
    final theme = gradientDarkThemeData();
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, Colors.transparent);
    expect(theme.chipTheme.selectedColor, Colors.black38);
    expect(theme.chipTheme.labelStyle?.color, Colors.white);
    expect(theme.chipTheme.secondaryLabelStyle?.color, AppGradientColors.gold);
    expect(theme.appBarTheme.backgroundColor, Colors.transparent);
  });

  testWidgets('AppGradientBackground paints the gradient behind its child', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppGradientBackground(
          colors: [Color(0xFF0E5A72), Color(0xFF3D0F33)],
          child: Text('gradient-child'),
        ),
      ),
    );
    expect(find.text('gradient-child'), findsOneWidget);
    final decorated = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final gradient =
        (decorated.decoration as BoxDecoration).gradient as LinearGradient;
    expect(gradient.colors, const [Color(0xFF0E5A72), Color(0xFF3D0F33)]);
  });

  testWidgets('EpisodeRangeBar shows range chips on phones', (tester) async {
    var located = -1;
    final episodes = List.generate(
      120,
      (index) => Episode({'id': 'e$index'}, index + 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EpisodeRangeBar(
            episodes: episodes,
            page: 0,
            onLocate: (index) => located = index,
          ),
        ),
      ),
    );
    expect(find.text('1-50'), findsOneWidget);
    expect(find.text('51-100'), findsOneWidget);
    expect(find.text('101-120'), findsOneWidget);
    expect(find.byKey(const ValueKey('episode-range-1')), findsOneWidget);
    await tester.tap(find.text('51-100'));
    expect(located, 50);
  });

  testWidgets('RemoteEpisodeButton paints the current number gold on demand', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteEpisodeButton(
            number: 5,
            current: true,
            selectedForegroundColor: AppGradientColors.gold,
            onPressed: () {},
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('5'));
    expect(text.style?.color, AppGradientColors.gold);
  });
}
