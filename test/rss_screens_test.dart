import 'package:duanju_app/rss_article_screens.dart';
import 'package:duanju_app/rss_engine.dart';
import 'package:duanju_app/rss_model.dart';
import 'package:duanju_app/subscription_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _source = RssSource(
  id: 'rss_test',
  name: '测试订阅',
  sourceUrl: 'http://example.com/feed',
  ruleArticles: '.item',
  ruleTitle: 'a@text',
  ruleLink: 'a@href',
);

class _FakeEngine implements RssEngineApi {
  @override
  Future<RssListResult> fetchItems(RssSource source, {int page = 1}) async {
    return const RssListResult(
      items: [
        RssItem(title: '第一条', link: 'http://example.com/1', date: '今天'),
        RssItem(title: '第二条', link: 'http://example.com/2'),
      ],
      nextPageUrl: null,
    );
  }

  @override
  Future<RssListResult> fetchPageUrl(RssSource source, String pageUrl) async {
    return const RssListResult(items: [], nextPageUrl: null);
  }

  @override
  Future<RssArticleResult> fetchArticle(
    RssSource source,
    RssItem item,
  ) async {
    return const RssArticleResult(
      blocks: [
        RssContentBlock.text('正文第一段'),
        RssContentBlock.image('http://example.com/a.png'),
      ],
      originalLink: 'http://example.com/1',
    );
  }
}

class _EmptyArticleEngine implements RssEngineApi {
  @override
  Future<RssListResult> fetchItems(RssSource source, {int page = 1}) async {
    return const RssListResult(items: [], nextPageUrl: null);
  }

  @override
  Future<RssListResult> fetchPageUrl(RssSource source, String pageUrl) async {
    return const RssListResult(items: [], nextPageUrl: null);
  }

  @override
  Future<RssArticleResult> fetchArticle(
    RssSource source,
    RssItem item,
  ) async {
    return RssArticleResult(blocks: const [], originalLink: item.link);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('subscription empty state shows import entry', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SubscriptionScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无订阅源'), findsOneWidget);
    expect(find.text('导入订阅源'), findsOneWidget);
  });

  testWidgets('item list shows items then article blocks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RssItemListScreen(source: _source, engine: _FakeEngine()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第二条'), findsOneWidget);
    await tester.tap(find.text('第一条'));
    await tester.pumpAndSettle();
    expect(find.text('正文第一段'), findsOneWidget);
  });

  testWidgets('article without content shows original link entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RssArticleScreen(
          source: _source,
          item: const RssItem(title: '无正文', link: 'http://example.com/9'),
          engine: _EmptyArticleEngine(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('打开原文'), findsOneWidget);
  });
}
