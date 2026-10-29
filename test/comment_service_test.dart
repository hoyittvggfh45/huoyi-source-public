import 'package:duanju_app/comment_api.dart';
import 'package:duanju_app/comment_identity.dart';
import 'package:duanju_app/comment_models.dart';
import 'package:duanju_app/comment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeCommentApi implements CommentApi {
  final pages = <String, List<VideoComment>>{};
  final posted = <VideoComment>[];
  int fetchCalls = 0;

  @override
  Future<CommentPageResult> fetch({
    required String videoKey,
    int limit = 100,
    String? before,
  }) async {
    fetchCalls++;
    if (before != null) {
      return const CommentPageResult(items: [], nextBefore: null);
    }
    return CommentPageResult(
      items: List.of(pages[videoKey] ?? const []),
      nextBefore: null,
    );
  }

  @override
  Future<VideoComment> post({
    required String videoKey,
    required String text,
    required int timeMs,
    required String senderId,
    required String nickname,
  }) async {
    final comment = VideoComment(
      id: 'id-${posted.length}',
      videoKey: videoKey,
      text: text,
      timeMs: timeMs,
      senderId: senderId,
      nickname: nickname,
      createdAt: 2000 + posted.length,
    );
    posted.add(comment);
    pages.putIfAbsent(videoKey, () => []).add(comment);
    return comment;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('send enforces interval and length, fetch caches and filters', () async {
    SharedPreferences.setMockInitialValues({});
    await CommentIdentity.instance.ensure();
    final api = FakeCommentApi();
    var now = DateTime.fromMillisecondsSinceEpoch(100000);
    final service = CommentService.forTest(
      api: api,
      prefs: await SharedPreferences.getInstance(),
      now: () => now,
    );
    const key = 'hongguo:1001';
    final first = await service.send(videoKey: key, text: '第一条', timeMs: 1000);
    expect(first.text, '第一条');
    expect(
      () => service.send(videoKey: key, text: '第二条', timeMs: 2000),
      throwsA(isA<CommentRateLimited>()),
    );
    now = DateTime.fromMillisecondsSinceEpoch(106000);
    final long = await service.send(
      videoKey: key,
      text: 'x' * 300,
      timeMs: 5000,
    );
    expect(long.text.runes.length, 200);
    expect(
      () => service.send(videoKey: key, text: '   ', timeMs: 0),
      throwsA(isA<CommentApiException>()),
    );
    final all = await service.fetchAll(key);
    expect(all.length, 2);
    expect(api.fetchCalls, 1);
    await service.fetchAll(key);
    expect(api.fetchCalls, 1);
    final windowItems = await service.window(key, 0, 3000);
    expect(windowItems.map((item) => item.timeMs), [1000]);
    await service.block(first.senderId);
    final afterBlock = await service.window(key, 0, 10000);
    expect(
      afterBlock.any((item) => item.id == first.id),
      isFalse,
    );
    await service.unblock(first.senderId);
    final afterUnblock = await service.window(key, 0, 10000);
    expect(
      afterUnblock.any((item) => item.id == first.id),
      isTrue,
    );
  });
}
