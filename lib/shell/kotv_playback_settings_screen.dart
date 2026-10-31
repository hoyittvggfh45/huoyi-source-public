import 'package:flutter/material.dart';

import '../app_page_route.dart';
import '../local_store.dart';
import '../playback_preferences.dart';
import '../player_core.dart';
import '../player_picker.dart';
import '../widgets.dart';
import 'kotv_option_dialogs.dart';
import 'kotv_theme.dart';

class KotvPlaybackSettingsScreen extends StatelessWidget {
  const KotvPlaybackSettingsScreen({super.key, required this.store});

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

  Widget _storeSwitch(
    BuildContext context,
    String title,
    bool value,
    Future<void> Function(bool changed) update,
  ) => KotvSettingsRow(
    title: title,
    trailing: Switch.adaptive(
      value: value,
      onChanged: store.locked
          ? null
          : (changed) => saveUserChange(context, () => update(changed)),
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

  Future<void> _chooseDecoder(BuildContext context) async {
    final chosen = await showKotvDecoderDialog(
      context: context,
      current: store.playbackPreferences.televisionDecoder,
    );
    if (chosen != null && context.mounted) {
      await _update(
        context,
        (preferences) => preferences.copyWith(televisionDecoder: chosen),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final preferences = store.playbackPreferences;
      return Scaffold(
        appBar: AppBar(title: const Text('播放设置')),
        body: KotvPastelBackground(
          child: ListView(
            padding: EdgeInsets.only(
              bottom: 32 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              KotvGroupCard(
                title: '播放行为',
                children: [
                  _switch(
                    context,
                    '自动连播',
                    preferences.autoAdvance,
                    (current, changed) =>
                        current.copyWith(autoAdvance: changed),
                  ),
                  _switch(
                    context,
                    '预加载下一集／下一部',
                    preferences.preload,
                    (current, changed) => current.copyWith(preload: changed),
                  ),
                  _storeSwitch(
                    context,
                    '续播',
                    store.resumePlayback,
                    store.setResumePlayback,
                  ),
                ],
              ),
              KotvGroupCard(
                title: '倍速',
                children: [
                  KotvSettingsRow(
                    title: '默认倍速',
                    value: '${speedLabel(preferences.speed)}x',
                    onTap: () => _choose<double>(
                      context,
                      '默认倍速',
                      playbackSpeeds,
                      preferences.speed,
                      (speed) => '${speedLabel(speed)}x',
                      (current, chosen) => current.copyWith(speed: chosen),
                    ),
                  ),
                  KotvSettingsRow(
                    title: '长按倍速',
                    value: '${speedLabel(preferences.holdSpeed)}x',
                    onTap: () => _choose<double>(
                      context,
                      '长按倍速',
                      holdSpeeds,
                      preferences.holdSpeed,
                      (speed) => '${speedLabel(speed)}x',
                      (current, chosen) =>
                          current.copyWith(holdSpeed: chosen),
                    ),
                  ),
                ],
              ),
              KotvGroupCard(
                title: '解码与后端',
                children: [
                  KotvSettingsRow(
                    title: '解码方式',
                    value: kotvDecoderLabel(preferences.televisionDecoder),
                    onTap: () => _chooseDecoder(context),
                  ),
                  KotvSettingsRow(
                    title: '播放器后端',
                    value: PlayerCoreStorage.read(
                      store.preferences,
                    ).dialogTitle,
                    onTap: () => Navigator.of(context).push(
                      appPageRoute<void>(
                        builder: (_) => PlayerPickerScreen(store: store),
                      ),
                    ),
                  ),
                  _storeSwitch(
                    context,
                    '自动切换播放器',
                    store.autoSwitchPlayer,
                    store.setAutoSwitchPlayer,
                  ),
                ],
              ),
              KotvGroupCard(
                title: '音频',
                children: [
                  _switch(
                    context,
                    '多声道音频输出',
                    preferences.multiChannelAudio,
                    (current, changed) =>
                        current.copyWith(multiChannelAudio: changed),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      '开启后 MPV 按多声道输出，关闭则混音为立体声；仅 MPV 后端生效。',
                      style: TextStyle(
                        fontSize: 13,
                        color: KotvTokens.unselectedColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
