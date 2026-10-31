import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_readers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeComicSource extends ContentSource {
  @override
  String get id => 'fake-comic';

  @override
  String get name => 'Fake Comic';

  @override
  ContentSection get section => ContentSection.comic;

  @override
  Future<List<ContentCategory>> categories() async => [];

  @override
  Future<ContentPage> catalog(String categoryId, int page) async =>
      const ContentPage(items: []);

  @override
  Future<ContentPage> search(String keyword, int page) async =>
      const ContentPage(items: []);

  @override
  Future<ContentBookDetail> detail(String bookId) async =>
      const ContentBookDetail(
        book: ContentBook(id: 'b1', title: 'Book'),
        chapters: [],
      );

  @override
  Future<List<String>> chapterPages(
    String bookId,
    ContentChapter chapter,
  ) async => [
    'https://example.test/p1.jpg',
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('comic reader shows synthetic chapter pages', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: ComicReaderScreen(
          source: _FakeComicSource(),
          book: const ContentBook(id: 'b1', title: 'Book'),
          chapters: const [
            ContentChapter(id: 'c1', title: '第1话'),
            ContentChapter(id: 'c2', title: '第2话'),
          ],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(
      MaterialApp(
        home: ComicReaderScreen(
          source: _FakeComicSource(),
          book: const ContentBook(id: 'b1', title: 'Book'),
          chapters: const [
            ContentChapter(id: 'c1', title: '第1话'),
            ContentChapter(id: 'c2', title: '第2话'),
          ],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第1话'), findsWidgets);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.byTooltip('切换分页'), findsOneWidget);
    expect(find.byTooltip('目录'), findsOneWidget);
  });
}
