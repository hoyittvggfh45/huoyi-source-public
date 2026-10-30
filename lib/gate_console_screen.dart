import 'package:flutter/material.dart';

import 'gate_config.dart';
import 'gate_service.dart';

const _effectPath = '客户端下次启动读取服务端配置后生效；已打开的客户端回到前台重查时生效';

class GateConsoleScreen extends StatefulWidget {
  const GateConsoleScreen({super.key});

  @override
  State<GateConsoleScreen> createState() => _GateConsoleScreenState();
}

class _GateConsoleScreenState extends State<GateConsoleScreen> {
  late GateConfig _draft;

  @override
  void initState() {
    super.initState();
    _draft = GateService.instance.config;
  }

  Future<void> _saveToServer() async {
    try {
      await GateService.instance.saveToServer(_draft);
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('服务端管理接口未接通'),
          content: const Text('本次未上传任何数据。缺的服务端件：门禁配置读写接口、配置签名校验、鉴权版身份校验。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  void _applyLocalPreview() {
    GateService.instance.applyConfig(_draft);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已应用到本机预览，不影响其他客户端')));
  }

  void _resetDraft() {
    setState(() {
      _draft = GateService.instance.config;
    });
  }

  void _refreshCurrent() {
    GateService.instance.refresh();
    _resetDraft();
  }

  List<Widget> _switchRows(
    Map<String, bool> values,
    Map<String, String> labels,
    void Function(String key, bool value) onChanged,
  ) => [
    for (final entry in values.entries)
      SwitchListTile(
        title: Text(labels[entry.key] ?? entry.key),
        subtitle: const Text(_effectPath),
        value: entry.value,
        onChanged: (changed) => onChanged(entry.key, changed),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final current = GateService.instance.config;
    final enabledFeatures = current.features.values
        .where((value) => value)
        .length;
    final enabledModules = current.modules.values
        .where((value) => value)
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('鉴权控制台')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '服务端管理接口未接通',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '以下开关仅为本机草稿。保存到服务端目前会明确失败，不会上传；应用到本机预览只改本机门禁，不影响其他客户端。',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '当前生效配置：版本 ${current.version}，功能开启 $enabledFeatures/${current.features.length}，模块开启 $enabledModules/${current.modules.length}',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _saveToServer,
                        child: const Text('保存到服务端'),
                      ),
                      OutlinedButton(
                        onPressed: _applyLocalPreview,
                        child: const Text('应用到本机预览'),
                      ),
                      TextButton(
                        onPressed: _resetDraft,
                        child: const Text('恢复为当前生效配置'),
                      ),
                      TextButton(
                        onPressed: _refreshCurrent,
                        child: const Text('重查当前配置'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('功能开关', style: TextStyle(fontWeight: FontWeight.w800)),
          ..._switchRows(_draft.features, GateFeature.labels, (key, value) {
            setState(() {
              _draft = _draft.copyWith(
                features: Map<String, bool>.from(_draft.features)
                  ..[key] = value,
              );
            });
          }),
          const SizedBox(height: 16),
          const Text('模块开关', style: TextStyle(fontWeight: FontWeight.w800)),
          ..._switchRows(_draft.modules, GateModule.labels, (key, value) {
            setState(() {
              _draft = _draft.copyWith(
                modules: Map<String, bool>.from(_draft.modules)..[key] = value,
              );
            });
          }),
          const SizedBox(height: 16),
          const Text('区域开关', style: TextStyle(fontWeight: FontWeight.w800)),
          ..._switchRows(_draft.regions, GateRegion.labels, (key, value) {
            setState(() {
              _draft = _draft.copyWith(
                regions: Map<String, bool>.from(_draft.regions)..[key] = value,
              );
            });
          }),
        ],
      ),
    );
  }
}
