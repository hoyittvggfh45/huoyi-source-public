import 'package:duanju_app/js_runtime/hiker_rule.dart';
import 'package:duanju_app/js_runtime/miniapp_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<MiniAppCard> _testCards() {
  return const [
    MiniAppCard(
      title: 'Test Card One',
      url: 'https://example.invalid/card-1',
      desc: 'First test desc',
    ),
    MiniAppCard(
      title: 'Test Card Two',
      url: 'https://example.invalid/card-2',
      desc: 'Second test desc',
    ),
    MiniAppCard(
      title: 'Test Card Three',
      url: 'https://example.invalid/card-3',
    ),
  ];
}

void main() {
  testWidgets('three column grid renders all cards', (tester) async {
    final cards = _testCards();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiniAppMovieGrid(cards: cards, columns: 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Card One'), findsOneWidget);
    expect(find.text('Test Card Two'), findsOneWidget);
    expect(find.text('Test Card Three'), findsOneWidget);
  });

  testWidgets('empty picUrl does not crash', (tester) async {
    final cards = _testCards();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiniAppMovieGrid(cards: cards, columns: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Card One'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiniAppDetailView(card: cards.first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Card One'), findsOneWidget);
  });

  testWidgets('text list renders titles and desc', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MiniAppTextList(cards: _testCards())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Card One'), findsOneWidget);
    expect(find.text('First test desc'), findsOneWidget);
    expect(find.text('Test Card Three'), findsOneWidget);
  });

  testWidgets('icon grid renders titles without tap callback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MiniAppIconGrid(cards: _testCards())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Card Two'), findsOneWidget);
    await tester.tap(find.text('Test Card Two'));
    await tester.pumpAndSettle();
    expect(find.text('Test Card Two'), findsOneWidget);
  });

  testWidgets('detail view shows synopsis and episodes', (tester) async {
    final card = const MiniAppCard(
      title: 'Detail Card',
      url: 'https://example.invalid/detail-1',
      desc: 'Detail synopsis body text',
    );
    String? tappedEpisode;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiniAppDetailView(
            card: card,
            episodes: const ['Episode 1', 'Episode 2'],
            onEpisodeTap: (episode) => tappedEpisode = episode,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Detail Card'), findsOneWidget);
    expect(find.text('简介'), findsOneWidget);
    expect(find.text('Detail synopsis body text'), findsOneWidget);
    expect(find.text('选集'), findsOneWidget);
    expect(find.text('Episode 1'), findsOneWidget);
    expect(find.text('Episode 2'), findsOneWidget);
    await tester.tap(find.text('Episode 2'));
    expect(tappedEpisode, 'Episode 2');
  });

  testWidgets('detail view hides episode section without episodes', (
    tester,
  ) async {
    final card = const MiniAppCard(
      title: 'No Episode Card',
      url: 'https://example.invalid/detail-2',
      desc: 'No episode synopsis text',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MiniAppDetailView(card: card)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No Episode Card'), findsOneWidget);
    expect(find.text('简介'), findsOneWidget);
    expect(find.text('No episode synopsis text'), findsOneWidget);
    expect(find.text('选集'), findsNothing);
  });

}
