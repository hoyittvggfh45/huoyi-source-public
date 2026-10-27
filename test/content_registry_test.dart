import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('内容注册表清单', () {
    test('漫画：动漫啦 + MangaDex + 拷贝漫画 + 包子漫画', () {
      final sources = ContentRegistry.sourcesFor(ContentSection.comic);
      expect(sources.map((s) => s.id), [
        'dongmanla',
        'mangadex',
        'copymanga',
        'baozimh',
      ]);
      expect(sources.map((s) => s.name), ['动漫啦', 'MangaDex', '拷贝漫画', '包子漫画']);
    });

    test('小说与听书已删：改走开源阅读书源，不再内置源', () {
      expect(ContentRegistry.sourcesFor(ContentSection.audio), isEmpty);
      expect(ContentRegistry.sourcesFor(ContentSection.novel), isEmpty);
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
