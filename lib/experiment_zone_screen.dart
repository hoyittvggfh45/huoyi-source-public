import 'package:flutter/material.dart';

class ExperimentZoneScreen extends StatelessWidget {
  const ExperimentZoneScreen({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.onOpenFloatingSettings,
    required this.onOpenAi,
    required this.onOpenLz,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onOpenFloatingSettings;
  final VoidCallback onOpenAi;
  final VoidCallback onOpenLz;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('实验区')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SwitchListTile(
            key: const ValueKey('experiment-master-switch'),
            title: const Text('实验区开关'),
            subtitle: const Text('关闭后实验项不再列出'),
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          const Divider(),
          if (!enabled)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 32),
                child: Text('实验区已关闭，打开开关后可看实验项。'),
              ),
            )
          else ...[
            ListTile(
              key: const ValueKey('experiment-tv-layout'),
              leading: const Icon(Icons.tv_rounded),
              title: const Text('TV 版式'),
              subtitle: const Text('电视布局：遥控焦点、大图标，日后按电视版式重写，本批暂缓'),
              trailing: const Chip(label: Text('暂缓')),
            ),
            ListTile(
              key: const ValueKey('experiment-floating'),
              leading: const Icon(Icons.picture_in_picture_alt_rounded),
              title: const Text('悬浮窗设置'),
              subtitle: const Text('悬浮球与展开面板，公开接口加悬浮窗权限'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onOpenFloatingSettings,
            ),
            ListTile(
              key: const ValueKey('experiment-ai-entries'),
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('AI 助手多入口'),
              subtitle: const Text('多个公开 AI 聊天页入口'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onOpenAi,
            ),
            ListTile(
              key: const ValueKey('experiment-lz-import'),
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('lz 导入兜底'),
              subtitle: const Text('直接读不到设备存储时，经文件选择器授权导入'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onOpenLz,
            ),
          ],
        ],
      ),
    );
  }
}
