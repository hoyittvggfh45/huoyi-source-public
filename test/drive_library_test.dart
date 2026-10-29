import 'package:duanju_app/drive_library.dart';
import 'package:duanju_app/drive_library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    driveLibraryRegistry.unregister('test-a');
    driveLibraryRegistry.unregister('test-b');
  });

  test('register appends and same id replaces', () {
    driveLibraryRegistry.register(
      const DriveLibrarySourceDescriptor(
        id: 'test-a',
        kind: DriveKind.webdav,
        name: '测试盘A',
      ),
    );
    expect(driveLibraryRegistry.sources.length, 1);
    driveLibraryRegistry.register(
      const DriveLibrarySourceDescriptor(
        id: 'test-a',
        kind: DriveKind.alist,
        name: '测试盘A改名',
      ),
    );
    expect(driveLibraryRegistry.sources.length, 1);
    expect(driveLibraryRegistry.sources.single.name, '测试盘A改名');
    expect(driveLibraryRegistry.sources.single.kind, DriveKind.alist);
  });

  test('unregister removes and reports', () {
    driveLibraryRegistry.register(
      const DriveLibrarySourceDescriptor(
        id: 'test-a',
        kind: DriveKind.webdav,
        name: '测试盘A',
      ),
    );
    expect(driveLibraryRegistry.unregister('test-a'), isTrue);
    expect(driveLibraryRegistry.unregister('test-a'), isFalse);
    expect(driveLibraryRegistry.sources, isEmpty);
  });

  test('sources list is unmodifiable', () {
    driveLibraryRegistry.register(
      const DriveLibrarySourceDescriptor(
        id: 'test-a',
        kind: DriveKind.webdav,
        name: '测试盘A',
      ),
    );
    expect(
      () => driveLibraryRegistry.sources.add(
        const DriveLibrarySourceDescriptor(
          id: 'test-b',
          kind: DriveKind.alist,
          name: '测试盘B',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  testWidgets('empty registry shows empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DriveLibraryScreen()));
    expect(find.byKey(const ValueKey('drive-library-empty')), findsOneWidget);
    expect(find.text('尚未接入网盘源'), findsOneWidget);
    expect(find.text('文件列表'), findsOneWidget);
  });

  testWidgets('mode toggle switches list header', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DriveLibraryScreen()));
    await tester.tap(find.byKey(const ValueKey('drive-mode-media')));
    await tester.pump();
    expect(find.text('媒体库'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('drive-mode-files')));
    await tester.pump();
    expect(find.text('文件列表'), findsOneWidget);
  });

  testWidgets('source without browser shows pending and does not push', (
    tester,
  ) async {
    driveLibraryRegistry.register(
      const DriveLibrarySourceDescriptor(
        id: 'test-a',
        kind: DriveKind.webdav,
        name: '测试盘A',
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: DriveLibraryScreen()));
    expect(find.byKey(const ValueKey('drive-source-test-a')), findsOneWidget);
    expect(find.text('即将接入'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drive-source-test-a')));
    await tester.pump();
    expect(find.byKey(const ValueKey('drive-source-test-a')), findsOneWidget);
    expect(find.text('即将接入'), findsOneWidget);
  });

  testWidgets('source with browser pushes on tap', (tester) async {
    driveLibraryRegistry.register(
      DriveLibrarySourceDescriptor(
        id: 'test-a',
        kind: DriveKind.alist,
        name: '测试盘A',
        browser: (_) => const Scaffold(body: Text('browser-body')),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: DriveLibraryScreen()));
    await tester.tap(find.byKey(const ValueKey('drive-source-test-a')));
    await tester.pumpAndSettle();
    expect(find.text('browser-body'), findsOneWidget);
  });

  testWidgets('filter chip narrows visible sources', (tester) async {
    driveLibraryRegistry.register(
      const DriveLibrarySourceDescriptor(
        id: 'test-a',
        kind: DriveKind.webdav,
        name: '测试盘A',
      ),
    );
    driveLibraryRegistry.register(
      const DriveLibrarySourceDescriptor(
        id: 'test-b',
        kind: DriveKind.alist,
        name: '测试盘B',
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: DriveLibraryScreen()));
    expect(find.byKey(const ValueKey('drive-source-test-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('drive-source-test-b')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drive-filter-test-b')));
    await tester.pump();
    expect(find.byKey(const ValueKey('drive-source-test-a')), findsNothing);
    expect(find.byKey(const ValueKey('drive-source-test-b')), findsOneWidget);
  });
}
