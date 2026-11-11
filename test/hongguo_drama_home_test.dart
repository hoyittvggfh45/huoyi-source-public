import 'package:flutter_test/flutter_test.dart';
import 'package:duanju_app/hongguo_drama_home.dart';

void main() {
  test('hongguo drama group detection', () {
    expect(isHongguoDramaGroup('hongguo'), isTrue);
    expect(isHongguoDramaGroup('dsd'), isFalse);
    expect(isHongguoDramaGroup(''), isFalse);
    expect(isHongguoDramaGroup('hongguo2'), isFalse);
  });

  group('hongguoFeedNext', () {
    test('same drama next episode', () {
      expect(
        hongguoFeedNext(
          drama: 0,
          episode: 0,
          dramaCount: 3,
          episodeCount: 5,
        ),
        (drama: 0, episode: 1),
      );
    });

    test('last episode goes to next drama first episode', () {
      expect(
        hongguoFeedNext(
          drama: 0,
          episode: 4,
          dramaCount: 3,
          episodeCount: 5,
        ),
        (drama: 1, episode: 0),
      );
    });

    test('last episode of last drama returns null', () {
      expect(
        hongguoFeedNext(
          drama: 2,
          episode: 4,
          dramaCount: 3,
          episodeCount: 5,
        ),
        isNull,
      );
    });
  });

  group('hongguoFeedPrevious', () {
    test('same drama previous episode', () {
      expect(
        hongguoFeedPrevious(
          drama: 1,
          episode: 2,
          previousEpisodeCount: 5,
        ),
        (drama: 1, episode: 1),
      );
    });

    test('first episode goes to previous drama last episode', () {
      expect(
        hongguoFeedPrevious(
          drama: 1,
          episode: 0,
          previousEpisodeCount: 5,
        ),
        (drama: 0, episode: 4),
      );
    });

    test('unknown previous count falls back to its first episode', () {
      expect(
        hongguoFeedPrevious(
          drama: 1,
          episode: 0,
          previousEpisodeCount: 0,
        ),
        (drama: 0, episode: 0),
      );
    });

    test('first episode of first drama returns null', () {
      expect(
        hongguoFeedPrevious(
          drama: 0,
          episode: 0,
          previousEpisodeCount: 0,
        ),
        isNull,
      );
    });
  });

  group('hongguoFeedHeat', () {
    test('formats raw counts with wan and yi', () {
      expect(hongguoFeedHeat('77030000'), '7703万');
      expect(hongguoFeedHeat('396605'), '39.7万');
      expect(hongguoFeedHeat('9999'), '9999');
      expect(hongguoFeedHeat('123456789'), '1.2亿');
    });

    test('keeps already formatted or empty values', () {
      expect(hongguoFeedHeat(''), '');
      expect(hongguoFeedHeat('7703万'), '7703万');
      expect(hongguoFeedHeat('115.6万'), '115.6万');
    });
  });
}
