import 'dart:io';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class CoverFixtureRepository extends FixtureRepository {
  final attempts = <bool>[];

  @override
  Future<String> cover(Drama drama, {bool force = false}) async {
    attempts.add(force);
    if (!force) {
      throw AppFailure('合成海报首次请求失败');
    }
    return File('test/fixtures/cover.png').absolute.path;
  }
}

class ProxyCoverRepository extends FixtureRepository {
  final seenCovers = <String>[];

  @override
  Future<String> cover(Drama drama, {bool force = false}) async {
    seenCovers.add(drama.cover);
    return File('test/fixtures/cover.png').absolute.path;
  }
}

const proxyCoverDrama = Drama(
  id: 'hghub:12',
  source: 'hghub',
  title: '代理封面测试',
  episodes: 1,
  cover: 'proxy://do=py&siteKey=hghub&u=https%3A%2F%2Fexample.com%2Fcover.jpg',
);

void main() {
  testWidgets('failed cover can retry and render a decoded local file', (
    tester,
  ) async {
    final repository = CoverFixtureRepository();
    final widget = MaterialApp(
      home: SizedBox(
        width: 100,
        height: 150,
        child: CachedCoverImage(
          drama: FixtureRepository.free,
          repository: repository,
          placeholder: const SizedBox(),
        ),
      ),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    expect(find.byTooltip('重试海报'), findsOneWidget);
    Object? decodeFailure;
    await tester.runAsync(() async {
      await precacheImage(
        ResizeImage.resizeIfNeeded(
          440,
          null,
          FileImage(File('test/fixtures/cover.png').absolute),
        ),
        tester.element(find.byType(CachedCoverImage)),
        onError: (error, stack) => decodeFailure = error,
      );
    });
    expect(decodeFailure, isNull);
    await tester.tap(find.byTooltip('重试海报'));
    await tester.pumpAndSettle();
    expect(repository.attempts, [false, true]);
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.imageProvider, isA<FileImage>());
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    expect(repository.attempts, [false, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('proxy cover goes through repository cover and renders a file',
      (tester) async {
    final repository = ProxyCoverRepository();
    final widget = MaterialApp(
      home: SizedBox(
        width: 100,
        height: 150,
        child: DramaCover(drama: proxyCoverDrama, repository: repository),
      ),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    expect(
      repository.seenCovers,
      ['proxy://do=py&siteKey=hghub&u=https%3A%2F%2Fexample.com%2Fcover.jpg'],
    );
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.imageProvider, isA<FileImage>());
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('proxy cover renders through cached cover image', (tester) async {
    final repository = ProxyCoverRepository();
    final widget = MaterialApp(
      home: SizedBox(
        width: 100,
        height: 150,
        child: CachedCoverImage(
          drama: proxyCoverDrama,
          repository: repository,
          placeholder: const SizedBox(),
        ),
      ),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    expect(
      repository.seenCovers,
      ['proxy://do=py&siteKey=hghub&u=https%3A%2F%2Fexample.com%2Fcover.jpg'],
    );
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.imageProvider, isA<FileImage>());
    expect(tester.takeException(), isNull);
  });
}
