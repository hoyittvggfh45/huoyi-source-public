import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_layout.dart';
import '../app_page_route.dart';
import '../app_update.dart';
import '../app_update_screen.dart';
import '../jar_bridge.dart';
import '../lan_controller.dart';
import '../py_bridge.dart';
import 'kotv_theme.dart';

Future<({String version, int build})> _kotvInstalledInfo() async {
  try {
    final info = await AppUpdateChannel.appInfo();
    return (
      version: info.versionName.isNotEmpty ? info.versionName : appVersion,
      build: info.build > 0 ? info.build : appBuild,
    );
  } catch (_) {
    return (version: appVersion, build: appBuild);
  }
}

Widget _kotvInfoDialog({
  required String title,
  required List<Widget> children,
  List<Widget>? actions,
}) {
  return Dialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
    ),
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...children,
            if (actions != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: actions,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }

class KotvRuntimeInfoDialog extends StatefulWidget {
  const KotvRuntimeInfoDialog({super.key});

  @override
  State<KotvRuntimeInfoDialog> createState() => _KotvRuntimeInfoDialogState();
}

class _KotvRuntimeInfoDialogState extends State<KotvRuntimeInfoDialog> {
  String _version = appVersion;
  int _build = appBuild;
  PyRuntimeStatus? _pyStatus;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await _kotvInstalledInfo();
    final pyStatus = await PyBridge.status();
    if (mounted) {
      setState(() {
        _version = info.version;
        _build = info.build;
        _pyStatus = pyStatus;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = LanController.current;
    final pyStatus = _pyStatus;
    return _kotvInfoDialog(
      title: '运行时信息',
      children: _loading
          ? [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            ]
          : [
              KotvSettingsRow(title: '应用', value: appName),
              KotvSettingsRow(title: '版本', value: _version),
              KotvSettingsRow(title: '构建', value: '$_build'),
              KotvSettingsRow(
                title: '平台',
                value: Platform.operatingSystem,
              ),
              KotvSettingsRow(
                title: '系统版本',
                value: Platform.operatingSystemVersion,
              ),
              KotvSettingsRow(
                title: '目标平台',
                value: defaultTargetPlatform.name,
              ),
              KotvSettingsRow(
                title: 'Dart 运行时',
                value: Platform.version,
              ),
              KotvSettingsRow(
                title: 'Python 桥',
                value: pyStatus == null
                    ? '读取中'
                    : pyStatus.available
                    ? pyStatus.python.isEmpty
                          ? '可用'
                          : '可用 · ${pyStatus.python}'
                    : pyStatus.detail.isEmpty
                    ? '不可用'
                    : '不可用 · ${pyStatus.detail}',
              ),
              KotvSettingsRow(
                title: 'JAR 桥',
                value: JarBridge.supported
                    ? '可用 · ${JarBridge.specs.length} 个已注册站点'
                    : '仅 Android 可用',
              ),
              KotvSettingsRow(
                title: '局域网',
                value: link == null ? '未就绪' : link.connectionLabel,
              ),
            ],
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class KotvAboutDialog extends StatefulWidget {
  const KotvAboutDialog({super.key});

  @override
  State<KotvAboutDialog> createState() => _KotvAboutDialogState();
}

class _KotvAboutDialogState extends State<KotvAboutDialog> {
  String _version = appVersion;
  int _build = appBuild;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await _kotvInstalledInfo();
    if (mounted) {
      setState(() {
        _version = info.version;
        _build = info.build;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _kotvInfoDialog(
      title: '关于',
      children: [
        KotvSettingsRow(title: '应用', value: appName),
        KotvSettingsRow(title: '版本', value: _version),
        KotvSettingsRow(title: '构建', value: '$_build'),
      ],
      actions: [
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              appPageRoute<void>(builder: (_) => const AppUpdateScreen()),
            );
          },
          child: const Text('检查更新'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

Future<void> showKotvRuntimeInfoDialog({required BuildContext context}) {
  return showDialog<void>(
    context: context,
    builder: (_) => const KotvRuntimeInfoDialog(),
  );
}

Future<void> showKotvAboutDialog({required BuildContext context}) {
  return showDialog<void>(
    context: context,
    builder: (_) => const KotvAboutDialog(),
  );
}
