import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';

enum AggregationColumn { video, novel, audio, tools }

extension AggregationColumnLabel on AggregationColumn {
  String get label => switch (this) {
    AggregationColumn.video => '视频',
    AggregationColumn.novel => '小说',
    AggregationColumn.audio => '听书·音乐',
    AggregationColumn.tools => '工具',
  };
}

class AggregationStationDef {
  const AggregationStationDef({
    required this.key,
    required this.name,
    required this.kind,
    required this.column,
  });

  final String key;
  final String name;
  final String kind;
  final AggregationColumn column;

  String get siteId => 'jar:zakatv:$key';
}

const List<AggregationStationDef> aggregationStationDefs = [
  AggregationStationDef(
    key: 'hgtv',
    name: '红果镜像',
    kind: '纯Java',
    column: AggregationColumn.video,
  ),
  AggregationStationDef(
    key: 'cntv',
    name: '央视',
    kind: '纯Java',
    column: AggregationColumn.video,
  ),
  AggregationStationDef(
    key: 'bili',
    name: 'B站Java版',
    kind: '纯Java',
    column: AggregationColumn.video,
  ),
  AggregationStationDef(
    key: 'go_bilibili',
    name: 'B站',
    kind: 'Go壳',
    column: AggregationColumn.video,
  ),
  AggregationStationDef(
    key: 'go_cjjh',
    name: 'CJJH',
    kind: 'Go壳',
    column: AggregationColumn.video,
  ),
  AggregationStationDef(
    key: 'go_hua',
    name: 'Hua',
    kind: 'Go壳',
    column: AggregationColumn.video,
  ),
  AggregationStationDef(
    key: 'go_ytdl',
    name: 'Ytdl',
    kind: 'Go壳',
    column: AggregationColumn.video,
  ),
  AggregationStationDef(
    key: 'go_webvod',
    name: '映画漫光',
    kind: 'Go壳',
    column: AggregationColumn.video,
  ),
  AggregationStationDef(
    key: 'go_lego',
    name: 'Lego',
    kind: 'Go壳',
    column: AggregationColumn.novel,
  ),
  AggregationStationDef(
    key: 'go_novelbd',
    name: 'NovelBd',
    kind: 'Go壳',
    column: AggregationColumn.novel,
  ),
  AggregationStationDef(
    key: 'go_tingshu',
    name: '听书',
    kind: 'Go壳',
    column: AggregationColumn.audio,
  ),
  AggregationStationDef(
    key: 'go_music1',
    name: '音乐',
    kind: 'Go壳',
    column: AggregationColumn.audio,
  ),
];

class AggregationStationEntry {
  const AggregationStationEntry({required this.def, required this.site});

  final AggregationStationDef def;
  final SourceSite? site;
}

List<AggregationStationEntry> aggregationEntries(
  List<SourceSite> visible,
) {
  return [
    for (final def in aggregationStationDefs)
      AggregationStationEntry(
        def: def,
        site: visible.where((site) => site.id == def.siteId).firstOrNull,
      ),
  ];
}

class AggregationDashboard extends StatefulWidget {
  const AggregationDashboard({
    super.key,
    required this.entries,
    required this.onOpenStation,
    required this.onSearch,
    required this.onOpenResult,
    required this.onOpenAi,
    required this.onOpenLz,
    required this.onOpenExperiment,
    required this.onOpenSettings,
  });

  final List<AggregationStationEntry> entries;
  final ValueChanged<SourceSite> onOpenStation;
  final Future<List<Drama>> Function(String query) onSearch;
  final ValueChanged<Drama> onOpenResult;
  final VoidCallback onOpenAi;
  final VoidCallback onOpenLz;
  final VoidCallback onOpenExperiment;
  final VoidCallback onOpenSettings;

  @override
  State<AggregationDashboard> createState() => _AggregationDashboardState();
}

class _AggregationDashboardState extends State<AggregationDashboard> {
  AggregationColumn _column = AggregationColumn.video;
  final _searchController = TextEditingController();
  List<Drama>? _results;
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AggregationStationEntry> get _visibleEntries => widget.entries
      .where((entry) => entry.def.column == _column)
      .toList();

  Future<void> _submitSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = null;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await widget.onSearch(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = error.toString();
      });
    }
  }

  String _sourceName(String sourceId) {
    final entry = widget.entries
        .where((entry) => entry.site?.id == sourceId)
        .firstOrNull;
    if (entry != null) return entry.site?.name ?? entry.def.name;
    return sourceId;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.primaryContainer, colors.secondaryContainer],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '聚合',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('移植站与工具的新分区，与现有分区并列'),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('aggregation-settings-button'),
                tooltip: '聚合设置',
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('aggregation-search-field'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearch(),
                decoration: const InputDecoration(
                  hintText: '在聚合站里搜索',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('aggregation-search-button'),
              onPressed: _searching ? null : _submitSearch,
              child: const Text('搜索'),
            ),
          ],
        ),
        if (_searching) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (_searchError != null) ...[
          const SizedBox(height: 8),
          Text(_searchError!, style: TextStyle(color: colors.error)),
        ],
        if (_results != null) ...[
          const SizedBox(height: 16),
          Text(
            '搜索结果（${_results!.length}）',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_results!.isEmpty)
            const Text('没有搜到内容，换个关键词试试。')
          else
            for (final drama in _results!)
              ListTile(
                key: ValueKey('aggregation-result-${drama.id}'),
                title: Text(drama.title, maxLines: 1),
                subtitle: Text(_sourceName(drama.source)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => widget.onOpenResult(drama),
              ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(() {
              _results = null;
              _searchController.clear();
            }),
            child: const Text('清除搜索结果'),
          ),
        ],
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final column in AggregationColumn.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('aggregation-column-${column.name}'),
                    label: Text(column.label),
                    selected: _column == column,
                    onSelected: (selected) {
                      if (selected) setState(() => _column = column);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_column == AggregationColumn.tools) ...[
          ListTile(
            key: const ValueKey('aggregation-tool-ai'),
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('AI 助手'),
            subtitle: const Text('打开公开 AI 聊天页，用你自己的账号登录'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: widget.onOpenAi,
          ),
          ListTile(
            key: const ValueKey('aggregation-tool-lz'),
            leading: const Icon(Icons.folder_open_rounded),
            title: const Text('lz 规则管理'),
            subtitle: const Text('查看、导入、删除 lz 与 novel 下的规则文件'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: widget.onOpenLz,
          ),
          ListTile(
            key: const ValueKey('aggregation-tool-experiment'),
            leading: const Icon(Icons.science_outlined),
            title: const Text('实验区'),
            subtitle: const Text('逐项开放的实验功能'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: widget.onOpenExperiment,
          ),
          ListTile(
            key: const ValueKey('aggregation-tool-settings'),
            leading: const Icon(Icons.settings_outlined),
            title: const Text('聚合设置'),
            subtitle: const Text('悬浮窗开关、AI 助手入口、lz 管理、实验区开关'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: widget.onOpenSettings,
          ),
        ] else ...[
          for (final entry in _visibleEntries)
            ListTile(
              key: ValueKey('aggregation-station-${entry.def.key}'),
              title: Text(
                entry.site?.name ?? entry.def.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: entry.site == null
                  ? const Text('未启用，到站源管理里开启')
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      entry.def.kind,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (entry.site != null) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ],
              ),
              enabled: entry.site != null,
              onTap: entry.site == null
                  ? null
                  : () => widget.onOpenStation(entry.site!),
            ),
          if (_visibleEntries.every((entry) => entry.site == null))
            const Text('本栏目暂无启用的站，到站源管理里开启后再来。'),
        ],
      ],
    );
  }
}
