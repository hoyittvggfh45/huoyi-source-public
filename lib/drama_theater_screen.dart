import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'drama_style_home.dart';
import 'models.dart';
import 'widgets.dart';

const theaterSegments = ['真人剧', '漫剧', 'AI剧', '视频'];

const _genericSegmentNames = {
  '短剧',
  '真人剧',
  '漫剧',
  'AI剧',
  'AI 剧',
  'AI短剧',
  'AI 短剧',
  'AI漫剧',
  'AI 漫剧',
};

String _theaterHaystack(Drama drama) {
  final parts = <String>[drama.category, ...drama.tags];
  return parts.join().replaceAll(' ', '');
}

bool theaterSegmentMatches(Drama drama, String segment) {
  if (drama.kind != 'video') return false;
  final haystack = _theaterHaystack(drama);
  switch (segment) {
    case '真人剧':
      return haystack.contains('真人剧');
    case '漫剧':
      return haystack.contains('漫剧') && !haystack.contains('AI');
    case 'AI剧':
      return haystack.contains('AI剧') ||
          haystack.contains('AI漫剧') ||
          haystack.contains('AI短剧') ||
          haystack.contains('AI换脸') ||
          haystack.contains('AI魔改');
    case '视频':
      return true;
    default:
      return true;
  }
}

List<Drama> theaterFilterDramas(
  List<Drama> dramas, {
  String segment = '真人剧',
  String category = '',
  String tag = '',
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return dramas.where((drama) {
    if (!theaterSegmentMatches(drama, segment)) return false;
    if (category.isNotEmpty && drama.category != category) return false;
    if (tag.isNotEmpty && !drama.tags.contains(tag)) return false;
    if (q.isNotEmpty && !drama.title.toLowerCase().contains(q)) return false;
    return true;
  }).toList();
}

List<String> theaterDistinctTags(List<Drama> dramas) {
  final tags = <String>[];
  for (final drama in dramas) {
    for (final tag in drama.tags) {
      if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
    }
  }
  return tags;
}

List<CatalogCategory> theaterGenreCategories(List<CatalogCategory> categories) {
  final result = <CatalogCategory>[];
  for (final category in categories) {
    if (category.name.isEmpty ||
        category.name == '全部' ||
        _genericSegmentNames.contains(category.name)) {
      continue;
    }
    if (result.any((entry) => entry.name == category.name)) continue;
    result.add(category);
  }
  return result;
}

class DramaTheaterScreen extends StatefulWidget {
  const DramaTheaterScreen({
    super.key,
    required this.dramas,
    required this.repository,
    required this.onOpenDrama,
    this.categories = const [],
    this.onOpenFeed,
    this.onSearchSubmitted,
  });

  final List<Drama> dramas;
  final AppRepository repository;
  final ValueChanged<Drama> onOpenDrama;
  final List<CatalogCategory> categories;
  final VoidCallback? onOpenFeed;
  final ValueChanged<String>? onSearchSubmitted;

  @override
  State<DramaTheaterScreen> createState() => _DramaTheaterScreenState();
}

class _DramaTheaterScreenState extends State<DramaTheaterScreen> {
  late String _segment;
  String _category = '';
  String _tag = '';
  String _query = '';
  bool _searching = false;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _segment = widget.dramas.any(
      (drama) => theaterSegmentMatches(drama, '真人剧'),
    )
        ? '真人剧'
        : '视频';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Drama> get _segmentDramas => widget.dramas
      .where((drama) => theaterSegmentMatches(drama, _segment))
      .toList();

  List<Drama> get _filtered => theaterFilterDramas(
    widget.dramas,
    segment: _segment,
    category: _category,
    tag: _tag,
    query: _query,
  );

  void _selectSegment(String segment) {
    if (_segment == segment) return;
    setState(() {
      _segment = segment;
      _category = '';
      _tag = '';
    });
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? Colors.white : colors.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _filterRow(
    BuildContext context, {
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final value = option == '全部' ? '' : option;
          return _filterChip(
            context,
            label: option,
            selected: selected == value,
            onTap: () => onSelected(value),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final genreCategories = theaterGenreCategories(widget.categories);
    final tags = theaterDistinctTags(_segmentDramas);
    final filtered = _filtered;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
            final tileWidth = (constraints.maxWidth - padding * 2 - 12) / 2;
            final extent = (tileWidth * 4 / 3 + 112).ceilToDouble();
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padding, 12, padding, 4),
                    child: Row(
                      children: [
                        const Text(
                          '剧场',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            setState(() => _searching = !_searching);
                          },
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.search_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_searching)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(padding, 8, padding, 4),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '搜索短剧',
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
                        onChanged: (value) =>
                            setState(() => _query = value),
                        onSubmitted: (value) {
                          setState(() => _query = value);
                          widget.onSearchSubmitted?.call(value);
                        },
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padding, 16, padding, 12),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: theaterSegments.map((segment) {
                          final selected = _segment == segment;
                          return Expanded(
                            child: InkWell(
                              onTap: () => _selectSegment(segment),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: selected
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: .08,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  segment,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                if (widget.categories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _filterRow(
                        context,
                        options: [
                          '全部',
                          ...genreCategories.map((entry) => entry.name),
                        ],
                        selected: _category,
                        onSelected: (value) =>
                            setState(() => _category = value),
                      ),
                    ),
                  ),
                if (tags.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _filterRow(
                        context,
                        options: ['全部', ...tags],
                        selected: _tag,
                        onSelected: (value) => setState(() => _tag = value),
                      ),
                    ),
                  ),
                if (filtered.isEmpty)
                  const SliverToBoxAdapter(
                    child: StatusPanel(
                      title: '暂无可播短剧',
                      message: '可以换个分段、筛选项或搜索后重试。',
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(padding, 4, padding, 16),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                        mainAxisExtent: extent,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final drama = filtered[index];
                        return _TheaterCard(
                          drama: drama,
                          repository: widget.repository,
                          onTap: () => widget.onOpenDrama(drama),
                        );
                      }, childCount: filtered.length),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        onDestinationSelected: (index) {
          if (index == 0) widget.onOpenFeed?.call();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.theater_comedy_outlined),
            selectedIcon: Icon(Icons.theater_comedy),
            label: '剧场',
          ),
        ],
      ),
    );
  }
}

class _TheaterCard extends StatelessWidget {
  const _TheaterCard({
    required this.drama,
    required this.repository,
    required this.onTap,
  });

  final Drama drama;
  final AppRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = theaterMetaLine(drama);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DramaCover(drama: drama, repository: repository),
                if (drama.episodes > 0)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '全${drama.episodes}集',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              drama.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
          if (drama.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                drama.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (meta != null && meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
