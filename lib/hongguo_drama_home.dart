import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'widgets.dart';

bool isHongguoDramaGroup(String groupId) => groupId == 'hongguo';

class HongguoDramaHome extends StatefulWidget {
  const HongguoDramaHome({
    super.key,
    required this.dramas,
    required this.repository,
    required this.store,
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
    required this.onMenuPressed,
    required this.onFilterPressed,
    required this.onRankingsPressed,
    required this.onNewPressed,
    required this.filtersActive,
    required this.newActive,
    required this.onOpenSaved,
    required this.onOpenDownloads,
    this.onSettingsPressed,
  });

  final List<Drama> dramas;
  final AppRepository repository;
  final LocalStore store;
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
  final VoidCallback onMenuPressed;
  final VoidCallback onFilterPressed;
  final VoidCallback onRankingsPressed;
  final VoidCallback onNewPressed;
  final bool filtersActive;
  final bool newActive;
  final void Function({required bool history}) onOpenSaved;
  final VoidCallback onOpenDownloads;
  final VoidCallback? onSettingsPressed;

  @override
  State<HongguoDramaHome> createState() => _HongguoDramaHomeState();
}

class _HongguoDramaHomeState extends State<HongguoDramaHome> {
  int _tab = 0;

  List<Drama> get _videos =>
      widget.dramas.where((drama) => drama.kind == 'video').toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_tab) {
        1 => _theater(context),
        2 => _mine(context),
        _ => _feed(context),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
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
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }

  Widget _feed(BuildContext context) {
    final videos = _videos;
    if (videos.isEmpty) {
      return const SafeArea(
        child: StatusPanel(
          title: '暂无可播短剧',
          message: '可以换个分类或刷新后重试。',
        ),
      );
    }
    return Stack(
      children: [
        PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final drama = videos[index];
            return GestureDetector(
              onTap: () => widget.onOpenDrama(drama),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DramaCover(drama: drama, repository: widget.repository),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.25),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.75),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 72,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (drama.tags.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            children: drama.tags
                                .take(4)
                                .map(
                                  (tag) => Chip(
                                    label: Text(tag),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          drama.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(color: Colors.white),
                        ),
                        if (drama.heat.isNotEmpty || drama.views.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              drama.heat.isNotEmpty
                                  ? drama.heat
                                  : drama.views,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => widget.onOpenDrama(drama),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            drama.episodes > 0
                                ? '观看完整短剧 · 全${drama.episodes}集'
                                : '观看完整短剧',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 96,
                    child: Column(
                      children: [
                        IconButton(
                          onPressed: widget.onOpenFeed,
                          icon: const Icon(
                            Icons.fullscreen,
                            color: Colors.white,
                          ),
                          tooltip: '全屏观看',
                        ),
                        IconButton(
                          onPressed: widget.onPickSource,
                          icon: const Icon(
                            Icons.swap_horiz,
                            color: Colors.white,
                          ),
                          tooltip: '换源',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onMenuPressed,
                  icon: const Icon(Icons.menu, color: Colors.white),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: widget.categories
                          .map(
                            (category) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(category.name),
                                selected:
                                    widget.selectedCategory == category.id,
                                onSelected: (_) =>
                                    widget.onCategorySelected(category.id),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onOpenFeed,
                  icon: const Icon(Icons.search, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _theater(BuildContext context) {
    final videos = _videos;
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: widget.searchController,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                ),
                onChanged: widget.onSearchChanged,
                onSubmitted: widget.onSearchSubmitted,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _theaterAction(
                    context,
                    label: '筛选',
                    icon: Icons.filter_list,
                    active: widget.filtersActive,
                    onPressed: widget.onFilterPressed,
                  ),
                  const SizedBox(width: 8),
                  _theaterAction(
                    context,
                    label: '排行榜',
                    icon: Icons.leaderboard_outlined,
                    active: false,
                    onPressed: widget.onRankingsPressed,
                  ),
                  const SizedBox(width: 8),
                  _theaterAction(
                    context,
                    label: '新剧',
                    icon: Icons.new_releases_outlined,
                    active: widget.newActive,
                    onPressed: widget.onNewPressed,
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: widget.categories
                    .map(
                      (category) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(category.name),
                          selected: widget.selectedCategory == category.id,
                          onSelected: (_) =>
                              widget.onCategorySelected(category.id),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final drama = videos[index];
                  return GestureDetector(
                    onTap: () => widget.onOpenDrama(drama),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: DramaCover(drama: drama, repository: widget.repository),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          drama.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (drama.heat.isNotEmpty || drama.views.isNotEmpty)
                          Text(
                            drama.heat.isNotEmpty ? drama.heat : drama.views,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  );
                },
                childCount: videos.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _theaterAction(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: active
          ? FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
            )
          : null,
    );
  }

  Widget _mine(BuildContext context) {
    return SafeArea(
      child: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: const Text('我的'),
            subtitle: Text(widget.sourceLabel),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('追剧'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => widget.onOpenSaved(history: false),
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('最近观看'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => widget.onOpenSaved(history: true),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('我的下载'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: widget.onOpenDownloads,
          ),
          if (widget.onSettingsPressed != null)
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: widget.onSettingsPressed,
            ),
        ],
      ),
    );
  }
}
