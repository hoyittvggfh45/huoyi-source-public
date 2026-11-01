import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/player_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('tapping a player tile persists it without the confirm button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'player': 'fongmi'});
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(store.player, 'fongmi');
    await tester.pumpWidget(
      MaterialApp(home: PlayerPickerScreen(store: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('guo 播放器'));
    await tester.pumpAndSettle();
    expect(store.player, 'guo');
  });
}
