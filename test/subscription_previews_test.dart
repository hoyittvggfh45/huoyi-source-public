import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:duanju_app/rss_article_screens.dart';
import 'package:duanju_app/rss_engine.dart';
import 'package:duanju_app/rss_model.dart';
import 'package:duanju_app/subscription_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (var i = 0; i < 10; i++) {
    if (tester.takeException() == null) break;
  }
}

Future<void> _capture(
  WidgetTester tester,
  Widget page,
  String name,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'PreviewCJK'),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('preview-boundary'),
          child: page,
        ),
      ),
    ),
  );
  await _settle(tester);
  final boundary =
      tester
              .element(find.byKey(const ValueKey('preview-boundary')))
              .renderObject
          as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('subscription_previews/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  expect(file.lengthSync(), greaterThan(0));
  image.dispose();
}

Directory _setupPreviewMocks() {
  final tempDir = Directory.systemTemp.createTempSync('rss_preview');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        },
      );
  return tempDir;
}

const _source = RssSource(
  id: 'rss_preview',
  name: '预览订阅源',
  sourceUrl: 'http://example.com/feed',
  ruleArticles: '.item',
  ruleTitle: 'a@text',
  ruleLink: 'a@href',
);

class _PreviewEngine implements RssEngineApi {
  @override
  Future<RssListResult> fetchItems(RssSource source, {int page = 1}) async {
    return const RssListResult(
      items: [
        RssItem(
          title: '预览条目一：今日要闻',
          link: 'http://example.com/1',
          date: '2026-11-03',
        ),
        RssItem(
          title: '预览条目二：深度报道',
          link: 'http://example.com/2',
          date: '2026-11-02',
        ),
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
        RssContentBlock.text('这是预览正文第一段，用于展示条目阅读页的排版。'),
        RssContentBlock.text('这是预览正文第二段，图片加载失败时会显示占位图标。'),
      ],
      originalLink: 'http://example.com/1',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    try {
      final subset = File('/home/hatch/workspace/huoyi_new/cjk_subset.ttf');
      final fallback = File('/tmp/preview_cjk_sc.ttf');
      final file = await subset.exists() ? subset : fallback;
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final loader = FontLoader('PreviewCJK')
        ..addFont(
          Future.value(
            ByteData.view(
              bytes.buffer,
              bytes.offsetInBytes,
              bytes.lengthInBytes,
            ),
          ),
        );
      await loader.load();
    } catch (_) {}
  });

  testWidgets('preview import', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _setupPreviewMocks();
    await _capture(tester, const SubscriptionScreen(), 'subscription_import');
  });

  testWidgets('preview list', (tester) async {
    final tempDir = _setupPreviewMocks();
    final spidersDir = Directory('${tempDir.path}/imported_spiders')
      ..createSync(recursive: true);
    File('${spidersDir.path}/preview1.json').writeAsStringSync(
      '{"sourceName": "预览订阅源", "sourceUrl": "http://example.com/feed", '
      '"ruleArticles": ".item", "ruleTitle": "a@text", "ruleLink": "a@href"}',
    );
    File('${spidersDir.path}/preview2.json').writeAsStringSync(
      '{"sourceName": "预览资讯", "sourceUrl": "http://example.com/news", '
      '"ruleArticles": ".item", "ruleTitle": "a@text", "ruleLink": "a@href"}',
    );
    SharedPreferences.setMockInitialValues({
      'rss_subscriptions': jsonEncode([
        {
          'id': 'preview1',
          'name': '预览订阅源',
          'sourceUrl': 'http://example.com/feed',
          'fileName': 'preview1.json',
        },
        {
          'id': 'preview2',
          'name': '预览资讯',
          'sourceUrl': 'http://example.com/news',
          'fileName': 'preview2.json',
        },
      ]),
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'PreviewCJK'),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('preview-boundary'),
              child: const SubscriptionScreen(),
            ),
          ),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });
    await _settle(tester);
    final boundary =
        tester
                .element(find.byKey(const ValueKey('preview-boundary')))
                .renderObject
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('subscription_previews/subscription_list.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(file.lengthSync(), greaterThan(0));
    image.dispose();
  });

  testWidgets('preview items', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _setupPreviewMocks();
    await _capture(
      tester,
      RssItemListScreen(source: _source, engine: _PreviewEngine()),
      'subscription_items',
    );
  });

  testWidgets('preview article', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _setupPreviewMocks();
    await _capture(
      tester,
      RssArticleScreen(
        source: _source,
        item: const RssItem(
          title: '预览条目一：今日要闻',
          link: 'http://example.com/1',
          date: '2026-11-03',
        ),
        engine: _PreviewEngine(),
      ),
      'subscription_article',
    );
  });
}
