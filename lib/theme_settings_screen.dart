import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'local_store.dart';
import 'theme_settings.dart';

class ThemeSettingsScreen extends StatefulWidget {
  const ThemeSettingsScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen> {
  bool _picking = false;

  Future<void> _pickImage() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      final file = files.isEmpty ? null : files.first;
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final name = file.name;
      final dot = name.lastIndexOf('.');
      final ext = dot >= 0 ? name.substring(dot + 1) : '';
      final saved = await saveThemeBackgroundImage(bytes, ext);
      await widget.store.setThemeBackgroundImage(saved);
      await widget.store.setThemeBackground('custom');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _clearImage() async {
    final fileName = widget.store.themeBackgroundImage;
    await deleteThemeBackgroundImage(fileName);
    await widget.store.setThemeBackgroundImage('');
    await widget.store.setThemeBackground('theme');
    if (mounted) setState(() {});
  }

  Future<void> _reset() async {
    final fileName = widget.store.themeBackgroundImage;
    await deleteThemeBackgroundImage(fileName);
    await widget.store.resetThemeSettings();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('主题设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _sectionTitle('主题模式'),
          for (final option in themeModeStyleOptions)
            _optionRow(
              title: option.name,
              subtitle: option.id == 'pureLight' ? '纯白画布，高对比' : '纯黑画布，省电',
              selected: store.themeModeStyle == option.id,
              onTap: () async {
                await store.setThemeModeStyle(option.id);
                if (mounted) setState(() {});
              },
            ),
          _sectionTitle('界面风格'),
          for (final option in themeStyleOptions)
            _optionRow(
              title: option.name,
              subtitle: _styleSubtitle(option.id),
              selected: store.themeStyle == option.id,
              onTap: () async {
                await store.setThemeStyle(option.id);
                if (mounted) setState(() {});
              },
            ),
          _sectionTitle('主题色'),
          for (final option in themeAccentOptions)
            _optionRow(
              title: option.name,
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: option.color,
                  shape: BoxShape.circle,
                ),
              ),
              selected: store.themeAccent == option.id ||
                  (store.themeAccent.isEmpty && option.id == 'default'),
              onTap: () async {
                await store.setThemeAccent(option.id);
                if (mounted) setState(() {});
              },
            ),
          _sectionTitle('背景'),
          for (final option in themeBackgroundOptions)
            _optionRow(
              title: option.name,
              subtitle: _backgroundSubtitle(option.id),
              selected: store.themeBackground == option.id,
              onTap: () async {
                await store.setThemeBackground(option.id);
                if (mounted) setState(() {});
              },
            ),
          if (store.themeBackground == 'custom') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _picking ? null : _pickImage,
                    icon: const Icon(Icons.image_rounded),
                    label: Text(
                      store.themeBackgroundImage.isEmpty
                          ? '选择背景图片'
                          : '更换背景图片',
                    ),
                  ),
                ),
                if (store.themeBackgroundImage.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _clearImage,
                    child: const Text('清除图片'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '图片会复制到应用目录保存，不依赖原图路径。',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _reset,
            child: const Text('恢复默认主题'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  );

  Widget _optionRow({
    required String title,
    String? subtitle,
    Widget? leading,
    required bool selected,
    required VoidCallback onTap,
  }) => ListTile(
    leading: leading,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: selected
        ? const Icon(Icons.check_rounded, color: Colors.green)
        : null,
    onTap: onTap,
  );

  String _styleSubtitle(String id) => switch (id) {
    'neon' => '黑底、霓虹描边',
    'deep' => '蓝黑分层、大圆角',
    'candy' => '大圆角、高饱和、全圆按钮',
    'paper' => '纸底、衬线标题、重分隔线',
    'glass' => '半透卡面、白描边',
    'aurora' => '紫青氛围光、大圆角、冷调',
    _ => '',
  };

  String _backgroundSubtitle(String id) => switch (id) {
    'theme' => '跟随当前主题',
    'solid' => '主题色纯色底',
    'gradient' => '主题色到背景渐变',
    'custom' => '从相册选一张图作背景',
    _ => '',
  };
}
