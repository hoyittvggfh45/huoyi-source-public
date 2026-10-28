import 'package:flutter/material.dart';

import 'app_layout.dart';

class SourcePickerEntry {
  const SourcePickerEntry({required this.id, required this.name});

  final String id;
  final String name;
}

class SourcePickerGroup {
  const SourcePickerGroup({required this.title, required this.entries});

  final String title;
  final List<SourcePickerEntry> entries;
}

Future<String?> showSourcePickerSheet(
  BuildContext context, {
  required String sectionName,
  required String currentName,
  required String currentId,
  required List<SourcePickerGroup> groups,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (context) => SourcePickerSheet(
    sectionName: sectionName,
    currentName: currentName,
    currentId: currentId,
    groups: groups,
  ),
);

Future<String?> showCenteredSourcePickerDialog(
  BuildContext context, {
  required String sectionName,
  required String currentName,
  required String currentId,
  required List<SourcePickerGroup> groups,
}) => showDialog<String>(
  context: context,
  builder: (context) => CenteredSourcePickerDialog(
    sectionName: sectionName,
    currentName: currentName,
    currentId: currentId,
    groups: groups,
  ),
);

class CenteredSourcePickerDialog extends StatelessWidget {
  const CenteredSourcePickerDialog({
    super.key,
    required this.sectionName,
    required this.currentName,
    required this.currentId,
    required this.groups,
  });

  final String sectionName;
  final String currentName;
  final String currentId;
  final List<SourcePickerGroup> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      key: const ValueKey('centered-source-picker'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('切换$sectionName源', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '当前：$currentName',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              for (final group in groups) ...[
                if (group.title.isNotEmpty) ...[
                  Text(
                    '${group.title}（${group.entries.length}）',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in group.entries)
                      ChoiceChip(
                        key: ValueKey('centered-source-${entry.id}'),
                        label: Text(entry.name),
                        selected: entry.id == currentId,
                        onSelected: (_) => Navigator.pop(context, entry.id),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const ValueKey('centered-source-close'),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SourcePickerSheet extends StatefulWidget {
  const SourcePickerSheet({
    super.key,
    required this.sectionName,
    required this.currentName,
    required this.currentId,
    required this.groups,
  });

  final String sectionName;
  final String currentName;
  final String currentId;
  final List<SourcePickerGroup> groups;

  @override
  State<SourcePickerSheet> createState() => _SourcePickerSheetState();
}

class _SourcePickerSheetState extends State<SourcePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  late final Set<int> _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = {
      for (var i = 0; i < widget.groups.length; i++)
        if (widget.groups[i].title.isNotEmpty &&
            !widget.groups[i].entries.any(
              (entry) => entry.id == widget.currentId,
            ))
          i,
    };
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final television = AppLayout.isTelevision(context);
    final allEntries = [for (final group in widget.groups) ...group.entries];
    final autofocusId = allEntries.any((entry) => entry.id == widget.currentId)
        ? widget.currentId
        : (allEntries.isEmpty ? '' : allEntries.first.id);
    final searching = _query.isNotEmpty;
    final visible = <({int index, List<SourcePickerEntry> entries})>[];
    for (var gi = 0; gi < widget.groups.length; gi++) {
      final entries = searching
          ? widget.groups[gi].entries
                .where((entry) => entry.name.toLowerCase().contains(_query))
                .toList()
          : widget.groups[gi].entries;
      if (searching && entries.isEmpty) continue;
      visible.add((index: gi, entries: entries));
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '切换${widget.sectionName}源',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '当前：${widget.currentName}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '点击站源立即切换',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('source-picker-search'),
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: '搜索站源',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            if (searching && visible.isEmpty) ...[
              const SizedBox(height: 24),
              Text(
                '没有匹配的站源',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            for (final group in visible) ...[
              if (widget.groups[group.index].title.isNotEmpty) ...[
                SizedBox(height: group.index == 0 ? 20 : 24),
                InkWell(
                  key: ValueKey('source-picker-group-${group.index}'),
                  onTap: searching
                      ? null
                      : () => setState(() {
                          if (_collapsed.contains(group.index)) {
                            _collapsed.remove(group.index);
                          } else {
                            _collapsed.add(group.index);
                          }
                        }),
                  child: Row(
                    children: [
                      Text(
                        widget.groups[group.index].title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '（${searching ? group.entries.length : widget.groups[group.index].entries.length}）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        searching || !_collapsed.contains(group.index)
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ] else
                SizedBox(height: group.index == 0 ? 16 : 12),
              if (widget.groups[group.index].title.isEmpty ||
                  searching ||
                  !_collapsed.contains(group.index))
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in group.entries)
                      ChoiceChip(
                        key: ValueKey('source-picker-${entry.id}'),
                        autofocus: television && entry.id == autofocusId,
                        label: Text(entry.name),
                        selected: entry.id == widget.currentId,
                        onSelected: (_) => Navigator.pop(context, entry.id),
                      ),
                  ],
                ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey('source-picker-close'),
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
