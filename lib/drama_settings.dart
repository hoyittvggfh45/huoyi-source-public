enum DramaSettingsTarget {
  style,
  account,
  resource,
  sources,
  playback,
  playerChoice,
  videoEnhancement,
  downloadPrefs,
  downloads,
  storage,
  lanSync,
  webdavSync,
  follow,
  history,
  coverCache,
  watchStats,
  reservation,
  tvSettings,
}

class DramaSettingsEntry {
  const DramaSettingsEntry({
    required this.target,
    required this.title,
    required this.subtitle,
    required this.available,
  });

  final DramaSettingsTarget target;
  final String title;
  final String subtitle;
  final bool available;
}

class DramaSettingsSection {
  const DramaSettingsSection({required this.title, required this.entries});

  final String title;
  final List<DramaSettingsEntry> entries;

  List<DramaSettingsEntry> get availableEntries =>
      entries.where((entry) => entry.available).toList();
}

List<DramaSettingsSection> dramaStyleSettingsSections() => const [
  DramaSettingsSection(
    title: '短剧区',
    entries: [
      DramaSettingsEntry(
        target: DramaSettingsTarget.style,
        title: '短剧区风格',
        subtitle: '只影响短剧区',
        available: true,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.account,
        title: '账号',
        subtitle: '登录态与退出登录',
        available: true,
      ),
    ],
  ),
  DramaSettingsSection(
    title: '资源',
    entries: [
      DramaSettingsEntry(
        target: DramaSettingsTarget.resource,
        title: '资源设置',
        subtitle: '代理、目录请求间隔、下载并发与站源目录',
        available: true,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.sources,
        title: '来源',
        subtitle: '站源管理',
        available: true,
      ),
    ],
  ),
  DramaSettingsSection(
    title: '播放',
    entries: [
      DramaSettingsEntry(
        target: DramaSettingsTarget.playback,
        title: '播放偏好',
        subtitle: '倍速、弹幕、自动连播与画质',
        available: true,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.playerChoice,
        title: '播放器选择',
        subtitle: '切换播放器后端',
        available: true,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.videoEnhancement,
        title: '视频增强',
        subtitle: '播放器菜单内可调，独立设置屏待做',
        available: false,
      ),
    ],
  ),
  DramaSettingsSection(
    title: '下载',
    entries: [
      DramaSettingsEntry(
        target: DramaSettingsTarget.downloadPrefs,
        title: '下载偏好',
        subtitle: '下载清晰度与并发',
        available: true,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.downloads,
        title: '下载',
        subtitle: '查看与管理已下载内容',
        available: true,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.storage,
        title: '存储',
        subtitle: '下载目录与空间',
        available: true,
      ),
    ],
  ),
  DramaSettingsSection(
    title: '同步',
    entries: [
      DramaSettingsEntry(
        target: DramaSettingsTarget.lanSync,
        title: '局域网同步',
        subtitle: '设备互联',
        available: true,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.webdavSync,
        title: 'WebDAV 同步',
        subtitle: '把配置备份存到自填的 WebDAV 地址',
        available: true,
      ),
    ],
  ),
  DramaSettingsSection(
    title: '数据',
    entries: [
      DramaSettingsEntry(
        target: DramaSettingsTarget.follow,
        title: '追剧',
        subtitle: '跟进中的短剧',
        available: true,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.history,
        title: '最近观看',
        subtitle: '观看历史',
        available: true,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.watchStats,
        title: '观看统计',
        subtitle: '独立展示页待做',
        available: false,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.reservation,
        title: '预约',
        subtitle: '未上映剧集预约待做',
        available: false,
      ),
    ],
  ),
  DramaSettingsSection(
    title: '更多',
    entries: [
      DramaSettingsEntry(
        target: DramaSettingsTarget.coverCache,
        title: '封面缓存',
        subtitle: '独立设置页待做',
        available: false,
      ),
      DramaSettingsEntry(
        target: DramaSettingsTarget.tvSettings,
        title: '电视设置',
        subtitle: '电视设置分支待做',
        available: false,
      ),
    ],
  ),
];

List<String> antStyleSectionTitles() => const ['通用', '内容', '下载', '管理', '备份'];

enum FeedSettingsTarget {
  playerChoice,
  speed,
  danmaku,
  autoAdvance,
  enhancement,
}

class FeedSettingsEntry {
  const FeedSettingsEntry({required this.target, required this.title});

  final FeedSettingsTarget target;
  final String title;
}

List<FeedSettingsEntry> fullscreenFeedSettingsEntries() => const [
  FeedSettingsEntry(target: FeedSettingsTarget.playerChoice, title: '播放器'),
  FeedSettingsEntry(target: FeedSettingsTarget.speed, title: '播放倍速'),
  FeedSettingsEntry(target: FeedSettingsTarget.danmaku, title: '显示弹幕'),
  FeedSettingsEntry(target: FeedSettingsTarget.autoAdvance, title: '自动连播'),
  FeedSettingsEntry(target: FeedSettingsTarget.enhancement, title: '画质增强'),
];
