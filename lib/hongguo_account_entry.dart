import 'package:flutter/material.dart';

import 'app_page_route.dart';
import 'core_bridge.dart';
import 'hongguo_account.dart';
import 'hongguo_login_page.dart';
import 'hongguo_playback_page.dart';
import 'local_store.dart';

class HongguoAccountEntry extends StatelessWidget {
  const HongguoAccountEntry({super.key, required this.controller});

  final HongguoAccountController controller;

  Future<void> _openLogin(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HongguoLoginPage(controller: controller),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('退出登录'),
            content: const Text('退出后停止上传云端进度，本机历史保留。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('退出'),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      await controller.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HongguoAccount?>(
      valueListenable: hongguoAccountNotifier,
      builder: (context, account, _) {
        if (account == null || !account.loggedIn) {
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: const Text('红果账号'),
            subtitle: const Text('未登录，登录后同步收藏与观看进度'),
            trailing: FilledButton(
              onPressed: () => _openLogin(context),
              child: const Text('登录'),
            ),
          );
        }
        return ListTile(
          leading: CircleAvatar(
            child: Text(
              account.displayName.isNotEmpty
                  ? account.displayName.characters.first
                  : '红',
            ),
          ),
          title: Text(account.displayName),
          subtitle: Text(
            [
              if (account.maskedPhone.isNotEmpty) account.maskedPhone,
              account.methodLabel,
            ].join(' · '),
          ),
          trailing: TextButton(
            onPressed: () => _confirmLogout(context),
            child: const Text('退出登录'),
          ),
          onTap: () => _openLogin(context),
        );
      },
    );
  }
}

class HongguoAccountCloudSection extends StatelessWidget {
  const HongguoAccountCloudSection({
    super.key,
    required this.controller,
    this.repository,
    this.store,
  });

  final HongguoAccountController controller;
  final AppRepository? repository;
  final LocalStore? store;

  String _clock(int seconds) {
    final total = seconds < 0 ? 0 : seconds;
    final minutes = total ~/ 60;
    final rest = total % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    if (minutes >= 60) {
      return '${two(minutes ~/ 60)}:${two(minutes % 60)}:${two(rest)}';
    }
    return '${two(minutes)}:${two(rest)}';
  }

  Future<void> _openCloudHistory(BuildContext context) async {
    final repository = this.repository;
    final store = this.store;
    if (repository == null || store == null) return;
    final history = controller.cloudHistory;
    if (history.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: ListView(
              children: [
                const ListTile(title: Text('云端历史续播')),
                for (final item in history)
                  ListTile(
                    title: Text(
                      item.seriesTitle.isEmpty
                          ? item.seriesId
                          : item.seriesTitle,
                    ),
                    subtitle: Text(
                      '第 ${item.episodeIndex + 1} 集 · ${_clock(item.position)}'
                      '${item.duration > 0 ? ' / ${_clock(item.duration)}' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push<void>(
                        appPageRoute<void>(
                          builder:
                              (_) => HongguoPlaybackPage(
                                drama: item.drama,
                                repository: repository,
                                store: store,
                                accountController: controller,
                                preferCloud: true,
                              ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final update = controller.favoriteUpdate;
        final canOpenHistory =
            repository != null &&
            store != null &&
            controller.cloudHistory.isNotEmpty;
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.favorite),
              title: const Text('账户收藏'),
              trailing: Text(
                '${controller.cloudFavorites.length} 部'
                '${update != null && update.added > 0 ? ' · 新增 ${update.added}' : ''}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('云端历史续播'),
              trailing: Text('${controller.cloudHistory.length} 部'),
              onTap:
                  canOpenHistory ? () => _openCloudHistory(context) : null,
            ),
            ListTile(
              leading: const Icon(Icons.event_available),
              title: const Text('已上线预约'),
              trailing: Text('${controller.onlineReservations.length} 部'),
            ),
            ListTile(
              leading: const Icon(Icons.event),
              title: const Text('待上线预约'),
              trailing: Text('${controller.upcomingReservations.length} 部'),
            ),
            if (controller.pendingUploads.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.cloud_upload),
                title: const Text('待上传进度'),
                trailing: Text('${controller.pendingUploads.length} 条'),
              ),
          ],
        );
      },
    );
  }
}
