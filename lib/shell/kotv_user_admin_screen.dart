import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account_screen.dart';
import '../app_page_route.dart';
import '../hongguo_account.dart';
import '../lan_controller.dart';
import '../local_profiles.dart';
import '../local_store.dart';
import '../models.dart';
import '../profiles_screen.dart';
import 'kotv_theme.dart';

class KotvUserAdminScreen extends StatefulWidget {
  const KotvUserAdminScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<KotvUserAdminScreen> createState() => _KotvUserAdminScreenState();
}

class _KotvUserAdminScreenState extends State<KotvUserAdminScreen> {
  bool _busy = false;
  String? _error;

  bool get _admin =>
      !widget.store.locked && widget.store.profile.admin;

  String _profileLabel(LocalProfile profile) {
    if (profile.admin) return '管理员 · 全部权限';
    final sources = profile.sources
        .where(SourceSite.isAvailable)
        .map((id) => SourceSite.byId(id).name)
        .join(' / ');
    final scope = sources.isEmpty ? '未开放站源' : sources;
    final download = profile.download ? '可下载' : '仅在线观看';
    final locked = profile.protected ? ' · 已设密码' : '';
    return '$scope · $download$locked';
  }

  Future<void> _switch(LocalProfile profile) async {
    if (profile.id == widget.store.profile.id) return;
    var pin = '';
    if (profile.protected) {
      final controller = TextEditingController();
      final value = await showDialog<String>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '登录 ${profile.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                  onSubmitted: (value) => Navigator.pop(context, value),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, controller.text),
                        child: const Text('登录'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      controller.dispose();
      if (value == null || !mounted) return;
      pin = value;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.switchProfile(profile.id, pin: pin);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final profile = await showKotvOptionDialog<LocalProfile>(
      context: context,
      title: '编辑用户',
      options: widget.store.profiles,
      current: widget.store.profile,
      label: (profile) => profile.name,
    );
    if (profile == null || !mounted) return;
    await Navigator.push(
      context,
      appPageRoute<void>(
        builder: (_) => ProfileEditor(store: widget.store, profile: profile),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    final candidates = widget.store.profiles
        .where((profile) => !profile.admin)
        .toList();
    if (candidates.isEmpty) {
      setState(() => _error = '没有可删除的非管理员用户');
      return;
    }
    final profile = await showKotvOptionDialog<LocalProfile>(
      context: context,
      title: '删除用户',
      options: candidates,
      current: candidates.first,
      label: (profile) => profile.name,
    );
    if (profile == null || !mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '删除此用户？',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text('会同时删除「${profile.name}」的追剧和观看记录。下载文件会保留。'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await widget.store.deleteProfile(profile.id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _add() async {
    await Navigator.push(
      context,
      appPageRoute<void>(
        builder: (_) => ProfileEditor(store: widget.store),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final link = LanController.current;
    final local = link?.local;
    return Scaffold(
      appBar: AppBar(title: const Text('用户管理')),
      body: KotvPastelBackground(
        child: AnimatedBuilder(
          animation: widget.store,
          builder: (context, _) {
            final children = <Widget>[
              KotvGroupCard(
                title: '本机用户',
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Text(
                      '当前用户：${widget.store.profile.name}，各用户的追剧和观看记录独立保存，下载文件由本机共享。',
                      style: const TextStyle(
                        fontSize: 13,
                        color: KotvTokens.unselectedColor,
                      ),
                    ),
                  ),
                  for (final profile in widget.store.profiles)
                    KotvSettingsRow(
                      title: profile.name,
                      value: profile.id == widget.store.profile.id
                          ? '当前 · ${_profileLabel(profile)}'
                          : _profileLabel(profile),
                      onTap: _busy || profile.id == widget.store.profile.id
                          ? null
                          : () => _switch(profile),
                    ),
                  if (_admin) ...[
                    KotvSettingsRow(
                      title: '添加用户',
                      onTap: _busy ? null : _add,
                    ),
                    KotvSettingsRow(
                      title: '编辑用户',
                      value: '改名或改密',
                      onTap: _busy ? null : _edit,
                    ),
                    KotvSettingsRow(
                      title: '删除用户',
                      value: '非管理员',
                      onTap: _busy ? null : _delete,
                    ),
                  ],
                ],
              ),
              KotvGroupCard(
                title: '账号',
                children: [
                  ValueListenableBuilder<HongguoAccount?>(
                    valueListenable: hongguoAccountNotifier,
                    builder: (context, account, _) => KotvSettingsRow(
                      title: '账号',
                      value: account != null && account.loggedIn
                          ? account.displayName
                          : '未登录',
                      onTap: () => Navigator.push(
                        context,
                        appPageRoute<void>(
                          builder: (_) => const AccountScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              KotvGroupCard(
                title: '登录与互联',
                children: [
                  if (_admin)
                    KotvSettingsRow(
                      title: '启动时需要登录',
                      value: widget.store.forceLogin ? '开启' : '关闭',
                      trailing: Switch.adaptive(
                        value: widget.store.forceLogin,
                        onChanged: _busy
                            ? null
                            : (value) async {
                                setState(() => _busy = true);
                                try {
                                  await widget.store.setForceLogin(value);
                                } catch (error) {
                                  if (mounted) {
                                    setState(() => _error = error.toString());
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _busy = false);
                                  }
                                }
                              },
                      ),
                    ),
                  if (link != null)
                    AnimatedBuilder(
                      animation: link,
                      builder: (context, _) => Column(
                        children: [
                          KotvSettingsRow(
                            title: '设备互联',
                            value: link.enabled ? '开启' : '关闭',
                            trailing: Switch.adaptive(
                              value: link.enabled,
                              onChanged: _busy
                                  ? null
                                  : (value) async {
                                      try {
                                        await link.setEnabled(value);
                                      } catch (error) {
                                        if (mounted) {
                                          setState(
                                            () => _error = error.toString(),
                                          );
                                        }
                                      }
                                    },
                            ),
                          ),
                          KotvSettingsRow(
                            title: '自动同步',
                            value: link.autoSync ? '开启' : '关闭',
                            trailing: Switch.adaptive(
                              value: link.autoSync,
                              onChanged: _busy
                                  ? null
                                  : (value) async {
                                      try {
                                        await link.setAutoSync(value);
                                      } catch (error) {
                                        if (mounted) {
                                          setState(
                                            () => _error = error.toString(),
                                          );
                                        }
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!widget.store.locked && widget.store.profile.protected)
                    KotvSettingsRow(
                      title: '锁定当前用户',
                      onTap: () => widget.store.lock(),
                    ),
                ],
              ),
              if (local != null && local.addresses.isNotEmpty)
                KotvGroupCard(
                  title: '本机访问地址',
                  children: [
                    for (final address in local.addresses)
                      KotvSettingsRow(
                        title: '本机地址',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: KotvTokens.unselectedColor,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '复制地址',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: address),
                              ),
                              icon: const Icon(Icons.copy_rounded, size: 18),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ];
            return ListView(children: children);
          },
        ),
      ),
    );
  }
}
