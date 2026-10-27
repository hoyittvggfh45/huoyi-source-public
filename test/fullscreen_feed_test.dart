import 'package:duanju_app/fullscreen_feed_screen.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feed resume key joins source and id', () {
    const drama = Drama(id: 'd1', source: 'hongguo', title: '剧名');
    expect(feedResumeKey(drama), 'hongguo|d1');
  });

  test('feed only keeps video dramas', () {
    const items = [
      Drama(id: 'v1', source: 's', title: '视频'),
      Drama(id: 'f1', source: 's', title: '文件夹', kind: 'folder'),
      Drama(id: 'v2', source: 's', title: '视频二'),
    ];
    final playable = feedPlayableDramas(items);
    expect(playable.map((drama) => drama.id), ['v1', 'v2']);
    expect(feedPlayableDramas([]), isEmpty);
  });

  test('feed episode index clamps to range', () {
    expect(clampFeedEpisodeIndex(2, 10), 2);
    expect(clampFeedEpisodeIndex(-1, 10), 0);
    expect(clampFeedEpisodeIndex(10, 10), 9);
    expect(clampFeedEpisodeIndex(0, 0), 0);
    expect(clampFeedEpisodeIndex(5, 1), 0);
  });
}
