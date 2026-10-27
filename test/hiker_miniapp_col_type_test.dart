import 'package:duanju_app/hiker_miniapp/hiker_col_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full col_type table maps to the hikerView span grid', () {
    const expected = {
      'text_1': (HikerColKind.text, 1),
      'text_2': (HikerColKind.text, 2),
      'text_3': (HikerColKind.text, 3),
      'text_4': (HikerColKind.text, 4),
      'text_center_1': (HikerColKind.text, 1),
      'movie_1': (HikerColKind.movie, 1),
      'movie_2': (HikerColKind.movie, 2),
      'movie_3': (HikerColKind.movie, 3),
      'movie_1_left_pic': (HikerColKind.movie, 1),
      'movie_1_vertical_pic': (HikerColKind.movie, 1),
      'movie_3_marquee': (HikerColKind.movie, 3),
      'pic_1': (HikerColKind.pic, 1),
      'pic_2': (HikerColKind.pic, 2),
      'pic_3': (HikerColKind.pic, 3),
      'pic_1_full': (HikerColKind.pic, 1),
      'pic_3_square': (HikerColKind.pic, 3),
      'pic_1_card': (HikerColKind.pic, 1),
      'icon_1_search': (HikerColKind.icon, 1),
      'icon_2': (HikerColKind.icon, 2),
      'icon_2_round': (HikerColKind.icon, 2),
      'icon_4': (HikerColKind.icon, 4),
      'icon_4_card': (HikerColKind.icon, 4),
      'icon_small_3': (HikerColKind.icon, 3),
      'icon_small_4': (HikerColKind.icon, 4),
      'icon_round_4': (HikerColKind.icon, 4),
      'icon_round_small_4': (HikerColKind.icon, 4),
      'long_text': (HikerColKind.longText, 1),
      'rich_text': (HikerColKind.richText, 1),
      'avatar': (HikerColKind.avatar, 1),
      'x5_webview_single': (HikerColKind.webview, 1),
      'header': (HikerColKind.header, 1),
      'footer': (HikerColKind.footer, 1),
      'line': (HikerColKind.line, 1),
      'line_blank': (HikerColKind.blank, 1),
      'blank_block': (HikerColKind.blank, 1),
      'big_blank_block': (HikerColKind.blank, 1),
      'flex_button': (HikerColKind.flexButton, 1),
    };
    expect(expected.length, 37);
    for (final entry in expected.entries) {
      final layout = hikerColLayout(entry.key);
      expect(layout.kind, entry.value.$1, reason: entry.key);
      expect(layout.columns, entry.value.$2, reason: entry.key);
      expect(layout.blurBackground, isFalse, reason: entry.key);
    }
  });

  test('blur suffix strips to the base code and flags blur background', () {
    final layout = hikerColLayout('movie_1_vertical_pic_blur');
    expect(layout.kind, HikerColKind.movie);
    expect(layout.columns, 1);
    expect(layout.blurBackground, isTrue);
  });

  test('unknown and empty codes fall back to one unknown column', () {
    final unknown = hikerColLayout('movie_9');
    expect(unknown.kind, HikerColKind.unknown);
    expect(unknown.columns, 1);
    expect(unknown.blurBackground, isFalse);
    final empty = hikerColLayout('');
    expect(empty.kind, HikerColKind.unknown);
    expect(empty.columns, 1);
  });

  test('aspect ratio follows kind', () {
    expect(hikerColAspect(HikerColKind.movie), 0.72);
    expect(hikerColAspect(HikerColKind.pic), 0.72);
    expect(hikerColAspect(HikerColKind.icon), 1.0);
    expect(hikerColAspect(HikerColKind.avatar), 1.0);
    expect(hikerColAspect(HikerColKind.text), 2.5);
    expect(hikerColAspect(HikerColKind.unknown), 2.5);
  });
}
