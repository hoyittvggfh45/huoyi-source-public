import 'dart:convert';

import 'package:duanju_app/clipboard_detect/clipboard_rule_match.dart';
import 'package:flutter_test/flutter_test.dart';

String _ruleJson({String title = '剪切板规则'}) => jsonEncode({
  'title': title,
  'type': '2',
  'url': 'https://example.invalid',
  'col_type': 'movie_3',
  'find_rule': 'x',
});

void main() {
  test('home_rule matches without prefix requirement', () {
    final match = matchClipboardRule('分享￥home_rule￥${_ruleJson()}');
    expect(match, isNotNull);
    expect(match!.kind, ClipboardMatchKind.hikerRuleText);
    expect(match.payload, _ruleJson());
  });

  test('home_rule payload rejoins extra segments', () {
    final match = matchClipboardRule('a￥home_rule￥{"x":1}￥tail');
    expect(match, isNotNull);
    expect(match!.payload, '{"x":1}￥tail');
  });

  test('home_rule_v2 decodes base64 payload', () {
    final encoded = base64Encode(utf8.encode(_ruleJson(title: 'V2规则')));
    final match = matchClipboardRule('分享￥home_rule_v2￥base64://@某规则@$encoded');
    expect(match, isNotNull);
    expect(match!.kind, ClipboardMatchKind.hikerRuleText);
    expect(match.payload, _ruleJson(title: 'V2规则'));
  });

  test('home_rule_v2 decode failure does not match', () {
    expect(matchClipboardRule('分享￥home_rule_v2￥base64://@某规则@!!!'), isNull);
    expect(matchClipboardRule('分享￥home_rule_v2￥no-at-sign'), isNull);
  });

  test('trailing yen sign is stripped from v1 and v2 payloads', () {
    final v1 = matchClipboardRule('分享￥home_rule￥${_ruleJson()}￥');
    expect(v1, isNotNull);
    expect(v1!.payload, _ruleJson());
    final encoded = base64Encode(utf8.encode(_ruleJson(title: 'V2规则')));
    final v2 = matchClipboardRule('分享￥home_rule_v2￥base64://@某规则@$encoded￥');
    expect(v2, isNotNull);
    expect(v2!.payload, _ruleJson(title: 'V2规则'));
  });

  test('unknown identifier with json payload still matches', () {
    final match = matchClipboardRule('分享￥home_bookmark￥${_ruleJson()}');
    expect(match, isNotNull);
    expect(match!.kind, ClipboardMatchKind.hikerRuleText);
    expect(match.payload, _ruleJson());
  });

  test('bare yen wrapped json matches', () {
    final wrapped = matchClipboardRule('￥${_ruleJson()}￥');
    expect(wrapped, isNotNull);
    expect(wrapped!.payload, _ruleJson());
    final trailing = matchClipboardRule('${_ruleJson()}￥');
    expect(trailing, isNotNull);
    expect(trailing!.payload, _ruleJson());
    final leading = matchClipboardRule('￥${_ruleJson()}');
    expect(leading, isNotNull);
    expect(leading!.payload, _ruleJson());
  });

  test('home_rule_url and home_sub match remote rule', () {
    final urlMatch = matchClipboardRule(
      '分享￥home_rule_url￥https://example.invalid/rules.json',
    );
    expect(urlMatch, isNotNull);
    expect(urlMatch!.kind, ClipboardMatchKind.remoteRule);
    expect(urlMatch.payload, 'https://example.invalid/rules.json');
    final subMatch = matchClipboardRule(
      '分享￥home_sub￥https://example.invalid/sub.json',
    );
    expect(subMatch, isNotNull);
    expect(subMatch!.kind, ClipboardMatchKind.remoteRule);
  });

  test('unknown password identifier does not match', () {
    expect(
      matchClipboardRule('a￥home_bookmark￥https://example.invalid'),
      isNull,
    );
    expect(matchClipboardRule('a￥home_rule'), isNull);
  });

  test('raw rule json matches object and array', () {
    final objectMatch = matchClipboardRule(_ruleJson());
    expect(objectMatch, isNotNull);
    expect(objectMatch!.kind, ClipboardMatchKind.hikerRuleText);
    final arrayMatch = matchClipboardRule('[${_ruleJson()}]');
    expect(arrayMatch, isNotNull);
    expect(arrayMatch!.kind, ClipboardMatchKind.hikerRuleText);
  });

  test('raw json without title or url does not match', () {
    expect(matchClipboardRule('{"foo":1}'), isNull);
    expect(matchClipboardRule('{not json'), isNull);
    expect(matchClipboardRule('[]'), isNull);
  });

  test('cloud code shape matches hint kind', () {
    final match = matchClipboardRule('云abc123/xyz789');
    expect(match, isNotNull);
    expect(match!.kind, ClipboardMatchKind.cloudCode);
  });

  test('cloud code shape rejects spaces long text and missing slash', () {
    expect(matchClipboardRule('云abc 123/xyz'), isNull);
    expect(matchClipboardRule('云abc123'), isNull);
    expect(matchClipboardRule('abc123/xyz789'), isNull);
    expect(matchClipboardRule('云${'a' * 200}/x'), isNull);
  });

  test('https zip link routes to ant install', () {
    final match = matchClipboardRule('https://example.invalid/app.zip');
    expect(match, isNotNull);
    expect(match!.kind, ClipboardMatchKind.antPackageLink);
    final queryMatch = matchClipboardRule(
      'https://example.invalid/app.ZIP?token=1',
    );
    expect(queryMatch, isNotNull);
    expect(queryMatch!.kind, ClipboardMatchKind.antPackageLink);
  });

  test('https non-zip link routes to remote rule', () {
    final match = matchClipboardRule('https://example.invalid/rules.json');
    expect(match, isNotNull);
    expect(match!.kind, ClipboardMatchKind.remoteRule);
  });

  test('http link and irrelevant text do not match', () {
    expect(matchClipboardRule('http://example.invalid/app.zip'), isNull);
    expect(matchClipboardRule('今天天气不错，晚上去散步'), isNull);
    expect(matchClipboardRule('123456'), isNull);
    expect(matchClipboardRule(''), isNull);
    expect(matchClipboardRule(null), isNull);
  });

  test('prompt hash is stable hex and differs by input', () {
    final first = clipboardPromptHash('abc');
    final second = clipboardPromptHash('abc');
    final other = clipboardPromptHash('abd');
    expect(first, second);
    expect(first, isNot(other));
    expect(first.length, 16);
    expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(first), isTrue);
  });
}
