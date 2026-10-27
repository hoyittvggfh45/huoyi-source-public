import 'package:duanju_app/hiker_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses home_rule password', () {
    final parsed = parseHikerPassword("海阔视界，小程序规则￥home_rule￥{'title':'VIP'}");
    expect(parsed?.identifier, 'home_rule');
    expect(parsed?.payload, "{'title':'VIP'}");
  });

  test('parses home_rule_url password', () {
    final parsed = parseHikerPassword(
      '海阔视界，小程序合集￥home_rule_url￥https://example.test/rule.json',
    );
    expect(parsed?.identifier, 'home_rule_url');
    expect(parsed?.payload, 'https://example.test/rule.json');
  });

  test('rejects non-hiker password text', () {
    expect(parseHikerPassword('名字￥home_rule￥{}'), isNull);
    expect(parseHikerPassword('{"title":"VIP"}'), isNull);
    expect(parseHikerPassword('海阔视界，名字'), isNull);
  });
}
