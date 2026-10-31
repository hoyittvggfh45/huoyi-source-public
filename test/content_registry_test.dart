import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('内容注册表清单', () {
    test('听书：听书网；小说漫画模块已删，不再内置源', () {
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.id),
        ['tingshuwang'],
      );
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.name),
        ['听书网'],
      );
    });

    test('id 全局唯一且分区归属自洽', () {
      final all = [
        for (final section in ContentSection.values)
          ...ContentRegistry.sourcesFor(section),
      ];
      expect(all, hasLength(1));
      expect(all.map((s) => s.id).toSet(), hasLength(1));
      for (final section in ContentSection.values) {
        for (final source in ContentRegistry.sourcesFor(section)) {
          expect(source.section, section);
        }
      }
    });
  });
}
