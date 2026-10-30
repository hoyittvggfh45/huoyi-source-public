import 'dart:async';

import 'app_page_route.dart';

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import 'core_bridge.dart';
import 'account_screen.dart';
import 'hongguo_account.dart';
import 'app_update.dart';
import 'app_update_screen.dart';
import 'builtin_sites_screen.dart';
import 'clearance_bridge.dart';
import 'crack_config_section.dart';
import 'downloads_screen.dart';
import 'import_center_screen.dart';
import 'splash_selection.dart';
import 'splash_sets.dart';
import 'splash_settings_screen.dart';
import 'parse_settings_screen.dart';
import 'app_theme.dart';
import 'ios_dialogs.dart';
import 'liquid_glass.dart';
import 'local_store.dart';
import 'profiles_screen.dart';
import 'remote_widgets.dart';
import 'sources_screen.dart';
import 'widgets.dart';
import 'resource_settings_screen.dart';
import 'lan_screen.dart';
import 'proxy_kernel_screen.dart';
import 'rule_editor_screen.dart';
import 'drama_settings.dart';
import 'ui_style.dart';
import 'xigua/playback_settings_screen.dart';
import 'app_layout.dart';
import 'detail_screen.dart';
import 'models.dart';
import 'playback_launch_screen.dart';
import 'miniapp/plugin_center_screen.dart';
import 'player_picker.dart';
import 'saved_library.dart';

String storageSize(int bytes) {
  if (bytes < 0) return '暂不可用';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.store,
    this.embedded = false,
  });
  final AppRepository repository;
  final LocalStore store;

  /// 作为底部导航「设置」tab 嵌入时不自带 Scaffold/AppBar。
  final bool embedded;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  String? _message;
  String _appUpdateSummary = '检查整包新版本';
  String _splashName = '默认启动图';

  @override
  void initState() {
    super.initState();
    ensureTelevisionFocus(context);
    _loadAppUpdateSummary();
    _loadSplashName();
  }

  Future<void> _loadAppUpdateSummary() async {
    try {
      final current = await AppUpdateChecker.currentVersion();
      final latest = await AppUpdateChecker.cachedLatestVersion();
      if (!mounted) return;
      setState(() {
        _appUpdateSummary = latest.isEmpty
            ? '当前版本 $current'
            : '当前版本 $current · 最新 $latest';
      });
    } catch (_) {}
  }

  Future<void> _loadSplashName() async {
    try {
      final selection = await loadSplashSelection();
      if (!mounted) return;
      setState(() => _splashName = splashSelectionDisplayName(selection));
    } catch (_) {}
  }

  Future<void> _chooseTheme() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('外观主题'),
        children: [
          RadioGroup<String>(
            groupValue: widget.store.themeMode,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in ['light', 'dark', 'system'])
                  RadioListTile<String>(
                    value: mode,
                    title: Text(AppTheme.label(mode)),
                    subtitle: mode == 'system'
                        ? const Text('随设备的深色模式自动切换')
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      await saveUserChange(context, () => widget.store.setThemeMode(selected));
    }
  }

  String _displayModeLabel(String mode) => switch (mode) {
    'television' => '电视 / 遥控器',
    'standard' => '手机 / 电脑',
    _ => '自动识别设备',
  };

  Future<void> _chooseDisplayMode() async {
    final selection = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('界面模式'),
        children: [
          RadioGroup<String>(
            groupValue: widget.store.displayMode,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in const {
                  'auto': '自动识别设备',
                  'television': '电视 / 遥控器',
                  'standard': '手机 / 电脑',
                }.entries)
                  RadioListTile<String>(
                    value: mode.key,
                    autofocus: mode.key == widget.store.displayMode,
                    title: Text(mode.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selection != null && mounted) {
      await saveUserChange(
        context,
        () => widget.store.setDisplayMode(selection),
      );
    }
  }

  void _openSavedDrama(Drama drama) {
    unawaited(
      openPlaybackDirectly(
        context,
        drama: drama,
        repository: widget.repository,
        store: widget.store,
      ),
    );
  }

  void _openSavedDownload(Drama drama) {
    Navigator.push(
      context,
      appPageRoute<void>(
        settings: const RouteSettings(name: 'detail'),
        builder: (_) => DetailScreen(
          drama: drama,
          repository: widget.repository,
          store: widget.store,
          downloadOnOpen: true,
        ),
      ),
    );
  }

  void _openSavedLibrary({required bool history}) {
    Navigator.push<void>(
      context,
      appPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(history ? '最近观看' : '追剧')),
          body: SavedLibrary(
            repository: widget.repository,
            store: widget.store,
            history: history,
            onOpen: _openSavedDrama,
            onContinue: _openSavedDrama,
            onDownload:
                widget.repository.supportsDownloads && widget.store.canDownload
                ? _openSavedDownload
                : null,
          ),
        ),
      ),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: appName,
      applicationVersion: AppLayout.versionOf(context),
      applicationIcon: Icon(
        glassDesign(context)
            ? LucideIcons.circlePlay
            : Icons.play_circle_filled_rounded,
        size: 48,
        color: const Color(0xFFFF765F),
      ),
      children: [const Text('独立运行，打开即可浏览和播放。观看记录与追剧收藏保存在当前设备。')],
    );
  }

  Future<void> _backup(bool restore) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!restore) {
        final content = await widget.store.exportBackup();
        final saved = await FilePicker.saveFile(
          fileName:
              '$appSlug-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
          bytes: Uint8List.fromList(utf8.encode(content)),
          mimeType: 'application/json',
        );
        if (saved != null && mounted) setState(() => _message = '备份已保存');
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (file == null || !mounted) return;
        final size = await file.length();
        if (size == null || size > 8 * 1024 * 1024) {
          throw const FormatException('备份文件过大或无法读取');
        }
        final content = utf8.decode(await file.readAsBytes());
        final data = widget.store.validateBackup(content);
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('恢复备份？'),
            content: Text(
              '包含 ${(data['profiles'] as List).length} 个用户。将替换本机的用户、追剧、观看记录和偏好设置；已下载视频保留。恢复后使用备份内的管理员密码登录。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('恢复'),
              ),
            ],
          ),
        );
        if (accepted != true || !mounted) return;
        await widget.store.importBackup(content);
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (_, _) => ValueListenableBuilder<DramaUiStyle>(
      valueListenable: dramaUiStyleNotifier,
      builder: (_, style, _) {
        final body = glassDesign(context)
            ? _glassBody(style)
            : _materialBody(style);
        if (widget.embedded) return body;
        return Scaffold(
          appBar: AppBar(title: const Text('设置与备份')),
          body: body,
        );
      },
    ),
  );

  bool _dramaEntryVisible(DramaSettingsTarget target) => switch (target) {
    DramaSettingsTarget.sources => widget.repository.supportsSourceManagement,
    DramaSettingsTarget.downloadPrefs ||
    DramaSettingsTarget.downloads ||
    DramaSettingsTarget.storage => widget.store.canDownload,
    _ => true,
  };

  VoidCallback _dramaEntryAction(
    DramaSettingsTarget target,
  ) => switch (target) {
    DramaSettingsTarget.style => () => unawaited(chooseDramaUiStyle(context)),
    DramaSettingsTarget.account => () => Navigator.push(
      context,
      appPageRoute<void>(builder: (_) => const AccountScreen()),
    ),
    DramaSettingsTarget.resource => () => Navigator.push(
      context,
      appPageRoute<void>(
        builder: (_) => ResourceSettingsScreen(
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    ),
    DramaSettingsTarget.sources => () => Navigator.push(
      context,
      appPageRoute<void>(
        builder: (_) =>
            SourcesScreen(repository: widget.repository, store: widget.store),
      ),
    ),
    DramaSettingsTarget.playback => () => Navigator.push(
      context,
      appPageRoute<void>(
        builder: (_) => PlaybackSettingsScreen(store: widget.store),
      ),
    ),
    DramaSettingsTarget.playerChoice => () => Navigator.push(
      context,
      appPageRoute<void>(
        builder: (_) => PlayerPickerScreen(store: widget.store),
      ),
    ),
    DramaSettingsTarget.downloadPrefs => () => Navigator.push(
      context,
      appPageRoute<void>(
        builder: (_) => DownloadPreferencesScreen(store: widget.store),
      ),
    ),
    DramaSettingsTarget.downloads => () => Navigator.push(
      context,
      appPageRoute<void>(
        builder: (_) =>
            DownloadsScreen(repository: widget.repository, store: widget.store),
      ),
    ),
    DramaSettingsTarget.storage => () => Navigator.push(
      context,
      appPageRoute<void>(
        builder: (_) =>
            StorageScreen(repository: widget.repository, store: widget.store),
      ),
    ),
    DramaSettingsTarget.lanSync => () => openLanSync(context),
    DramaSettingsTarget.follow => () => _openSavedLibrary(history: false),
    DramaSettingsTarget.history => () => _openSavedLibrary(history: true),
    _ => () {},
  };

  IconData _dramaEntryIcon(DramaSettingsTarget target) => switch (target) {
    DramaSettingsTarget.style => Icons.style_outlined,
    DramaSettingsTarget.account => Icons.person_outline,
    DramaSettingsTarget.resource => Icons.settings_ethernet_rounded,
    DramaSettingsTarget.sources => Icons.dns_outlined,
    DramaSettingsTarget.playback => Icons.play_circle_outline,
    DramaSettingsTarget.playerChoice => Icons.video_settings_outlined,
    DramaSettingsTarget.videoEnhancement => Icons.auto_fix_high_outlined,
    DramaSettingsTarget.downloadPrefs => Icons.download_outlined,
    DramaSettingsTarget.downloads => Icons.download_rounded,
    DramaSettingsTarget.storage => Icons.folder_outlined,
    DramaSettingsTarget.lanSync => Icons.devices_rounded,
    DramaSettingsTarget.follow => Icons.bookmark_outline,
    DramaSettingsTarget.history => Icons.history_outlined,
    DramaSettingsTarget.coverCache => Icons.image_outlined,
    DramaSettingsTarget.watchStats => Icons.bar_chart_outlined,
    DramaSettingsTarget.reservation => Icons.alarm_add_outlined,
    DramaSettingsTarget.tvSettings => Icons.tv_outlined,
  };

  List<Widget> _materialDramaSections() {
    final widgets = <Widget>[];
    for (final section in dramaStyleSettingsSections()) {
      final entries = section.availableEntries
          .where((entry) => _dramaEntryVisible(entry.target))
          .toList();
      if (entries.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
          child: Text(
            section.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      for (final entry in entries) {
        widgets.add(
          ListTile(
            leading: Icon(_dramaEntryIcon(entry.target)),
            title: Text(entry.title),
            subtitle: Text(entry.subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _dramaEntryAction(entry.target),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _materialBody(DramaUiStyle style) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(
        key: const ValueKey('settings-list'),
        padding: const EdgeInsets.all(16),
        children: [
          if (style == DramaUiStyle.drama) ..._materialDramaSections(),
          ListTile(
            key: const ValueKey('lan-settings'),
            leading: const Icon(Icons.devices_rounded),
            title: const Text('设备互联'),
            subtitle: const Text('局域网自动同步追剧与推送播放'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => openLanSync(context),
          ),
          if (widget.repository.supportsSourceManagement)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('站源管理'),
              subtitle: const Text('独立更新、连接与播放检测'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                appPageRoute<void>(
                  builder: (_) => SourcesScreen(
                    repository: widget.repository,
                    store: widget.store,
                  ),
                ),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: const Text('蜘蛛规则编辑器'),
            subtitle: const Text('编辑、校验与本地试跑 XBPQ 规则'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              appPageRoute<void>(
                builder: (_) => RuleEditorScreen(repository: widget.repository),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.video_settings_outlined),
            title: const Text('播放器选择'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              appPageRoute<void>(
                builder: (_) => PlayerPickerScreen(store: widget.store),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('builtin-sites-entry'),
            leading: const Icon(Icons.toggle_on_outlined),
            title: const Text('内置站管理'),
            subtitle: const Text('内置站逐站显示/隐藏，可恢复默认'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              appPageRoute<void>(
                builder: (_) => BuiltinSitesScreen(
                  store: widget.store,
                  repository: widget.repository,
                ),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('app-update-entry'),
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('软件更新'),
            subtitle: Text(_appUpdateSummary),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              appPageRoute<void>(builder: (_) => const AppUpdateScreen()),
            ),
          ),
          ListTile(
            key: const ValueKey('proxy-kernel-entry'),
            leading: const Icon(Icons.shield_outlined),
            title: const Text('代理内核'),
            subtitle: const Text('mihomo 本地代理：内置核、更新内核、订阅、选节点、测速、自启'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              appPageRoute<void>(
                builder: (_) =>
                    ProxyKernelScreen(repository: widget.repository),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('import-center-entry'),
            leading: const Icon(Icons.library_add_outlined),
            title: const Text('导入中心'),
            subtitle: const Text('TVBox 远程配置与 jar 直导入，分组共存'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              appPageRoute<void>(
                builder: (_) => ImportCenterScreen(
                  repository: widget.repository,
                  store: widget.store,
                ),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('parse-settings-entry'),
            leading: const Icon(Icons.alt_route_rounded),
            title: const Text('解析接口'),
            subtitle: const Text('播放解析接口列表与默认选中'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              appPageRoute<void>(builder: (_) => const ParseSettingsScreen()),
            ),
          ),
          ListTile(
            key: const ValueKey('clearance-entry'),
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('站点验证'),
            subtitle: const Text('为被拦截的站点完成浏览器验证'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => openClearanceFlow(context, widget.repository),
          ),
          ListTile(
            key: const ValueKey('crack-config-entry'),
            leading: const Icon(Icons.shield_outlined),
            title: const Text('过盾与 VIP 配置'),
            subtitle: const Text('导入导出各站过盾与 VIP 配置'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              appPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('过盾与 VIP 配置')),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: CrackConfigSection(repository: widget.repository),
                  ),
                ),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('theme-setting'),
            leading: const Icon(Icons.palette_outlined),
            title: const Text('外观主题'),
            subtitle: Text(AppTheme.label(widget.store.themeMode)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _chooseTheme,
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('开机启动图'),
            subtitle: Text(_splashName),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await Navigator.push(
                context,
                appPageRoute<void>(
                  builder: (_) => const SplashSettingsScreen(),
                ),
              );
              if (mounted) await _loadSplashName();
            },
          ),
          ListTile(
            leading: const Icon(Icons.display_settings_outlined),
            title: const Text('界面模式'),
            subtitle: Text(_displayModeLabel(widget.store.displayMode)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _chooseDisplayMode,
          ),
          if (style != DramaUiStyle.drama)
            ListTile(
              leading: const Icon(Icons.style_outlined),
              title: const Text('短剧区风格'),
              subtitle: ValueListenableBuilder<DramaUiStyle>(
                valueListenable: dramaUiStyleNotifier,
                builder: (context, style, _) => Text(style.label),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => unawaited(chooseDramaUiStyle(context)),
            ),
          if (style != DramaUiStyle.drama)
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
              onTap: () => Navigator.push(
                context,
                appPageRoute<void>(builder: (_) => const AccountScreen()),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('用户管理'),
            subtitle: Text('当前：${widget.store.profile.name}'),
            onTap: () => Navigator.push(
              context,
              appPageRoute<void>(
                builder: (_) => ProfilesScreen(store: widget.store),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outlined),
            title: Text('关于$appName'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showAbout,
          ),
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('插件中心'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openPluginCenter(),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('追剧'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openSavedLibrary(history: false),
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('最近观看'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openSavedLibrary(history: true),
          ),
          if (widget.store.canDownload)
            ListTile(
              key: const ValueKey('downloads-entry'),
              leading: const Icon(Icons.download_rounded),
              title: const Text('下载'),
              subtitle: const Text('查看与管理已下载内容'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                appPageRoute<void>(
                  builder: (_) => DownloadsScreen(
                    repository: widget.repository,
                    store: widget.store,
                  ),
                ),
              ),
            ),
          if (widget.store.canDownload)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('下载偏好'),
              subtitle: Text(widget.store.downloadPreferences.qualityLabel),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                appPageRoute<void>(
                  builder: (_) =>
                      DownloadPreferencesScreen(store: widget.store),
                ),
              ),
            ),
          if (widget.store.canDownload)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('下载目录与空间'),
              subtitle: const Text('查看存储用量、迁移已下载文件'),
              onTap: () => Navigator.push(
                context,
                appPageRoute<void>(
                  builder: (_) => StorageScreen(
                    repository: widget.repository,
                    store: widget.store,
                  ),
                ),
              ),
            ),
          if (widget.store.profile.admin) ...[
            ListTile(
              leading: const Icon(Icons.settings_ethernet_rounded),
              title: const Text('网络与资源'),
              subtitle: const Text('代理、目录请求间隔、下载并发与站源目录'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                appPageRoute<void>(
                  builder: (_) => ResourceSettingsScreen(
                    repository: widget.repository,
                    store: widget.store,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('导出配置备份'),
              subtitle: const Text('包含本地用户、追剧、历史和设置，不含视频文件'),
              onTap: _busy ? null : () => _backup(false),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('恢复配置备份'),
              onTap: _busy ? null : () => _backup(true),
            ),
          ],
          if (Platform.isIOS)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('iOS 下载需要保持应用在前台；切到后台会暂停，回到前台后可继续。'),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_message!),
            ),
        ],
      ),
    ),
  );

  Future<void> _push(Widget page) =>
      Navigator.push(context, appPageRoute<void>(builder: (_) => page));

  Future<void> _openPluginCenter() async {
    await _push(
      PluginCenterScreen(store: widget.store, repository: widget.repository),
    );
  }

  Future<void> _chooseGlassTheme() async {
    final selected = await showChoiceSheet<String>(
      context,
      title: '外观主题',
      choices: [
        for (final mode in ['system', 'light', 'dark'])
          SheetChoice(
            mode,
            AppTheme.label(mode),
            selected: widget.store.themeMode == mode,
            icon: switch (mode) {
              'light' => LucideIcons.sun,
              'dark' => LucideIcons.moon,
              _ => LucideIcons.sunMoon,
            },
          ),
      ],
    );
    if (selected != null && mounted) {
      await saveUserChange(context, () => widget.store.setThemeMode(selected));
    }
  }

  Widget _glassIcon(IconData icon, Color color) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: SizedBox.square(
      dimension: 30,
      child: Icon(icon, size: 18, color: Colors.white),
    ),
  );

  Widget _glassSection(
    String? header,
    List<Widget> children, {
    String? footer,
  }) {
    final colors = Theme.of(context).colorScheme;
    final caption = TextStyle(
      fontSize: 12,
      letterSpacing: 0,
      color: colors.onSurfaceVariant,
    );
    if (iosDesign(context)) {
      return CupertinoListSection.insetGrouped(
        backgroundColor: Colors.transparent,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(18),
        ),
        separatorColor: colors.outlineVariant,
        header: header == null ? null : Text(header, style: caption),
        footer: footer == null ? null : Text(footer, style: caption),
        children: children,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(header, style: caption),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(children: children),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(footer, style: caption),
            ),
        ],
      ),
    );
  }

  Widget _glassRow({
    Key? key,
    required IconData icon,
    required Color color,
    required String title,
    String? detail,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    if (!iosDesign(context)) {
      return GlassTapTarget(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: SizedBox(
          height: 62,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _glassIcon(icon, color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: onTap == null && trailing == null
                              ? colors.onSurface.withValues(alpha: .4)
                              : colors.onSurface,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                ?trailing,
                if (trailing == null && onTap != null)
                  Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return CupertinoListTile.notched(
      key: key,
      leading: _glassIcon(icon, color),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 0,
          color: onTap == null && trailing == null
              ? colors.onSurface.withValues(alpha: .4)
              : colors.onSurface,
        ),
      ),
      additionalInfo: detail == null
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
      trailing:
          trailing ?? (onTap == null ? null : const CupertinoListTileChevron()),
      backgroundColorActivated: colors.surfaceContainerHigh,
      onTap: onTap,
    );
  }

  List<Widget> _glassDramaSection(DramaSettingsSection section, Color color) {
    final rows = <Widget>[];
    for (final entry in section.availableEntries) {
      if (!_dramaEntryVisible(entry.target)) continue;
      rows.add(
        _glassRow(
          icon: _dramaEntryIcon(entry.target),
          color: color,
          title: entry.title,
          detail: entry.subtitle,
          onTap: _dramaEntryAction(entry.target),
        ),
      );
    }
    if (rows.isEmpty) return [];
    return [_glassSection(section.title, rows)];
  }

  Widget _glassBody(DramaUiStyle style) {
    final store = widget.store;
    return ListView(
      key: const ValueKey('settings-list'),
      padding: EdgeInsets.fromLTRB(
        0,
        4,
        0,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _glassSection('短剧区', [
          _glassRow(
            icon: Icons.style_outlined,
            color: const Color(0xFFAF52DE),
            title: '短剧区风格',
            detail: style.label,
            onTap: () => unawaited(chooseDramaUiStyle(context)),
          ),
          ValueListenableBuilder<HongguoAccount?>(
            valueListenable: hongguoAccountNotifier,
            builder: (context, account, _) => _glassRow(
              icon: Icons.person_outline,
              color: const Color(0xFF34C759),
              title: '账号',
              detail: account != null && account.loggedIn
                  ? account.displayName
                  : '未登录',
              onTap: () => _push(const AccountScreen()),
            ),
          ),
        ]),
        if (style == DramaUiStyle.drama)
          for (final section in dramaStyleSettingsSections())
            if (section.title != '短剧区')
              ..._glassDramaSection(section, switch (section.title) {
                '资源' => const Color(0xFF5E5CE6),
                '播放' => const Color(0xFF64D2FF),
                '下载' => const Color(0xFF0A84FF),
                '同步' => const Color(0xFF30D158),
                '数据' => const Color(0xFFFF9F0A),
                _ => const Color(0xFF8E8E93),
              }),
        _glassSection('通用', [
          _glassRow(
            key: const ValueKey('lan-settings'),
            icon: LucideIcons.monitorSmartphone,
            color: const Color(0xFF0A84FF),
            title: '设备互联',
            detail: '同步与推送',
            onTap: () => openLanSync(context),
          ),
          if (widget.repository.supportsSourceManagement)
            _glassRow(
              icon: LucideIcons.server,
              color: const Color(0xFF30B0C7),
              title: '站源管理',
              onTap: () => _push(
                SourcesScreen(repository: widget.repository, store: store),
              ),
            ),
          _glassRow(
            icon: LucideIcons.code,
            color: const Color(0xFFBF5AF2),
            title: '蜘蛛规则编辑器',
            onTap: () => _push(RuleEditorScreen(repository: widget.repository)),
          ),
          _glassRow(
            icon: LucideIcons.clapperboard,
            color: const Color(0xFF64D2FF),
            title: '播放器选择',
            onTap: () => _push(PlayerPickerScreen(store: store)),
          ),
          _glassRow(
            key: const ValueKey('builtin-sites-entry'),
            icon: LucideIcons.listChecks,
            color: const Color(0xFF30D158),
            title: '内置站管理',
            detail: '内置站逐站显示/隐藏，可恢复默认',
            onTap: () => _push(
              BuiltinSitesScreen(store: store, repository: widget.repository),
            ),
          ),
          _glassRow(
            key: const ValueKey('app-update-entry'),
            icon: LucideIcons.arrowDownToLine,
            color: const Color(0xFF0A84FF),
            title: '软件更新',
            detail: _appUpdateSummary,
            onTap: () => _push(const AppUpdateScreen()),
          ),
          _glassRow(
            key: const ValueKey('import-center-entry'),
            icon: LucideIcons.libraryBig,
            color: const Color(0xFF64D2FF),
            title: '导入中心',
            detail: 'TVBox 配置 / jar',
            onTap: () => _push(
              ImportCenterScreen(repository: widget.repository, store: store),
            ),
          ),
          _glassRow(
            key: const ValueKey('parse-settings-entry'),
            icon: LucideIcons.route,
            color: const Color(0xFFFF6482),
            title: '解析接口',
            detail: '默认选中',
            onTap: () => _push(const ParseSettingsScreen()),
          ),
          _glassRow(
            key: const ValueKey('clearance-entry'),
            icon: LucideIcons.shieldCheck,
            color: const Color(0xFF64D2FF),
            title: '站点验证',
            detail: '浏览器过盾回填',
            onTap: () => openClearanceFlow(context, widget.repository),
          ),
          _glassRow(
            key: const ValueKey('proxy-kernel-entry'),
            icon: LucideIcons.shield,
            color: const Color(0xFF5E5CE6),
            title: '代理内核',
            detail: 'mihomo 本地代理',
            onTap: () =>
                _push(ProxyKernelScreen(repository: widget.repository)),
          ),
          _glassRow(
            key: const ValueKey('theme-setting'),
            icon: LucideIcons.palette,
            color: const Color(0xFFAF52DE),
            title: '外观主题',
            detail: AppTheme.label(store.themeMode),
            onTap: _chooseGlassTheme,
          ),
          _glassRow(
            icon: LucideIcons.monitor,
            color: const Color(0xFF5E5CE6),
            title: '界面模式',
            detail: _displayModeLabel(store.displayMode),
            onTap: _chooseDisplayMode,
          ),
          _glassRow(
            icon: LucideIcons.users,
            color: const Color(0xFF34C759),
            title: '用户管理',
            detail: store.profile.name,
            onTap: () => _push(ProfilesScreen(store: store)),
          ),
          _glassRow(
            icon: LucideIcons.info,
            color: const Color(0xFF8E8E93),
            title: '关于$appName',
            onTap: _showAbout,
          ),
          _glassRow(
            icon: LucideIcons.puzzle,
            color: const Color(0xFFBF5AF2),
            title: '插件中心',
            onTap: () => _openPluginCenter(),
          ),
        ]),
        _glassSection('内容', [
          _glassRow(
            icon: LucideIcons.bookmark,
            color: const Color(0xFFFF9F0A),
            title: '追剧',
            onTap: () => _openSavedLibrary(history: false),
          ),
          _glassRow(
            icon: LucideIcons.history,
            color: const Color(0xFF30B0C7),
            title: '最近观看',
            onTap: () => _openSavedLibrary(history: true),
          ),
        ]),
        if (store.canDownload)
          _glassSection(
            '下载',
            [
              _glassRow(
                key: const ValueKey('downloads-entry'),
                icon: LucideIcons.arrowDownToLine,
                color: const Color(0xFF0A84FF),
                title: '下载',
                detail: '已下载内容',
                onTap: () => _push(
                  DownloadsScreen(repository: widget.repository, store: store),
                ),
              ),
              _glassRow(
                icon: LucideIcons.arrowDownToLine,
                color: const Color(0xFFFF9F0A),
                title: '下载偏好',
                detail: store.downloadPreferences.qualityLabel,
                onTap: () => _push(DownloadPreferencesScreen(store: store)),
              ),
              _glassRow(
                icon: LucideIcons.hardDrive,
                color: const Color(0xFF8E8E93),
                title: '下载目录与空间',
                onTap: () => _push(
                  StorageScreen(repository: widget.repository, store: store),
                ),
              ),
            ],
            footer: Platform.isIOS
                ? 'iOS 下载需要保持应用在前台；切到后台会暂停，回到前台后可继续。'
                : null,
          ),
        if (store.profile.admin) ...[
          _glassSection('管理', [
            _glassRow(
              icon: LucideIcons.network,
              color: const Color(0xFF5E5CE6),
              title: '网络与资源',
              detail: '代理与并发',
              onTap: () => _push(
                ResourceSettingsScreen(
                  repository: widget.repository,
                  store: store,
                ),
              ),
            ),
          ]),
          _glassSection('备份', [
            _glassRow(
              icon: LucideIcons.databaseBackup,
              color: const Color(0xFF0A84FF),
              title: '导出配置备份',
              onTap: _busy ? null : () => _backup(false),
            ),
            _glassRow(
              icon: LucideIcons.archiveRestore,
              color: const Color(0xFFFF9F0A),
              title: '恢复配置备份',
              onTap: _busy ? null : () => _backup(true),
            ),
          ], footer: '包含本地用户、追剧、历史和设置，不含视频文件。'),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
            child: SelectableText(
              _message!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class StorageScreen extends StatefulWidget {
  const StorageScreen({
    super.key,
    required this.repository,
    required this.store,
  });
  final AppRepository repository;
  final LocalStore store;
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, dynamic>? _info;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final info = await widget.repository.storage();
      if (mounted) {
        setState(() {
          _info = info;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _move() async {
    String? parent;
    if (Platform.isAndroid || Platform.isIOS) {
      final support = await getApplicationSupportDirectory();
      final directories = <String, String>{support.path: '应用内部存储'};
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectories() ?? [];
        for (var i = 0; i < external.length; i++) {
          directories[external[i].path] = i == 0
              ? '设备共享存储（应用目录）'
              : 'SD 卡 ${i + 1}（应用目录）';
        }
      } else {
        final documents = await getApplicationDocumentsDirectory();
        directories[documents.path] = '文件 App 可见目录';
      }
      if (!mounted) return;
      parent = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择下载位置'),
          children: [
            for (final entry in directories.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
      );
    } else {
      parent = await FilePicker.getDirectoryPath(dialogTitle: '选择下载保存位置');
    }
    if (parent == null || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('迁移已下载内容？'),
        content: Text(
          '将视频、合并成品及导出内容迁移到：\n$parent\n\n下载会先暂停，复制成功后清理旧目录。请保证目标有足够空间，并在完成后继续下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('迁移'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.moveDownloads(parent);
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('下载目录与空间')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_info != null) ...[
                Text(
                  '已使用 ${storageSize((_info!['bytes'] as num?)?.toInt() ?? 0)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '剩余 ${storageSize((_info!['free'] as num?)?.toInt() ?? -1)} · ${_info!['files'] ?? 0} 个文件',
                ),
                const SizedBox(height: 24),
                const Text('当前下载目录'),
                const SizedBox(height: 8),
                SelectableText(_info!['directory'] as String? ?? ''),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: _info!['directory'] as String? ?? ''),
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('复制路径'),
                ),
                const SizedBox(height: 20),
                const Text('在下载页删除不需要的分集，可释放空间。'),
              ],
              if (_busy || (_info == null && _error == null))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: LinearProgressIndicator(),
                ),
              if (_busy) const Text('正在迁移，请保持应用运行…'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_error!),
                ),
              if (widget.store.profile.admin)
                FilledButton.icon(
                  onPressed: _busy ? null : _move,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('更改并迁移目录'),
                ),
              TextButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('刷新用量'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
