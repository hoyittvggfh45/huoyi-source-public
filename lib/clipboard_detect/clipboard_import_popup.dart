import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content_http.dart';
import '../miniapp/installer.dart';
import '../miniapp/manifest.dart';
import 'clipboard_rule_match.dart';

const _promptedHashKey = 'clipboard_prompted_hash_v1';
const _maxPromptedHashes = 100;

Future<bool> isClipboardPrompted(String text) async {
  final prefs = await SharedPreferences.getInstance();
  final hashes = prefs.getStringList(_promptedHashKey) ?? const [];
  return hashes.contains(clipboardPromptHash(text));
}

Future<void> markClipboardPrompted(String text) async {
  final prefs = await SharedPreferences.getInstance();
  final hashes = <String>[
    ...prefs.getStringList(_promptedHashKey) ?? const <String>[],
  ];
  final hash = clipboardPromptHash(text);
  if (!hashes.contains(hash)) {
    hashes.add(hash);
    while (hashes.length > _maxPromptedHashes) {
      hashes.removeAt(0);
    }
    await prefs.setStringList(_promptedHashKey, hashes);
  }
}

Future<bool> showClipboardImportDialog(
  BuildContext context,
  ClipboardRuleMatch match,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('温馨提示'),
      content: const Text('剪贴板检测到小程序安装包链接，是否立即下载安装？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('立即导入'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<MiniAppManifest> installAntPackageFromUrl(String url) async {
  final client = ContentHttp();
  try {
    final bytes = await client.getBytes(url);
    final docs = await getApplicationDocumentsDirectory();
    final installer = MiniAppInstaller(Directory('${docs.path}/miniapps'));
    return await installer.installFromZip(bytes);
  } finally {
    client.close();
  }
}
