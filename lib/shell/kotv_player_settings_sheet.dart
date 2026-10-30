import 'package:flutter/material.dart';

import '../app_page_route.dart';
import '../local_store.dart';
import '../picture_quality.dart';
import '../playback_preferences.dart';
import '../video_enhancement_preferences.dart';
import '../widgets.dart';
import 'kotv_option_dialogs.dart';
import 'kotv_playback_settings_screen.dart';
import 'kotv_theme.dart';

Future<void> showKotvPlayerSettingsSheet(
  BuildContext context, {
  required LocalStore store,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.white,
  isScrollControlled: true,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(KotvTokens.cardRadius),
    ),
  ),
  builder: (_) => _KotvPlayerSettingsSheet(store: store),
);

class _KotvPlayerSettingsSheet extends StatelessWidget {
  const _KotvPlayerSettingsSheet({required this.store});

  final LocalStore store;

  Future<void> _update(
    BuildContext context,
    PlaybackPreferences Function(PlaybackPreferences current) update,
  ) => saveUserChange(
    context,
    () => store.setPlaybackPreferences(update(store.playbackPreferences)),
  );

  Widget _switch(
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
          : (changed) => _update(
              context,
              (current) => update(current, changed),
            ),
    ),
  );

  Future<void> _choose<T>(
    BuildContext context,
    String title,
    List<T> options,
    T current,
    String Function(T value) label,
    PlaybackPreferences Function(PlaybackPreferences current, T chosen) update,
  ) async {
    final chosen = await showKotvOptionDialog<T>(
      context: context,
      title: title,
      options: options,
      current: current,
      label: label,
    );
    if (chosen != null && context.mounted) {
      await _update(context, (current) => update(current, chosen));
    }
  }

  Future<void> _chooseDecoder(BuildContext context, TelevisionDecoder current) async {
    final chosen = await showKotvDecoderDialog(
      context: context,
      current: current,
    );
    if (chosen != null && context.mounted) {
      await _update(
        context,
        (preferences) => preferences.copyWith(televisionDecoder: chosen),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final preferences = store.playbackPreferences;
        final pictureQuality = preferences.pictureQuality;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '播放器设置',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                KotvGroupCard(
                  title: '缓存与缓冲',
                  children: [
                    _switch(
                      context,
                      '预加载下一集',
                      preferences.preload,
                      (current, changed) =>
                          current.copyWith(preload: changed),
                    ),
                    _switch(
                      context,
                      '去广告',
                      preferences.adBlock,
                      (current, changed) =>
                          current.copyWith(adBlock: changed),
                    ),
                  ],
                ),
                KotvGroupCard(
                  title: '画面',
                  children: [
                    KotvSettingsRow(
                      title: '清晰度偏好',
                      value: preferences.quality == 0
                          ? '自动 · 优先高清'
                          : '${preferences.quality}P',
                      onTap: () => _choose<int>(
                        context,
                        '清晰度偏好',
                        const [0, 1080, 720, 480],
                        preferences.quality,
                        (quality) => quality == 0
                            ? '自动 · 优先高清'
                            : '${quality}P',
                        (current, chosen) =>
                            current.copyWith(quality: chosen),
                      ),
                    ),
                    KotvSettingsRow(
                      title: '画质档',
                      value: pictureQuality.mode.label,
                      onTap: () => _choose<PictureQualityMode>(
                        context,
                        '画质档',
                        PictureQualityMode.values,
                        pictureQuality.mode,
                        (mode) => mode.label,
                        (current, chosen) => current.copyWith(
                          pictureQuality: current.pictureQuality.copyWith(
                            mode: chosen,
                          ),
                        ),
                      ),
                    ),
                    if (pictureQuality.mode == PictureQualityMode.sharpen)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '锐化强度',
                              style: TextStyle(fontSize: 14),
                            ),
                            Expanded(
                              child: Slider(
                                value: pictureQuality.strength.toDouble(),
                                min: 0,
                                max: 100,
                                divisions: 10,
                                label: '${pictureQuality.strength}',
                                onChanged: store.locked
                                    ? null
                                    : (next) => _update(
                                        context,
                                        (current) => current.copyWith(
                                          pictureQuality: current
                                              .pictureQuality
                                              .copyWith(
                                                strength: next.round(),
                                              ),
                                        ),
                                      ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '${pictureQuality.strength}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    KotvSettingsRow(
                      title: '视频增强模式',
                      value: preferences.enhancement.mode.label,
                      onTap: () => _choose<VideoEnhancementMode>(
                        context,
                        '视频增强模式',
                        VideoEnhancementMode.values,
                        preferences.enhancement.mode,
                        (mode) => mode.label,
                        (current, chosen) => current.copyWith(
                          enhancement: current.enhancement.copyWith(
                            mode: chosen,
                          ),
                        ),
                      ),
                    ),
                    KotvSettingsRow(
                      title: '视频增强内容',
                      value: preferences.enhancement.content.label,
                      onTap: () => _choose<VideoEnhancementContent>(
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
                    _switch(
                      context,
                      '显示弹幕',
                      preferences.danmaku,
                      (current, changed) =>
                          current.copyWith(danmaku: changed),
                    ),
                    KotvSettingsRow(
                      title: '电视解码',
                      value: kotvDecoderLabel(preferences.televisionDecoder),
                      onTap: () => _chooseDecoder(
                        context,
                        preferences.televisionDecoder,
                      ),
                    ),
                    KotvSettingsRow(
                      title: '播放方向',
                      value: preferences.orientationMode.label,
                      onTap: () => _choose<PlaybackOrientationMode>(
                        context,
                        '播放方向',
                        PlaybackOrientationMode.values,
                        preferences.orientationMode,
                        (mode) => mode.label,
                        (current, chosen) =>
                            current.copyWith(orientationMode: chosen),
                      ),
                    ),
                  ],
                ),
                KotvGroupCard(
                  title: '更多',
                  children: [
                    KotvSettingsRow(
                      title: '全部播放设置',
                      value: '自动连播、预加载、倍速、解码与后端',
                      onTap: () => Navigator.of(context).push(
                        appPageRoute<void>(
                          builder: (_) =>
                              KotvPlaybackSettingsScreen(store: store),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16 + MediaQuery.paddingOf(context).bottom),
              ],
            ),
          ),
        );
      },
    );
  }
}
