import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:duanju_app/miniapp/installer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

base class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile({required this.bytes, required this.uri});

  final Uint8List bytes;

  @override
  final Uri uri;

  @override
  String get name => 'picked.zip';

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

Uint8List _validZip() {
  final archive = Archive()
    ..add(
      ArchiveFile.string(
        'manifest.json',
        '{"id":"picked","name":"拾取应用","entry":"index.html"}',
      ),
    )
    ..add(ArchiveFile.string('index.html', '<h1>hi</h1>'));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FilePickerPlatform previousPicker;

  setUpAll(() {
    previousPicker = FilePickerPlatform.instance;
  });

  tearDownAll(() {
    FilePickerPlatform.instance = previousPicker;
  });

  test('content uri file installs through bytes, never path', () async {
    FilePickerPlatform.instance = _FakeFilePicker([
      _FakePlatformFile(
        bytes: _validZip(),
        uri: Uri.parse('content://com.example.provider/doc/1'),
      ),
    ]);
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    expect(picked.single.path, isNull);
    final bytes = await picked.single.readAsBytes();
    final root = await Directory.systemTemp.createTemp('jhminiapp_root_');
    try {
      final manifest = await MiniAppInstaller(root).installFromZip(bytes);
      expect(manifest.id, 'picked');
      final installed = await MiniAppInstaller(root).list();
      expect(installed.map((app) => app.id), contains('picked'));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('invalid zip bytes fail install and leave list unchanged', () async {
    FilePickerPlatform.instance = _FakeFilePicker([
      _FakePlatformFile(
        bytes: Uint8List.fromList(utf8.encode('not a zip')),
        uri: Uri.parse('content://com.example.provider/doc/2'),
      ),
    ]);
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    expect(picked.single.path, isNull);
    final bytes = await picked.single.readAsBytes();
    final root = await Directory.systemTemp.createTemp('jhminiapp_root_');
    try {
      final installer = MiniAppInstaller(root);
      await expectLater(installer.installFromZip(bytes), throwsFormatException);
      expect(await installer.list(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
