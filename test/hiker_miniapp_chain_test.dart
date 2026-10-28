import 'package:duanju_app/hiker_miniapp/hiker_rule_chain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('declarative chain split', () {
    test('selector, text, html and attribute segments classify correctly', () {
      final steps = parseHikerChain(
        'div.list&&a&&Text&&div.detail&&Html&&href',
      );
      expect(steps.length, 6);
      expect(steps[0].extractor, HikerChainExtractor.selector);
      expect(steps[0].raw, 'div.list');
      expect(steps[1].extractor, HikerChainExtractor.selector);
      expect(steps[2].extractor, HikerChainExtractor.text);
      expect(steps[3].extractor, HikerChainExtractor.selector);
      expect(steps[4].extractor, HikerChainExtractor.html);
      expect(steps[5].extractor, HikerChainExtractor.attribute);
      expect(steps[5].attribute, 'href');
    });

    test('all fourteen Go engine attributes classify as attributes', () {
      for (final attribute in hikerChainAttributes) {
        final steps = parseHikerChain('div&&$attribute');
        expect(steps.length, 2);
        expect(steps[1].extractor, HikerChainExtractor.attribute);
        expect(steps[1].attribute, attribute);
      }
    });

    test('js scripts and empty rules yield no chain', () {
      expect(parseHikerChain('js: setResult([]);'), isEmpty);
      expect(parseHikerChain(''), isEmpty);
      expect(parseHikerChain('   '), isEmpty);
    });

    test('empty segments are skipped', () {
      final steps = parseHikerChain('div&&&&a');
      expect(steps.length, 2);
    });
  });

  group('link classification', () {
    test('hiker empty marker is empty and not playable', () {
      expect(classifyHikerLink('hiker://empty'), HikerLinkKind.empty);
      expect(isHikerEmptyLink('hiker://empty'), isTrue);
      expect(isPlayableHikerUrl('hiker://empty'), isFalse);
    });

    test('http and https are playable', () {
      expect(
        classifyHikerLink('https://example.invalid/a.m3u8'),
        HikerLinkKind.http,
      );
      expect(isPlayableHikerUrl('http://example.invalid/a.mp4'), isTrue);
    });

    test('other hiker links are hiker kind, not playable', () {
      expect(classifyHikerLink('hiker://search?kw=x'), HikerLinkKind.hiker);
      expect(isPlayableHikerUrl('hiker://search?kw=x'), isFalse);
    });

    test(
      'relative paths are relative, empty and unknown schemes are other',
      () {
        expect(classifyHikerLink('/movie/1'), HikerLinkKind.relative);
        expect(classifyHikerLink(''), HikerLinkKind.other);
        expect(classifyHikerLink('magnet:?xt=urn:btih:x'), HikerLinkKind.other);
      },
    );
  });

  group('page url', () {
    test('fypage is replaced by the page number', () {
      expect(
        hikerPageUrl('https://example.invalid/list/fypage', 3),
        'https://example.invalid/list/3',
      );
    });

    test('templates without fypage pass through unchanged', () {
      expect(
        hikerPageUrl('https://example.invalid/list', 3),
        'https://example.invalid/list',
      );
    });
  });

  group('url resolution', () {
    test(
      'root relative and protocol relative refs resolve against http base',
      () {
        expect(
          resolveHikerUrl('https://example.invalid/a/b', '/x/y'),
          'https://example.invalid/x/y',
        );
        expect(
          resolveHikerUrl('https://example.invalid/a/b', '//cdn.invalid/x.jpg'),
          'https://cdn.invalid/x.jpg',
        );
        expect(
          resolveHikerUrl('http://example.invalid/a', '/x'),
          'http://example.invalid/x',
        );
      },
    );

    test(
      'bare keys, hiker links and non http bases pass through unchanged',
      () {
        expect(resolveHikerUrl('https://example.invalid', 'real'), 'real');
        expect(
          resolveHikerUrl('https://example.invalid', 'hiker://empty'),
          'hiker://empty',
        );
        expect(
          resolveHikerUrl('https://example.invalid', 'https://other.invalid/x'),
          'https://other.invalid/x',
        );
        expect(resolveHikerUrl('hiker://empty##', '/x'), '/x');
        expect(resolveHikerUrl('', '/x'), '/x');
        expect(resolveHikerUrl('https://example.invalid', ''), '');
      },
    );

    test('result walker resolves url fields and leaves other fields alone', () {
      final resolved = resolveHikerResultUrls([
        {
          'title': '卡',
          'url': '/d/1',
          'pic_url': '/p/1.jpg',
          'desc': '/not-a-link',
          'nested': {'playUrl': '/m/1.m3u8'},
        },
        'plain',
      ], 'https://example.invalid/list');
      final items = resolved as List;
      final first = items.first as Map;
      expect(first['url'], 'https://example.invalid/d/1');
      expect(first['pic_url'], 'https://example.invalid/p/1.jpg');
      expect(first['desc'], '/not-a-link');
      expect(
        (first['nested'] as Map)['playUrl'],
        'https://example.invalid/m/1.m3u8',
      );
      expect(items[1], 'plain');
    });

    test('result walker decodes json strings before resolving', () {
      final resolved = resolveHikerResultUrls(
        '[{"title":"卡","url":"/d/2"}]',
        'https://example.invalid',
      );
      expect((resolved as List).first['url'], 'https://example.invalid/d/2');
      expect(
        resolveHikerResultUrls('not json', 'https://example.invalid'),
        'not json',
      );
    });
  });
}
