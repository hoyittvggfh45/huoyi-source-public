import 'dart:convert';

import 'package:duanju_app/legado_builtin_data.dart';
import 'package:duanju_app/legado_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bom stripped', () {
    const text =
        '\uFEFF[{"bookSourceName":"A","bookSourceUrl":"https://a.example","searchUrl":"https://a.example/s"}]';
    final report = parseLegadoSourcesReport(text);
    expect(report.sources.length, 1);
    expect(report.sources.first.name, 'A');
    expect(report.dropped, isEmpty);
  });

  test('bookSources wrapper accepted', () {
    const text =
        '{"bookSources":[{"bookSourceName":"B","bookSourceUrl":"https://b.example","searchUrl":"https://b.example/s"}]}';
    final report = parseLegadoSourcesReport(text);
    expect(report.sources.length, 1);
    expect(report.sources.first.name, 'B');
  });

  test('data wrapper accepted', () {
    const text =
        '{"data":[{"bookSourceName":"C","bookSourceUrl":"https://c.example","searchUrl":"https://c.example/s"}]}';
    expect(parseLegadoSourcesReport(text).sources.length, 1);
  });

  test('sources wrapper still accepted', () {
    const text =
        '{"sources":[{"bookSourceName":"D","bookSourceUrl":"https://d.example","searchUrl":"https://d.example/s"}]}';
    expect(parseLegadoSourcesReport(text).sources.length, 1);
  });

  test('single object still accepted', () {
    const text =
        '{"bookSourceName":"E","bookSourceUrl":"https://e.example","searchUrl":"https://e.example/s"}';
    expect(parseLegadoSourcesReport(text).sources.length, 1);
  });

  test('ndjson fallback', () {
    const text =
        '{"bookSourceName":"F","bookSourceUrl":"https://f.example","searchUrl":"https://f.example/s"}\n{"bookSourceName":"G","bookSourceUrl":"https://g.example","searchUrl":"https://g.example/s"}';
    final report = parseLegadoSourcesReport(text);
    expect(report.sources.map((s) => s.name).toList(), ['F', 'G']);
  });

  test('ndjson with one bad line still succeeds', () {
    const text =
        'not json\n{"bookSourceName":"H","bookSourceUrl":"https://h.example","searchUrl":"https://h.example/s"}';
    final report = parseLegadoSourcesReport(text);
    expect(report.sources.length, 1);
    expect(report.sources.first.name, 'H');
  });

  test('invalid text still throws', () {
    expect(
      () => parseLegadoSourcesReport('not json at all'),
      throwsA(anything),
    );
  });

  test('drop reasons', () {
    const text =
        '[{"bookSourceUrl":"https://x.example","searchUrl":"https://x.example/s"},{"bookSourceName":"NoUrl","bookSourceUrl":"https://y.example"},"bad-item"]';
    final report = parseLegadoSourcesReport(text);
    expect(report.sources, isEmpty);
    expect(report.dropped.length, 3);
    expect(report.dropped[0].reason, LegadoDrop.reasonMissingName);
    expect(report.dropped[1].reason, LegadoDrop.reasonMissingSearchUrl);
    expect(report.dropped[2].reason, LegadoDrop.reasonBadShape);
  });

  test('duplicate import adds zero', () async {
    SharedPreferences.setMockInitialValues({});
    final sources = parseLegadoSources(
      '[{"bookSourceName":"Dup","bookSourceUrl":"https://d.example","searchUrl":"https://d.example/s"}]',
    );
    final first = await LegadoStore.addAll(sources);
    expect(first.length, 1);
    final second = await LegadoStore.addAll(sources);
    expect(second.length, 1);
    expect(second.length - first.length, 0);
  });

  test('old parseLegadoSources behavior unchanged', () {
    expect(
      parseLegadoSources(
        '[{"bookSourceName":"A","bookSourceUrl":"https://a.example","searchUrl":"https://a.example/s"}]',
      ).length,
      1,
    );
    expect(
      parseLegadoSources(
        '{"bookSourceName":"A","bookSourceUrl":"https://a.example","searchUrl":"https://a.example/s"}',
      ).length,
      1,
    );
  });

  test('json api source file parses with rules intact', () {
    const text =
        '{"bookSourceName":"JsonApi","bookSourceUrl":"https://j.example","searchUrl":"https://j.example/s?key={{key}}","ruleSearch":{"bookList":"\$.data.list[*]","name":"\$.title","author":"\$.author","bookUrl":"\$.url"},"ruleToc":{"tocList":"\$.data.toc[*]","chapterName":"\$.name","chapterUrl":"\$.link"},"ruleContent":{"content":"\$.data.content"}}';
    final report = parseLegadoSourcesReport(text);
    expect(report.sources.length, 1);
    expect(report.sources.first.name, 'JsonApi');
    expect(report.sources.first.rawJson, contains('bookList'));
    expect(report.dropped, isEmpty);
  });

  test('gbk import bytes fall back to gbk decode', () {
    final bytes = <int>[
      ...'[{"bookSourceName":"'.codeUnits,
      0xB2,
      0xE2,
      0xCA,
      0xD4,
      0xCA,
      0xE9,
      0xD4,
      0xB4,
      ...'","bookSourceUrl":"https://g.example","searchUrl":"https://g.example/s"}]'
          .codeUnits,
    ];
    expect(() => utf8.decode(bytes), throwsA(isA<FormatException>()));
    final decoded = decodeLegadoImportBytes(bytes);
    final report = parseLegadoSourcesReport(decoded);
    expect(report.sources.length, 1);
    expect(report.sources.first.name, '测试书源');
  });

  test('utf8 import bytes unchanged', () {
    const text =
        '[{"bookSourceName":"U","bookSourceUrl":"https://u.example","searchUrl":"https://u.example/s"}]';
    expect(decodeLegadoImportBytes(text.codeUnits), text);
  });

  test('builtin comic set is 210 including seven added rules', () {
    final decoded = jsonDecode(builtinLegadoRulesJson) as List<dynamic>;
    final comics = decoded
        .where((e) => (e as Map<String, dynamic>)['bookSourceType'] == 2)
        .toList();
    expect(decoded, hasLength(216));
    expect(comics, hasLength(210));
    final keys = comics
        .map((e) => '${e['bookSourceName']}::${e['bookSourceUrl']}')
        .toList();
    expect(keys.toSet(), hasLength(210));
    for (final name in [
      '啵乐屋🔞',
      '🔞 夜色韩漫',
      'XiuRenBox 秀人网写真',
      '美人图 写真美图',
      'MMRGB 魅色MM',
      '漫小肆韓漫',
      '4KHD 高清写真',
    ]) {
      final found = comics.where((e) => e['bookSourceName'] == name).toList();
      expect(found, hasLength(1));
      expect((found.first['searchUrl'] as String).isNotEmpty, isTrue);
    }
    expect(
      comics.where((e) => e['bookSourceName'] == '🔞 快乐图书').length,
      1,
    );
    final novels = decoded
        .where((e) => (e as Map<String, dynamic>)['bookSourceType'] != 2)
        .map((e) => (e as Map<String, dynamic>)['bookSourceName'])
        .toList();
    expect(novels, ['顶果', '趣果', '棠果', '墨果', '同果', '猫果']);
  });

  test('v3 seed merges seven new comic entries but gate blocks rerun', () async {
    const newNames = {
      '啵乐屋🔞',
      '🔞 夜色韩漫',
      'XiuRenBox 秀人网写真',
      '美人图 写真美图',
      'MMRGB 魅色MM',
      '漫小肆韓漫',
      '4KHD 高清写真',
    };
    final parsed = parseLegadoSources(builtinLegadoRulesJson);
    final oldRaw = parsed
        .where((s) => !newNames.contains(s.name))
        .map((s) => jsonDecode(s.rawJson))
        .toList();
    SharedPreferences.setMockInitialValues({
      'legado_sources_v1': jsonEncode(oldRaw),
    });
    final added = await LegadoStore.seedBuiltin();
    expect(added, 7);
    expect((await LegadoStore.load()).length, 216);
    SharedPreferences.setMockInitialValues({
      'legado_sources_v1': jsonEncode(oldRaw),
      'legado_builtin_seeded_v3': true,
    });
    expect(await LegadoStore.seedBuiltin(), 0);
    expect((await LegadoStore.load()).length, 209);
  });

  test('check reason text', () {
    expect(legadoCheckReasonText({'supported': true}), '');
    expect(
      legadoCheckReasonText({
        'supported': false,
        'unsupportedFields': [
          {'field': 'bookList', 'rule': '//div', 'reason': 'xpath'},
          {'field': 'name', 'rule': '@js:x', 'reason': 'js'},
          {'field': 'intro', 'rule': '\$..x', 'reason': 'jsonpath'},
        ],
      }),
      '搜索列表（XPath）、书名（JS）、简介（高级 JSONPath）',
    );
  });
}
