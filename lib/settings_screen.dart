import 'dart:async';

import 'app_page_route.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'core_bridge.dart';
import 'app_update.dart';
import 'app_update_screen.dart';
import 'clearance_bridge.dart';
import 'crack_config_section.dart';
import 'custom_headers_screen.dart';
import 'jar_bridge.dart';
import 'import_center_screen.dart';
import 'parse_settings_screen.dart';
import 'app_theme.dart';
import 'liquid_glass.dart';
import 'local_store.dart';
import 'py_bridge.dart';
import 'remote_widgets.dart';
import 'site_check_screen.dart';
import 'sources_screen.dart';
import 'resource_settings_screen.dart';
import 'lan_screen.dart';
import 'proxy_kernel_screen.dart';
import 'rule_editor_screen.dart';
import 'theme_settings_screen.dart';
import 'hongguo_device_screen.dart';
import 'app_layout.dart';
import 'player_picker.dart';
import 'xigua/playback_settings_screen.dart';

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
  String _appUpdateSummary = '检查整包新版本';
  final Map<String, bool> _groupOpen = {
    'sites': true,
    'playback': true,
    'network': false,
    'device': true,
    'system': false,
  };

  @override
  void initState() {
    super.initState();
    ensureTelevisionFocus(context);
    _loadAppUpdateSummary();
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (_, _) {
      final body = glassDesign(context) ? _glassBody() : _materialBody();
      if (widget.embedded) return body;
      return Scaffold(
        appBar: AppBar(title: const Text('设置与备份')),
        body: body,
      );
    },
  );

  Widget _materialGroup({
    required String id,
    required String title,
    required List<Widget> children,
  }) {
    final open = _groupOpen[id] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _groupOpen[id] = !open),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                children: [
                  Icon(
                    open
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${children.length} 项',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    children[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _glassGroup({
    required String id,
    required String title,
    required List<Widget> children,
  }) {
    final open = _groupOpen[id] ?? false;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: open ? 0 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassTapTarget(
            onTap: () => setState(() => _groupOpen[id] = !open),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Icon(
                    open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${children.length} 项',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open) _glassSection(null, children),
        ],
      ),
    );
  }
  Widget _materialBody() {
    final sites = <Widget>[
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
        key: const ValueKey('site-check-entry'),
        leading: const Icon(Icons.fact_check_outlined),
        title: const Text('站点检查'),
        subtitle: const Text('逐站测活，失效站自动隐藏'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(
          context,
          appPageRoute<void>(
            builder: (_) => SiteCheckScreen(
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
    ];
    final playback = <Widget>[
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
        key: const ValueKey('playback-settings-entry'),
        leading: const Icon(Icons.tune_rounded),
        title: const Text('播放设置'),
        subtitle: const Text('倍速、弹幕、自动连播与画质偏好'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(
          context,
          appPageRoute<void>(
            builder: (_) => PlaybackSettingsScreen(store: widget.store),
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
    ];
    final network = <Widget>[
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
        key: const ValueKey('python-cf-disguise-entry'),
        leading: const Icon(Icons.fingerprint),
        title: const Text('Python 指纹过盾'),
        subtitle: Text(
          widget.store.pythonCfDisguise
              ? '已开启 · 按蜘蛛 UA 匹配浏览器'
              : '已关闭 · 只用普通请求',
        ),
        trailing: Switch.adaptive(
          activeTrackColor: Theme.of(context).colorScheme.tertiary,
          value: widget.store.pythonCfDisguise,
          onChanged: (value) async {
            try {
              await widget.store.setPythonCfDisguise(value);
              await PyBridge.setCfDisguise(value);
            } catch (error) {
              if (mounted) {
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(SnackBar(content: Text('切换失败：$error')));
              }
            }
            if (mounted) setState(() {});
          },
        ),
      ),
      ListTile(
        key: const ValueKey('jar-fingerprint-entry'),
        leading: const Icon(Icons.fingerprint),
        title: const Text('Jar 指纹过盾'),
        subtitle: Text(
          widget.store.jarFingerprintEnabled
              ? '已开启 · 按蜘蛛 UA 匹配浏览器'
              : '已关闭 · 只用普通请求',
        ),
        trailing: Switch.adaptive(
          activeTrackColor: Theme.of(context).colorScheme.tertiary,
          value: widget.store.jarFingerprintEnabled,
          onChanged: (value) async {
            try {
              await widget.store.setJarFingerprintEnabled(value);
              await JarBridge.setJarFingerprint(value);
            } catch (error) {
              if (mounted) {
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(SnackBar(content: Text('切换失败：$error')));
              }
            }
            if (mounted) setState(() {});
          },
        ),
      ),
      ListTile(
        key: const ValueKey('custom-headers-entry'),
        leading: const Icon(Icons.tune),
        title: const Text('自定义请求头'),
        subtitle: Text(
          widget.store.customHeadersEnabled
              ? '已开启 · ${widget.store.customHeaderRules.length} 条规则'
              : '已关闭',
        ),
        onTap: () => Navigator.push(
          context,
          appPageRoute<void>(
            builder: (_) => CustomHeadersScreen(store: widget.store),
          ),
        ),
        trailing: Switch.adaptive(
          activeTrackColor: Theme.of(context).colorScheme.tertiary,
          value: widget.store.customHeadersEnabled,
          onChanged: (value) async {
            try {
              await widget.store.setCustomHeadersEnabled(value);
            } catch (error) {
              if (mounted) {
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(SnackBar(content: Text('切换失败：$error')));
              }
            }
            if (mounted) setState(() {});
          },
        ),
      ),
    ];
    final device = <Widget>[
      ListTile(
        key: const ValueKey('lan-settings'),
        leading: const Icon(Icons.devices_rounded),
        title: const Text('设备互联'),
        subtitle: const Text('局域网自动同步追剧与推送播放'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => openLanSync(context),
      ),
      ListTile(
        key: const ValueKey('theme-settings-entry'),
        leading: const Icon(Icons.palette_outlined),
        title: const Text('外观主题'),
        subtitle: const Text('模式、风格、主题色与背景'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(
          context,
          appPageRoute<void>(
            builder: (_) => ThemeSettingsScreen(store: widget.store),
          ),
        ),
      ),
      ListTile(
        key: const ValueKey('hongguo-device-entry'),
        leading: const Icon(Icons.badge_outlined),
        title: const Text('设备注册档案'),
        subtitle: const Text('红果设备身份与注册状态'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(
          context,
          appPageRoute<void>(
            builder: (_) =>
                HongguoDeviceScreen(repository: widget.repository),
          ),
        ),
      ),
    ];
    final system = <Widget>[
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
        leading: const Icon(Icons.info_outlined),
        title: Text('关于$appName'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _showAbout,
      ),
      if (widget.store.profile.admin) ...[
        ListTile(
          leading: const Icon(Icons.settings_ethernet_rounded),
          title: const Text('网络与资源'),
          subtitle: const Text('代理、目录请求间隔与站源目录'),
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
      ],
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          key: const ValueKey('settings-list'),
          padding: const EdgeInsets.all(16),
          children: [
            _materialGroup(id: 'sites', title: '站源与导入', children: sites),
            _materialGroup(id: 'playback', title: '播放与解析', children: playback),
            _materialGroup(id: 'network', title: '网络与过盾', children: network),
            _materialGroup(id: 'device', title: '外观与设备', children: device),
            _materialGroup(id: 'system', title: '系统与关于', children: system),
          ],
        ),
      ),
    );
  }

  Future<void> _push(Widget page) =>
      Navigator.push(context, appPageRoute<void>(builder: (_) => page));

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

  Widget _glassBody() {
    final store = widget.store;
    final sites = <Widget>[
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
        key: const ValueKey('site-check-entry'),
        icon: LucideIcons.listChecks,
        color: const Color(0xFF30B0C7),
        title: '站点检查',
        detail: '逐站测活 · 失效自动隐藏',
        onTap: () => _push(
          SiteCheckScreen(repository: widget.repository, store: store),
        ),
      ),
      _glassRow(
        icon: LucideIcons.code,
        color: const Color(0xFFBF5AF2),
        title: '蜘蛛规则编辑器',
        onTap: () => _push(RuleEditorScreen(repository: widget.repository)),
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
    ];
    final playback = <Widget>[
      _glassRow(
        icon: LucideIcons.clapperboard,
        color: const Color(0xFF64D2FF),
        title: '播放器选择',
        onTap: () => _push(PlayerPickerScreen(store: store)),
      ),
      _glassRow(
        key: const ValueKey('playback-settings-entry'),
        icon: LucideIcons.slidersHorizontal,
        color: const Color(0xFFBF5AF2),
        title: '播放设置',
        detail: '倍速、弹幕、自动连播与画质偏好',
        onTap: () => _push(PlaybackSettingsScreen(store: store)),
      ),
      _glassRow(
        key: const ValueKey('parse-settings-entry'),
        icon: LucideIcons.route,
        color: const Color(0xFFFF6482),
        title: '解析接口',
        detail: '默认选中',
        onTap: () => _push(const ParseSettingsScreen()),
      ),
    ];
    final network = <Widget>[
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
        key: const ValueKey('clearance-entry'),
        icon: LucideIcons.shieldCheck,
        color: const Color(0xFF64D2FF),
        title: '站点验证',
        detail: '浏览器过盾回填',
        onTap: () => openClearanceFlow(context, widget.repository),
      ),
      _glassRow(
        key: const ValueKey('crack-config-entry'),
        icon: LucideIcons.shield,
        color: const Color(0xFF5E5CE6),
        title: '过盾与 VIP 配置',
        detail: '导入导出各站过盾与 VIP 配置',
        onTap: () => _push(
          Scaffold(
            appBar: AppBar(title: const Text('过盾与 VIP 配置')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: CrackConfigSection(repository: widget.repository),
            ),
          ),
        ),
      ),
      _glassRow(
        key: const ValueKey('python-cf-disguise-entry'),
        icon: LucideIcons.fingerprint,
        color: const Color(0xFF30D158),
        title: 'Python 指纹过盾',
        detail: store.pythonCfDisguise
            ? '已开启 · 按蜘蛛 UA 匹配浏览器'
            : '已关闭 · 只用普通请求',
        trailing: Switch.adaptive(
          activeTrackColor: Theme.of(context).colorScheme.tertiary,
          value: store.pythonCfDisguise,
          onChanged: (value) async {
            try {
              await store.setPythonCfDisguise(value);
              await PyBridge.setCfDisguise(value);
            } catch (error) {
              if (mounted) {
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(SnackBar(content: Text('切换失败：$error')));
              }
            }
            if (mounted) setState(() {});
          },
        ),
      ),
      _glassRow(
        key: const ValueKey('jar-fingerprint-entry'),
        icon: LucideIcons.fingerprint,
        color: const Color(0xFF30D158),
        title: 'Jar 指纹过盾',
        detail: store.jarFingerprintEnabled
            ? '已开启 · 按蜘蛛 UA 匹配浏览器'
            : '已关闭 · 只用普通请求',
        trailing: Switch.adaptive(
          activeTrackColor: Theme.of(context).colorScheme.tertiary,
          value: store.jarFingerprintEnabled,
          onChanged: (value) async {
            try {
              await store.setJarFingerprintEnabled(value);
              await JarBridge.setJarFingerprint(value);
            } catch (error) {
              if (mounted) {
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(SnackBar(content: Text('切换失败：$error')));
              }
            }
            if (mounted) setState(() {});
          },
        ),
      ),
      _glassRow(
        key: const ValueKey('custom-headers-entry'),
        icon: LucideIcons.slidersHorizontal,
        color: const Color(0xFF0A84FF),
        title: '自定义请求头',
        detail: store.customHeadersEnabled
            ? '已开启 · ${store.customHeaderRules.length} 条规则'
            : '已关闭',
        onTap: () => _push(CustomHeadersScreen(store: store)),
        trailing: Switch.adaptive(
          activeTrackColor: Theme.of(context).colorScheme.tertiary,
          value: store.customHeadersEnabled,
          onChanged: (value) async {
            try {
              await store.setCustomHeadersEnabled(value);
            } catch (error) {
              if (mounted) {
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(SnackBar(content: Text('切换失败：$error')));
              }
            }
            if (mounted) setState(() {});
          },
        ),
      ),
    ];
    final device = <Widget>[
      _glassRow(
        key: const ValueKey('lan-settings'),
        icon: LucideIcons.monitorSmartphone,
        color: const Color(0xFF0A84FF),
        title: '设备互联',
        detail: '同步与推送',
        onTap: () => openLanSync(context),
      ),
      _glassRow(
        key: const ValueKey('theme-setting'),
        icon: LucideIcons.palette,
        color: const Color(0xFFAF52DE),
        title: '外观主题',
        detail: AppTheme.label(store.themeMode),
        onTap: () => _push(ThemeSettingsScreen(store: widget.store)),
      ),
      _glassRow(
        key: const ValueKey('hongguo-device-entry'),
        icon: LucideIcons.badge,
        color: const Color(0xFFFF765F),
        title: '设备注册档案',
        detail: '红果设备身份与注册状态',
        onTap: () =>
            _push(HongguoDeviceScreen(repository: widget.repository)),
      ),
    ];
    final system = <Widget>[
      _glassRow(
        key: const ValueKey('app-update-entry'),
        icon: LucideIcons.arrowDownToLine,
        color: const Color(0xFF0A84FF),
        title: '软件更新',
        detail: _appUpdateSummary,
        onTap: () => _push(const AppUpdateScreen()),
      ),
      _glassRow(
        icon: LucideIcons.info,
        color: const Color(0xFF8E8E93),
        title: '关于$appName',
        onTap: _showAbout,
      ),
      if (store.profile.admin) ...[
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
      ],
    ];
    return ListView(
      key: const ValueKey('settings-list'),
      padding: EdgeInsets.fromLTRB(
        0,
        4,
        0,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _glassGroup(id: 'sites', title: '站源与导入', children: sites),
        _glassGroup(id: 'playback', title: '播放与解析', children: playback),
        _glassGroup(id: 'network', title: '网络与过盾', children: network),
        _glassGroup(id: 'device', title: '外观与设备', children: device),
        _glassGroup(id: 'system', title: '系统与关于', children: system),
      ],
    );
  }
}
