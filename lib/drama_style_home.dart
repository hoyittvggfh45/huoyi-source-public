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

class DramaStyleHome extends StatelessWidget {
  const DramaStyleHome({
    super.key,
    required this.dramas,
    required this.repository,
    required this.onOpenDrama,
    required this.onOpenFeed,
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
    required this.onSectionSelected,
    required this.onMenuPressed,
    required this.onAccountPressed,
    this.onSettingsPressed,
    this.badgeOf,
  });

  final List<Drama> dramas;
  final AppRepository repository;
  final ValueChanged<Drama> onOpenDrama;
  final VoidCallback onOpenFeed;
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
  final ValueChanged<String> onSectionSelected;
  final VoidCallback onMenuPressed;
  final VoidCallback onAccountPressed;
  final VoidCallback? onSettingsPressed;
  final String? Function(Drama)? badgeOf;

  String _tagText(Drama drama) {
    final badge = badgeOf?.call(drama);
    if (badge != null && badge.isNotEmpty) return badge;
    if (drama.category.isNotEmpty) return drama.category;
    if (drama.tags.isNotEmpty) return drama.tags.first;
    return '';
  }

  Widget _sectionCard(Drama drama) {
    return GestureDetector(
      onTap: () => onOpenDrama(drama),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 160,
              child: DramaCover(drama: drama, repository: repository),
            ),
            const SizedBox(height: 6),
            Text(
              drama.title,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              _tagText(drama),
              style: const TextStyle(fontSize: 11.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sections = groupDramaSections(dramas, '全部');
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
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
                        selected: selected,
                        onSelected: (_) => onCategorySelected(category.id),
                      );
                    },
                  ),
                ),
              ),
            if (sections.isEmpty)
              const SliverToBoxAdapter(
                child: StatusPanel(
                  title: '暂无可播短剧',
                  message: '可以换个分类、站源或刷新后重试。',
                ),
              )
            else
              for (final section in sections) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padding, 20, padding, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            section.title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: '查看${section.title}',
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: () => onSectionSelected(section.title),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 226,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      itemCount: section.items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) =>
                          _sectionCard(section.items[index]),
                    ),
                  ),
                ),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        );
      },
    );
  }
}
