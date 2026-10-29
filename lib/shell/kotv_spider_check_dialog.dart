import 'dart:async';

import 'package:flutter/material.dart';

import '../core_bridge.dart';
import '../local_store.dart';
import '../models.dart';
import 'kotv_theme.dart';

class _KotvSpiderCheckEntry {
  _KotvSpiderCheckEntry(this.source);

  final SourceSite source;
  String state = 'waiting';
  String message = '';
  int elapsedMs = 0;
  bool disabled = false;
}

class KotvSpiderCheckDialog extends StatefulWidget {
  const KotvSpiderCheckDialog({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<KotvSpiderCheckDialog> createState() => _KotvSpiderCheckDialogState();
}

class _KotvSpiderCheckDialogState extends State<KotvSpiderCheckDialog> {
  late final List<_KotvSpiderCheckEntry> _entries;
  bool _cancelled = false;
  bool _running = true;

  int get _checked =>
      _entries.where((entry) => entry.state != 'waiting').length;
  int get _failed =>
      _entries.where((entry) => entry.state == 'failed').length;

  @override
  void initState() {
    super.initState();
    _entries = [
      for (final source in widget.store.sources)
        _KotvSpiderCheckEntry(source)
          ..disabled = !widget.store.siteVisible(source.id),
    ];
    unawaited(_run());
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _run() async {
    for (final entry in _entries) {
      if (_cancelled || !mounted) return;
      final stopwatch = Stopwatch()..start();
      try {
        final page = await widget.repository
            .catalog(entry.source.id, page: 1)
            .timeout(const Duration(seconds: 30));
        stopwatch.stop();
        if (_cancelled || !mounted) return;
        setState(() {
          entry.elapsedMs = stopwatch.elapsedMilliseconds;
          if (page.items.isEmpty) {
            entry.state = 'empty';
            entry.message = '目录为空（0 条）';
          } else {
            entry.state = 'ok';
            entry.message = '${page.items.length} 条 · ${stopwatch.elapsedMilliseconds} 毫秒';
          }
        });
      } catch (error) {
        stopwatch.stop();
        if (_cancelled || !mounted) return;
        setState(() {
          entry.elapsedMs = stopwatch.elapsedMilliseconds;
          entry.state = 'failed';
          entry.message = error is TimeoutException
              ? '超时（30 秒）'
              : error.toString();
        });
      }
    }
    if (mounted) setState(() => _running = false);
  }

  Future<void> _disable(_KotvSpiderCheckEntry entry) async {
    try {
      await widget.store.setSiteVisible(entry.source.id, false);
      if (mounted) setState(() => entry.disabled = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Widget _row(_KotvSpiderCheckEntry entry) {
    final icon = switch (entry.state) {
      'ok' => const Icon(Icons.check_circle_rounded, color: Colors.green),
      'empty' => const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      'failed' => const Icon(Icons.error_outline_rounded, color: Colors.red),
      _ => const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.source.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.message.isNotEmpty)
                  Text(
                    entry.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: KotvTokens.unselectedColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (entry.disabled)
            const Text(
              '已禁用',
              style: TextStyle(
                fontSize: 13,
                color: KotvTokens.unselectedColor,
              ),
            )
          else
            TextButton(
              onPressed: () => _disable(entry),
              child: const Text('禁用'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _running
                          ? '检测中 $_checked/${_entries.length} · 失败 $_failed'
                          : '检测完成 $_checked/${_entries.length} · 失败 $_failed',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (_running) const LinearProgressIndicator(minHeight: 2),
            Flexible(
              child: _entries.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '当前用户没有可用站源',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final entry in _entries) _row(entry),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showKotvSpiderCheckDialog({
  required BuildContext context,
  required AppRepository repository,
  required LocalStore store,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => KotvSpiderCheckDialog(
      repository: repository,
      store: store,
    ),
  );
}
