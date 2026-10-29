import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_page_route.dart';
import 'content_source_screen.dart';
import 'core_bridge.dart';
import 'import_center.dart';
import 'legado_gbk.dart';
import 'local_store.dart';
import 'py_spider_validator.dart';

const maxExternalPyBytes = 32 * 1024 * 1024;

class ExternalPyFile {
  const ExternalPyFile({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;

  factory ExternalPyFile.fromJson(Map<String, dynamic> json) => ExternalPyFile(
    path: json['path'] as String? ?? '',
    name: json['name'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
  );
}

class ExternalPyImportChannel {
  ExternalPyImportChannel._();

  static const _channel = MethodChannel('huoyi/pyimport');

  static Future<List<ExternalPyFile>> takePending() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('takePending');
      if (raw == null) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            ExternalPyFile.fromJson(Map<String, dynamic>.from(item)),
      ].where((file) => file.path.isNotEmpty).toList();
    } on MissingPluginException {
      return const [];
    } catch (_) {
      return const [];
    }
  }
}

class PyImportPreview {
  const PyImportPreview({
    required this.ok,
    required this.reason,
    required this.displayName,
    required this.playOnly,
    required this.filledNote,
  });

  final bool ok;
  final String reason;
  final String displayName;
  final bool playOnly;
  final String filledNote;
}

PyImportPreview describePyImportCandidate(String fileName, List<int> bytes) {
  final dot = fileName.lastIndexOf('.');
  final displayName = dot < 0 ? fileName : fileName.substring(0, dot);
  String source;
  try {
    final decoded = utf8.decode(bytes);
    source = decoded.startsWith('\uFEFF') ? decoded.substring(1) : decoded;
  } catch (_) {
    source = decodeGbkBytes(bytes);
  }
  final validation = validatePySource(source);
  if (!validation.ok) {
    return PyImportPreview(
      ok: false,
      reason: validation.message,
      displayName: displayName,
      playOnly: false,
      filledNote: '',
    );
  }
  return PyImportPreview(
    ok: true,
    reason: '',
    displayName: displayName,
    playOnly: validation.playOnly,
    filledNote: validation.filledNote,
  );
}

class ExternalPyImportListener extends StatefulWidget {
  const ExternalPyImportListener({
    super.key,
    required this.store,
    required this.repository,
    required this.child,
  });

  final LocalStore store;
  final AppRepository repository;
  final Widget child;

  @override
  State<ExternalPyImportListener> createState() =>
      _ExternalPyImportListenerState();
}

class _ExternalPyImportListenerState extends State<ExternalPyImportListener>
    with WidgetsBindingObserver {
  final _processing = <String>{};
  bool _draining = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_drain()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining || !mounted) return;
    _draining = true;
    try {
      final pending = await ExternalPyImportChannel.takePending();
      for (final file in pending) {
        if (!mounted) break;
        if (_processing.contains(file.path)) continue;
        _processing.add(file.path);
        try {
          await _handle(file);
        } finally {
          _processing.remove(file.path);
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _deleteStaged(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _showNotice(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入 py 蜘蛛'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _handle(ExternalPyFile file) async {
    List<int> bytes;
    try {
      final staged = File(file.path);
      final size = await staged.length();
      if (size <= 0 || size > maxExternalPyBytes) {
        await _showNotice(
          '文件「${file.name}」无法导入：${size <= 0 ? '文件为空' : '文件过大'}',
        );
        await _deleteStaged(file.path);
        return;
      }
      bytes = await staged.readAsBytes();
    } catch (_) {
      await _showNotice('文件「${file.name}」无法读取');
      await _deleteStaged(file.path);
      return;
    }
    final preview = describePyImportCandidate(file.name, bytes);
    if (!preview.ok) {
      await _showNotice('文件「${file.name}」不是可用的 TVBox py 蜘蛛：${preview.reason}');
      await _deleteStaged(file.path);
      return;
    }
    if (!mounted) {
      await _deleteStaged(file.path);
      return;
    }
    final confirmLines = <String>['是否导入「${file.name}」并注册为站点？'];
    if (preview.playOnly) confirmLines.add('仅播放模式。');
    if (preview.filledNote.isNotEmpty) confirmLines.add(preview.filledNote);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入 py 蜘蛛'),
        content: Text(confirmLines.join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      await _deleteStaged(file.path);
      return;
    }
    final report = await ImportEngine(
      store: widget.store,
      repository: widget.repository,
    ).importAll([ImportCandidate(name: file.name, bytes: bytes)]);
    await _deleteStaged(file.path);
    if (!mounted) return;
    final outcome = report.outcomes.isEmpty ? null : report.outcomes.first;
    final succeeded = outcome?.status == ImportOutcomeStatus.success;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(succeeded ? '导入成功' : '导入结果'),
        content: Text(
          outcome == null
              ? report.summary
              : succeeded && outcome.siteName.isNotEmpty
              ? '已注册为站点「${outcome.siteName}」\n${outcome.reason}'
              : outcome.reason,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
          if (succeeded)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  appPageRoute(
                    builder: (_) => ContentSourceScreen(
                      repository: widget.repository,
                      store: widget.store,
                    ),
                  ),
                );
              },
              child: const Text('去内容源管理'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
