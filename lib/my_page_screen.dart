import 'dart:io';

import 'package:flutter/material.dart';

import 'app_page_route.dart';

import 'gate_config.dart';
import 'gate_guard.dart';
import 'app_update_screen.dart';
import 'core_bridge.dart';
import 'downloads_screen.dart';
import 'local_store.dart';
import 'midnight_zone.dart';
import 'miniapp/plugin_center_screen.dart';
import 'models.dart';
import 'saved_library.dart';
import 'account_screen.dart';
import 'hongguo_account.dart';
import 'settings_screen.dart';

class MyPageScreen extends StatelessWidget {
  const MyPageScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.onOpenDrama,
    this.onDownloadDrama,
  });

  final AppRepository repository;
  final LocalStore store;
  final ValueChanged<Drama> onOpenDrama;
  final ValueChanged<Drama>? onDownloadDrama;

  void _openSaved(BuildContext context, {required bool history}) {
    Navigator.of(context).push(
      appPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(history ? '最近观看' : '追剧')),
          body: SavedLibrary(
            repository: repository,
            store: store,
            history: history,
            onOpen: onOpenDrama,
            onContinue: onOpenDrama,
            onDownload: onDownloadDrama,
          ),
        ),
      ),
    );
  }

  Future<void> _activateMidnight(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('激活午夜区？'),
        content: const Text('激活后重启 App，底栏出现午夜区。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('激活'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await saveMidnightActivated(true);
    exit(0);
  }

  Future<void> _hideMidnight(BuildContext context) async {
    await saveMidnightActivated(false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已隐藏，重启 App 后生效')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('追剧'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openSaved(context, history: false),
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('最近观看'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openSaved(context, history: true),
          ),
          if (store.canDownload)
            GateGuard(
              feature: GateFeature.download,
              child: ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('下载'),
                subtitle: const Text('查看与管理已下载内容'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  appPageRoute<void>(
                    builder: (_) =>
                        DownloadsScreen(repository: repository, store: store),
                  ),
                ),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.apps_rounded),
            title: const Text('小程序'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await Navigator.of(context).push(
                appPageRoute<void>(
                  builder: (_) =>
                      PluginCenterScreen(store: store, repository: repository),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('账号'),
            subtitle: ValueListenableBuilder<HongguoAccount?>(
              valueListenable: hongguoAccountNotifier,
              builder: (context, account, _) => Text(
                account != null && account.loggedIn
                    ? account.displayName
                    : '未登录',
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(
              context,
            ).push(appPageRoute<void>(builder: (_) => const AccountScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              appPageRoute<void>(
                builder: (_) =>
                    SettingsScreen(repository: repository, store: store),
              ),
            ),
          ),
          FutureBuilder<bool>(
            future: loadMidnightActivated(),
            builder: (context, snapshot) {
              final activated = snapshot.data ?? false;
              return ListTile(
                leading: const Icon(Icons.nightlight_rounded),
                title: const Text('午夜区'),
                subtitle: Text(activated ? '已激活' : '未激活，点击激活'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  if (activated) {
                    _hideMidnight(context);
                  } else {
                    _activateMidnight(context);
                  }
                },
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.system_update_rounded),
            title: const Text('软件更新'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(
              context,
            ).push(appPageRoute<void>(builder: (_) => const AppUpdateScreen())),
          ),
        ],
      ),
    );
  }
}
