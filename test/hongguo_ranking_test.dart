import 'package:duanju_app/hongguo_ranking_screen.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/ranking_models.dart';
import 'package:flutter_test/flutter_test.dart';

RankingItem _item(int rank, List<String> tags, {String heat = ''}) {
  return RankingItem(
    rank,
    Drama(
      id: 'hongguo:$rank',
      source: 'hongguo',
      title: '剧$rank',
      tags: tags,
      heat: heat,
    ),
  );
}

void main() {
  test('rank topics count down then sort alphabetically', () {
    final items = [
      _item(1, ['古言', '重生']),
      _item(2, ['古言', '甜宠']),
      _item(3, ['重生']),
    ];
    expect(hongguoRankTopics(items), ['古言', '重生', '甜宠']);
  });

  test('rank topics drop pure-digit tokens', () {
    final items = [
      _item(1, ['2026', '古言']),
      _item(2, ['古言']),
    ];
    expect(hongguoRankTopics(items), ['古言']);
  });

  test('rank topic filter keeps the original rank order', () {
    final items = [
      _item(1, ['古言']),
      _item(2, ['甜宠']),
      _item(3, ['古言']),
    ];
    final filtered = hongguoRankFiltered(items, '古言');
    expect([for (final item in filtered) item.rank], [1, 3]);
    expect(hongguoRankFiltered(items, '').length, 3);
  });

  test('rank heat prefers the drama heat over the metric', () {
    expect(hongguoRankHeat(_item(1, [], heat: '12万热度')), '12万热度');
    expect(
      hongguoRankHeat(RankingItem(1, _item(1, []).drama, metric: '9万热度')),
      '9万热度',
    );
    expect(hongguoRankHeat(_item(1, [])), '');
  });

  test('rank cache is fresh within ten minutes and stale after', () {
    final cache = HongguoRankCache();
    final snapshot = HongguoRankSnapshot(
      boardId: 'hongguo-hot',
      items: [_item(1, [])],
      updatedText: '刚刚更新',
      fetchedAt: DateTime.now().subtract(const Duration(minutes: 9)),
    );
    cache.endRefresh('hongguo-hot', snapshot);
    expect(cache.isFresh('hongguo-hot'), isTrue);
    expect(
      cache.isFresh(
        'hongguo-hot',
        now: DateTime.now().add(const Duration(minutes: 2)),
      ),
      isFalse,
    );
    expect(cache.isFresh('hongguo-real'), isFalse);
  });

  test('rank refresh deduplicates per board and keeps old snapshots', () {
    final cache = HongguoRankCache();
    expect(cache.beginRefresh('hongguo-hot'), isTrue);
    expect(cache.beginRefresh('hongguo-hot'), isFalse);
    expect(cache.beginRefresh('hongguo-real'), isTrue);
    expect(cache.isRefreshing('hongguo-hot'), isTrue);
    final snapshot = HongguoRankSnapshot(
      boardId: 'hongguo-hot',
      items: [_item(1, [])],
      updatedText: '',
      fetchedAt: DateTime.now(),
    );
    cache.endRefresh('hongguo-hot', snapshot);
    expect(cache.isRefreshing('hongguo-hot'), isFalse);
    expect(cache.snapshots['hongguo-hot'], snapshot);
    cache.beginRefresh('hongguo-hot');
    cache.endRefresh('hongguo-hot', null);
    expect(cache.snapshots['hongguo-hot'], snapshot);
  });
}
