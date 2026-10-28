import 'package:duanju_app/mdk_video_pane.dart';
import 'package:duanju_app/player_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse falls back to mpv for unknown values', () {
    expect(PlayerCore.parse('mpv'), PlayerCore.mpv);
    expect(PlayerCore.parse('mdk'), PlayerCore.mdk);
    expect(PlayerCore.parse('exo'), PlayerCore.exo);
    expect(PlayerCore.parse(null), PlayerCore.mpv);
    expect(PlayerCore.parse('bogus'), PlayerCore.mpv);
  });

  test('dialog titles carry engine names', () {
    expect(PlayerCore.mpv.dialogTitle, 'MPV (media_kit)');
    expect(PlayerCore.mdk.dialogTitle, 'MDK (fvp)');
    expect(PlayerCore.exo.dialogTitle, 'EXO (Media3)');
  });

  test('every core has a description', () {
    for (final core in PlayerCore.values) {
      expect(core.description.isNotEmpty, isTrue);
      expect(core.label.isNotEmpty, isTrue);
    }
  });

  test('options enable all cores when exo is available', () {
    final options = playerCoreOptions(exoAvailable: true);
    expect(options.length, 3);
    expect(options.every((option) => option.enabled), isTrue);
  });

  test('options disable exo when it is unavailable', () {
    final options = playerCoreOptions(exoAvailable: false);
    final exo = options.firstWhere((option) => option.core == PlayerCore.exo);
    expect(exo.enabled, isFalse);
    expect(exo.disabledNote, '仅 Android 可用');
    expect(
      options
          .where((option) => option.core != PlayerCore.exo)
          .every((option) => option.enabled),
      isTrue,
    );
  });

  test('mdk handle defaults and speed tracking', () async {
    final handle = MdkPlaybackHandle();
    expect(handle.speed, 1.0);
    expect(handle.position, Duration.zero);
    expect(handle.duration, Duration.zero);
    expect(handle.playing, isFalse);
    expect(handle.completed, isFalse);
    expect(handle.positionSeconds, 0);
    expect(handle.durationSeconds, 0);
    await handle.setSpeed(1.5);
    expect(handle.speed, 1.5);
    await handle.play();
    await handle.pause();
    await handle.seek(const Duration(seconds: 10));
  });
}
