import 'package:duanju_app/clipboard_detect/clipboard_rule_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('http link and irrelevant text do not match', () {
    expect(matchClipboardRule('http://example.invalid/app.zip'), isNull);
    expect(matchClipboardRule('https://example.invalid/rules.json'), isNull);
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
