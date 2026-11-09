import 'package:flutter/material.dart';

import 'app_build.dart';

enum HomeZone { drama, vod, midnight, live, audio, novel }

enum AppDrawerTool {
  sources,
  settings,
  player,
  appUpdate,
  importCenter,
  contentSources,
  parse,
  clearance,
  proxyKernel,
  lanSync,
  ruleEditor,
  playbackSettings,
  downloads,
  theme,
  miniApp,
}

class SiteSourceBox extends StatelessWidget {
  const SiteSourceBox({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.zone,
    required this.currentVersion,
    required this.onZoneSelected,
    required this.onWatchRoom,
    required this.onTool,
    required this.onMinorProtectionChanged,
  });

  final HomeZone zone;
  final String currentVersion;
  final ValueChanged<HomeZone> onZoneSelected;
  final VoidCallback onWatchRoom;
  final ValueChanged<AppDrawerTool> onTool;
  final ValueChanged<bool> onMinorProtectionChanged;

  Widget _zoneTab({
    required BuildContext context,
    required HomeZone tabZone,
    required IconData icon,
    required String label,
  }) {
    final colors = Theme.of(context).colorScheme;
    final selected = zone == tabZone;
    final labelColor = selected ? colors.onPrimary : colors.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => onZoneSelected(tabZone),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: labelColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTab({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colors.onSurface),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool emphasized = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: emphasized
          ? Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colors.primary),
            )
          : Icon(icon),
      title: Text(label),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  Widget _groupCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required List<Widget> rows,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.grid_view_rounded),
          ),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final versionText = currentVersion.isEmpty ? '' : '当前版本 $currentVersion';
    return Drawer(
      backgroundColor: colors.surfaceContainerLowest,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            margin: EdgeInsets.zero,
            decoration: BoxDecoration(color: colors.primaryContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (versionText.isNotEmpty) ...[
                  Text(versionText),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/ant_logo.png',
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.person_rounded, size: 56),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _zoneTab(
                        context: context,
                        tabZone: HomeZone.drama,
                        icon: Icons.movie_rounded,
                        label: '短剧',
                      ),
                      _zoneTab(
                        context: context,
                        tabZone: HomeZone.vod,
                        icon: Icons.video_library_rounded,
                        label: '点播',
                      ),
                      _zoneTab(
                        context: context,
                        tabZone: HomeZone.midnight,
                        icon: Icons.nightlight_rounded,
                        label: '午夜',
                      ),
                      _zoneTab(
                        context: context,
                        tabZone: HomeZone.live,
                        icon: Icons.live_tv_rounded,
                        label: '直播',
                      ),
                      _zoneTab(
                        context: context,
                        tabZone: HomeZone.audio,
                        icon: Icons.headphones_rounded,
                        label: '听书',
                      ),
                      _zoneTab(
                        context: context,
                        tabZone: HomeZone.novel,
                        icon: Icons.menu_book_rounded,
                        label: '阅读',
                      ),
                      _actionTab(
                        context: context,
                        icon: Icons.apps_rounded,
                        label: '小程序',
                        onTap: () => onTool(AppDrawerTool.miniApp),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _groupCard(
            context: context,
            title: '影视模块',
            subtitle: '选择一项配置或进入模块',
            rows: [
              _toolTile(
                context: context,
                icon: Icons.group_rounded,
                label: '一起看房间',
                subtitle: '与好友同步观影',
                onTap: onWatchRoom,
                emphasized: true,
              ),
              _toolTile(
                context: context,
                icon: Icons.list_rounded,
                label: '站源管理',
                subtitle: '影视站源、接口与播放来源',
                onTap: () => onTool(AppDrawerTool.sources),
              ),
              _toolTile(
                context: context,
                icon: Icons.dns_rounded,
                label: '配置源切换',
                subtitle: '远程配置与内容源',
                onTap: () => onTool(AppDrawerTool.contentSources),
              ),
              _toolTile(
                context: context,
                icon: Icons.tune_rounded,
                label: '播放设置',
                subtitle: '倍速、弹幕、自动连播与画质偏好',
                onTap: () => onTool(AppDrawerTool.playbackSettings),
              ),
              _toolTile(
                context: context,
                icon: Icons.play_circle_rounded,
                label: '播放器选择',
                subtitle: '切换播放器后端',
                onTap: () => onTool(AppDrawerTool.player),
              ),
            ],
          ),
          _groupCard(
            context: context,
            title: '应用工具',
            subtitle: '通用配置与管理',
            rows: [
              _toolTile(
                context: context,
                icon: Icons.download_rounded,
                label: '影视下载',
                subtitle: '管理已下载影片并离线观看',
                onTap: () => onTool(AppDrawerTool.downloads),
              ),
              _toolTile(
                context: context,
                icon: Icons.palette_rounded,
                label: '外观主题',
                subtitle: '模式、风格、主题色与背景',
                onTap: () => onTool(AppDrawerTool.theme),
              ),
              _toolTile(
                context: context,
                icon: Icons.vpn_key_rounded,
                label: '代理内核',
                subtitle: '本地代理、订阅节点、测速与自启',
                onTap: () => onTool(AppDrawerTool.proxyKernel),
              ),
              _toolTile(
                context: context,
                icon: Icons.link_rounded,
                label: '解析接口',
                subtitle: '播放解析接口列表与默认选中',
                onTap: () => onTool(AppDrawerTool.parse),
              ),
              _toolTile(
                context: context,
                icon: Icons.verified_user_rounded,
                label: '站点验证',
                subtitle: '为被拦截的站点完成浏览器验证',
                onTap: () => onTool(AppDrawerTool.clearance),
              ),
              _toolTile(
                context: context,
                icon: Icons.devices_rounded,
                label: '设备互联',
                subtitle: '局域网自动同步追剧与推送播放',
                onTap: () => onTool(AppDrawerTool.lanSync),
              ),
              _toolTile(
                context: context,
                icon: Icons.library_add_outlined,
                label: '导入中心',
                subtitle: 'TVBox 远程配置与 jar 直导入，分组共存',
                onTap: () => onTool(AppDrawerTool.importCenter),
              ),
              _toolTile(
                context: context,
                icon: Icons.code_rounded,
                label: '蜘蛛规则编辑器',
                subtitle: '编辑、校验与本地试跑 XBPQ 规则',
                onTap: () => onTool(AppDrawerTool.ruleEditor),
              ),
              _toolTile(
                context: context,
                icon: Icons.settings_outlined,
                label: '设置',
                subtitle: '外观、备份与全部设置项',
                onTap: () => onTool(AppDrawerTool.settings),
              ),
              _toolTile(
                context: context,
                icon: Icons.system_update_rounded,
                label: '软件更新',
                subtitle: versionText,
                onTap: () => onTool(AppDrawerTool.appUpdate),
              ),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.shield_rounded),
            title: const Text('未成年保护'),
            subtitle: const Text('点按后隐藏午夜区'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onMinorProtectionChanged(true),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Center(child: Text('© 2026 红蚁TV')),
          ),
        ],
      ),
    );
  }
}
