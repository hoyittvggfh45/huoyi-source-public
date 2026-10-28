import 'dart:math';

import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'models.dart';
import 'remote_widgets.dart';

class CatalogFilters extends StatefulWidget {
  const CatalogFilters({
    super.key,
    required this.categories,
    required this.category,
    required this.onCategory,
    required this.onRetry,
    this.error,
    this.trailing,
    this.remoteKey,
    this.remoteAutofocus = false,
    this.onExitUp,
    this.onExitDown,
  });

  final List<CatalogCategory> categories;
  final String category;
  final String? error;
  final ValueChanged<String> onCategory;
  final VoidCallback onRetry;
  final Widget? trailing;
  final GlobalKey<RemoteRowState>? remoteKey;
  final bool remoteAutofocus;
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;

  @override
  State<CatalogFilters> createState() => _CatalogFiltersState();
}

class _CatalogFiltersState extends State<CatalogFilters> {
  final _anchors = <String, GlobalKey>{};

  int get _selectedIndex {
    final index = widget.categories.indexWhere(
      (entry) => entry.id == widget.category,
    );
    return index < 0 ? 0 : index;
  }

  @override
  void didUpdateWidget(covariant CatalogFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final anchor = _anchors[widget.category]?.currentContext;
        if (mounted && anchor != null) {
          Scrollable.ensureVisible(
            anchor,
            alignment: .4,
            duration: const Duration(milliseconds: 180),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final television = AppLayout.isTelevision(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: television
          ? 64
          : max(52, MediaQuery.textScalerOf(context).scale(14) + 28),
      child: Row(
        children: [
          Expanded(
            child: television
                ? RemoteRow(
                    key: widget.remoteKey,
                    itemKeys: [for (final entry in widget.categories) entry.id],
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    initialIndex: _selectedIndex,
                    autofocus: widget.remoteAutofocus,
                    onExitUp: widget.onExitUp,
                    onExitDown: widget.onExitDown,
                    itemBuilder: (_, index, node, onFocus) {
                      final entry = widget.categories[index];
                      return KeyedSubtree(
                        key: _anchors.putIfAbsent(entry.id, GlobalKey.new),
                        child: RemoteButton(
                          key: ValueKey('category-${entry.id}'),
                          label: entry.name,
                          selected: entry.id == widget.category,
                          focusNode: node,
                          onFocus: onFocus,
                          onPressed: () => widget.onCategory(entry.id),
                        ),
                      );
                    },
                  )
                : SingleChildScrollView(
                    key: const ValueKey('catalog-categories'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        for (final entry in widget.categories)
                          Padding(
                            key: _anchors.putIfAbsent(entry.id, GlobalKey.new),
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              key: ValueKey('category-${entry.id}'),
                              label: Text(entry.name),
                              selected: entry.id == widget.category,
                              showCheckmark: false,
                              selectedColor: const Color(0xFFC8E6C9),
                              backgroundColor: scheme.surfaceContainerHighest,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface,
                              ),
                              onSelected: (_) => widget.onCategory(entry.id),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          if (widget.error != null)
            IconButton(
              tooltip: widget.error,
              onPressed: widget.onRetry,
              icon: Icon(
                Icons.refresh_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

class CatalogFilterRows extends StatelessWidget {
  const CatalogFilterRows({
    super.key,
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  final List<CatalogFilterGroup> groups;
  final Map<String, String> selected;
  final void Function(String groupKey, String optionId) onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final group in groups)
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: SizedBox(
                    width: 44,
                    child: Text(
                      group.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 12),
                    children: [
                      _chip(context, group, '', '全部'),
                      for (final option in group.options)
                        _chip(context, group, option.id, option.name),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    CatalogFilterGroup group,
    String id,
    String label,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = (selected[group.key] ?? '') == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        key: ValueKey('filter-${group.key}-$id'),
        label: Text(label),
        selected: isSelected,
        showCheckmark: false,
        selectedColor: const Color(0xFFC8E6C9),
        backgroundColor: scheme.surfaceContainerHighest,
        labelStyle: TextStyle(fontSize: 12, color: scheme.onSurface),
        side: BorderSide.none,
        onSelected: (_) => onSelected(group.key, id),
      ),
    );
  }
}
