import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DramaUiStyle {
  fullscreen,
  ant,
  drama;

  String get storageValue => switch (this) {
    DramaUiStyle.fullscreen => 'fullscreen',
    DramaUiStyle.ant => 'ant',
    DramaUiStyle.drama => 'drama',
  };

  String get label => switch (this) {
    DramaUiStyle.fullscreen => '首页全屏',
    DramaUiStyle.ant => '蚂蚁',
    DramaUiStyle.drama => '短剧',
  };

  static DramaUiStyle fromStorageValue(String? value) => switch (value) {
    'fullscreen' => DramaUiStyle.fullscreen,
    'drama' => DramaUiStyle.drama,
    _ => DramaUiStyle.ant,
  };
}

const dramaUiStyleStorageKey = 'dramaUiStyle';

final dramaUiStyleNotifier = ValueNotifier<DramaUiStyle>(DramaUiStyle.ant);

bool _dramaUiStyleLoaded = false;

Future<void> ensureDramaUiStyleLoaded() async {
  if (_dramaUiStyleLoaded) return;
  final preferences = await SharedPreferences.getInstance();
  dramaUiStyleNotifier.value = DramaUiStyle.fromStorageValue(
    preferences.getString(dramaUiStyleStorageKey),
  );
  _dramaUiStyleLoaded = true;
}

Future<void> saveDramaUiStyle(DramaUiStyle style) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(dramaUiStyleStorageKey, style.storageValue);
  dramaUiStyleNotifier.value = style;
}

Future<void> chooseDramaUiStyle(BuildContext context) async {
  final selected = await showDialog<DramaUiStyle>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('短剧区风格'),
      children: [
        RadioGroup<DramaUiStyle>(
          groupValue: dramaUiStyleNotifier.value,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in DramaUiStyle.values)
                RadioListTile<DramaUiStyle>(
                  value: style,
                  title: Text(style.label),
                  subtitle: Text(switch (style) {
                    DramaUiStyle.fullscreen => '短剧区默认全屏上下滑播放',
                    DramaUiStyle.ant => '抽屉导航，现有布局',
                    DramaUiStyle.drama => '精选横幅加分区卡片，底部导航',
                  }),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Text('只影响短剧区；午夜区固定为蚂蚁风格，电视与桌面端保持现有布局'),
        ),
      ],
    ),
  );
  if (selected != null) {
    await saveDramaUiStyle(selected);
  }
}
