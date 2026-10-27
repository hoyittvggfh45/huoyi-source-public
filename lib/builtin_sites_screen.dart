import 'package:flutter/material.dart';

import 'content_models.dart';
import 'content_registry.dart';
import 'local_store.dart';
import 'models.dart';
import 'widgets.dart';

class BuiltinSitesScreen extends StatefulWidget {
  const BuiltinSitesScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<BuiltinSitesScreen> createState() => _BuiltinSitesScreenState();
}

class _BuiltinSitesScreenState extends State<BuiltinSitesScreen> {
  final Set<String> _pending = {};

  Future<void> _toggle(String id, bool visible) async {
    if (_pending.contains(id)) return;
    setState(() => _pending.add(id));
    await saveUserChange(
      context,
      () => widget.store.setSiteVisible(id, visible),
    );
    if (mounted) setState(() => _pending.remove(id));
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复默认显示'),
        content: const Text('将恢复全部内置站的默认显示/隐藏状态，确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await saveUserChange(context, widget.store.resetSiteVisibility);
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _toggleTile(String id, String name, String? subtitle) {
    final visible = widget.store.siteVisible(id);
    return SwitchListTile(
      title: Text(name),
      subtitle: subtitle == null || subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      value: visible,
      onChanged: _pending.contains(id) ? null : (value) => _toggle(id, value),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final dramaSites = [
        for (final site in SourceSite.values)
          if (site.isDramaSection) site,
      ];
      final videoSites = [
        for (final site in SourceSite.values)
          if (site.isVideoSection) site,
      ];
      return Scaffold(
        appBar: AppBar(
          title: const Text('内置站管理'),
          actions: [TextButton(onPressed: _reset, child: const Text('恢复默认'))],
        ),
        body: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                '关闭的内置站在分区列表与搜索中都不再出现；导入的站源（TVBox 配置 / jar）请在导入中心或站源管理里删除，不在此列。',
              ),
            ),
            _sectionHeader('短剧'),
            for (final site in dramaSites)
              _toggleTile(site.id, site.name, site.description),
            _sectionHeader('影视'),
            for (final site in videoSites)
              _toggleTile(site.id, site.name, site.description),
            for (final section in ContentSection.values) ...[
              _sectionHeader(section.title),
              for (final source in ContentRegistry.sourcesFor(section))
                _toggleTile(source.id, source.name, source.note),
            ],
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
}
