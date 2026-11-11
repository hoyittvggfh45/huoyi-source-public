import 'package:duanju_app/hongguo_discovery_filters.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('discovery labels cover the eight server dimensions', () {
    expect(hongguoDiscoveryLabels.keys.toList(), [
      'genre',
      'category_dim_theme',
      'category_dim_role',
      'category_dim_epoch',
      'sort',
      'gender',
      'online_time',
      'creation_status',
    ]);
  });

  test('genre options use the real server genre ids', () {
    expect(
      hongguoDiscoveryGenres.map((entry) => entry.id).toList(),
      ['short_play', 'comic_series', 'ai_series'],
    );
  });

  test('choosing a genre discards the previous type conditions', () {
    const selection = HongguoDiscoverySelection({
      'genre': 'short_play',
      'category_dim_theme': 'theme-a',
      'sort': 'online_time',
    });
    final next = selection.choose('genre', 'comic_series');
    expect(next.values, {'genre': 'comic_series'});
  });

  test('choosing a non-genre dimension keeps the others', () {
    const selection = HongguoDiscoverySelection({
      'genre': 'short_play',
      'category_dim_theme': 'theme-a',
    });
    final next = selection.choose('sort', 'online_time');
    expect(next.values, {
      'genre': 'short_play',
      'category_dim_theme': 'theme-a',
      'sort': 'online_time',
    });
  });

  test('empty id removes the dimension and bad ids are rejected', () {
    const selection = HongguoDiscoverySelection({
      'genre': 'short_play',
      'sort': 'online_time',
    });
    expect(selection.choose('sort', '').values, {'genre': 'short_play'});
    expect(
      selection.choose('sort', 'bad id!').values,
      selection.values,
    );
    expect(selection.choose('nope', 'x').values, selection.values);
  });

  test('first page request body asks for the selector panel', () {
    const selection = HongguoDiscoverySelection({'genre': 'comic_series'});
    final body = selection.requestBody();
    expect(body['offset'], 0);
    expect(body['limit'], 24);
    expect(body['need_selector_panel'], isTrue);
    expect(body['req_type'], 'default');
    expect(body['client_req_type'], 3);
    expect(body['filter_ids'], '');
    expect(body['req_scene'], 'comic_series');
    final selected = body['select_items'] as Map<String, List<String>>;
    expect(selected['genre'], ['comic_series']);
    expect(selected['sort'], isEmpty);
  });

  test('follow-up page request body carries the session cursor', () {
    const selection = HongguoDiscoverySelection({'genre': 'short_play'});
    final body = selection.requestBody(
      offset: 24,
      sessionId: 'session-1',
      firstPage: false,
    );
    expect(body['offset'], 24);
    expect(body['need_selector_panel'], isFalse);
    expect(body['req_type'], 'only_content');
    expect(body['session_id'], 'session-1');
    expect(body['req_scene'], 'default');
  });

  test('fromCategory only accepts genres present in the categories', () {
    const categories = [
      CatalogCategory('short_play', '真人剧'),
      CatalogCategory('comic_series', '漫剧'),
    ];
    expect(
      HongguoDiscoverySelection.fromCategory('short_play', categories).genre,
      'short_play',
    );
    expect(
      HongguoDiscoverySelection.fromCategory('ai_series', categories).values,
      isEmpty,
    );
    expect(
      HongguoDiscoverySelection.fromCategory('nope', categories).values,
      isEmpty,
    );
  });
}
