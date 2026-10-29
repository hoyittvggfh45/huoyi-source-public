import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_build.dart';
import '../local_store.dart';
import 'kotv_theme.dart';

class KotvBackupExportDialog extends StatefulWidget {
  const KotvBackupExportDialog({super.key, required this.store});

  final LocalStore store;

  @override
  State<KotvBackupExportDialog> createState() =>
      _KotvBackupExportDialogState();
}

class _KotvBackupExportDialogState extends State<KotvBackupExportDialog> {
  late final _name = TextEditingController(
    text:
        '$appSlug-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
  );
  bool _busy = false;
  bool _done = false;
  String _result = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final fileName = _name.text.trim();
    if (fileName.isEmpty) {
      setState(() => _result = '请填写备份文件名');
      return;
    }
    setState(() {
      _busy = true;
      _result = '';
    });
    try {
      final content = await widget.store.exportBackup();
      final saved = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: 'application/json',
      );
      if (mounted) {
        setState(() {
          _result = saved == null ? '未选择保存位置' : '备份已保存：$saved';
          _done = saved != null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _result = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '备份导出路径',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '备份文件名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '包含本地用户、追剧、历史和设置，不含视频文件。确定后选择保存位置。',
                style: TextStyle(
                  fontSize: 13,
                  color: KotvTokens.unselectedColor,
                ),
              ),
              if (_result.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_result),
              ],
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_busy) const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy || _done ? null : _export,
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
              if (_done) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class KotvBackupFileDialog extends StatefulWidget {
  const KotvBackupFileDialog({super.key, required this.store});

  final LocalStore store;

  @override
  State<KotvBackupFileDialog> createState() => _KotvBackupFileDialogState();
}

class _KotvBackupFileDialogState extends State<KotvBackupFileDialog> {
  String? _path;
  String? _content;
  String _summary = '';
  bool _busy = false;
  bool _done = false;
  String _result = '';

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null || !mounted) return;
    setState(() {
      _busy = true;
      _result = '';
      _summary = '';
    });
    try {
      final size = await file.length();
      if (size == null || size > 8 * 1024 * 1024) {
        throw const FormatException('备份文件过大或无法读取');
      }
      final content = utf8.decode(await file.readAsBytes());
      final data = widget.store.validateBackup(content);
      if (mounted) {
        setState(() {
          _path = file.path ?? file.name;
          _content = content;
          _summary =
              '包含 ${(data['profiles'] as List).length} 个用户。将替换本机的用户、追剧、观看记录和偏好设置；已下载视频保留。恢复后使用备份内的管理员密码登录。';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _result = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final content = _content;
    if (content == null) return;
    setState(() {
      _busy = true;
      _result = '';
    });
    try {
      await widget.store.importBackup(content);
      if (mounted) {
        setState(() {
          _result = '已恢复备份';
          _done = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _result = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '备份文件路径',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.folder_open_rounded, size: 20),
                label: const Text('选择备份文件'),
              ),
              if (_path != null) ...[
                const SizedBox(height: 12),
                Text(
                  _path!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: KotvTokens.unselectedColor,
                  ),
                ),
              ],
              if (_summary.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_summary),
              ],
              if (_result.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_result),
              ],
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_busy) const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy || _done || _content == null
                          ? null
                          : _restore,
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
              if (_done) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showKotvBackupExportDialog({
  required BuildContext context,
  required LocalStore store,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => KotvBackupExportDialog(store: store),
  );
}

Future<void> showKotvBackupFileDialog({
  required BuildContext context,
  required LocalStore store,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => KotvBackupFileDialog(store: store),
  );
}
