import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content_http.dart';
import '../hiker_miniapp/hiker_miniapp_rule.dart';
import '../hiker_rule.dart';
import '../miniapp/installer.dart';
import '../miniapp/manifest.dart';
import 'clipboard_rule_match.dart';

class ClipboardImportFailure implements Exception {
  const ClipboardImportFailure(this.message, {this.network = false});

  final String message;
  final bool network;

  @override
  String toString() => message;
}

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
  final String body;
  final bool cloudOnly;
  switch (match.kind) {
    case ClipboardMatchKind.hikerRuleText:
      body = '剪贴板检测到小程序规则，是否立即导入？';
      cloudOnly = false;
    case ClipboardMatchKind.remoteRule:
      body = '剪贴板检测到小程序远程规则（合集/单个规则），是否立即导入？';
      cloudOnly = false;
    case ClipboardMatchKind.antPackageLink:
      body = '剪贴板检测到小程序安装包链接，是否立即下载安装？';
      cloudOnly = false;
    case ClipboardMatchKind.cloudCode:
      body = '检测到云口令，当前版本无法解析云口令（未接入云口令解析服务），暂不能导入';
      cloudOnly = true;
  }
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('温馨提示'),
      content: Text(body),
      actions: [
        if (cloudOnly)
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('关闭'),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('立即导入'),
          ),
        ],
      ],
    ),
  );
  return result ?? false;
}

Future<({List<HikerRule> merged, int imported})> importHikerRulesFromText(
  String text,
) async {
  late final List<HikerMiniappRule> rules;
  try {
    rules = parseHikerMiniappRules(text);
  } catch (_) {
    throw const ClipboardImportFailure('规则 JSON 解析失败');
  }
  if (rules.isEmpty) {
    throw const ClipboardImportFailure('未解析出规则');
  }
  final merged = await HikerStore.addAll([
    for (final rule in rules) HikerRule.fromJson(rule.toJson()),
  ]);
  return (merged: merged, imported: rules.length);
}

Future<({List<HikerRule> merged, int imported})> importHikerRulesFromUrl(
  String url,
) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme != 'https') {
    throw const ClipboardImportFailure('仅支持 https 规则地址');
  }
  final client = ContentHttp();
  final String text;
  try {
    text = await client.get(url);
  } catch (_) {
    throw const ClipboardImportFailure('网络连接错误', network: true);
  } finally {
    client.close();
  }
  return importHikerRulesFromText(text);
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
