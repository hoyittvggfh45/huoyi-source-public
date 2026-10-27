import 'package:flutter/material.dart';

import 'app_build.dart';

enum HomeZone { drama, vod, midnight, live, novel, comic }

enum AppDrawerTool {
  sources,
  settings,
  player,
  builtinSites,
  appUpdate,
  importCenter,
  contentSources,
  parse,
  clearance,
  proxyKernel,
  lanSync,
  ruleEditor,
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.zone,
    required this.midnightActivated,
    required this.currentVersion,
    required this.onZoneSelected,
    required this.onMiniApp,
    required this.onHikerMiniApp,
    required this.onWatchRoom,
    required this.onTool,
    required this.onMinorProtectionChanged,
    required this.onVersionDoubleTap,
  });

  final HomeZone zone;
  final bool midnightActivated;
  final String currentVersion;
  final ValueChanged<HomeZone> onZoneSelected;
  final VoidCallback onMiniApp;
  final VoidCallback onHikerMiniApp;
  final VoidCallback onWatchRoom;
  final ValueChanged<AppDrawerTool> onTool;
  final ValueChanged<bool> onMinorProtectionChanged;
  final VoidCallback onVersionDoubleTap;

  Widget _sectionLabel(BuildContext context, String label) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _moduleTile({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: onTap,
    );
  }

  Widget _toolTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? subtitle,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  Widget _group({required String title, required List<Widget> children}) {
    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      initiallyExpanded: true,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final versionSubtitle = currentVersion.isEmpty
        ? null
        : Text('当前版本 $currentVersion');
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: colors.primaryContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  appName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (versionSubtitle != null) ...[
                  const SizedBox(height: 4),
                  versionSubtitle,
                ],
              ],
            ),
          ),
          _group(
            title: '影视区',
            children: [
              _moduleTile(
                icon: Icons.movie_rounded,
                label: '短剧',
                selected: zone == HomeZone.drama,
                onTap: () => onZoneSelected(HomeZone.drama),
              ),
              _moduleTile(
                icon: Icons.movie_filter_rounded,
                label: '点播',
                selected: zone == HomeZone.vod,
                onTap: () => onZoneSelected(HomeZone.vod),
              ),
              if (midnightActivated)
                _moduleTile(
                  icon: Icons.nightlight_rounded,
                  label: '午夜区',
                  selected: zone == HomeZone.midnight,
                  onTap: () => onZoneSelected(HomeZone.midnight),
                ),
              _moduleTile(
                icon: Icons.live_tv_rounded,
                label: '直播',
                selected: zone == HomeZone.live,
                onTap: () => onZoneSelected(HomeZone.live),
              ),
              _moduleTile(
                icon: Icons.meeting_room_rounded,
                label: '一起看房间',
                selected: false,
                onTap: onWatchRoom,
              ),
            ],
          ),
          _group(
            title: '阅读',
            children: [
              _moduleTile(
                icon: Icons.menu_book_rounded,
                label: '小说',
                selected: zone == HomeZone.novel,
                onTap: () => onZoneSelected(HomeZone.novel),
              ),
              _moduleTile(
                icon: Icons.image_rounded,
                label: '漫画',
                selected: zone == HomeZone.comic,
                onTap: () => onZoneSelected(HomeZone.comic),
              ),
            ],
          ),
          _group(
            title: '小程序',
            children: [
              _moduleTile(
                icon: Icons.apps_rounded,
                label: '蚂蚁',
                selected: false,
                onTap: onMiniApp,
              ),
              _moduleTile(
                icon: Icons.web_asset_rounded,
                label: '海阔',
                selected: false,
                onTap: onHikerMiniApp,
              ),
            ],
          ),
          const Divider(),
          _toolTile(
            icon: Icons.list_rounded,
            label: '站源管理',
            onTap: () => onTool(AppDrawerTool.sources),
          ),
          _toolTile(
            icon: Icons.dns_rounded,
            label: '内容源管理',
            onTap: () => onTool(AppDrawerTool.contentSources),
          ),
          _toolTile(
            icon: Icons.settings_outlined,
            label: '设置',
            onTap: () => onTool(AppDrawerTool.settings),
          ),
          const Divider(),
          _sectionLabel(context, '工具'),
          _toolTile(
            icon: Icons.play_circle_rounded,
            label: '播放器选择',
            onTap: () => onTool(AppDrawerTool.player),
          ),
          _toolTile(
            icon: Icons.web_asset_rounded,
            label: '内置站管理',
            onTap: () => onTool(AppDrawerTool.builtinSites),
          ),
          InkWell(
            onTap: () => onTool(AppDrawerTool.appUpdate),
            onDoubleTap: onVersionDoubleTap,
            child: ListTile(
              leading: const Icon(Icons.system_update_rounded),
              title: const Text('软件更新'),
              subtitle: versionSubtitle,
            ),
          ),
          _toolTile(
            icon: Icons.download_rounded,
            label: '导入中心',
            onTap: () => onTool(AppDrawerTool.importCenter),
          ),
          _toolTile(
            icon: Icons.link_rounded,
            label: '解析接口',
            onTap: () => onTool(AppDrawerTool.parse),
          ),
          _toolTile(
            icon: Icons.verified_user_rounded,
            label: '站点验证',
            onTap: () => onTool(AppDrawerTool.clearance),
          ),
          _toolTile(
            icon: Icons.vpn_key_rounded,
            label: '代理内核',
            onTap: () => onTool(AppDrawerTool.proxyKernel),
          ),
          _toolTile(
            icon: Icons.devices_rounded,
            label: '设备互联',
            onTap: () => onTool(AppDrawerTool.lanSync),
          ),
          _toolTile(
            icon: Icons.code_rounded,
            label: '蜘蛛规则编辑器',
            onTap: () => onTool(AppDrawerTool.ruleEditor),
          ),
          if (midnightActivated)
            SwitchListTile(
              secondary: const Icon(Icons.shield_rounded),
              title: const Text('未成年保护'),
              subtitle: const Text('开启后隐藏午夜区'),
              value: false,
              onChanged: (value) {
                if (value) onMinorProtectionChanged(true);
              },
            ),
        ],
      ),
    );
  }
}
