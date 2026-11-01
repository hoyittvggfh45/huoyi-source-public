import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'local_store.dart';

class ThemeOption {
  const ThemeOption(this.id, this.name);

  final String id;
  final String name;
}

const themeModeStyleOptions = [
  ThemeOption('pureLight', '极白'),
  ThemeOption('pureDark', '极黑'),
];

const themeStyleOptions = [
  ThemeOption('neon', '霓虹暗夜'),
  ThemeOption('deep', '深邃'),
  ThemeOption('candy', '糖果活力'),
  ThemeOption('paper', '纸感复古'),
  ThemeOption('glass', '磨砂玻璃'),
  ThemeOption('aurora', '极光渐变'),
];

class ThemeAccentOption {
  const ThemeAccentOption(this.id, this.name, this.color);

  final String id;
  final String name;
  final Color color;
}

const themeAccentOptions = [
  ThemeAccentOption('default', '默认', Color(0xFFFF664F)),
  ThemeAccentOption('green', '绿系', Color(0xFF2E7D32)),
  ThemeAccentOption('blue', '蓝系', Color(0xFF1565C0)),
  ThemeAccentOption('purple', '紫系', Color(0xFF6A1B9A)),
  ThemeAccentOption('red', '红系', Color(0xFFC62828)),
  ThemeAccentOption('orange', '橙系', Color(0xFFEF6C00)),
];

const themeBackgroundOptions = [
  ThemeOption('theme', '跟随主题'),
  ThemeOption('solid', '纯色'),
  ThemeOption('gradient', '渐变'),
  ThemeOption('custom', '自定义图片'),
];

const themeBackgroundFileName = 'theme_background_image';

Color? themeAccentColor(String id) {
  for (final option in themeAccentOptions) {
    if (option.id == id) return option.color;
  }
  return null;
}

ThemeMode themeModeFor(String modeStyle, String legacyMode) {
  if (modeStyle == 'pureLight') return ThemeMode.light;
  if (modeStyle == 'pureDark') return ThemeMode.dark;
  return switch (legacyMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

ThemeData applyThemePreferences(
  ThemeData base, {
  String modeStyle = '',
  String style = '',
  String accent = '',
}) {
  var scheme = base.colorScheme;
  var scaffold = base.scaffoldBackgroundColor;
  var canvas = base.canvasColor;
  var brightness = base.brightness;
  if (modeStyle == 'pureLight') {
    brightness = Brightness.light;
    scheme = scheme.copyWith(brightness: Brightness.light);
  } else if (modeStyle == 'pureDark') {
    brightness = Brightness.dark;
    scheme = scheme.copyWith(brightness: Brightness.dark);
  }
  final dark = brightness == Brightness.dark;
  if (modeStyle == 'pureLight') {
    scaffold = Colors.white;
    canvas = Colors.white;
    scheme = scheme.copyWith(
      surface: Colors.white,
      onSurface: const Color(0xFF1A1A1A),
      onSurfaceVariant: const Color(0xFF5A5A5A),
      outline: const Color(0xFFBDBDBD),
      outlineVariant: const Color(0xFFE0E0E0),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF7F7F7),
      surfaceContainer: const Color(0xFFF2F2F2),
      surfaceContainerHigh: const Color(0xFFEDEDED),
      surfaceContainerHighest: const Color(0xFFE6E6E6),
    );
  } else if (modeStyle == 'pureDark') {
    scaffold = Colors.black;
    canvas = Colors.black;
    scheme = scheme.copyWith(
      surface: Colors.black,
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFFB0B0B0),
      outline: const Color(0xFF444444),
      outlineVariant: const Color(0xFF262626),
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF121212),
      surfaceContainerHigh: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFF242424),
    );
  }
  final accentColor = themeAccentColor(accent);
  if (accentColor != null && accent != 'default') {
    scheme = scheme.copyWith(
      primary: accentColor,
      onPrimary: Colors.white,
      primaryContainer: dark
          ? Color.lerp(accentColor, Colors.black, 0.72)!
          : Color.lerp(accentColor, Colors.white, 0.82)!,
      onPrimaryContainer: dark
          ? Color.lerp(accentColor, Colors.white, 0.82)!
          : Color.lerp(accentColor, Colors.black, 0.35)!,
    );
  }
  var cardTheme = base.cardTheme;
  var dialogTheme = base.dialogTheme;
  var bottomSheetTheme = base.bottomSheetTheme;
  var inputTheme = base.inputDecorationTheme;
  var textTheme = base.textTheme;
  var filledButtonTheme = base.filledButtonTheme;
  var elevatedButtonTheme = base.elevatedButtonTheme;
  var outlinedButtonTheme = base.outlinedButtonTheme;
  double? radius;
  if (style == 'deep' || style == 'candy' || style == 'aurora') {
    radius = 20;
  } else if (style == 'neon') {
    radius = 10;
  } else if (style == 'paper') {
    radius = 8;
  } else if (style == 'glass') {
    radius = 16;
  }
  if (radius != null) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    cardTheme = cardTheme.copyWith(shape: shape);
    dialogTheme = dialogTheme.copyWith(shape: shape);
    bottomSheetTheme = bottomSheetTheme.copyWith(shape: shape);
    inputTheme = inputTheme.copyWith(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
    );
  }
  if (style == 'candy') {
    const shape = StadiumBorder();
    filledButtonTheme = FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape),
    );
    elevatedButtonTheme = ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(shape: shape),
    );
    outlinedButtonTheme = OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: shape),
    );
  }
  if (style == 'paper') {
    textTheme = textTheme.copyWith(
      titleLarge: textTheme.titleLarge?.copyWith(fontFamily: 'serif'),
      titleMedium: textTheme.titleMedium?.copyWith(fontFamily: 'serif'),
      titleSmall: textTheme.titleSmall?.copyWith(fontFamily: 'serif'),
    );
  }
  if (style == 'glass') {
    scheme = scheme.copyWith(
      surface: scheme.surface.withValues(alpha: 0.92),
      surfaceContainerLowest: scheme.surfaceContainerLowest.withValues(
        alpha: 0.92,
      ),
      surfaceContainerLow: scheme.surfaceContainerLow.withValues(alpha: 0.92),
      surfaceContainer: scheme.surfaceContainer.withValues(alpha: 0.92),
      surfaceContainerHigh: scheme.surfaceContainerHigh.withValues(
        alpha: 0.92,
      ),
      surfaceContainerHighest: scheme.surfaceContainerHighest.withValues(
        alpha: 0.92,
      ),
      outline: dark ? Colors.white38 : Colors.black26,
    );
  }
  if (style == 'neon') {
    scheme = scheme.copyWith(
      outline: scheme.primary,
      outlineVariant: scheme.primary.withValues(alpha: 0.35),
    );
  }
  if (style == 'aurora') {
    scheme = scheme.copyWith(surfaceTint: scheme.primary);
  }
  if (style == 'deep') {
    cardTheme = cardTheme.copyWith(elevation: 2);
  }
  return base.copyWith(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    canvasColor: canvas,
    drawerTheme: DrawerThemeData(backgroundColor: scheme.surface),
    cardTheme: cardTheme,
    dialogTheme: dialogTheme,
    bottomSheetTheme: bottomSheetTheme,
    inputDecorationTheme: inputTheme,
    textTheme: textTheme,
    filledButtonTheme: filledButtonTheme,
    elevatedButtonTheme: elevatedButtonTheme,
    outlinedButtonTheme: outlinedButtonTheme,
  );
}

Future<Directory> _themeBackgroundDir() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/theme_background');
}

Future<File?> themeBackgroundFile(String fileName) async {
  if (fileName.isEmpty) return null;
  final dir = await _themeBackgroundDir();
  final file = File('${dir.path}/$fileName');
  return file.existsSync() ? file : null;
}

Future<String> saveThemeBackgroundImage(
  List<int> bytes,
  String extension,
) async {
  final dir = await _themeBackgroundDir();
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final safeExt = extension.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final fileName = safeExt.isEmpty
      ? themeBackgroundFileName
      : '$themeBackgroundFileName.$safeExt';
  await File('${dir.path}/$fileName').writeAsBytes(bytes, flush: true);
  return fileName;
}

Future<void> deleteThemeBackgroundImage(String fileName) async {
  if (fileName.isEmpty) return;
  try {
    final dir = await _themeBackgroundDir();
    final file = File('${dir.path}/$fileName');
    if (file.existsSync()) await file.delete();
  } catch (_) {}
}

class ThemeBackgroundWrapper extends StatefulWidget {
  const ThemeBackgroundWrapper({
    super.key,
    required this.store,
    required this.child,
  });

  final LocalStore? store;
  final Widget child;

  @override
  State<ThemeBackgroundWrapper> createState() => _ThemeBackgroundWrapperState();
}

class _ThemeBackgroundWrapperState extends State<ThemeBackgroundWrapper> {
  File? _image;
  String _resolvedFor = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ThemeBackgroundWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  Future<void> _resolve() async {
    final store = widget.store;
    if (store == null) return;
    final fileName = store.themeBackgroundImage;
    if (store.themeBackground != 'custom' || fileName.isEmpty) {
      if (_image != null && mounted) setState(() => _image = null);
      _resolvedFor = '';
      return;
    }
    if (fileName == _resolvedFor) return;
    final file = await themeBackgroundFile(fileName);
    if (!mounted) return;
    setState(() {
      _image = file;
      _resolvedFor = fileName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = widget.store;
    final background = store?.themeBackground ?? 'theme';
    final scaffold = theme.scaffoldBackgroundColor;
    if (background == 'solid') {
      return ColoredBox(
        color: theme.colorScheme.primaryContainer,
        child: widget.child,
      );
    }
    if (background == 'gradient') {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [theme.colorScheme.primaryContainer, scaffold],
          ),
        ),
        child: widget.child,
      );
    }
    if (background == 'custom' && _image != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(_image!, fit: BoxFit.cover),
          widget.child,
        ],
      );
    }
    return ColoredBox(color: scaffold, child: widget.child);
  }
}
