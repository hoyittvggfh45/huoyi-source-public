import 'dart:async';

import 'package:flutter/material.dart';

import '../core_bridge.dart';
import '../local_store.dart';
import '../models.dart';
import 'kotv_theme.dart';

String _kotvDownloadSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
}

class KotvDownloadsPage extends StatefulWidget {
  const KotvDownloadsPage({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<KotvDownloadsPage> createState() => _KotvDownloadsPageState();
}

class _KotvDownloadsPageState extends State<KotvDownloadsPage> {
  static const _filters = [
    ('all', '全部'),
    ('downloading', '下载中'),
    ('queued', '排队中'),
    ('paused', '已暂停'),
    ('completed', '已完成'),
  ];

  Timer? _timer;
  late final int _epoch;
  List<DownloadJob> _jobs = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _busy = false;
  bool _selecting = false;
  String _filter = 'all';
  String? _error;
  final _selected = <String>{};

  bool get _allowed =>
      widget.store.profileEpoch == _epoch && widget.store.canDownload;

  List<DownloadJob> get _visible {
    final jobs = _jobs.where((job) => !job.archived).toList();
    if (_filter == 'all') return jobs;
    return jobs.where((job) => job.state == _filter).toList();
  }

  @override
  void initState() {
    super.initState();
    _epoch = widget.store.profileEpoch;
    widget.store.addListener(_changed);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.store.removeListener(_changed);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing || !_allowed) return;
    _refreshing = true;
    try {
      final jobs = await widget.repository.downloads();
      if (mounted && _allowed) {
        setState(() {
          _jobs = jobs;
          _selected.retainAll(jobs.map((job) => job.id));
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && _allowed) setState(() => _error = error.toString());
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _batch(String command) async {
    if (_busy || !_allowed) return;
    final jobs = _jobs
        .where((job) => _selected.contains(job.id))
        .where(
          (job) => switch (command) {
            'pause' => job.active,
            'resume' => job.resumable,
            'remove' => true,
            _ => false,
          },
        )
        .toList();
    if (jobs.isEmpty) {
      _message('没有适合此操作的任务');
      return;
    }
    if (command == 'remove') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '删除所选视频？',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text('共 ${jobs.length} 项，文件也会删除。需要保留视频时请改用既有下载页的清理任务。'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('保留'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('确认删除'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (accepted != true || !mounted || !_allowed) return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.repository.controlDownloadBatch(
        command,
        jobs.map((job) => job.id).toList(),
      );
      if (!mounted || !_allowed) return;
      _selected.removeAll(result.completed);
      if (result.failures.isNotEmpty) {
        _message('已处理 ${result.completed.length} 项，${result.failures.length} 项失败：${result.failures.values.first}');
      } else {
        _message('已处理 ${result.completed.length} 项');
      }
      await _refresh();
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _jobRow(DownloadJob job) {
    final selected = _selected.contains(job.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: KotvTokens.cardColor,
        borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: _selecting
                ? Checkbox(
                    value: selected,
                    onChanged: _busy
                        ? null
                        : (_) => setState(() {
                            if (selected) {
                              _selected.remove(job.id);
                            } else {
                              _selected.add(job.id);
                            }
                          }),
                  )
                : Icon(
                    job.completed
                        ? Icons.offline_pin_outlined
                        : job.state == 'failed'
                        ? Icons.error_outline
                        : Icons.downloading_rounded,
                    color: KotvTokens.primary,
                  ),
            title: Text(
              job.drama.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '第 ${job.episode.number} 集 · ${job.stateLabel} · ${_kotvDownloadSize(job.bytes)}'
              '${job.active ? ' · ${(job.progress * 100).round()}%' : ''}'
              '${job.error.isNotEmpty ? '\n${job.error}' : ''}',
            ),
          ),
          if (!job.completed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: LinearProgressIndicator(
                value: job.progress > 0 || !job.active ? job.progress : null,
                minHeight: 3,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('下载')),
        body: const Center(child: Text('当前用户无权访问下载')),
      );
    }
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? '已选 ${_selected.length} 项' : '下载'),
        actions: [
          if (_selecting)
            IconButton(
              tooltip: '全选当前',
              onPressed: _busy
                  ? null
                  : () => setState(
                      () => _selected.addAll(visible.map((job) => job.id)),
                    ),
              icon: const Icon(Icons.select_all_rounded),
            )
          else
            IconButton(
              tooltip: '多选',
              onPressed: () => setState(() => _selecting = true),
              icon: const Icon(Icons.checklist_rounded),
            ),
          if (_selecting)
            IconButton(
              tooltip: '退出多选',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _selecting = false;
                      _selected.clear();
                    }),
              icon: const Icon(Icons.close_rounded),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: KotvPastelBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  for (final entry in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.$2),
                        selected: _filter == entry.$1,
                        selectedColor: KotvTokens.primary,
                        labelStyle: TextStyle(
                          color: _filter == entry.$1
                              ? Colors.white
                              : KotvTokens.unselectedColor,
                        ),
                        onSelected: (_) =>
                            setState(() => _filter = entry.$1),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Text(
                '共 ${visible.length} 项',
                style: const TextStyle(
                  fontSize: 13,
                  color: KotvTokens.unselectedColor,
                ),
              ),
            ),
            if (_error != null && _jobs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : _error != null && _jobs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.download_outlined,
                            size: 48,
                            color: KotvTokens.unselectedColor,
                          ),
                          const SizedBox(height: 12),
                          const Text('无法读取下载记录'),
                          const SizedBox(height: 4),
                          Text(_error!),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _refresh,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : visible.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.download_outlined,
                            size: 48,
                            color: KotvTokens.unselectedColor,
                          ),
                          SizedBox(height: 12),
                          Text('还没有下载任务'),
                          SizedBox(height: 4),
                          Text(
                            '在剧集详情选择下载，或调整筛选查看其它状态。',
                            style: TextStyle(
                              color: KotvTokens.unselectedColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: visible.length,
                      itemBuilder: (_, index) => _jobRow(visible[index]),
                    ),
            ),
            if (_selecting)
              Material(
                color: Colors.white,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _selected.isEmpty || _busy
                              ? null
                              : () => _batch('pause'),
                          child: const Text('暂停'),
                        ),
                        TextButton(
                          onPressed: _selected.isEmpty || _busy
                              ? null
                              : () => _batch('resume'),
                          child: const Text('继续'),
                        ),
                        TextButton(
                          onPressed: _selected.isEmpty || _busy
                              ? null
                              : () => _batch('remove'),
                          child: const Text('删除'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _selecting = false;
                                  _selected.clear();
                                }),
                          child: const Text('退出多选'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
