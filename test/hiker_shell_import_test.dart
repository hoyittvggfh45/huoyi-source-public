import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:duanju_app/hiker_miniapp/hiker_category_shell.dart';
import 'package:duanju_app/hiker_miniapp/hiker_miniapp_rule.dart';
import 'package:duanju_app/hiker_rule.dart';
import 'package:duanju_app/local_store.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

base class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile({required this.bytes, required this.uri});

  final Uint8List bytes;

  @override
  final Uri uri;

  @override
  String get name => 'rule.json';

  @override
  XFile get xFile => XFile.fromData(bytes);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _FakeFilePicker extends FilePickerPlatform {
  _FakeFilePicker(this.files);

  final List<PlatformFile> files;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => files;
}

String _ruleJson() => jsonEncode({
  'title': '导入的规则',
  'type': '2',
  'url': 'https://example.invalid',
  'col_type': 'movie_3',
  'class_name': '分类A&分类B',
  'class_url': '/a/fypage&/b/fypage',
  'area_name': '地区A',
  'area_url': '/area/a',
  'sort_name': '排序A',
  'sort_url': '/sort/a',
  'year_name': '2024',
  'year_url': '/year/2024',
  'group': '分组',
  'find_rule': 'js: setResult([]);',
  'searchFind': 'js: setResult([]);',
  'search_url': 'hiker://empty',
  'detail_col_type': 'movie_1_vertical_pic_blur',
  'detail_find_rule': 'js: setResult([]);',
  'sdetail_col_type': 'movie_1_vertical_pic',
  'sdetail_find_rule': 'js: setResult([]);',
  'last_chapter_rule': 'js: setResult([]);',
  'ua': '',
  'preRule': '',
});

Future<dynamic> _stubRun(String ruleJson, String action, String input) async {
  if (action == 'list') {
    return [
      {'title': '列表卡一', 'url': 'https://example.invalid/1'},
      {'title': '列表卡二', 'url': 'https://example.invalid/2'},
    ];
  }
  return [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late FilePickerPlatform previousPicker;

  setUpAll(() {
    previousPicker = FilePickerPlatform.instance;
  });

  tearDownAll(() {
    FilePickerPlatform.instance = previousPicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('huoyi_shell_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('hiker rule survives store round trip with categories', () {
    final rule = HikerMiniappRule.fromJson(
      jsonDecode(_ruleJson()) as Map<String, dynamic>,
    );
    final stored = HikerRule.fromJson(rule.toJson());
    final restored = HikerMiniappRule.fromJson(stored.toJson());
    expect(restored.categories.map((category) => category.name), [
      '分类A',
      '分类B',
    ]);
    expect(restored.categories.map((category) => category.url), [
      '/a/fypage',
      '/b/fypage',
    ]);
    expect(restored.areaFilters.map((filter) => filter.name), ['地区A']);
    expect(restored.sortFilters.map((filter) => filter.name), ['排序A']);
    expect(restored.yearFilters.map((filter) => filter.name), ['2024']);
    expect(restored.group, '分组');
    expect(restored.detailColType, 'movie_1_vertical_pic_blur');
    expect(restored.sdetailColType, 'movie_1_vertical_pic');
    expect(restored.sdetailFindRule, 'js: setResult([]);');
    expect(restored.lastChapterRule, 'js: setResult([]);');
  });

  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HikerCategoryShell(
          store: store,
          hikerRun: _stubRun,
          hikerRules: const [],
          initialTab: HikerMiniappTab.hiker,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntilMessage(WidgetTester tester, String needle) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining(needle).evaluate().isNotEmpty) return;
    }
  }

  testWidgets('shell imports rule file and shows category chips', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakeFilePicker([
      _FakePlatformFile(
        bytes: Uint8List.fromList(utf8.encode(_ruleJson())),
        uri: Uri.parse('content://com.example.provider/doc/1'),
      ),
    ]);
    await pumpShell(tester);
    expect(find.text('暂无海阔规则'), findsOneWidget);
    await tester.tap(find.text('导入规则文件'));
    await pumpUntilMessage(tester, '已导入 1 条海阔规则');
    expect(find.textContaining('已导入 1 条海阔规则'), findsOneWidget);
    expect(find.text('导入的规则'), findsOneWidget);
    final stored = await HikerStore.load();
    expect(stored.length, 1);
    expect(stored.first.toJson()['class_name'], '分类A&分类B');
    await tester.tap(find.text('导入的规则'));
    await tester.pumpAndSettle();
    expect(find.text('分类A'), findsOneWidget);
    expect(find.text('分类B'), findsOneWidget);
  });

  testWidgets('shell rejects invalid json without writing store', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakeFilePicker([
      _FakePlatformFile(
        bytes: Uint8List.fromList(utf8.encode('not json')),
        uri: Uri.parse('content://com.example.provider/doc/2'),
      ),
    ]);
    await pumpShell(tester);
    await tester.tap(find.text('导入规则文件'));
    await pumpUntilMessage(tester, '导入失败');
    expect(find.textContaining('导入失败'), findsOneWidget);
    expect(find.text('暂无海阔规则'), findsOneWidget);
    expect(await HikerStore.load(), isEmpty);
  });

  testWidgets('shell reports empty parse result without writing store', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakeFilePicker([
      _FakePlatformFile(
        bytes: Uint8List.fromList(utf8.encode('[]')),
        uri: Uri.parse('content://com.example.provider/doc/3'),
      ),
    ]);
    await pumpShell(tester);
    await tester.tap(find.text('导入规则文件'));
    await pumpUntilMessage(tester, '文件里没有解析出规则');
    expect(find.text('文件里没有解析出规则'), findsOneWidget);
    expect(find.text('暂无海阔规则'), findsOneWidget);
    expect(await HikerStore.load(), isEmpty);
  });
}
