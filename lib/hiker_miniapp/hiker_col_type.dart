enum HikerColKind {
  text,
  movie,
  pic,
  icon,
  header,
  footer,
  line,
  blank,
  flexButton,
  webview,
  avatar,
  longText,
  richText,
  unknown,
}

class HikerColLayout {
  const HikerColLayout({
    required this.kind,
    required this.columns,
    required this.blurBackground,
  });

  final HikerColKind kind;
  final int columns;
  final bool blurBackground;
}

class _HikerColEntry {
  const _HikerColEntry(this.kind, this.span);

  final HikerColKind kind;
  final int span;
}

const Map<String, _HikerColEntry> _hikerColTable = {
  'text_1': _HikerColEntry(HikerColKind.text, 12),
  'text_2': _HikerColEntry(HikerColKind.text, 6),
  'text_3': _HikerColEntry(HikerColKind.text, 4),
  'text_4': _HikerColEntry(HikerColKind.text, 3),
  'text_center_1': _HikerColEntry(HikerColKind.text, 12),
  'movie_1': _HikerColEntry(HikerColKind.movie, 12),
  'movie_2': _HikerColEntry(HikerColKind.movie, 6),
  'movie_3': _HikerColEntry(HikerColKind.movie, 4),
  'movie_1_left_pic': _HikerColEntry(HikerColKind.movie, 12),
  'movie_1_vertical_pic': _HikerColEntry(HikerColKind.movie, 12),
  'movie_3_marquee': _HikerColEntry(HikerColKind.movie, 4),
  'pic_1': _HikerColEntry(HikerColKind.pic, 12),
  'pic_2': _HikerColEntry(HikerColKind.pic, 6),
  'pic_3': _HikerColEntry(HikerColKind.pic, 4),
  'pic_1_full': _HikerColEntry(HikerColKind.pic, 12),
  'pic_3_square': _HikerColEntry(HikerColKind.pic, 4),
  'pic_1_card': _HikerColEntry(HikerColKind.pic, 12),
  'icon_1_search': _HikerColEntry(HikerColKind.icon, 12),
  'icon_2': _HikerColEntry(HikerColKind.icon, 6),
  'icon_2_round': _HikerColEntry(HikerColKind.icon, 6),
  'icon_4': _HikerColEntry(HikerColKind.icon, 3),
  'icon_4_card': _HikerColEntry(HikerColKind.icon, 3),
  'icon_small_3': _HikerColEntry(HikerColKind.icon, 4),
  'icon_small_4': _HikerColEntry(HikerColKind.icon, 3),
  'icon_round_4': _HikerColEntry(HikerColKind.icon, 3),
  'icon_round_small_4': _HikerColEntry(HikerColKind.icon, 3),
  'long_text': _HikerColEntry(HikerColKind.longText, 12),
  'rich_text': _HikerColEntry(HikerColKind.richText, 12),
  'avatar': _HikerColEntry(HikerColKind.avatar, 12),
  'x5_webview_single': _HikerColEntry(HikerColKind.webview, 12),
  'header': _HikerColEntry(HikerColKind.header, 12),
  'footer': _HikerColEntry(HikerColKind.footer, 12),
  'line': _HikerColEntry(HikerColKind.line, 12),
  'line_blank': _HikerColEntry(HikerColKind.blank, 12),
  'blank_block': _HikerColEntry(HikerColKind.blank, 12),
  'big_blank_block': _HikerColEntry(HikerColKind.blank, 12),
  'flex_button': _HikerColEntry(HikerColKind.flexButton, 12),
};

HikerColLayout hikerColLayout(String colType) {
  var code = colType.trim();
  var blur = false;
  if (code.endsWith('_blur')) {
    blur = true;
    code = code.substring(0, code.length - 5);
  }
  final entry = _hikerColTable[code];
  if (entry == null) {
    var columns = 3;
    if (code.contains('_4_') || code.endsWith('_4')) {
      columns = 4;
    } else if (code.contains('_2_') || code.endsWith('_2')) {
      columns = 2;
    }
    final kind = code.contains('movie') || code.contains('pic')
        ? HikerColKind.movie
        : code.contains('icon') || code.contains('avatar')
        ? HikerColKind.icon
        : HikerColKind.unknown;
    return HikerColLayout(kind: kind, columns: columns, blurBackground: blur);
  }
  final columns = 12 ~/ entry.span;
  return HikerColLayout(
    kind: entry.kind,
    columns: columns < 1 ? 1 : columns,
    blurBackground: blur,
  );
}

double hikerColAspect(HikerColKind kind) {
  switch (kind) {
    case HikerColKind.movie:
    case HikerColKind.pic:
      return 0.72;
    case HikerColKind.icon:
    case HikerColKind.avatar:
      return 1.0;
    default:
      return 2.5;
  }
}
