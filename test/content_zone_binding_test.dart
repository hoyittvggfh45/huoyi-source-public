import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_registry.dart';
import 'package:duanju_app/content_zone_binding.dart';
import 'package:duanju_app/content_zone_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeContentSource extends ContentSource {
  FakeContentSource(this._id, this._name, this._section);

  final String _id;
  final String _name;
  final ContentSection _section;

  @override
  String get id => _id;
  @override
  String get name => _name;
  @override
  ContentSection get section => _section;

  @override
  Future<List<ContentCategory>> categories() async => [
    ContentCategory(id: 'hot', name: '$_name-分类'),
  ];

  @override
  Future<ContentPage> catalog(String categoryId, int page) async => ContentPage(
    items: [ContentBook(id: '$_id-book', title: '$_name-作品')],
  );

  @override
  Future<ContentPage> search(String keyword, int page) async =>
      const ContentPage(items: []);

  @override
  Future<ContentBookDetail> detail(String bookId) async => ContentBookDetail(
    book: ContentBook(id: bookId, title: '$_name-作品'),
    chapters: const [],
  );
}

final fakeSources = <ContentSource>[
  FakeContentSource('fake_audio_a', '听书甲', ContentSection.audio),
  FakeContentSource('fake_audio_b', '听书乙', ContentSection.audio),
];

List<ContentSource> fakeProvider(ContentSection section) => [
  for (final source in fakeSources)
    if (source.section == section) source,
];

ContentZoneBinding fakeBinding({Map<String, String>? store}) =>
    ContentZoneBinding(
      sourcesProvider: fakeProvider,
      readPersisted: store == null ? null : (key) => store[key],
      writePersisted: store == null ? null : (key, value) => store[key] = value,
    );

void main() {
  group('ContentZoneBinding 听书绑定', () {
    test('听书可选源只来自听书分区', () {
      final binding = fakeBinding();
      expect(binding.sourcesFor(ContentSection.audio).map((s) => s.id), [
        'fake_audio_a',
        'fake_audio_b',
      ]);
    });

    test('无选择时默认本区第一源', () {
      final binding = fakeBinding();
      expect(binding.sourceFor(ContentSection.audio)?.id, 'fake_audio_a');
    });

    test('select 拒绝未注册源', () {
      final binding = fakeBinding();
      binding.select(
        ContentSection.audio,
        FakeContentSource('ghost', '幽灵源', ContentSection.audio),
      );
      expect(binding.sourceFor(ContentSection.audio)?.id, 'fake_audio_a');
    });

    test('选择落盘后新 binding 按区恢复，失效 id 回退第一源', () {
      final store = <String, String>{};
      final first = fakeBinding(store: store);
      first.select(
        ContentSection.audio,
        fakeSources.firstWhere((s) => s.id == 'fake_audio_b'),
      );
      expect(store['content_zone_source_audio'], 'fake_audio_b');

      store['content_zone_source_audio'] = 'no_longer_exists';
      final restored = fakeBinding(store: store);
      expect(restored.sourceFor(ContentSection.audio)?.id, 'fake_audio_a');
    });

    test('真实注册表默认源与锁定清单一致', () {
      final binding = ContentZoneBinding();
      for (final section in ContentSection.values) {
        expect(
          binding.sourcesFor(section).map((s) => s.id),
          ContentRegistry.sourcesFor(section).map((s) => s.id),
        );
      }
      expect(binding.sourceFor(ContentSection.audio)?.id, 'tingshuwang');
    });
  });

  group('ContentZoneScreen 听书', () {
    Widget host(ContentZoneBinding binding, ContentSection section) =>
        MaterialApp(
          home: Scaffold(
            body: ContentZoneScreen(section: section, binding: binding),
          ),
        );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('选择器只列本区源，点选只改本区且落盘', (tester) async {
      final store = <String, String>{};
      final binding = fakeBinding(store: store);
      await tester.pumpWidget(host(binding, ContentSection.audio));
      await settle(tester);
      expect(find.text('听书甲'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('content-source-switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('听书乙'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('site-picker-row-fake_audio_b')),
      );
      await settle(tester);
      expect(find.text('听书乙'), findsOneWidget);
      expect(find.text('听书乙-作品'), findsOneWidget);
      expect(binding.sourceFor(ContentSection.audio)?.id, 'fake_audio_b');
      expect(store['content_zone_source_audio'], 'fake_audio_b');
    });

    testWidgets('重进保留已选源（听书双源不回归）', (tester) async {
      final binding = fakeBinding();
      await tester.pumpWidget(host(binding, ContentSection.audio));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('content-source-switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey('site-picker-row-fake_audio_b')),
      );
      await settle(tester);
      expect(find.text('听书乙'), findsOneWidget);

      await tester.pumpWidget(host(binding, ContentSection.audio));
      await settle(tester);
      expect(find.text('听书乙'), findsOneWidget);
      expect(find.text('听书乙-作品'), findsOneWidget);
    });
  });
}
