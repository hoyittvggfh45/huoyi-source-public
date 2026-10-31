import 'dart:convert';

import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_readers.dart';
import 'package:duanju_app/legado_builtin_data.dart';
import 'package:duanju_app/legado_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNovelSource extends ContentSource {
  _FakeNovelSource(this.texts);

  final Map<String, String> texts;

  @override
  String get id => 'fake-novel';

  @override
  String get name => 'Fake Novel';

  @override
  ContentSection get section => ContentSection.novel;

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
  Future<String> chapterText(String bookId, ContentChapter chapter) async =>
      texts[chapter.id] ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builtin novel set is six sources including new ones', () {
    final sources = parseLegadoSources(
      builtinLegadoRulesJson,
    ).where((s) => s.type == '0').toList();
    expect(sources.map((s) => s.name).toSet(), {
      '顶果',
      '趣果',
      '棠果',
      '墨果',
      '同果',
      '猫果',
    });
    final tong = sources.firstWhere((s) => s.name == '同果');
    expect(tong.searchUrl, contains('/e/search/index.php'));
    final mao = sources.firstWhere((s) => s.name == '猫果');
    expect(mao.searchUrl, isEmpty);
    expect(mao.exploreUrl, isNotEmpty);
  });

  test(
    'maoguo explore and toc rules present, search and content stay missing',
    () {
      final sources = parseLegadoSources(
        builtinLegadoRulesJson,
      ).where((s) => s.type == '0').toList();
      final mao = sources.firstWhere((s) => s.name == '猫果');
      expect(mao.searchUrl, isEmpty);
      expect(mao.exploreUrl, isNotEmpty);
      final raw = jsonDecode(mao.rawJson) as Map<String, dynamic>;
      final explore = jsonDecode(raw['exploreUrl'] as String) as List<dynamic>;
      expect(
        explore.map((e) => (e as Map<String, dynamic>)['title']).toList(),
        ['全部', '男生原创', '女生原创', '出版图书', '武侠仙侠', '都市生活', '现代言情', '悬疑推理'],
      );
      for (final category in explore) {
        final url = (category as Map<String, dynamic>)['url'] as String;
        expect(url, contains('{{page}}'));
      }
      final ruleExplore = raw['ruleExplore'] as Map<String, dynamic>;
      for (final key in [
        'bookList',
        'name',
        'bookUrl',
        'coverUrl',
        'author',
        'intro',
        'kind',
      ]) {
        expect((ruleExplore[key] as String).isNotEmpty, isTrue);
      }
      final ruleToc = raw['ruleToc'] as Map<String, dynamic>;
      expect((ruleToc['chapterList'] as String).startsWith('@js:'), isTrue);
      expect(ruleToc['chapterName'], r'$.title');
      expect(ruleToc['chapterUrl'], r'$.url');
      expect(ruleToc['nextTocUrl'], isEmpty);
      expect(ruleToc.containsKey('maxTocPages'), isFalse);
      final ruleContent = raw['ruleContent'] as Map<String, dynamic>;
      expect(ruleContent['content'], isEmpty);
      expect(ruleContent['nextContentUrl'], isEmpty);
    },
  );

  test('paginate splits on paragraphs and grows with font size', () {
    final text = List.generate(
      40,
      (i) => '第${i + 1}段正文内容填充，句子拉长到约一百字以便分页能够区分字号档位的影响。',
    ).join('\n');
    final small = paginateNovelText(text, 14);
    final large = paginateNovelText(text, 24);
    expect(small.length, greaterThan(1));
    expect(large.length, greaterThanOrEqualTo(small.length));
    expect(small.join(''), contains('第1段正文内容填充，'));
  });

  test('reading progress round trips through chapter and page', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await NovelReadingProgress.load('s1', 'b1'), isNull);
    await NovelReadingProgress.save('s1', 'b1', 3, 2);
    final progress = await NovelReadingProgress.load('s1', 'b1');
    expect(progress?.chapter, 3);
    expect(progress?.page, 2);
  });

  testWidgets('novel reader shows text and switches chapter', (tester) async {
    final source = _FakeNovelSource({
      'c1': '第一章正文第一段。\n第二段。',
      'c2': '第二章正文内容。',
    });
    const book = ContentBook(id: 'b1', title: 'Book');
    const chapters = [
      ContentChapter(id: 'c1', title: '第一章'),
      ContentChapter(id: 'c2', title: '第二章'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderScreen(
          source: source,
          book: book,
          chapters: chapters,
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('第一章正文第一段。'), findsOneWidget);
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第二章正文内容。'), findsOneWidget);
    final progress = await NovelReadingProgress.load('fake-novel', 'b1');
    expect(progress?.chapter, 1);
  });
}
