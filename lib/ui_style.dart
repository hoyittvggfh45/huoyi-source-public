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

enum VodDetailStyle {
  ant,
  immersive;

  String get storageValue => switch (this) {
    VodDetailStyle.ant => 'ant',
    VodDetailStyle.immersive => 'immersive',
  };

  String get label => switch (this) {
    VodDetailStyle.ant => '蚂蚁',
    VodDetailStyle.immersive => '沉浸',
  };

  static VodDetailStyle fromStorageValue(String? value) => switch (value) {
    'immersive' => VodDetailStyle.immersive,
    _ => VodDetailStyle.ant,
  };
}

const vodDetailStyleStorageKey = 'vodDetailStyle';

final vodDetailStyleNotifier = ValueNotifier<VodDetailStyle>(
  VodDetailStyle.ant,
);

bool _vodDetailStyleLoaded = false;

Future<void> ensureVodDetailStyleLoaded() async {
  if (_vodDetailStyleLoaded) return;
  final preferences = await SharedPreferences.getInstance();
  vodDetailStyleNotifier.value = VodDetailStyle.fromStorageValue(
    preferences.getString(vodDetailStyleStorageKey),
  );
  _vodDetailStyleLoaded = true;
}

Future<void> saveVodDetailStyle(VodDetailStyle style) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(vodDetailStyleStorageKey, style.storageValue);
  vodDetailStyleNotifier.value = style;
}

Future<void> chooseVodDetailStyle(BuildContext context) async {
  final selected = await showDialog<VodDetailStyle>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('点播区 UI 风格'),
      children: [
        RadioGroup<VodDetailStyle>(
          groupValue: vodDetailStyleNotifier.value,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in VodDetailStyle.values)
                RadioListTile<VodDetailStyle>(
                  value: style,
                  title: Text(style.label),
                  subtitle: Text(switch (style) {
                    VodDetailStyle.ant => '现有布局',
                    VodDetailStyle.immersive => '播放器卡片加选集网格详情页',
                  }),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Text('只影响点播区详情页；午夜区与短剧区不受影响'),
        ),
      ],
    ),
  );
  if (selected != null) {
    await saveVodDetailStyle(selected);
  }
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
          child: Text('只影响短剧区；午夜区固定为蚂蚁风格，点播区风格另见“点播区 UI 风格”，电视与桌面端保持现有布局'),
        ),
      ],
    ),
  );
  if (selected != null) {
    await saveDramaUiStyle(selected);
  }
}
