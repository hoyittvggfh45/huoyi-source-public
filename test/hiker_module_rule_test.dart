import 'dart:convert';

import 'package:duanju_app/clipboard_detect/clipboard_rule_match.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_engine.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_models.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_rule.dart';
import 'package:duanju_app/hiker_player_screen.dart';
import 'package:duanju_app/hiker_rule.dart';
import 'package:flutter_test/flutter_test.dart';

HikerMiniappRule _moduleRule() => HikerMiniappRule.fromJson({
  'title': '模块规则',
  'type': 'video',
  'url': 'hiker://empty',
  'col_type': 'movie_3',
  'class_name': '',
  'class_url': '',
  'find_rule': 'js: setResult([]);',
  'searchFind': 'js: setResult([]);',
  'search_url': 'hiker://empty',
  'detail_find_rule': 'js: setResult([]);',
});

void main() {
  test('name segment wrapper unwraps to a parseable rule', () {
    final payload = jsonEncode({
      'title': '合成规则',
      'type': 'video',
      'url': 'hiker://empty',
      'col_type': 'movie_3',
      'find_rule': 'js: setResult([]);',
      'searchFind': 'js: setResult([]);',
      'detail_find_rule': 'js: setResult([]);',
      'pages': jsonEncode([
        {'path': 'm', 'rule': 'js: 1;'},
      ]),
    });
    final text =
        '海阔视界规则分享，当前分享的是：小程序￥home_rule_v2￥base64://@合成规则名@${base64Encode(utf8.encode(payload))}';
    final match = matchClipboardRule(text);
    expect(match, isNotNull);
    expect(match!.kind, ClipboardMatchKind.hikerRuleText);
    final rules = parseHikerMiniappRules(match.payload);
    expect(rules.length, 1);
    expect(rules.first.title, '合成规则');
    expect(rules.first.pages.length, 1);
    expect(rules.first.pages.first.path, 'm');
  });

  test('pages survive storage round trip in string and list forms', () {
    final rule = HikerMiniappRule.fromJson({
      'title': '模块规则',
      'url': 'hiker://empty',
      'pages': jsonEncode([
        {'path': 'jz', 'rule': 'js: 1;'},
        {'path': 'uir', 'rule': 'js: 2;'},
      ]),
    });
    expect(rule.pages.map((p) => p.path).toList(), ['jz', 'uir']);
    final stored = HikerRule.fromJson(rule.toJson());
    expect(stored.pages.length, 2);
    final restored = HikerMiniappRule.fromJson(stored.toJson());
    expect(restored.pages.map((p) => p.path).toList(), ['jz', 'uir']);
    expect(restored.pages.first.rule, 'js: 1;');
    expect((restored.toEngineJson()['pages'] as List).length, 2);
    final listForm = HikerMiniappRule.fromJson({
      'title': '模块规则',
      'pages': [
        {'path': 'm', 'rule': 'js: 3;'},
      ],
    });
    expect(listForm.pages.length, 1);
    expect(listForm.pages.first.path, 'm');
  });

  test('module home separates navs and drops chrome cards', () async {
    String lazy(List<String> args) =>
        'hiker://lazy?args=${Uri.encodeQueryComponent(jsonEncode(args))}';
    final items = [
      {
        'title': '首页',
        'col_type': 'scroll_button',
        'url': lazy(['']),
      },
      {
        'title': '<b><font color="#17A34A">✓ 真人剧</font></b>',
        'col_type': 'scroll_button',
        'url': lazy(['real']),
      },
      {'title': '', 'col_type': 'input', 'url': ''},
      {'title': '▍热门推荐', 'col_type': 'text_icon', 'url': 'hiker://empty'},
      {
        'title': '卡一',
        'col_type': 'movie_3',
        'url': 'https://example.invalid/1',
        'pic_url': 'https://example.invalid/1.jpg',
      },
      {'col_type': 'line_blank'},
      {'title': '下一页', 'col_type': 'text_center_1', 'url': 'hiker://empty'},
    ];
    final engine = HikerMiniappEngine(
      rule: _moduleRule(),
      run: (ruleJson, action, input) async => items,
    );
    final home = await engine.home();
    expect(home.cards.map((c) => c.title).toList(), ['卡一']);
    expect(home.navs.map((n) => n.title).toList(), ['首页', '真人剧']);
    expect(home.navs.map((n) => n.sid).toList(), ['', 'real']);
  });

  test('module home encodes nav sid and page into the input url', () async {
    String? seen;
    final engine = HikerMiniappEngine(
      rule: _moduleRule(),
      run: (ruleJson, action, input) async {
        seen = input;
        return [];
      },
    );
    await engine.home();
    expect(seen, 'hiker://empty');
    await engine.home(categorySid: 'real', page: 2);
    expect(seen, 'hiker://empty?sd_cls=real&sd_page=2');
    await engine.home(page: 3);
    expect(seen, 'hiker://empty?sd_page=3');
  });

  test('module detail strips poster suffix, html tags and button items', () {
    final items = [
      const HikerDetailItem(
        title: '剧名',
        colType: 'movie_1_vertical_pic_blur',
        url: 'https://example.invalid/d/1',
        img: '',
        picUrl:
            'https://example.invalid/poster.jpg@Referer=https://example.invalid/',
        desc: '',
        actor: '演员甲',
      ),
      const HikerDetailItem(
        title: '📍 地区：中国',
        colType: 'text_1',
        url: 'hiker://empty',
        img: '',
        picUrl: '',
        desc: '',
        actor: '',
      ),
      const HikerDetailItem(
        title: '<b><font color="#098AC1">∷剧情简介\t</font></b>　　这是一段简介。',
        colType: 'rich_text',
        url: 'javascript:;',
        img: '',
        picUrl: '',
        desc: '',
        actor: '',
      ),
      const HikerDetailItem(
        title: '倒序',
        colType: 'scroll_button',
        url: 'hiker://lazy?args=%5B%22desc%22%5D',
        img: '',
        picUrl: '',
        desc: '',
        actor: '',
      ),
      const HikerDetailItem(
        title: '第1集',
        colType: 'text_3',
        url: 'https://example.invalid/play/1.mp4#isVideo=true#',
        img: '',
        picUrl: '',
        desc: '',
        actor: '',
      ),
      const HikerDetailItem(
        title: '第2集',
        colType: 'text_3',
        url: 'video://https://example.invalid/play/2',
        img: '',
        picUrl: '',
        desc: '',
        actor: '',
      ),
      const HikerDetailItem(
        title: '第3集',
        colType: 'text_3',
        url: 'toast://解析失败',
        img: '',
        picUrl: '',
        desc: '',
        actor: '',
      ),
    ];
    final detail = HikerMiniappDetail.fromItems(items);
    expect(detail.title, '剧名');
    expect(detail.poster, 'https://example.invalid/poster.jpg');
    expect(detail.actress, '演员甲');
    expect(detail.synopsis.contains('<'), isFalse);
    expect(detail.synopsis.contains('这是一段简介'), isTrue);
    expect(detail.lines.length, 1);
    expect(detail.lines.first.name, '在线播放');
    expect(detail.lines.first.episodes.map((e) => e.title).toList(), ['第1集']);
    expect(detail.unavailable.map((e) => e.title).toList(), ['第2集', '第3集']);
  });

  test('play fragment strip keeps plain urls unchanged', () {
    expect(
      stripHikerPlayFragment(
        'https://example.invalid/play/1.mp4#isVideo=true#',
      ),
      'https://example.invalid/play/1.mp4',
    );
    expect(
      stripHikerPlayFragment('https://example.invalid/play/1.m3u8'),
      'https://example.invalid/play/1.m3u8',
    );
  });
}
