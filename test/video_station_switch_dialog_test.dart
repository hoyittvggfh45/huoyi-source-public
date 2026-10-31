import 'package:duanju_app/video_station_list.dart';
import 'package:duanju_app/video_station_switch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video station list totals match the registry dialog counts', () {
    expect(videoStationEntries.length, 80);
    expect(
      videoStationEntries
          .where((entry) => entry.group == VideoStationGroup.green)
          .length,
      13,
    );
    expect(
      videoStationEntries
          .where((entry) => entry.group == VideoStationGroup.restricted)
          .length,
      67,
    );
    final ids = videoStationEntries.map((entry) => entry.id).toSet();
    expect(ids.length, 80);
    for (final name in [
      '豆果',
      '剧果',
      '野果',
      '帝果',
      '黄果',
      '智果',
      '故果',
      '艳果',
      '桃果',
      '柚果',
      '榴果',
      '美果',
      '城果',
      '宵果',
      '樱果',
      '露果',
      '荔果',
      '橘果',
      '枣果',
      '柠果',
      '芒果',
      '橙果',
      '角果',
      '贞果',
      '学果',
      '二果',
      '会果',
      '撩果',
      '春果',
      '波果',
      '仓果',
      '巴果',
      '杰果',
      '档果',
      '汉果',
      '番果',
      '超果',
      '熊果',
      '草果',
      '榜果',
    ]) {
      expect(
        videoStationEntries.any((entry) => entry.name == name),
        isTrue,
        reason: 'missing screenshot name $name',
      );
    }
  });

  test('hidden stations are excluded from the switch list', () {
    final visible = videoStationsVisible({'douguo', 'hongguo'});
    expect(visible.length, 78);
    expect(visible.any((entry) => entry.id == 'douguo'), isFalse);
    expect(visible.any((entry) => entry.id == 'hongguo'), isFalse);
  });

  testWidgets('switch dialog filters and returns the tapped station',
      (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showVideoStationSwitchDialog(
                  context,
                  currentId: 'jiaoguo',
                  hiddenIds: {'douguo'},
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('切换站源'), findsOneWidget);
    expect(find.text('当前：角果'), findsOneWidget);
    expect(find.text('绿色 13'), findsOneWidget);
    expect(find.text('限制级 66'), findsOneWidget);
    expect(find.text('豆果'), findsNothing);
    await tester.tap(find.text('绿色 13'));
    await tester.pumpAndSettle();
    expect(find.text('红果'), findsOneWidget);
    expect(find.text('角果'), findsNothing);
    await tester.tap(find.text('绿色 13'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('橙果'), 200);
    await tester.tap(find.text('橙果'));
    await tester.pumpAndSettle();
    expect(result, 'chengguodj');
  });

  testWidgets('switch dialog close returns null', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showVideoStationSwitchDialog(
                  context,
                  currentId: 'hongguo',
                  hiddenIds: {},
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
