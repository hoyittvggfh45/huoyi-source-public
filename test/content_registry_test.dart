import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('内容注册表清单', () {
    test('听书：听书网、喜马拉雅、红果听书', () {
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.id),
        ['tingshuwang', 'ximalaya', 'hongguo_audio'],
      );
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.name),
        ['听书网', '喜马拉雅', '红果听书'],
      );
    });

    test('id 全局唯一且分区归属自洽', () {
      final all = [
        for (final section in ContentSection.values)
          ...ContentRegistry.sourcesFor(section),
      ];
      expect(all, hasLength(3));
      expect(all.map((s) => s.id).toSet(), hasLength(3));
      for (final section in ContentSection.values) {
        for (final source in ContentRegistry.sourcesFor(section)) {
          expect(source.section, section);
        }
      }
    });
  });
}
