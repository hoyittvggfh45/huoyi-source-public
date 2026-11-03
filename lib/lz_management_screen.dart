import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'lz_rule_store.dart';

class LzManagementScreen extends StatefulWidget {
  const LzManagementScreen({super.key, required this.store});

  final LzRuleStore store;

  @override
  State<LzManagementScreen> createState() => _LzManagementScreenState();
}

class _LzManagementScreenState extends State<LzManagementScreen> {
  List<LzRuleEntry>? _entries;
  bool? _rootReadable;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final readable = await widget.store.rootReadable;
      final entries = await widget.store.scan();
      if (!mounted) return;
      setState(() {
        _rootReadable = readable;
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importInto(LzRulePath target) async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null || picked.path == null || !mounted) return;
    try {
      await widget.store.importFile(target, File(picked.path!));
      _showMessage('已导入到 ${target.relative}');
      await _refresh();
    } catch (error) {
      _showMessage('导入失败：$error');
    }
  }

  Future<void> _deleteEntry(LzRuleEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除规则文件'),
        content: Text('确定删除 ${entry.path.relative} 吗？只删这份用户自备文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.store.deleteEntry(entry.path);
      _showMessage('已删除 ${entry.path.relative}');
      await _refresh();
    } catch (error) {
      _showMessage('删除失败：$error');
    }
  }

  String _detail(LzRuleEntry entry) {
    if (!entry.exists) return '未找到';
    final parts = <String>[];
    if (entry.count != null) parts.add('${entry.count} 条');
    if (entry.sizeBytes != null) {
      final size = entry.sizeBytes!;
      parts.add(
        size < 1024
            ? '$size 字节'
            : size < 1024 * 1024
            ? '${(size / 1024).toStringAsFixed(1)} KB'
            : '${(size / 1024 / 1024).toStringAsFixed(1)} MB',
      );
    }
    if (entry.modified != null) {
      final modified = entry.modified!;
      parts.add(
        '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')}',
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('lz 规则管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (_rootReadable == false)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '读不到设备存储',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'App 未能直接列出设备存储目录，可能是系统或容器又拦了一道。请先在系统设置里给 App 存储权限；也可以用下面每项的导入按钮，经文件选择器授权后导入。',
                          ),
                        ],
                      ),
                    ),
                  ),
                const Text(
                  '路径与 pro 完全一致，不改名、不改格式；Go 链直接按这些路径读规则。',
                ),
                const SizedBox(height: 8),
                for (final entry in _entries!)
                  Card(
                    key: ValueKey('lz-entry-${entry.path.relative}'),
                    child: ListTile(
                      title: Text(entry.path.relative),
                      subtitle: Text(_detail(entry)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!entry.exists ||
                              entry.path.kind != LzRuleKind.dir)
                            TextButton(
                              key: ValueKey(
                                'lz-import-${entry.path.relative}',
                              ),
                              onPressed: () => _importInto(entry.path),
                              child: const Text('导入'),
                            ),
                          if (entry.exists)
                            TextButton(
                              key: ValueKey(
                                'lz-delete-${entry.path.relative}',
                              ),
                              onPressed: () => _deleteEntry(entry),
                              child: const Text('删除'),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
