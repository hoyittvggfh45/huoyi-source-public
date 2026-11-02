import 'package:duanju_app/novel_source_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('小说导入识别', () {
    test('含 novel:// 的是小说源', () {
      expect(
        NovelSourceStore.isNovelComicPyText(
          'return {"parse": 0, "url": "novel://" + payload}',
        ),
        isTrue,
      );
    });

    test('含 pics:// 的是漫画源', () {
      expect(
        NovelSourceStore.isNovelComicPyText(
          'return {"parse": 0, "url": "pics://" + urls}',
        ),
        isTrue,
      );
    });

    test('只回视频地址的不是小说漫画源', () {
      expect(
        NovelSourceStore.isNovelComicPyText(
          'return {"parse": 0, "url": "https://cdn.example.com/v.m3u8"}',
        ),
        isFalse,
      );
    });

    test('只回音频地址的不是小说漫画源', () {
      expect(
        NovelSourceStore.isNovelComicPyText(
          'return {"parse": 0, "url": "https://cdn.example.com/a.mp3"}',
        ),
        isFalse,
      );
    });

    test('大写协议头不算', () {
      expect(
        NovelSourceStore.isNovelComicPyText(
          'return {"parse": 0, "url": "NOVEL://" + payload}',
        ),
        isFalse,
      );
    });

    test('空文本不是小说漫画源', () {
      expect(NovelSourceStore.isNovelComicPyText(''), isFalse);
    });
  });
}
