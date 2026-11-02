import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_py.dart';
import 'package:duanju_app/content_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('内容注册表清单', () {
    test('听书：听书网、喜马拉雅、红果听书、懒人听书', () {
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.id),
        ['tingshuwang', 'ximalaya', 'hongguo_audio', 'lrts'],
      );
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.name),
        ['听书网', '喜马拉雅', '红果听书', '懒人听书'],
      );
    });

    test('午夜未激活时成人源隐藏，激活后出现', () {
      addTearDown(() => ContentRegistry.midnightActivated = false);
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.id),
        ['tingshuwang', 'ximalaya', 'hongguo_audio', 'lrts'],
      );
      ContentRegistry.midnightActivated = true;
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.id),
        ['tingshuwang', 'ximalaya', 'hongguo_audio', 'lrts', 'hsvoice31'],
      );
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).last.name,
        '🔞黄色有声小说',
      );
    });

    test('小说：默认无源，导入后只进小说区', () {
      addTearDown(() => ContentRegistry.setNovelImports([]));
      expect(ContentRegistry.sourcesFor(ContentSection.novel), isEmpty);
      ContentRegistry.setNovelImports([
        PyContentSource(
          id: 'novel_demo',
          name: '演示小说',
          importedFileName: 'demo.py',
          section: ContentSection.novel,
        ),
      ]);
      expect(
        ContentRegistry.sourcesFor(ContentSection.novel).map((s) => s.id),
        ['novel_demo'],
      );
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.id),
        ['tingshuwang', 'ximalaya', 'hongguo_audio', 'lrts'],
      );
    });

    test('小说内置源默认隐藏，午夜激活后出现且排在导入源前面', () {
      addTearDown(() {
        ContentRegistry.setNovelImports([]);
        ContentRegistry.midnightActivated = false;
      });
      expect(ContentRegistry.sourcesFor(ContentSection.novel), isEmpty);
      ContentRegistry.midnightActivated = true;
      expect(
        ContentRegistry.sourcesFor(ContentSection.novel).map((s) => s.id),
        ['aabook'],
      );
      expect(
        ContentRegistry.sourcesFor(ContentSection.novel).first.name,
        '🔞疯情书库',
      );
      ContentRegistry.setNovelImports([
        PyContentSource(
          id: 'novel_demo',
          name: '演示小说',
          importedFileName: 'demo.py',
          section: ContentSection.novel,
        ),
      ]);
      expect(
        ContentRegistry.sourcesFor(ContentSection.novel).map((s) => s.id),
        ['aabook', 'novel_demo'],
      );
    });

    test('id 全局唯一且分区归属自洽', () {
      final all = [
        for (final section in ContentSection.values)
          ...ContentRegistry.sourcesFor(section),
      ];
      expect(all, hasLength(4));
      expect(all.map((s) => s.id).toSet(), hasLength(4));
      for (final section in ContentSection.values) {
        for (final source in ContentRegistry.sourcesFor(section)) {
          expect(source.section, section);
        }
      }
    });
  });
}
