import 'package:flutter/material.dart';

import 'atmosphere_background.dart';

abstract final class AppGradientColors {
  static const Color gold = Color(0xFFFFC93C);
  static const Color fixedTop = Color(0xFF0E5A72);
  static const Color fixedBottom = Color(0xFF3D0F33);
}

Color darkenForGradient(Color color, double amount) {
  final factor = (1 - amount.clamp(0.0, 1.0)).toDouble();
  return Color.fromRGBO(
    (color.r * 255 * factor).round(),
    (color.g * 255 * factor).round(),
    (color.b * 255 * factor).round(),
    1,
  );
}

List<Color> gradientColorsForPalette(AtmospherePalette? palette) {
  if (palette == null) {
    return const [AppGradientColors.fixedTop, AppGradientColors.fixedBottom];
  }
  final top = darkenForGradient(palette.primary, 0.3);
  var bottom = darkenForGradient(palette.secondary, 0.62);
  if (bottom.computeLuminance() > 0.15) {
    bottom = darkenForGradient(palette.secondary, 0.8);
  }
  return [top, bottom];
}

ThemeData gradientDarkThemeData() {
  final dark = ThemeData.dark();
  return dark.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    colorScheme: dark.colorScheme.copyWith(
      primary: const Color(0xFFE75480),
      secondary: const Color(0xFFE75480),
    ),
    chipTheme: dark.chipTheme.copyWith(
      backgroundColor: Colors.white.withValues(alpha: 0.12),
      selectedColor: Colors.black38,
      labelStyle: const TextStyle(color: Colors.white),
      secondaryLabelStyle: const TextStyle(
        color: AppGradientColors.gold,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class AppGradientBackground extends StatelessWidget {
  const AppGradientBackground({
    super.key,
    required this.colors,
    required this.child,
  });

  final List<Color> colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
