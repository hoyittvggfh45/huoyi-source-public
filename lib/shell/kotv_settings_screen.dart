import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../account_screen.dart';
import '../app_build.dart';
import '../app_page_route.dart';
import '../app_theme.dart';
import '../app_update.dart';
import '../app_update_screen.dart';
import '../background_downloads.dart';
import '../builtin_sites_screen.dart';
import '../clearance_bridge.dart';
import '../content_source_screen.dart';
import '../core_bridge.dart';
import '../crack_config_section.dart';
import '../detail_screen.dart';
import '../downloads_screen.dart';
import '../drive_library_screen.dart';
import '../hongguo_account.dart';
import '../import_center_screen.dart';
import '../lan_screen.dart';
import '../gate_config.dart';
import '../gate_console_screen.dart';
import '../gate_guard.dart';
import '../local_store.dart';
import '../midnight_zone.dart';
import '../my_page_screen.dart';
import '../miniapp/plugin_center_screen.dart';
import '../models.dart';
import '../parse_settings_screen.dart';
import '../playback_launch_screen.dart';
import '../playback_parse.dart';
import '../playback_preferences.dart';
import '../player_core.dart';
import '../profiles_screen.dart';
import '../proxy_kernel_screen.dart';
import '../resource_settings_screen.dart';
import '../rfw_theme/rfw_theme_store.dart';
import '../rule_editor_screen.dart';
import '../saved_library.dart';
import '../settings_screen.dart';
import '../sources_screen.dart';
import '../splash_selection.dart';
import '../splash_sets.dart';
import '../splash_settings_screen.dart';
import '../ui_style.dart';
import '../video_enhancement_preferences.dart';
import '../webdav_screen.dart';
import '../widgets.dart';
import 'kotv_add_source_dialog.dart';
import 'kotv_backup_dialogs.dart';
import 'kotv_clear_cache_dialog.dart';
import 'kotv_downloads_page.dart';
import 'kotv_option_dialogs.dart';
import 'kotv_playback_settings_screen.dart';
import 'kotv_player_settings_sheet.dart';
import 'kotv_runtime_info_dialog.dart';
import 'kotv_send_to_device_dialog.dart';
import 'kotv_spider_check_dialog.dart';
import 'kotv_theme.dart';
import 'kotv_update_address_dialog.dart';
import 'kotv_user_admin_screen.dart';

class KotvSettingsScreen extends StatelessWidget {
  const KotvSettingsScreen({
    super.key,
    required this.repository,
    required this.store,
    this.onHideMidnight,
  });

  final AppRepository repository;
  final LocalStore store;
  final VoidCallback? onHideMidnight;

  Future<void> _push(BuildContext context, Widget page) =>
      Navigator.push(context, appPageRoute<void>(builder: (_) => page));

  Future<void> _pushCrackConfig(BuildContext context) => _push(
    context,
    Scaffold(
      appBar: AppBar(title: const Text('过盾与 VIP 配置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: CrackConfigSection(repository: repository),
      ),
    ),
  );

  void _openSavedDrama(BuildContext context, Drama drama) {
    unawaited(
      openPlaybackDirectly(
        context,
        drama: drama,
        repository: repository,
        store: store,
      ),
    );
  }

  void _openSavedDownload(BuildContext context, Drama drama) {
    _push(
      context,
      DetailScreen(
        drama: drama,
        repository: repository,
        store: store,
        downloadOnOpen: true,
      ),
    );
  }

  void _openSavedLibrary(BuildContext context, {required bool history}) {
    _push(
      context,
      Scaffold(
        appBar: AppBar(title: Text(history ? '最近观看' : '追剧')),
        body: SavedLibrary(
          repository: repository,
          store: store,
          history: history,
          onOpen: (drama) => _openSavedDrama(context, drama),
          onContinue: (drama) => _openSavedDrama(context, drama),
          onDownload: repository.supportsDownloads && store.canDownload
              ? (drama) => _openSavedDownload(context, drama)
              : null,
        ),
      ),
    );
  }

  Future<String> _appUpdateSummary() async {
    try {
      final current = await AppUpdateChecker.currentVersion();
      final latest = await AppUpdateChecker.cachedLatestVersion();
      return latest.isEmpty
          ? '当前版本 $current'
          : '当前版本 $current · 最新 $latest';
    } catch (_) {
      return '检查整包新版本';
    }
  }

  Future<String> _splashName() async {
    try {
      final selection = await loadSplashSelection();
      return splashSelectionDisplayName(selection);
    } catch (_) {
      return '默认启动图';
    }
  }

  Future<void> _chooseTheme(BuildContext context) async {
    final selected = await showKotvOptionDialog<String>(
      context: context,
      title: '外观主题',
      current: store.themeMode,
      options: const ['light', 'dark', 'system'],
      label: (mode) => AppTheme.label(mode),
    );
    if (selected != null && context.mounted) {
      await saveUserChange(context, () => store.setThemeMode(selected));
    }
  }

  Future<void> _chooseDisplayMode(BuildContext context) async {
    final selected = await showKotvOptionDialog<String>(
      context: context,
      title: '界面模式',
      current: store.displayMode,
      options: const ['auto', 'television', 'standard'],
      label: (mode) => switch (mode) {
        'television' => '电视 / 遥控器',
        'standard' => '手机 / 电脑',
        _ => '自动识别设备',
      },
    );
    if (selected != null && context.mounted) {
      await saveUserChange(context, () => store.setDisplayMode(selected));
    }
  }

  Future<void> _choosePlaybackOption<T>(
    BuildContext context,
    String title,
    List<T> options,
    T selected,
    String Function(T) label,
    PlaybackPreferences Function(PlaybackPreferences current, T chosen) update,
  ) async {
    final chosen = await showKotvOptionDialog<T>(
      context: context,
      title: title,
      current: selected,
      options: options,
      label: label,
    );
    if (chosen != null && context.mounted) {
      await saveUserChange(
        context,
        () => store.setPlaybackPreferences(
          update(store.playbackPreferences, chosen),
        ),
      );
    }
  }

  Widget _playbackSwitch(
    BuildContext context,
    String title,
    bool value,
    PlaybackPreferences Function(PlaybackPreferences current, bool changed)
    update,
  ) => KotvSettingsRow(
    title: title,
    trailing: Switch.adaptive(
      value: value,
      onChanged: store.locked
          ? null
          : (changed) => saveUserChange(
              context,
              () => store.setPlaybackPreferences(
                update(store.playbackPreferences, changed),
              ),
            ),
    ),
  );

  Future<void> _exportBackup(BuildContext context) async {
    try {
      final content = await store.exportBackup();
      final saved = await FilePicker.saveFile(
        fileName:
            '$appSlug-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: 'application/json',
      );
      if (saved != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备份已保存')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null || !context.mounted) return;
      final size = await file.length();
      if (size == null || size > 8 * 1024 * 1024) {
        throw const FormatException('备份文件过大或无法读取');
      }
      final content = utf8.decode(await file.readAsBytes());
      final data = store.validateBackup(content);
      if (!context.mounted) return;
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
      if (accepted != true || !context.mounted) return;
      await store.importBackup(content);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备份已恢复')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  String _decoderLabel(TelevisionDecoder decoder) => switch (decoder) {
    TelevisionDecoder.optimized => '自动优化',
    TelevisionDecoder.hardware => '硬件解码',
    TelevisionDecoder.software => '软件解码',
  };

  Future<void> _chooseAspectRatio(BuildContext context) async {
    await showKotvAspectRatioDialog(
      context: context,
      current: KotvAspectRatio.fit,
    );
  }

  Future<String> _defaultParserName() async {
    try {
      final selected = await ParseInterfaceStore.loadSelected();
      return selected?.name ?? '不使用解析';
    } catch (_) {
      return '不使用解析';
    }
  }

  Future<void> _chooseDefaultParser(BuildContext context) async {
    final interfaces = await ParseInterfaceStore.loadEnabled();
    if (!context.mounted) return;
    final selectedId = await ParseInterfaceStore.loadSelectedId();
    if (!context.mounted) return;
    final chosen = await showKotvDefaultParserDialog(
      context: context,
      interfaces: interfaces,
      selectedId: selectedId,
    );
    if (chosen != null && context.mounted) {
      await saveUserChange(
        context,
        () => store.setDefaultParserId(chosen),
      );
    }
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final preferences = store.playbackPreferences;
      final admin = store.profile.admin;
      final canDownload = store.canDownload;
      return KotvPastelBackground(
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
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
                  onTap: () => _push(
                    context,
                    MyPageScreen(repository: repository, store: store),
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
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: KotvTokens.unselectedColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            KotvGroupCard(
              title: '界面壳',
              children: [
                KotvSettingsRow(
                  title: '使用新壳',
                  trailing: Switch.adaptive(
                    value: store.useNewShell,
                    onChanged: (changed) async {
                      await saveUserChange(
                        context,
                        () => store.setUseNewShell(changed),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('重启 App 后生效')),
                        );
                      }
                    },
                  ),
                ),
                const KotvSettingsRow(
                  title: '切换说明',
                  value: '关闭后回到旧壳，重启 App 后生效',
                ),
                if (gateConsoleVisible)
                  KotvSettingsRow(
                    title: '鉴权控制台',
                    value: '功能、区域与模块开关管理',
                    onTap: () => _push(context, const GateConsoleScreen()),
                  ),
              ],
            ),
            KotvGroupCard(
              title: '数据源',
              children: [
                KotvSettingsRow(
                  title: '内容源管理',
                  value: 'TVBox 远程配置与 py 互斥切换',
                  onTap: () => _push(
                    context,
                    ContentSourceScreen(repository: repository, store: store),
                  ),
                ),
                if (repository.supportsSourceManagement)
                  KotvSettingsRow(
                    title: '站源管理',
                    value: '独立更新、连接与播放检测',
                    onTap: () => _push(
                      context,
                      SourcesScreen(repository: repository, store: store),
                    ),
                  ),
                KotvSettingsRow(
                  title: '内置站管理',
                  value: '内置站逐站显示/隐藏，可恢复默认',
                  onTap: () => _push(
                    context,
                    BuiltinSitesScreen(store: store, repository: repository),
                  ),
                ),
                KotvSettingsRow(
                  title: '导入中心',
                  value: 'TVBox 远程配置与 jar 直导入，分组共存',
                  onTap: () => _push(
                    context,
                    ImportCenterScreen(repository: repository, store: store),
                  ),
                ),
                KotvSettingsRow(
                  title: '蜘蛛规则编辑器',
                  value: '编辑、校验与本地试跑 XBPQ 规则',
                  onTap: () =>
                      _push(context, RuleEditorScreen(repository: repository)),
                ),
                KotvSettingsRow(
                  title: '站点验证',
                  value: '为被拦截的站点完成浏览器验证',
                  onTap: () => openClearanceFlow(context, repository),
                ),
                KotvSettingsRow(
                  title: '过盾与 VIP 配置',
                  value: '导入导出各站过盾与 VIP 配置',
                  onTap: () => _pushCrackConfig(context),
                ),
                if (admin)
                  KotvSettingsRow(
                    title: '网络与资源',
                    value: '代理、目录请求间隔、下载并发与站源目录',
                    onTap: () => _push(
                      context,
                      ResourceSettingsScreen(
                        repository: repository,
                        store: store,
                      ),
                    ),
                  ),
                GateGuard(
                  feature: GateFeature.proxyKernel,
                  child: KotvSettingsRow(
                    title: '代理内核',
                    value: 'mihomo 本地代理：内置核、更新内核、订阅、选节点、测速、自启',
                    onTap: () => _push(
                      context,
                      ProxyKernelScreen(repository: repository),
                    ),
                  ),
                ),
                KotvSettingsRow(
                  title: '添加点播源',
                  value: '单线路、多仓索引、本地路径与 JSON 导入',
                  onTap: () => showKotvAddSourceDialog(
                    context: context,
                    repository: repository,
                    store: store,
                  ),
                ),
                KotvSettingsRow(
                  title: '检测爬虫',
                  value: '逐站检测蜘蛛可用性',
                  onTap: () => showKotvSpiderCheckDialog(
                    context: context,
                    repository: repository,
                    store: store,
                  ),
                ),
              ],
            ),
            KotvGroupCard(
              title: '播放器',
              children: [
                KotvSettingsRow(
                  title: '播放设置',
                  value:
                      '${PlayerCoreStorage.read(store.preferences).label} · ${speedLabel(preferences.speed)}x',
                  onTap: () => _push(
                    context,
                    KotvPlaybackSettingsScreen(store: store),
                  ),
                ),
                KotvSettingsRow(
                  title: '解析接口',
                  value: '播放解析接口列表与默认选中',
                  onTap: () => _push(context, const ParseSettingsScreen()),
                ),
                KotvSettingsRow(
                  title: '滑动快进秒数',
                  value: '${preferences.swipeSeekSeconds} 秒',
                  onTap: () => _choosePlaybackOption<int>(
                    context,
                    '滑动快进秒数',
                    swipeSeekChoices,
                    preferences.swipeSeekSeconds,
                    (seconds) => '$seconds 秒',
                    (current, chosen) =>
                        current.copyWith(swipeSeekSeconds: chosen),
                  ),
                ),
                KotvSettingsRow(
                  title: '清晰度偏好',
                  value: preferences.quality == 0
                      ? '自动 · 优先高清'
                      : '${preferences.quality}P',
                  onTap: () => _choosePlaybackOption<int>(
                    context,
                    '清晰度偏好',
                    const [0, 1080, 720, 480],
                    preferences.quality,
                    (quality) => quality == 0 ? '自动 · 优先高清' : '${quality}P',
                    (current, chosen) => current.copyWith(quality: chosen),
                  ),
                ),
                GateGuard(
                  feature: GateFeature.danmaku,
                  child: _playbackSwitch(
                    context,
                    '显示弹幕',
                    preferences.danmaku,
                    (current, changed) => current.copyWith(danmaku: changed),
                  ),
                ),
                _playbackSwitch(
                  context,
                  '去广告',
                  preferences.adBlock,
                  (current, changed) => current.copyWith(adBlock: changed),
                ),
                _playbackSwitch(
                  context,
                  '回到桌面自动小窗',
                  preferences.autoPictureInPicture,
                  (current, changed) =>
                      current.copyWith(autoPictureInPicture: changed),
                ),
                KotvSettingsRow(
                  title: '视频增强模式',
                  value: preferences.enhancement.mode.label,
                  onTap: () => _choosePlaybackOption<VideoEnhancementMode>(
                    context,
                    '视频增强模式',
                    VideoEnhancementMode.values,
                    preferences.enhancement.mode,
                    (mode) => mode.label,
                    (current, chosen) => current.copyWith(
                      enhancement: current.enhancement.copyWith(mode: chosen),
                    ),
                  ),
                ),
                KotvSettingsRow(
                  title: '视频增强内容',
                  value: preferences.enhancement.content.label,
                  onTap: () => _choosePlaybackOption<VideoEnhancementContent>(
                    context,
                    '视频增强内容',
                    VideoEnhancementContent.values,
                    preferences.enhancement.content,
                    (content) => content.label,
                    (current, chosen) => current.copyWith(
                      enhancement: current.enhancement.copyWith(
                        content: chosen,
                      ),
                    ),
                  ),
                ),
                KotvSettingsRow(
                  title: '电视解码',
                  value: _decoderLabel(preferences.televisionDecoder),
                  onTap: () => _choosePlaybackOption<TelevisionDecoder>(
                    context,
                    '电视解码',
                    TelevisionDecoder.values,
                    preferences.televisionDecoder,
                    (decoder) => _decoderLabel(decoder),
                    (current, chosen) =>
                        current.copyWith(televisionDecoder: chosen),
                  ),
                ),
                KotvSettingsRow(
                  title: '播放方向',
                  value: preferences.orientationMode.label,
                  onTap: () => _choosePlaybackOption<PlaybackOrientationMode>(
                    context,
                    '播放方向',
                    PlaybackOrientationMode.values,
                    preferences.orientationMode,
                    (mode) => mode.label,
                    (current, chosen) =>
                        current.copyWith(orientationMode: chosen),
                  ),
                ),
                KotvSettingsRow(
                  title: '播放器设置',
                  value: '画质、弹幕、解码与增强',
                  onTap: () => showKotvPlayerSettingsSheet(
                    context,
                    store: store,
                  ),
                ),
                KotvSettingsRow(
                  title: '画面比例',
                  value: '适应',
                  onTap: () => _chooseAspectRatio(context),
                ),
                FutureBuilder<String>(
                  future: _defaultParserName(),
                  builder: (context, snapshot) => KotvSettingsRow(
                    title: '默认解析器',
                    value: snapshot.data ?? '不使用解析',
                    onTap: () => _chooseDefaultParser(context),
                  ),
                ),
              ],
            ),
            KotvGroupCard(
              title: '功能',
              children: [
                ValueListenableBuilder<DramaUiStyle>(
                  valueListenable: dramaUiStyleNotifier,
                  builder: (context, style, _) => KotvSettingsRow(
                    title: '短剧区风格',
                    value: style.label,
                    onTap: () => chooseDramaUiStyle(context),
                  ),
                ),
                KotvSettingsRow(
                  title: '追剧',
                  value: '跟进中的短剧',
                  onTap: () => _openSavedLibrary(context, history: false),
                ),
                KotvSettingsRow(
                  title: '最近观看',
                  value: '观看历史',
                  onTap: () => _openSavedLibrary(context, history: true),
                ),
                if (canDownload)
                  GateGuard(
                    feature: GateFeature.download,
                    child: KotvSettingsRow(
                      title: '下载',
                      value: '查看与管理已下载内容',
                      onTap: () => _push(
                        context,
                        DownloadsScreen(repository: repository, store: store),
                      ),
                    ),
                  ),
                if (canDownload)
                  GateGuard(
                    feature: GateFeature.download,
                    child: KotvSettingsRow(
                      title: '下载偏好',
                      value: store.downloadPreferences.qualityLabel,
                      onTap: () => _push(
                        context,
                        DownloadPreferencesScreen(store: store),
                      ),
                    ),
                  ),
                if (canDownload)
                  GateGuard(
                    feature: GateFeature.download,
                    child: KotvSettingsRow(
                      title: '下载目录与空间',
                      value: '查看存储用量、迁移已下载文件',
                      onTap: () => _push(
                        context,
                        StorageScreen(repository: repository, store: store),
                      ),
                    ),
                  ),
                KotvSettingsRow(
                  title: '插件中心',
                  value: '市场安装与本地插件',
                  onTap: () => _push(
                    context,
                    PluginCenterScreen(store: store, repository: repository),
                  ),
                ),
                if (admin)
                  KotvSettingsRow(
                    title: '下载完成后自动导出 Emby',
                    trailing: Switch.adaptive(
                      value: store.autoExport,
                      onChanged: (changed) async {
                        try {
                          if (changed) {
                            await BackgroundDownloads.ensureStarted();
                          }
                          await store.setAutoExport(changed);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );
                          }
                        }
                      },
                    ),
                  ),
                if (admin)
                  KotvSettingsRow(
                    title: '同时导出海报文件',
                    trailing: Switch.adaptive(
                      value: store.exportPosters,
                      onChanged: (changed) => saveUserChange(
                        context,
                        () => store.setExportPosters(changed),
                      ),
                    ),
                  ),
                GateGuard(
                  feature: GateFeature.download,
                  child: KotvSettingsRow(
                    title: '下载页',
                    value: '查看下载中、排队中与已完成任务',
                    onTap: () => _push(
                      context,
                      KotvDownloadsPage(repository: repository, store: store),
                    ),
                  ),
                ),
                KotvSettingsRow(
                  title: '媒体库',
                  value: '本地文件与网盘浏览',
                  onTap: () => _push(context, const DriveLibraryScreen()),
                ),
                KotvSettingsRow(
                  title: '用户管理',
                  value: '管理本机用户与远端鉴权',
                  onTap: () => _push(
                    context,
                    KotvUserAdminScreen(store: store),
                  ),
                ),
              ],
            ),
            KotvGroupCard(
              title: '界面',
              children: [
                KotvSettingsRow(
                  title: '外观主题',
                  value: AppTheme.label(store.themeMode),
                  onTap: () => _chooseTheme(context),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: rfwThemeModeNotifier,
                  builder: (context, enabled, _) => KotvSettingsRow(
                    title: 'RFW 主题模式',
                    trailing: Switch.adaptive(
                      value: enabled,
                      onChanged: (changed) => saveRfwThemeMode(changed),
                    ),
                  ),
                ),
                KotvSettingsRow(
                  title: '界面模式',
                  value: switch (store.displayMode) {
                    'television' => '电视 / 遥控器',
                    'standard' => '手机 / 电脑',
                    _ => '自动识别设备',
                  },
                  onTap: () => _chooseDisplayMode(context),
                ),
                FutureBuilder<String>(
                  future: _splashName(),
                  builder: (context, snapshot) => KotvSettingsRow(
                    title: '开机启动图',
                    value: snapshot.data ?? '默认启动图',
                    onTap: () => _push(context, const SplashSettingsScreen()),
                  ),
                ),
                KotvSettingsRow(
                  title: '隐藏 VIP 内容',
                  trailing: Switch.adaptive(
                    value: store.hideVip,
                    onChanged: (changed) => saveUserChange(
                      context,
                      () => store.setHideVip(changed),
                    ),
                  ),
                ),
              ],
            ),
            KotvGroupCard(
              title: '隐私与同步',
              children: [
                SwitchListTile(
                  title: const Text('未成年保护'),
                  subtitle: const Text('开启后隐藏午夜区并回到短剧区'),
                  value: false,
                  onChanged: onHideMidnight == null
                      ? null
                      : (changed) {
                          if (changed) onHideMidnight!();
                        },
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
                          onHideMidnight?.call();
                        } else {
                          _activateMidnight(context);
                        }
                      },
                    );
                  },
                ),
                ValueListenableBuilder<HongguoAccount?>(
                  valueListenable: hongguoAccountNotifier,
                  builder: (context, account, _) => KotvSettingsRow(
                    title: '账号',
                    value: account != null && account.loggedIn
                        ? account.displayName
                        : '未登录',
                    onTap: () => _push(context, const AccountScreen()),
                  ),
                ),
                KotvSettingsRow(
                  title: '用户管理',
                  value: '当前：${store.profile.name}',
                  onTap: () => _push(context, ProfilesScreen(store: store)),
                ),
                KotvSettingsRow(
                  title: '设备互联',
                  value: '局域网自动同步追剧与推送播放',
                  onTap: () => openLanSync(context),
                ),
                if (admin)
                  KotvSettingsRow(
                    title: 'WebDAV 同步',
                    value: '把配置备份存到自填的 WebDAV 地址',
                    onTap: () => _push(context, WebdavScreen(store: store)),
                  ),
                if (admin)
                  KotvSettingsRow(
                    title: '导出配置备份',
                    value: '包含本地用户、追剧、历史和设置，不含视频文件',
                    onTap: () => _exportBackup(context),
                  ),
                if (admin)
                  KotvSettingsRow(
                    title: '恢复配置备份',
                    value: '从备份文件恢复用户与设置',
                    onTap: () => _importBackup(context),
                  ),
                KotvSettingsRow(
                  title: '发送到设备',
                  value: '局域网同步追剧与观看进度',
                  onTap: () =>
                      showKotvSendToDeviceDialog(context: context),
                ),
              ],
            ),
            KotvGroupCard(
              title: '更多',
              children: [
                KotvSettingsRow(
                  title: '通用设置',
                  value: '外观、备份与全部设置项',
                  onTap: () => _push(
                    context,
                    SettingsScreen(repository: repository, store: store),
                  ),
                ),
                FutureBuilder<String>(
                  future: _appUpdateSummary(),
                  builder: (context, snapshot) => KotvSettingsRow(
                    title: '软件更新',
                    value: snapshot.data ?? '检查整包新版本',
                    onTap: () => _push(context, const AppUpdateScreen()),
                  ),
                ),
                KotvSettingsRow(
                  title: '更新地址',
                  value: '查看既有更新地址，确定后打开软件更新屏',
                  onTap: () =>
                      showKotvUpdateAddressDialog(context: context),
                ),
                KotvSettingsRow(
                  title: '数据备份',
                  value: '导出本机用户、追剧与设置',
                  onTap: () => showKotvBackupExportDialog(
                    context: context,
                    store: store,
                  ),
                ),
                KotvSettingsRow(
                  title: '恢复备份',
                  value: '从备份文件恢复用户与设置',
                  onTap: () => showKotvBackupFileDialog(
                    context: context,
                    store: store,
                  ),
                ),
                KotvSettingsRow(
                  title: '清理缓存',
                  value: '仅清理已完成下载任务，其余项暂无后端',
                  onTap: () => showKotvClearCacheDialog(
                    context: context,
                    repository: repository,
                  ),
                ),
                KotvSettingsRow(
                  title: '运行时信息',
                  value: '应用、平台、桥与局域网状态',
                  onTap: () =>
                      showKotvRuntimeInfoDialog(context: context),
                ),
                KotvSettingsRow(
                  title: '关于$appName',
                  value: '独立运行，打开即可浏览和播放',
                  onTap: () => showKotvAboutDialog(context: context),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}
