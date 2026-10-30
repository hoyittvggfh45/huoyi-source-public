import 'package:duanju_app/playback_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multiChannelAudio defaults to false when the key is missing', () {
    final preferences = PlaybackPreferences.fromJson(const {});
    expect(preferences.multiChannelAudio, isFalse);
  });

  test('multiChannelAudio round-trips through json', () {
    final preferences = const PlaybackPreferences(
      multiChannelAudio: true,
    );
    final restored = PlaybackPreferences.fromJson(preferences.toJson());
    expect(restored.multiChannelAudio, isTrue);
  });

  test('copyWith keeps multiChannelAudio unless overridden', () {
    const preferences = PlaybackPreferences(multiChannelAudio: true);
    expect(preferences.copyWith().multiChannelAudio, isTrue);
    expect(
      preferences.copyWith(multiChannelAudio: false).multiChannelAudio,
      isFalse,
    );
  });
}
