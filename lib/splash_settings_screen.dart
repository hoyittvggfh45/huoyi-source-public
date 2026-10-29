import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_page_route.dart';
import 'splash_selection.dart';
import 'splash_sets.dart';

class SplashSettingsScreen extends StatefulWidget {
  const SplashSettingsScreen({super.key});

  @override
  State<SplashSettingsScreen> createState() => _SplashSettingsScreenState();
}

class _SplashSettingsScreenState extends State<SplashSettingsScreen> {
  String _selection = splashSelectionDefault;
  bool _hasCustom = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    var selection = await loadSplashSelection();
    final docs = await getApplicationDocumentsDirectory();
    final custom = findCustomSplashFile(docs.path);
    if (selection == splashSelectionCustom && custom == null) {
      selection = splashSelectionDefault;
      await saveSplashSelection(selection);
    }
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _hasCustom = custom != null;
    });
  }

  Future<void> _select(String id) async {
    await saveSplashSelection(id);
    if (!mounted) return;
    setState(() => _selection = normalizeSplashSelection(id));
  }

  void _snack(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickCustom() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null) return;
      final name = picked.name;
      final dot = name.lastIndexOf('.');
      final ext = dot >= 0 ? name.substring(dot + 1) : '';
      final bytes = await picked.readAsBytes();
      final error = validateCustomImage(extension: ext, bytes: bytes.length);
      if (error != null) {
        _snack(messenger, error);
        return;
      }
      final docs = await getApplicationDocumentsDirectory();
      await deleteCustomSplashFiles(docs.path);
      final target = File(customSplashPath(docs.path, ext));
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes);
      await saveSplashSelection(splashSelectionCustom);
      if (!mounted) return;
      setState(() {
        _selection = splashSelectionCustom;
        _hasCustom = true;
      });
      _snack(messenger, '已设为启动图');
    } catch (_) {
      _snack(messenger, '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearCustom() async {
    final messenger = ScaffoldMessenger.of(context);
    final docs = await getApplicationDocumentsDirectory();
    await deleteCustomSplashFiles(docs.path);
    await saveSplashSelection(splashSelectionDefault);
    if (!mounted) return;
    setState(() {
      _selection = splashSelectionDefault;
      _hasCustom = false;
    });
    _snack(messenger, '已恢复默认启动图');
  }

  Future<void> _previewDefault() async {
    final changed = await Navigator.push<bool>(
      context,
      appPageRoute<bool>(
        builder: (_) => SplashPreviewScreen(
          title: '默认启动图',
          preview: Container(
            width: double.infinity,
            height: double.infinity,
            color: const Color(0xFF131619),
            child: Center(
              child: Image.asset(
                'assets/splash/hongyi_tv.png',
                width: 260,
                height: 260,
                fit: BoxFit.cover,
              ),
            ),
          ),
          onUse: () => _select(splashSelectionDefault),
        ),
      ),
    );
    if (changed == true) await _reload();
  }

  Future<void> _previewSet(SplashSet set) async {
    final changed = await Navigator.push<bool>(
      context,
      appPageRoute<bool>(
        builder: (_) => SplashPreviewScreen(
          title: set.name,
          preview: set.build(),
          onUse: () => _select(set.id),
        ),
      ),
    );
    if (changed == true) await _reload();
  }

  Future<void> _previewCustom() async {
    final docs = await getApplicationDocumentsDirectory();
    final file = findCustomSplashFile(docs.path);
    if (file == null || !mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      appPageRoute<bool>(
        builder: (_) => SplashPreviewScreen(
          title: '自定义图片',
          preview: Container(
            width: double.infinity,
            height: double.infinity,
            color: const Color(0xFF131619),
            child: Image.file(file, fit: BoxFit.contain),
          ),
          onUse: () => _select(splashSelectionCustom),
        ),
      ),
    );
    if (changed == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('开机启动图')),
      body: RadioGroup<String>(
        groupValue: _selection,
        onChanged: (value) {
          if (value != null && (value != splashSelectionCustom || _hasCustom)) {
            _select(value);
          }
        },
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('内置'),
            ),
            RadioListTile<String>(
              value: splashSelectionDefault,
              title: const Text('默认启动图'),
              subtitle: const Text('当前红蚁TV启动图淡入'),
              secondary: IconButton(
                icon: const Icon(Icons.visibility_outlined),
                tooltip: '预览',
                onPressed: _previewDefault,
              ),
            ),
            for (final set in splashSets)
              RadioListTile<String>(
                value: set.id,
                title: Text(set.name),
                subtitle: Text(set.effect),
                secondary: IconButton(
                  icon: const Icon(Icons.visibility_outlined),
                  tooltip: '预览',
                  onPressed: () => _previewSet(set),
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('自定义'),
            ),
            RadioListTile<String>(
              value: splashSelectionCustom,
              enabled: _hasCustom,
              title: const Text('自定义图片'),
              subtitle: Text(_hasCustom ? '已设置自定义图片' : '未设置'),
              secondary: _hasCustom
                  ? IconButton(
                      icon: const Icon(Icons.visibility_outlined),
                      tooltip: '预览',
                      onPressed: _previewCustom,
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _pickCustom,
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('从手机选图'),
                  ),
                  const SizedBox(width: 12),
                  if (_hasCustom)
                    OutlinedButton(
                      onPressed: _busy ? null : _clearCustom,
                      child: const Text('清除自定义，恢复默认'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SplashPreviewScreen extends StatelessWidget {
  const SplashPreviewScreen({
    super.key,
    required this.title,
    required this.preview,
    required this.onUse,
  });

  final String title;
  final Widget preview;
  final Future<void> Function() onUse;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: preview,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('返回'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    await onUse();
                    if (context.mounted) Navigator.pop(context, true);
                  },
                  child: const Text('设为启动图'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
