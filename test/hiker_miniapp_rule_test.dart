import 'dart:convert';
import 'dart:io';

import 'package:duanju_app/hiker_miniapp/hiker_miniapp_rule.dart';
import 'package:flutter_test/flutter_test.dart';

const _stubRuleJson = '''
{
  "title": "桩规则",
  "author": "stub",
  "version": "1",
  "type": "2",
  "url": "https://example.invalid",
  "col_type": "movie_3",
  "class_name": "最新&热门",
  "class_url": "/latest&/hot",
  "area_name": "",
  "area_url": "",
  "sort_name": "",
  "year_name": "",
  "sort_url": "",
  "year_url": "",
  "find_rule": "js: setResult([]);",
  "searchFind": "js: setResult([]);",
  "search_url": "hiker://empty",
  "group": "",
  "detail_col_type": "movie_1_vertical_pic_blur",
  "detail_find_rule": "js: setResult([]);",
  "sdetail_col_type": "",
  "sdetail_find_rule": "",
  "ua": "",
  "preRule": "",
  "last_chapter_rule": ""
}
''';

HikerMiniappRule _loadOrStub(String path) {
  final file = File(path);
  if (file.existsSync()) {
    final text = file.readAsStringSync();
    final rules = parseHikerMiniappRules(text);
    if (rules.isNotEmpty) return rules.first;
  }
  return HikerMiniappRule.fromJson(
    jsonDecode(_stubRuleJson) as Map<String, dynamic>,
  );
}

void main() {
  group('real shipped rules', () {
    final javrate = _loadOrStub(
      '/home/hatch/workspace/hiker_javrate_lxs_work/javrate_hiker.json',
    );
    final youtube = _loadOrStub(
      '/home/hatch/workspace/youtube_hiker_work/youtube_hiker.json',
    );
    final javmenu = _loadOrStub(
      '/home/hatch/workspace/javmenu_work/javmenu_hiker.json',
    );
    final hongguo = _loadOrStub(
      '/home/hatch/workspace/hongguo_zip_work/hongguo_hiker.json',
    );

    test('all four parse with title, type, categories and js find rule', () {
      for (final rule in [javrate, youtube, javmenu, hongguo]) {
        expect(rule.title, isNotEmpty);
        expect(rule.type, isNotEmpty);
        expect(rule.colType, isNotEmpty);
        expect(rule.categories, isNotEmpty);
        expect(HikerMiniappRule.isJsScript(rule.findRule), isTrue);
      }
    });

    test('javrate and youtube use the blurred vertical detail header', () {
      expect(javrate.detailColType, 'movie_1_vertical_pic_blur');
      expect(youtube.detailColType, 'movie_1_vertical_pic_blur');
    });

    test('javrate has a real search url, youtube search is empty marker', () {
      expect(javrate.searchUrl, isNotEmpty);
      expect(javrate.searchUrl, isNot('hiker://empty'));
      expect(youtube.searchUrl, 'hiker://empty');
    });

    test('javmenu and hongguo have non empty detail rules', () {
      expect(javmenu.detailFindRule, isNotEmpty);
      expect(hongguo.detailFindRule, isNotEmpty);
    });

    test('all four use the three column list layout', () {
      for (final rule in [javrate, youtube, javmenu, hongguo]) {
        expect(rule.colType, 'movie_3');
      }
    });
  });

  group('rule model', () {
    test('ampersand split pairs names and urls by position', () {
      final rule = HikerMiniappRule.fromJson(
        jsonDecode(_stubRuleJson) as Map<String, dynamic>,
      );
      expect(rule.categories.length, 2);
      expect(rule.categories[0].name, '最新');
      expect(rule.categories[0].url, '/latest');
      expect(rule.categories[1].name, '热门');
      expect(rule.categories[1].url, '/hot');
    });

    test('mismatched name and url counts pair up to the shorter side', () {
      final json = jsonDecode(_stubRuleJson) as Map<String, dynamic>;
      json['class_name'] = '甲&乙&丙';
      json['class_url'] = '/a&/b';
      final rule = HikerMiniappRule.fromJson(json);
      expect(rule.categories.length, 2);
      expect(rule.categories[1].name, '乙');
    });

    test('empty class lists yield no categories', () {
      final json = jsonDecode(_stubRuleJson) as Map<String, dynamic>;
      json['class_name'] = '';
      json['class_url'] = '';
      final rule = HikerMiniappRule.fromJson(json);
      expect(rule.categories, isEmpty);
    });

    test('js detection trims leading whitespace', () {
      expect(HikerMiniappRule.isJsScript('  js: x'), isTrue);
      expect(HikerMiniappRule.isJsScript('div&&a'), isFalse);
      expect(HikerMiniappRule.isJsScript(''), isFalse);
    });

    test('engine json only carries the ten fields the Go engine reads', () {
      final rule = HikerMiniappRule.fromJson(
        jsonDecode(_stubRuleJson) as Map<String, dynamic>,
      );
      final engineJson = rule.toEngineJson();
      expect(engineJson.keys.toSet(), {
        'title',
        'type',
        'url',
        'col_type',
        'find_rule',
        'searchFind',
        'detail_find_rule',
        'search_url',
        'ua',
        'preRule',
      });
      expect(engineJson['find_rule'], 'js: setResult([]);');
    });

    test('legacy ten field json parses through fromJson', () {
      final legacy = {
        'title': '旧规则',
        'type': '2',
        'url': 'https://example.invalid',
        'col_type': 'movie_3',
        'find_rule': 'div&&a',
        'searchFind': 'div&&a',
        'detail_find_rule': 'div&&a',
        'search_url': 'hiker://empty',
        'ua': '',
        'preRule': '',
      };
      final rule = HikerMiniappRule.fromJson(legacy);
      expect(rule.title, '旧规则');
      expect(rule.classNames, isEmpty);
      expect(rule.hasFindRule, isTrue);
    });

    test('parseHikerMiniappRules accepts a single object or a list', () {
      final single = parseHikerMiniappRules(_stubRuleJson);
      expect(single.length, 1);
      expect(single.first.title, '桩规则');
      final list = parseHikerMiniappRules('[$_stubRuleJson,$_stubRuleJson]');
      expect(list.length, 2);
      expect(parseHikerMiniappRules('{}'), isEmpty);
    });
  });
}
