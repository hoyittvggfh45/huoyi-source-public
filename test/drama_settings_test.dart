import 'package:duanju_app/drama_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drama style sections follow the short-drama reference grouping', () {
    final sections = dramaStyleSettingsSections();
    final titles = [for (final section in sections) section.title];
    expect(titles, ['短剧区', '资源', '播放', '下载', '同步', '数据', '更多']);
    final all = sections.expand((section) => section.entries).toList();
    expect(
      all.where((entry) => entry.available).map((entry) => entry.target),
      containsAll([
        DramaSettingsTarget.style,
        DramaSettingsTarget.account,
        DramaSettingsTarget.resource,
        DramaSettingsTarget.sources,
        DramaSettingsTarget.playback,
        DramaSettingsTarget.playerChoice,
        DramaSettingsTarget.downloadPrefs,
        DramaSettingsTarget.downloads,
        DramaSettingsTarget.storage,
        DramaSettingsTarget.lanSync,
        DramaSettingsTarget.follow,
        DramaSettingsTarget.history,
      ]),
    );
    for (final target in [
      DramaSettingsTarget.coverCache,
      DramaSettingsTarget.watchStats,
      DramaSettingsTarget.reservation,
      DramaSettingsTarget.tvSettings,
      DramaSettingsTarget.videoEnhancement,
    ]) {
      final entry = all.firstWhere((entry) => entry.target == target);
      expect(entry.available, isFalse);
    }
    final first = sections.first;
    expect(first.entries.first.target, DramaSettingsTarget.style);
    expect(first.entries[1].target, DramaSettingsTarget.account);
  });

  test('ant style sections differ from drama style sections', () {
    final ant = antStyleSectionTitles();
    final drama = [
      for (final section in dramaStyleSettingsSections()) section.title,
    ];
    expect(ant, ['通用', '内容', '下载', '管理', '备份']);
    expect(ant.toSet().intersection(drama.toSet()), {'下载'});
    expect(drama, isNot(equals(ant)));
  });

  test('fullscreen feed settings stay playback-only', () {
    final entries = fullscreenFeedSettingsEntries();
    expect(
      [for (final entry in entries) entry.target],
      [
        FeedSettingsTarget.playerChoice,
        FeedSettingsTarget.speed,
        FeedSettingsTarget.danmaku,
        FeedSettingsTarget.autoAdvance,
        FeedSettingsTarget.enhancement,
      ],
    );
    for (final entry in entries) {
      expect(entry.title, isNotEmpty);
      expect(entry.title, isNot(contains('搜索红果')));
    }
  });

  test('drama settings titles use own copy', () {
    final titles = dramaStyleSettingsSections()
        .expand((section) => section.entries)
        .map((entry) => entry.title)
        .toList();
    for (final title in titles) {
      expect(title, isNot(contains('MiniReel')));
      expect(title, isNot(contains('短剧之家')));
    }
  });
}
