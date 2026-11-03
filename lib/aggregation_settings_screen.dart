import 'package:flutter/material.dart';

import 'aggregation_prefs.dart';
import 'floating_window.dart';

class AggregationSettingsScreen extends StatefulWidget {
  const AggregationSettingsScreen({
    super.key,
    required this.onOpenAi,
    required this.onOpenLz,
    required this.onOpenExperiment,
  });

  final VoidCallback onOpenAi;
  final VoidCallback onOpenLz;
  final VoidCallback onOpenExperiment;

  @override
  State<AggregationSettingsScreen> createState() =>
      _AggregationSettingsScreenState();
}

class _AggregationSettingsScreenState extends State<AggregationSettingsScreen> {
  bool _floatingOn = false;
  bool _experimentOn = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final showing = await FloatingWindow.isShowing();
    final experiment = await AggregationPrefs.experimentEnabled();
    if (!mounted) return;
    setState(() {
      _floatingOn = showing;
      _experimentOn = experiment;
      _loaded = true;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setFloating(bool value) async {
    if (value) {
      final granted = await FloatingWindow.isPermissionGranted();
      if (!granted) {
        await FloatingWindow.requestPermission();
        _showMessage('请在系统设置里允许悬浮窗权限，允许后回来再打开开关');
        return;
      }
      try {
        await FloatingWindow.show();
      } catch (error) {
        _showMessage('打开悬浮窗失败：$error');
        return;
      }
    } else {
      try {
        await FloatingWindow.hide();
      } catch (error) {
        _showMessage('关闭悬浮窗失败：$error');
        return;
      }
    }
    if (!mounted) return;
    setState(() => _floatingOn = value);
  }

  Future<void> _setExperiment(bool value) async {
    await AggregationPrefs.setExperimentEnabled(value);
    if (!mounted) return;
    setState(() => _experimentOn = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('聚合设置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                SwitchListTile(
                  key: const ValueKey('aggregation-setting-floating'),
                  title: const Text('悬浮窗开关'),
                  subtitle: const Text('桌面悬浮球与展开面板，需系统悬浮窗权限'),
                  value: _floatingOn,
                  onChanged: _setFloating,
                ),
                ListTile(
                  key: const ValueKey('aggregation-setting-ai'),
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('AI 助手入口'),
                  subtitle: const Text('打开公开 AI 聊天页'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenAi,
                ),
                ListTile(
                  key: const ValueKey('aggregation-setting-lz'),
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('lz 规则管理'),
                  subtitle: const Text('查看、导入、删除 lz 与 novel 下的规则文件'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenLz,
                ),
                SwitchListTile(
                  key: const ValueKey('aggregation-setting-experiment'),
                  title: const Text('实验区开关'),
                  subtitle: const Text('关闭后实验区不再列出实验项'),
                  value: _experimentOn,
                  onChanged: _setExperiment,
                ),
                ListTile(
                  key: const ValueKey('aggregation-setting-experiment-entry'),
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('实验区'),
                  subtitle: const Text('逐项开放的实验功能'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenExperiment,
                ),
              ],
            ),
    );
  }
}
