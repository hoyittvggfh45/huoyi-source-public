import 'package:duanju_app/comment_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('comment parses strictly and roundtrips', () {
    final json = <String, dynamic>{
      'id': 'c1',
      'videoKey': 'hongguo:1001',
      'text': '好看',
      'timeMs': 12345,
      'senderId': 'user-a',
      'nickname': '用户a',
      'createdAt': 1700000000000,
    };
    final comment = VideoComment.fromJson(json);
    expect(comment.toJson(), json);
    final invalid = [
      {...json, 'id': ''},
      {...json, 'videoKey': ''},
      {...json, 'text': '   '},
      {...json, 'text': 'x' * 201},
      {...json, 'timeMs': -1},
      {...json, 'timeMs': 1.5},
      {...json, 'senderId': ''},
      {...json, 'nickname': 'n' * 41},
      {...json, 'createdAt': 0},
    ];
    for (final row in invalid) {
      expect(() => VideoComment.fromJson(row), throwsFormatException);
    }
  });

  test('relative time buckets', () {
    const now = 1700000000000;
    expect(commentRelativeTime(now, now), '刚刚');
    expect(commentRelativeTime(now - 30000, now), '刚刚');
    expect(commentRelativeTime(now - 90000, now), '1分钟前');
    expect(commentRelativeTime(now - 2 * 3600000, now), '2小时前');
    expect(commentRelativeTime(now - 3 * 86400000, now), '3天前');
  });

  test('display name falls back to sender tail', () {
    const named = VideoComment(
      id: 'c1',
      videoKey: 'k',
      text: 't',
      timeMs: 0,
      senderId: 'user-a',
      nickname: '阿明',
      createdAt: 1,
    );
    expect(commentDisplayName(named), '阿明');
    const unnamed = VideoComment(
      id: 'c2',
      videoKey: 'k',
      text: 't',
      timeMs: 0,
      senderId: 'abcdef1234',
      nickname: '',
      createdAt: 1,
    );
    expect(commentDisplayName(unnamed), '用户1234');
  });

  test('comment thread key isolates episodes', () {
    expect(commentThreadKey('src:1001', 'ep5'), 'src:1001:ep5');
    expect(
      commentThreadKey('src:1001', 'ep5') != commentThreadKey('src:1001', 'ep6'),
      isTrue,
    );
  });
}
