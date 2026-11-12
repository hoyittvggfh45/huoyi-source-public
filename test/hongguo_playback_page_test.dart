import 'package:duanju_app/hongguo_playback_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hongguoPlaybackSwipeEpisode', () {
    test('swipe up goes to the next episode', () {
      expect(
        hongguoPlaybackSwipeEpisode(
          episode: 0,
          episodeCount: 521,
          dy: -100,
          velocity: -200,
        ),
        1,
      );
      expect(
        hongguoPlaybackSwipeEpisode(
          episode: 10,
          episodeCount: 521,
          dy: -80,
          velocity: -100,
        ),
        11,
      );
    });

    test('fast short swipe up goes to the next episode', () {
      expect(
        hongguoPlaybackSwipeEpisode(
          episode: 0,
          episodeCount: 521,
          dy: -30,
          velocity: -700,
        ),
        1,
      );
    });

    test('swipe down goes to the previous episode', () {
      expect(
        hongguoPlaybackSwipeEpisode(
          episode: 5,
          episodeCount: 521,
          dy: 100,
          velocity: 200,
        ),
        4,
      );
    });

    test('fast short swipe down goes to the previous episode', () {
      expect(
        hongguoPlaybackSwipeEpisode(
          episode: 5,
          episodeCount: 521,
          dy: 30,
          velocity: 700,
        ),
        4,
      );
    });

    test('first episode swipe down stays put', () {
      expect(
        hongguoPlaybackSwipeEpisode(
          episode: 0,
          episodeCount: 521,
          dy: 200,
          velocity: 900,
        ),
        isNull,
      );
    });

    test('last episode swipe up stays put', () {
      expect(
        hongguoPlaybackSwipeEpisode(
          episode: 520,
          episodeCount: 521,
          dy: -200,
          velocity: -900,
        ),
        isNull,
      );
    });

    test('small slow movement changes nothing', () {
      expect(
        hongguoPlaybackSwipeEpisode(
          episode: 3,
          episodeCount: 521,
          dy: -20,
          velocity: -100,
        ),
        isNull,
      );
      expect(
        hongguoPlaybackSwipeEpisode(
          episode: 3,
          episodeCount: 521,
          dy: 10,
          velocity: 50,
        ),
        isNull,
      );
    });

    test('empty episode list changes nothing', () {
      expect(
        hongguoPlaybackSwipeEpisode(
          episode: 0,
          episodeCount: 0,
          dy: -200,
          velocity: -900,
        ),
        isNull,
      );
    });
  });
}
