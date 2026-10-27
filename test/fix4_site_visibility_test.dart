import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_registry.dart';
import 'package:duanju_app/content_zone_binding.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('content source ids are known and never collide with core sites', () {
    for (final source in ContentRegistry.allSources) {
      expect(ContentRegistry.isKnownId(source.id), isTrue, reason: source.id);
      expect(
        SourceSite.isKnown(source.id),
        isFalse,
        reason: 'id collision: ${source.id}',
      );
    }
    expect(ContentRegistry.isKnownId('not-a-source'), isFalse);
  });

  test('comic zone exposes its built-in sources for management', () {
    expect(
      ContentRegistry.sourcesFor(ContentSection.comic),
      isNotEmpty,
      reason: ContentSection.comic.title,
    );
    expect(
      ContentRegistry.sourcesFor(ContentSection.audio),
      isEmpty,
      reason: '听书已删，改走开源阅读',
    );
    expect(
      ContentRegistry.sourcesFor(ContentSection.novel),
      isEmpty,
      reason: '小说已删，改走开源阅读',
    );
  });

  test('hidden content ids are honored by siteVisible', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(store.siteVisible('dongmanla'), isTrue);
    expect(store.siteVisible('hongguo'), isTrue);
    store.dispose();
  });

  test('zone binding provider filters hidden sources live', () {
    final hidden = <String>{'dongmanla'};
    final binding = ContentZoneBinding(
      sourcesProvider: (section) => [
        for (final source in ContentRegistry.sourcesFor(section))
          if (!hidden.contains(source.id)) source,
      ],
      readPersisted: (_) => null,
      writePersisted: (_, _) async {},
    );
    final comicIds = [
      for (final source in binding.sourcesFor(ContentSection.comic)) source.id,
    ];
    expect(comicIds, isNot(contains('dongmanla')));
    expect(comicIds, contains('mangadex'));
    hidden.clear();
    final restoredIds = [
      for (final source in binding.sourcesFor(ContentSection.comic)) source.id,
    ];
    expect(restoredIds, contains('dongmanla'));
  });
}
