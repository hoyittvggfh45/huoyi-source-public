import 'package:duanju_app/miniapp/source_shapes.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vod json carries vod fields plus host aliases', () {
    final drama = Drama(
      id: 'd1',
      source: 'site',
      title: '剧一',
      cover: 'https://x/cover.jpg',
      description: '简介',
      category: '短剧',
      heat: '1.2万',
      views: '999',
      onlineDate: '2025-03-01',
    );
    final json = miniappVodJson(drama);
    expect(json['vod_id'], 'd1');
    expect(json['vod_name'], '剧一');
    expect(json['vod_pic'], 'https://x/cover.jpg');
    expect(json['vod_remarks'], '1.2万');
    expect(json['vod_year'], '2025');
    expect(json['vod_type'], '短剧');
    expect(json['vod_content'], '简介');
    expect(json['id'], 'd1');
    expect(json['title'], '剧一');
    expect(json['cover'], 'https://x/cover.jpg');
  });

  test('vod remarks falls back to views when heat is empty', () {
    final drama = Drama(id: 'd2', source: 'site', title: '剧二', views: '42');
    expect(miniappVodJson(drama)['vod_remarks'], '42');
  });

  test('play lines group by flag and keep order', () {
    final episodes = [
      Episode({'id': 'ep1', 'title': '第1集', 'flag': '线路A'}, 1),
      Episode({'id': 'ep2', 'title': '第1集', 'flag': '线路B'}, 2),
      Episode({'id': 'ep3', 'title': '第2集', 'flag': '线路A'}, 3),
    ];
    final lines = miniappPlayLines(episodes);
    expect(lines.map((line) => line['name']), ['线路A', '线路B']);
    final first = lines.first['episodes'] as List;
    expect(first.map((episode) => episode['id']), ['ep1', 'ep3']);
  });

  test('play lines fall back to one line without flag', () {
    final episodes = [
      Episode({'id': 'ep1', 'title': '第1集'}, 1),
      Episode({'id': 'ep2', 'title': '第2集'}, 2),
    ];
    final lines = miniappPlayLines(episodes);
    expect(lines.length, 1);
    expect(lines.single['name'], '线路1');
  });

  test('detail json rebuilds vod play from and url', () {
    final drama = Drama(id: 'd1', source: 'site', title: '剧一');
    final detail = DramaDetail(drama, [
      Episode({'id': 'ep1', 'title': '第1集', 'flag': '线路A'}, 1),
      Episode({'id': 'ep2', 'title': '第1集', 'flag': '线路B'}, 2),
      Episode({'id': 'ep3', 'title': '第2集', 'flag': '线路A'}, 3),
    ]);
    final json = miniappDetailJson(detail);
    expect(json['vod_name'], '剧一');
    expect(json['vod_play_from'], ['线路A', '线路B']);
    expect(json['vod_play_url'], ['第1集\$ep1#第2集\$ep3', '第1集\$ep2']);
    expect((json['episodes'] as List).length, 3);
  });

  test('page count advances only while more pages exist', () {
    expect(miniappPageCount(true, 2), 3);
    expect(miniappPageCount(false, 2), 2);
  });

  test('media detection separates playable urls from pages', () {
    expect(miniappLooksLikeMedia('https://x/a.m3u8'), isTrue);
    expect(miniappLooksLikeMedia('https://x/a.mp4?token=1'), isTrue);
    expect(miniappLooksLikeMedia('https://x/play.html'), isFalse);
    expect(miniappLooksLikeMedia('https://x/api'), isFalse);
  });
}
