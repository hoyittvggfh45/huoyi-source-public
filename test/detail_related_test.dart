import 'package:duanju_app/detail_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

class RelatedTestRepository extends FixtureRepository {
  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';

  @override
  Future<DramaDetail> detail(Drama drama) async {
    return DramaDetail(
      drama,
      [
        Episode({'id': '1', 'title': '第1集', 'currentEpisode': 1}, 1),
      ],
      related: [
        const Drama(
          id: 'hongguo:rel1',
          source: 'hongguo',
          title: '相关剧一',
          cover: 'https://example.test/rel1.jpg',
        ),
        const Drama(
          id: 'hongguo:rel2',
          source: 'hongguo',
          title: '相关剧二',
          cover: 'https://example.test/rel2.jpg',
        ),
      ],
    );
  }
}

void main() {
  test('detail related rows keep covers and leave coverless rows empty', () {
    final detail = DramaDetail.fromJson({
      'drama': {'id': 'test:main', 'source': 'test', 'title': '主剧'},
      'chapters': [],
      'related': [
        {
          'id': 'test:rel1',
          'source': 'test',
          'title': '相关一',
          'cover': 'https://example.test/rel1.jpg',
        },
        {'id': 'test:rel2', 'source': 'test', 'title': '相关二'},
      ],
    });
    expect(detail.related, hasLength(2));
    expect(detail.related[0].cover, 'https://example.test/rel1.jpg');
    expect(detail.related[1].cover, '');
  });

  testWidgets('detail related section sits below synopsis', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = RelatedTestRepository();
    final player = ScriptedPlayer();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: DetailScreen(
          drama: const Drama(
            id: 'hongguo:main',
            source: 'hongguo',
            title: '主剧',
            description: '主剧简介',
            cover: 'https://example.test/main.jpg',
          ),
          repository: repository,
          store: store,
          playerFactory: () => Player(platformPlayer: player),
          videoBuilder: (controls) => controls,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('简介'), findsOneWidget);
    expect(find.text('相关推荐'), findsOneWidget);
    expect(find.text('相关剧一'), findsOneWidget);
    final synopsisTop = tester.getTopLeft(find.text('简介')).dy;
    final relatedTop = tester.getTopLeft(find.text('相关推荐')).dy;
    expect(relatedTop, greaterThan(synopsisTop));
    expect(tester.takeException(), isNull);
  });
}
