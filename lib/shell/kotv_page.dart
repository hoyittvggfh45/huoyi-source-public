import 'package:flutter/material.dart';

import '../app_drawer.dart';

enum KotvPageKind {
  drama,
  vod,
  midnight,
  live,
  novel,
  comic,
  audio,
  driveLibrary,
  watchRoom,
  settings,
  sources,
  downloads,
}

class KotvPage {
  const KotvPage(this.kind);

  static const drama = KotvPage(KotvPageKind.drama);
  static const vod = KotvPage(KotvPageKind.vod);
  static const midnight = KotvPage(KotvPageKind.midnight);
  static const live = KotvPage(KotvPageKind.live);
  static const novel = KotvPage(KotvPageKind.novel);
  static const comic = KotvPage(KotvPageKind.comic);
  static const audio = KotvPage(KotvPageKind.audio);
  static const settings = KotvPage(KotvPageKind.settings);

  final KotvPageKind kind;

  String get label => switch (kind) {
    KotvPageKind.drama => '短剧',
    KotvPageKind.vod => '点播',
    KotvPageKind.midnight => '午夜区',
    KotvPageKind.live => '直播',
    KotvPageKind.novel => '小说',
    KotvPageKind.comic => '漫画',
    KotvPageKind.audio => '听书',
    KotvPageKind.driveLibrary => '网盘',
    KotvPageKind.watchRoom => '一起看',
    KotvPageKind.settings => '设置',
    KotvPageKind.sources => '站源',
    KotvPageKind.downloads => '下载',
  };

  IconData get icon => switch (kind) {
    KotvPageKind.drama => Icons.movie_rounded,
    KotvPageKind.vod => Icons.movie_filter_rounded,
    KotvPageKind.midnight => Icons.nightlight_rounded,
    KotvPageKind.live => Icons.live_tv_rounded,
    KotvPageKind.novel => Icons.menu_book_rounded,
    KotvPageKind.comic => Icons.image_rounded,
    KotvPageKind.audio => Icons.headphones_rounded,
    KotvPageKind.driveLibrary => Icons.cloud_rounded,
    KotvPageKind.watchRoom => Icons.home_rounded,
    KotvPageKind.settings => Icons.settings_outlined,
    KotvPageKind.sources => Icons.list_rounded,
    KotvPageKind.downloads => Icons.download_rounded,
  };

  IconData get selectedIcon => switch (kind) {
    KotvPageKind.drama => Icons.movie,
    KotvPageKind.vod => Icons.movie_filter,
    KotvPageKind.midnight => Icons.nightlight,
    KotvPageKind.live => Icons.live_tv,
    KotvPageKind.novel => Icons.menu_book,
    KotvPageKind.comic => Icons.image,
    KotvPageKind.audio => Icons.headphones,
    KotvPageKind.driveLibrary => Icons.cloud,
    KotvPageKind.watchRoom => Icons.home,
    KotvPageKind.settings => Icons.settings,
    KotvPageKind.sources => Icons.list,
    KotvPageKind.downloads => Icons.download,
  };

  bool get requiresMidnightActivation => kind == KotvPageKind.midnight;

  HomeZone? get zone => switch (kind) {
    KotvPageKind.drama => HomeZone.drama,
    KotvPageKind.vod => HomeZone.vod,
    KotvPageKind.midnight => HomeZone.midnight,
    KotvPageKind.live => HomeZone.live,
    KotvPageKind.novel => HomeZone.novel,
    KotvPageKind.comic => HomeZone.comic,
    KotvPageKind.audio => HomeZone.audio,
    KotvPageKind.driveLibrary => null,
    KotvPageKind.watchRoom => null,
    KotvPageKind.settings => null,
    KotvPageKind.sources => null,
    KotvPageKind.downloads => null,
  };

  @override
  bool operator ==(Object other) =>
      other is KotvPage && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}
