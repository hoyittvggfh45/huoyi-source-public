import 'package:duanju_app/content_models.dart';
import 'package:duanju_app/content_registry.dart';
import 'package:duanju_app/content_zone_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('小说区无源时显示导入入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ContentRegistry.setNovelImports([]);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ContentZoneScreen(section: ContentSection.novel)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('小说暂无可用源'), findsOneWidget);
    expect(find.byKey(const ValueKey('novel-import-py')), findsOneWidget);
  });
}
