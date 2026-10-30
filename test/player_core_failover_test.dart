import 'package:duanju_app/player_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mpv failure falls through to mdk then exo on android', () {
    expect(
      nextFailoverCore(
        PlayerCore.mpv,
        tried: const {},
        exoAvailable: true,
      ),
      PlayerCore.mdk,
    );
    expect(
      nextFailoverCore(
        PlayerCore.mpv,
        tried: {PlayerCore.mdk},
        exoAvailable: true,
      ),
      PlayerCore.exo,
    );
  });

  test('mdk failure falls back to mpv first', () {
    expect(
      nextFailoverCore(
        PlayerCore.mdk,
        tried: const {},
        exoAvailable: true,
      ),
      PlayerCore.mpv,
    );
  });

  test('exo failure falls back to mpv first', () {
    expect(
      nextFailoverCore(
        PlayerCore.exo,
        tried: const {},
        exoAvailable: true,
      ),
      PlayerCore.mpv,
    );
  });

  test('current core is never returned even when not in tried', () {
    expect(
      nextFailoverCore(
        PlayerCore.mdk,
        tried: const {},
        exoAvailable: true,
      ),
      isNot(PlayerCore.mdk),
    );
  });

  test('exo is skipped when unavailable', () {
    expect(
      nextFailoverCore(
        PlayerCore.mpv,
        tried: {PlayerCore.mdk},
        exoAvailable: false,
      ),
      isNull,
    );
  });

  test('null when every core is tried', () {
    expect(
      nextFailoverCore(
        PlayerCore.mpv,
        tried: {PlayerCore.mpv, PlayerCore.mdk, PlayerCore.exo},
        exoAvailable: true,
      ),
      isNull,
    );
  });
}
