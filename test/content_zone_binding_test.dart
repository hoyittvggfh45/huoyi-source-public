import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_registry.dart';
import 'package:duanju_app/content_zone_binding.dart';
import 'package:duanju_app/content_zone_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 分区源绑定回归（fix3）：用户真机实报 1.4.7 漫画/小说两区的源选择器与内容
// 都串到听书的哔哩哔哩音频。根因是三区共用同一 widget 类型且宿主切换时无 Key、
// State 又只在 initState 按 section 绑一次，section 变化后旧 State 被复用。
// 本测试落在状态/绑定层：每区可选源集合、默认源、跨区选择隔离、落盘往返，
// 以及 widget 层同位无 Key 换 section（复现原宿主路径）必须再绑新区。
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
  FakeContentSource('fake_comic_a', '漫画甲', ContentSection.comic),
  FakeContentSource('fake_comic_b', '漫画乙', ContentSection.comic),
  FakeContentSource('fake_novel_a', '小说甲', ContentSection.novel),
  FakeContentSource('fake_novel_b', '小说乙', ContentSection.novel),
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
  group('ContentZoneBinding 分区绑定', () {
    test('每区可选源只来自本区分区', () {
      final binding = fakeBinding();
      expect(binding.sourcesFor(ContentSection.audio).map((s) => s.id), [
        'fake_audio_a',
        'fake_audio_b',
      ]);
      expect(binding.sourcesFor(ContentSection.comic).map((s) => s.id), [
        'fake_comic_a',
        'fake_comic_b',
      ]);
      expect(binding.sourcesFor(ContentSection.novel).map((s) => s.id), [
        'fake_novel_a',
        'fake_novel_b',
      ]);
    });

    test('无选择时默认本区第一源', () {
      final binding = fakeBinding();
      expect(binding.sourceFor(ContentSection.audio)?.id, 'fake_audio_a');
      expect(binding.sourceFor(ContentSection.comic)?.id, 'fake_comic_a');
      expect(binding.sourceFor(ContentSection.novel)?.id, 'fake_novel_a');
    });

    test('跨区选择互不污染', () {
      final binding = fakeBinding();
      binding.select(
        ContentSection.comic,
        fakeSources.firstWhere((s) => s.id == 'fake_comic_b'),
      );
      binding.select(
        ContentSection.novel,
        fakeSources.firstWhere((s) => s.id == 'fake_novel_b'),
      );
      expect(binding.sourceFor(ContentSection.comic)?.id, 'fake_comic_b');
      expect(binding.sourceFor(ContentSection.novel)?.id, 'fake_novel_b');
      expect(binding.sourceFor(ContentSection.audio)?.id, 'fake_audio_a');
    });

    test('select 拒绝外区源与未注册源', () {
      final binding = fakeBinding();
      binding.select(
        ContentSection.comic,
        fakeSources.firstWhere((s) => s.id == 'fake_audio_b'),
      );
      expect(binding.sourceFor(ContentSection.comic)?.id, 'fake_comic_a');
      binding.select(
        ContentSection.novel,
        FakeContentSource('ghost', '幽灵源', ContentSection.novel),
      );
      expect(binding.sourceFor(ContentSection.novel)?.id, 'fake_novel_a');
    });

    test('选择落盘后新 binding 按区恢复，失效 id 回退第一源', () {
      final store = <String, String>{};
      final first = fakeBinding(store: store);
      first.select(
        ContentSection.comic,
        fakeSources.firstWhere((s) => s.id == 'fake_comic_b'),
      );
      expect(store['content_zone_source_comic'], 'fake_comic_b');
      expect(store.containsKey('content_zone_source_audio'), isFalse);

      store['content_zone_source_novel'] = 'no_longer_exists';
      final restored = fakeBinding(store: store);
      expect(restored.sourceFor(ContentSection.comic)?.id, 'fake_comic_b');
      expect(restored.sourceFor(ContentSection.novel)?.id, 'fake_novel_a');
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
      expect(binding.sourceFor(ContentSection.comic)?.id, 'dongmanla');
      expect(binding.sourceFor(ContentSection.novel), isNull);
    });
  });

  group('ContentZoneScreen 分区再绑', () {
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

    testWidgets('同位无 Key 换 section 必须显示新区源与内容（原串区路径）', (tester) async {
      final binding = fakeBinding();
      await tester.pumpWidget(host(binding, ContentSection.audio));
      await settle(tester);
      expect(find.text('听书甲'), findsOneWidget);
      expect(find.text('听书甲-作品'), findsOneWidget);

      await tester.pumpWidget(host(binding, ContentSection.comic));
      await settle(tester);
      expect(find.text('漫画甲'), findsOneWidget);
      expect(find.text('漫画甲-作品'), findsOneWidget);
      expect(find.text('听书甲'), findsNothing);
      expect(find.text('听书甲-作品'), findsNothing);

      await tester.pumpWidget(host(binding, ContentSection.novel));
      await settle(tester);
      expect(find.text('小说甲'), findsOneWidget);
      expect(find.text('小说甲-作品'), findsOneWidget);
      expect(find.text('漫画甲'), findsNothing);
    });

    testWidgets('选择器只列本区源，点选只改本区且落盘', (tester) async {
      final store = <String, String>{};
      final binding = fakeBinding(store: store);
      await tester.pumpWidget(host(binding, ContentSection.comic));
      await settle(tester);
      expect(find.text('漫画甲'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('content-source-switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('漫画乙'), findsOneWidget);
      expect(find.text('听书甲'), findsNothing);
      expect(find.text('小说甲'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('site-picker-row-fake_comic_b')),
      );
      await settle(tester);
      expect(find.text('漫画乙'), findsOneWidget);
      expect(find.text('漫画乙-作品'), findsOneWidget);
      expect(binding.sourceFor(ContentSection.comic)?.id, 'fake_comic_b');
      expect(binding.sourceFor(ContentSection.audio)?.id, 'fake_audio_a');
      expect(binding.sourceFor(ContentSection.novel)?.id, 'fake_novel_a');
      expect(store['content_zone_source_comic'], 'fake_comic_b');
    });

    testWidgets('换区再回来保留本区已选源（听书双源不回归）', (tester) async {
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

      await tester.pumpWidget(host(binding, ContentSection.novel));
      await settle(tester);
      expect(find.text('小说甲'), findsOneWidget);

      await tester.pumpWidget(host(binding, ContentSection.audio));
      await settle(tester);
      expect(find.text('听书乙'), findsOneWidget);
      expect(find.text('听书乙-作品'), findsOneWidget);
    });
  });
}
