import 'package:duanju_app/danmaku_controller.dart';
import 'package:duanju_app/danmaku_models.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'danmaku_fixtures.dart';

Future<void> flushComment() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.value();
  }
}

void updateComment(
  DanmakuController controller, {
  int position = 0,
  int duration = 180000,
}) {
  controller.update(
    position: Duration(milliseconds: position),
    duration: Duration(milliseconds: duration),
    speed: 1,
    playing: true,
    buffering: false,
    foreground: true,
    available: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('comment loader fills overlay items without a source plan', () async {
    final repository = DanmakuFixtureRepository();
    final controller = DanmakuController(
      repository,
      commentPage: (plan, start, duration) async {
        final next = (start + danmakuWindowMs).clamp(start + 1, duration);
        return DanmakuPage(
          episodeId: plan.danmakuId,
          startMs: start,
          nextMs: next,
          items: const [
            DanmakuItem(id: 'c1', text: '用户a：好看', timeMs: 1000),
            DanmakuItem(id: 'c2', text: '用户b：一般', timeMs: 5000),
          ],
        );
      },
    );
    addTearDown(controller.dispose);
    controller.setCommentVideoKey('hongguo:1001');
    updateComment(controller);
    await flushComment();
    expect(controller.visible, isTrue);
    expect(controller.items.map((item) => item.id), ['c1', 'c2']);
    controller.setCommentVideoKey(null);
    expect(controller.items, isEmpty);
    expect(controller.visible, isFalse);
  });

  test('live comment items append once and dedupe by id', () async {
    final repository = DanmakuFixtureRepository();
    final controller = DanmakuController(repository);
    addTearDown(controller.dispose);
    controller.addCommentItem(
      const DanmakuItem(id: 'live-1', text: '用户a：来了', timeMs: 1000),
    );
    controller.addCommentItem(
      const DanmakuItem(id: 'live-1', text: '用户a：来了', timeMs: 1000),
    );
    expect(controller.items.length, 1);
    expect(controller.items.first.text, '用户a：来了');
  });
}
