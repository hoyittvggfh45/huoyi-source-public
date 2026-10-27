import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'manifest.dart';

class MiniAppInstaller {
  MiniAppInstaller(this.root);
  final Directory root;

  Directory directoryFor(String id) => Directory(p.join(root.path, id));

  Future<List<MiniAppManifest>> list() async {
    if (!await root.exists()) return [];
    final out = <MiniAppManifest>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      try {
        out.add(await load(entity));
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Future<MiniAppManifest> load(Directory directory) async {
    final text = await File(
      p.join(directory.path, 'manifest.json'),
    ).readAsString();
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('miniapp manifest must be a JSON object');
    }
    return MiniAppManifest.fromJson(decoded);
  }

  Future<MiniAppManifest> install({
    required String manifestJson,
    required Directory files,
  }) async {
    final decoded = jsonDecode(manifestJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('miniapp manifest must be a JSON object');
    }
    final manifest = MiniAppManifest.fromJson(decoded);
    if (!await files.exists()) {
      throw ArgumentError(
        'miniapp files directory does not exist: ${files.path}',
      );
    }
    final target = directoryFor(manifest.id);
    if (await target.exists()) {
      await target.delete(recursive: true);
    }
    await target.create(recursive: true);
    await for (final entity in files.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: files.path);
      if (relative == 'manifest.json') continue;
      final dest = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(dest).create(recursive: true);
      } else if (entity is File) {
        await File(dest).create(recursive: true);
        await entity.copy(dest);
      }
    }
    await File(
      p.join(target.path, 'manifest.json'),
    ).writeAsString(manifestJson);
    return manifest;
  }

  Future<MiniAppManifest> installFromZip(
    List<int> bytes, {
    String? expectedMd5,
  }) async {
    if (expectedMd5 != null && expectedMd5.isNotEmpty) {
      final actual = md5.convert(bytes).toString().toLowerCase();
      if (actual != expectedMd5.toLowerCase()) {
        throw const FormatException('miniapp package md5 mismatch');
      }
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('miniapp package is not a valid zip');
    }
    final temp = await Directory.systemTemp.createTemp('jhminiapp_zip_');
    try {
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final name = file.name.replaceAll('\\', '/');
        if (name.startsWith('/') || name.split('/').contains('..')) continue;
        final dest = File(p.join(temp.path, name));
        await dest.create(recursive: true);
        await dest.writeAsBytes(file.content);
      }
      final manifestDir = await _manifestDirectory(temp);
      final manifestFile = File(p.join(manifestDir.path, 'manifest.json'));
      final manifestJson = await manifestFile.readAsString();
      final installed = await install(
        manifestJson: manifestJson,
        files: manifestDir,
      );
      return installed;
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<Directory> _manifestDirectory(Directory root) async {
    if (await File(p.join(root.path, 'manifest.json')).exists()) return root;
    await for (final entity in root.list()) {
      if (entity is Directory &&
          await File(p.join(entity.path, 'manifest.json')).exists()) {
        return entity;
      }
    }
    throw const FormatException('miniapp package has no manifest.json');
  }

  Future<void> remove(String id) async {
    final target = directoryFor(id);
    if (await target.exists()) {
      await target.delete(recursive: true);
    }
  }
}
