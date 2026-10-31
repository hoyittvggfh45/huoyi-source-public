import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'models.dart';
import 'widgets.dart';

List<({String title, List<Drama> items})> groupDramaSections(
  List<Drama> items,
  String fallbackTitle,
) {
  final sections = <({String title, List<Drama> items})>[];
  final byTitle = <String, List<Drama>>{};
  for (final drama in items) {
    if (drama.kind != 'video') continue;
    final title = drama.category.isNotEmpty ? drama.category : fallbackTitle;
    final section = byTitle.putIfAbsent(title, () => <Drama>[]);
    if (section.isEmpty) {
      sections.add((title: title, items: section));
    }
    section.add(drama);
  }
  return sections;
}

String? theaterMetaLine(Drama drama) {
  if (drama.heat.isNotEmpty) return drama.heat;
  if (drama.views.isNotEmpty) return drama.views;
  return null;
}

String theaterTagLine(Drama drama) => drama.tags.join(' · ');

class DramaStyleHome extends StatelessWidget {
  const DramaStyleHome({
    super.key,
    required this.dramas,
    required this.repository,
    required this.onOpenDrama,
    required this.onOpenFeed,
    this.onOpenTheater,
    required this.onPickSource,
    required this.sourceLabel,
    required this.feedEnabled,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.searchController,
    required this.searchHint,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onMenuPressed,
    required this.onAccountPressed,
    required this.onFilterPressed,
    required this.onRankingsPressed,
    required this.onNewPressed,
    required this.filtersActive,
    required this.newActive,
    this.onSettingsPressed,
    this.badgeOf,
  });

  final List<Drama> dramas;
  final AppRepository repository;
  final ValueChanged<Drama> onOpenDrama;
  final VoidCallback onOpenFeed;
  final VoidCallback? onOpenTheater;
  final VoidCallback onPickSource;
  final String sourceLabel;
  final bool feedEnabled;
  final List<CatalogCategory> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final TextEditingController searchController;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onMenuPressed;
  final VoidCallback onAccountPressed;
  final VoidCallback onFilterPressed;
  final VoidCallback onRankingsPressed;
  final VoidCallback onNewPressed;
  final bool filtersActive;
  final bool newActive;
  final VoidCallback? onSettingsPressed;
  final String? Function(Drama)? badgeOf;

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(fontSize: 12, color: colors.onSurface),
      selected: selected,
      selectedColor: const Color(0xFFC8E6C9),
      backgroundColor: colors.surfaceContainerHighest,
      onSelected: (_) => onSelected(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final videos = dramas.where((drama) => drama.kind == 'video').toList();
    final hasTags = videos.any((drama) => drama.tags.isNotEmpty);
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
        final tileWidth = (constraints.maxWidth - padding * 2 - 12) / 2;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 12, padding, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: searchHint,
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: colors.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        textInputAction: TextInputAction.search,
                        onChanged: onSearchChanged,
                        onSubmitted: onSearchSubmitted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '账号',
                      icon: const Icon(Icons.person_outline),
                      onPressed: onAccountPressed,
                    ),
                    if (onSettingsPressed != null)
                      IconButton(
                        tooltip: '设置',
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: onSettingsPressed,
                      ),
                    IconButton(
                      tooltip: '导航',
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: onMenuPressed,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 8, padding, 4),
                child: Row(
                  children: [
                    InkWell(
                      onTap: onPickSource,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.outlineVariant),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sourceLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.expand_more_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (onOpenTheater != null)
                      OutlinedButton.icon(
                        onPressed: onOpenTheater,
                        icon: const Icon(Icons.theater_comedy_outlined),
                        label: const Text('剧场'),
                      ),
                    if (onOpenTheater != null) const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: feedEnabled ? onOpenFeed : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('全屏流'),
                    ),
                  ],
                ),
              ),
            ),
            if (categories.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    itemCount: categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final selected = category.id == selectedCategory;
                      return ChoiceChip(
                        label: Text(category.name),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: colors.onSurface,
                        ),
                        selected: selected,
                        selectedColor: const Color(0xFFC8E6C9),
                        backgroundColor: colors.surfaceContainerHighest,
                        onSelected: (_) => onCategorySelected(category.id),
                      );
                    },
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 8, padding, 4),
                child: Row(
                  children: [
                    _filterChip(
                      context,
                      label: '筛选',
                      selected: filtersActive,
                      onSelected: onFilterPressed,
                    ),
                    const SizedBox(width: 8),
                    _filterChip(
                      context,
                      label: '排行榜',
                      selected: false,
                      onSelected: onRankingsPressed,
                    ),
                    const SizedBox(width: 8),
                    _filterChip(
                      context,
                      label: '新剧',
                      selected: newActive,
                      onSelected: onNewPressed,
                    ),
                  ],
                ),
              ),
            ),
            if (videos.isEmpty)
              const SliverToBoxAdapter(
                child: StatusPanel(
                  title: '暂无可播短剧',
                  message: '可以换个分类、站源或刷新后重试。',
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padding, 12, padding, 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                    mainAxisExtent: hasTags
                        ? DramaTile.theaterExtentFor(context, tileWidth)
                        : DramaTile.extentFor(context, tileWidth),
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final drama = videos[index];
                    return DramaTile(
                      drama: drama,
                      repository: repository,
                      onTap: () => onOpenDrama(drama),
                      subtitle: theaterMetaLine(drama),
                      topBadge: badgeOf?.call(drama),
                      tagText: theaterTagLine(drama),
                    );
                  }, childCount: videos.length),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        );
      },
    );
  }
}
