import 'package:flutter/material.dart';

import '../core_bridge.dart';
import '../models.dart';
import 'kotv_theme.dart';

class KotvClearCacheDialog extends StatefulWidget {
  const KotvClearCacheDialog({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<KotvClearCacheDialog> createState() => _KotvClearCacheDialogState();
}

class _KotvClearCacheDialogState extends State<KotvClearCacheDialog> {
  List<DownloadJob> _jobs = [];
  bool _loading = true;
  bool _busy = false;
  String _result = '';

  List<DownloadJob> get _clearable =>
      _jobs.where((job) => job.completed && !job.archived).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final jobs = await widget.repository.downloads();
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _result = error.toString();
        });
      }
    }
  }

  Future<void> _clearCompleted() async {
    final jobs = _clearable;
    if (jobs.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _result = '';
    });
    try {
      final result = await widget.repository.controlDownloadBatch(
        'archive',
        jobs.map((job) => job.id).toList(),
      );
      if (mounted) {
        setState(() {
          _result = result.failures.isEmpty
              ? '已清理 ${result.completed.length} 项任务，视频仍可本地播放'
              : '已清理 ${result.completed.length} 项，${result.failures.length} 项失败：${result.failures.values.first}';
        });
        await _load();
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
                '清理缓存',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else
                KotvSettingsRow(
                  title: '已完成下载任务',
                  value: _clearable.isEmpty
                      ? '暂无可清理任务'
                      : '${_clearable.length} 项 · 保留视频',
                  onTap: _clearable.isEmpty || _busy ? null : _clearCompleted,
                ),
              const SizedBox(height: 8),
              const Text(
                '其余清理项暂无对应后端，未列出。',
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
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showKotvClearCacheDialog({
  required BuildContext context,
  required AppRepository repository,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => KotvClearCacheDialog(repository: repository),
  );
}
