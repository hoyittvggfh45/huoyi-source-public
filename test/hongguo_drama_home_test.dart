import 'package:duanju_app/hongguo_drama_home.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/ranking_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hongguo drama group detection', () {
    expect(isHongguoDramaGroup('hongguo'), isTrue);
    expect(isHongguoDramaGroup('dsd'), isFalse);
    expect(isHongguoDramaGroup(''), isFalse);
    expect(isHongguoDramaGroup('hongguo2'), isFalse);
  });

  group('hongguoFeedNextDrama', () {
    test('moves to the next drama', () {
      expect(hongguoFeedNextDrama(drama: 0, dramaCount: 3), 1);
      expect(hongguoFeedNextDrama(drama: 1, dramaCount: 3), 2);
    });

    test('last drama returns null', () {
      expect(hongguoFeedNextDrama(drama: 2, dramaCount: 3), isNull);
    });

    test('single drama returns null', () {
      expect(hongguoFeedNextDrama(drama: 0, dramaCount: 1), isNull);
    });

    test('empty feed returns null', () {
      expect(hongguoFeedNextDrama(drama: 0, dramaCount: 0), isNull);
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

  group('hongguoRankBadgeHeat', () {
    test('uses the ranking item heat without duplicating the suffix', () {
      const item = RankingItem(
        3,
        Drama(id: 'hongguo:1', source: 'hongguo', title: '剧名', heat: '7351万热度'),
      );
      expect(hongguoRankBadgeHeat(item), '7351万');
    });

    test('falls back to the ranking metric', () {
      const item = RankingItem(
        1,
        Drama(id: 'hongguo:1', source: 'hongguo', title: '剧名'),
        metric: '8835万热度',
      );
      expect(hongguoRankBadgeHeat(item), '8835万');
    });

    test('formats a raw ranking heat count', () {
      const item = RankingItem(
        2,
        Drama(id: 'hongguo:1', source: 'hongguo', title: '剧名', heat: '77030000'),
      );
      expect(hongguoRankBadgeHeat(item), '7703万');
    });

    test('keeps an empty heat empty', () {
      const item = RankingItem(
        5,
        Drama(id: 'hongguo:1', source: 'hongguo', title: '剧名'),
      );
      expect(hongguoRankBadgeHeat(item), '');
    });
  });
}
