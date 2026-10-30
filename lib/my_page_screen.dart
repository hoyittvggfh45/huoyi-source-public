import 'dart:io';

import 'package:flutter/material.dart';

import 'app_page_route.dart';
import 'app_update_screen.dart';
import 'core_bridge.dart';
import 'detail_screen.dart';
import 'downloads_screen.dart';
import 'gate_config.dart';
import 'gate_guard.dart';
import 'hongguo_account.dart';
import 'local_store.dart';
import 'midnight_zone.dart';
import 'miniapp/plugin_center_screen.dart';
import 'models.dart';
import 'saved_library.dart';
import 'account_screen.dart';
import 'settings_screen.dart';
import 'shell/kotv_runtime_info_dialog.dart';
import 'shell/kotv_theme.dart';

class MyPageScreen extends StatelessWidget {
  const MyPageScreen({
    super.key,
    required this.repository,
    required this.store,
    this.onDownloadDrama,
  });

  final AppRepository repository;
  final LocalStore store;
  final ValueChanged<Drama>? onDownloadDrama;

  void _openDrama(BuildContext context, Drama drama) {
    Navigator.of(context).push(
      appPageRoute<void>(
        builder: (_) => DetailScreen(
          drama: drama,
          repository: repository,
          store: store,
        ),
      ),
    );
  }

  void _openSaved(BuildContext context, {required bool history}) {
    Navigator.of(context).push(
      appPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(history ? '最近观看' : '追剧')),
          body: SavedLibrary(
            repository: repository,
            store: store,
            history: history,
            onOpen: (drama) => _openDrama(context, drama),
            onContinue: (drama) => _openDrama(context, drama),
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

  Widget _colorBlock(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) => Expanded(
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: KotvPastelBackground(
        child: ListView(
          padding: EdgeInsets.only(
            bottom: 32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: KotvTokens.cardColor,
                borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: KotvTokens.primary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ValueListenableBuilder<HongguoAccount?>(
                        valueListenable: hongguoAccountNotifier,
                        builder: (context, account, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              store.profile.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              account != null && account.loggedIn
                                  ? account.displayName
                                  : '未登录',
                              style: const TextStyle(
                                fontSize: 13,
                                color: KotvTokens.unselectedColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _colorBlock(
                    context,
                    '设置',
                    Icons.settings_rounded,
                    KotvTokens.primary,
                    () => Navigator.of(context).push(
                      appPageRoute<void>(
                        builder: (_) => SettingsScreen(
                          repository: repository,
                          store: store,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _colorBlock(
                    context,
                    '软件更新',
                    Icons.system_update_rounded,
                    KotvTokens.pastelBlue,
                    () => Navigator.of(context).push(
                      appPageRoute<void>(
                        builder: (_) => const AppUpdateScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _colorBlock(
                    context,
                    '关于',
                    Icons.info_outline_rounded,
                    const Color(0xFF8ED0A0),
                    () => showKotvAboutDialog(context: context),
                  ),
                ],
              ),
            ),
            KotvGroupCard(
              title: '功能',
              children: [
                KotvSettingsRow(
                  title: '追剧',
                  value: '跟进中的短剧',
                  onTap: () => _openSaved(context, history: false),
                ),
                KotvSettingsRow(
                  title: '最近观看',
                  value: '观看历史',
                  onTap: () => _openSaved(context, history: true),
                ),
                if (store.canDownload)
                  GateGuard(
                    feature: GateFeature.download,
                    child: KotvSettingsRow(
                      title: '下载',
                      value: '查看与管理已下载内容',
                      onTap: () => Navigator.of(context).push(
                        appPageRoute<void>(
                          builder: (_) => DownloadsScreen(
                            repository: repository,
                            store: store,
                          ),
                        ),
                      ),
                    ),
                  ),
                KotvSettingsRow(
                  title: '小程序',
                  value: '市场安装与本地插件',
                  onTap: () async {
                    await Navigator.of(context).push(
                      appPageRoute<void>(
                        builder: (_) => PluginCenterScreen(
                          store: store,
                          repository: repository,
                        ),
                      ),
                    );
                  },
                ),
                KotvSettingsRow(
                  title: '账号',
                  value: '红果账号登录状态',
                  onTap: () => Navigator.of(context).push(
                    appPageRoute<void>(
                      builder: (_) => const AccountScreen(),
                    ),
                  ),
                ),
                FutureBuilder<bool>(
                  future: loadMidnightActivated(),
                  builder: (context, snapshot) {
                    final activated = snapshot.data ?? false;
                    return KotvSettingsRow(
                      title: '午夜区',
                      value: activated ? '已激活' : '未激活，点击激活',
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
