import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'hongguotv_vertical_screen.dart';
import 'local_store.dart';
import 'models.dart';
import 'player_picker.dart';

class HongguotvOfficialScreen extends StatefulWidget {
  const HongguotvOfficialScreen({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<HongguotvOfficialScreen> createState() =>
      _HongguotvOfficialScreenState();
}

class _HongguotvOfficialScreenState extends State<HongguotvOfficialScreen> {
  var _tab = 0;

  Future<void> _pickVariant(String variant) async {
    if (variant == 'official') {
      return;
    }
    await widget.store.setHongguotvUi(variant);
    if (!mounted) {
      return;
    }
    if (variant == 'existing') {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(
        builder: (_) => HongguotvVerticalScreen(
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('红果TV'),
        actions: [
          PopupMenuButton<String>(
            key: const Key('hongguotv-official-variant-menu'),
            icon: const Icon(Icons.tune),
            onSelected: _pickVariant,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'existing', child: Text('现有界面')),
              PopupMenuItem(value: 'vertical', child: Text('竖版界面')),
              PopupMenuItem(value: 'official', child: Text('官方界面')),
            ],
          ),
        ],
      ),
      body: _tab == 0
          ? HongguotvOfficialHome(
              repository: widget.repository,
              store: widget.store,
            )
          : HongguotvOfficialMy(
              repository: widget.repository,
              store: widget.store,
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (index) => setState(() => _tab = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}

class HongguotvOfficialHome extends StatefulWidget {
  const HongguotvOfficialHome({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<HongguotvOfficialHome> createState() => _HongguotvOfficialHomeState();
}

class _HongguotvOfficialHomeState extends State<HongguotvOfficialHome> {
  var _categories = const <CatalogCategory>[CatalogCategory.all];
  var _category = '';
  var _items = const <Drama>[];
  var _page = 1;
  var _hasMore = false;
  var _loading = true;
  var _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories =
          await widget.repository.categories(hongguotvSourceId);
      if (!mounted) {
        return;
      }
      setState(() {
        if (categories.isNotEmpty) {
          _categories = categories;
        }
      });
    } catch (_) {
    }
    await _loadPage(1);
  }

  Future<void> _loadPage(int page) async {
    if (page == 1) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _loadingMore = true;
      });
    }
    try {
      final result = await widget.repository.catalog(
        hongguotvSourceId,
        category: _category,
        page: page,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _items = page == 1 ? result.items : [..._items, ...result.items];
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
        if (result.warning.isNotEmpty) {
          _error = result.warning;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  void _pickCategory(String id) {
    if (id == _category) {
      return;
    }
    setState(() {
      _category = id;
      _items = const [];
      _hasMore = false;
    });
    _loadPage(1);
  }

  void _openDetail(Drama drama) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => HongguotvOfficialDetailScreen(
          drama: drama,
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: InkWell(
            key: const Key('hongguotv-official-search-bar'),
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => HongguotvOfficialSearchScreen(
                    repository: widget.repository,
                    store: widget.store,
                  ),
                ),
              );
            },
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, size: 20),
                  SizedBox(width: 8),
                  Text('搜索剧名'),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final category in _categories)
                InkWell(
                  key: Key('hongguotv-official-tab-${category.id}'),
                  onTap: () => _pickCategory(category.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _category == category.id
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      category.name,
                      style: TextStyle(
                        fontWeight: _category == category.id
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error ?? '暂无内容'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _loadPage(1),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.58,
                  ),
                  itemCount: _items.length + 1,
                  itemBuilder: (context, index) {
                    if (index >= _items.length) {
                      return Center(
                        child: _loadingMore
                            ? const CircularProgressIndicator()
                            : _hasMore
                            ? TextButton(
                                onPressed: () => _loadPage(_page + 1),
                                child: const Text('加载更多'),
                              )
                            : const Text('已经到底了'),
                      );
                    }
                    return _HongguotvStaggeredCard(
                      drama: _items[index],
                      onTap: () => _openDetail(_items[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HongguotvStaggeredCard extends StatelessWidget {
  const _HongguotvStaggeredCard({required this.drama, required this.onTap});

  final Drama drama;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (drama.heat.isNotEmpty) drama.heat,
      if (drama.views.isNotEmpty) drama.views,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  drama.cover.isEmpty
                      ? Container(color: Colors.black12)
                      : Image.network(
                          drama.cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(color: Colors.black12),
                        ),
                  if (drama.releaseLabel != '状态未知')
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          drama.releaseLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  if (drama.episodes > 0)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '全${drama.episodes}集',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            drama.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (meta.isNotEmpty)
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (drama.tags.isNotEmpty)
            Text(
              drama.tags.take(2).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class HongguotvOfficialDetailScreen extends StatefulWidget {
  const HongguotvOfficialDetailScreen({
    super.key,
    required this.drama,
    required this.repository,
    required this.store,
  });

  final Drama drama;
  final AppRepository repository;
  final LocalStore store;

  @override
  State<HongguotvOfficialDetailScreen> createState() =>
      _HongguotvOfficialDetailScreenState();
}

class _HongguotvOfficialDetailScreenState
    extends State<HongguotvOfficialDetailScreen> {
  DramaDetail? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.repository.detail(widget.drama);
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  int get _resumeIndex {
    final detail = _detail;
    if (detail == null) {
      return 0;
    }
    final watched = widget.store.watched(detail.drama.id);
    if (watched == null || watched.finished) {
      return 0;
    }
    final index = detail.episodes
        .indexWhere((episode) => episode.number == watched.episode);
    return index >= 0 ? index : 0;
  }

  Future<void> _play(int index) async {
    final detail = _detail;
    if (detail == null || index < 0 || index >= detail.episodes.length) {
      return;
    }
    final watched = widget.store.watched(detail.drama.id);
    final position =
        watched != null &&
            watched.episode == detail.episodes[index].number &&
            !watched.finished
        ? watched.position
        : 0.0;
    await pushPlayer<void>(
      context,
      detail: detail,
      initialIndex: index,
      initialPosition: position,
      repository: widget.repository,
      store: widget.store,
      startFullscreen: false,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openEpisodeSheet() async {
    final detail = _detail;
    if (detail == null) {
      return;
    }
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HongguotvEpisodeSheet(
        detail: detail,
        watchedEpisode:
            widget.store.watched(detail.drama.id)?.episode,
      ),
    );
    if (selected != null && mounted) {
      _play(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(title: Text(widget.drama.title)),
      body: detail == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _error = null;
                            });
                            _load();
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (detail.drama.cover.isNotEmpty)
                    Image.network(
                      detail.drama.cover,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(height: 220),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.drama.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (detail.drama.releaseLabel != '状态未知')
                              detail.drama.releaseLabel,
                            ...detail.drama.tags,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(detail.drama.description),
                        const SizedBox(height: 16),
                        InkWell(
                          key: const Key('hongguotv-official-episode-bar'),
                          onTap: _openEpisodeSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '选集 · ${detail.drama.releaseLabel} · 全${detail.episodes.length}集',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.keyboard_arrow_up),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: detail.episodes.isEmpty
                                    ? null
                                    : () => _play(_resumeIndex),
                                child: Text(
                                  widget.store.watched(detail.drama.id) !=
                                              null &&
                                          !widget.store
                                              .watched(detail.drama.id)!
                                              .finished
                                      ? '继续观看'
                                      : '开始播放',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _openEpisodeSheet,
                              child: const Text('选集'),
                            ),
                          ],
                        ),
                        if (detail.related.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Text(
                            '相关推荐',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 190,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final item in detail.related)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: SizedBox(
                                      width: 110,
                                      child: _HongguotvStaggeredCard(
                                        drama: item,
                                        onTap: () {
                                          Navigator.push<void>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  HongguotvOfficialDetailScreen(
                                                drama: item,
                                                repository: widget.repository,
                                                store: widget.store,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (detail.warning.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(detail.warning),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _HongguotvEpisodeSheet extends StatefulWidget {
  const _HongguotvEpisodeSheet({
    required this.detail,
    required this.watchedEpisode,
  });

  final DramaDetail detail;
  final int? watchedEpisode;

  @override
  State<_HongguotvEpisodeSheet> createState() => _HongguotvEpisodeSheetState();
}

class _HongguotvEpisodeSheetState extends State<_HongguotvEpisodeSheet> {
  var _group = 0;

  @override
  Widget build(BuildContext context) {
    final total = widget.detail.episodes.length;
    final groupCount = hongguotvGroupCount(total);
    if (_group >= groupCount && groupCount > 0) {
      _group = groupCount - 1;
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (widget.detail.drama.cover.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        widget.detail.drama.cover,
                        width: 48,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const SizedBox(width: 48, height: 64),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.detail.drama.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text('全$total集'),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _group > 0
                        ? () => setState(() => _group--)
                        : null,
                    child: const Text('‹ 上一组'),
                  ),
                  Expanded(
                    child: Center(
                      child: groupCount == 0
                          ? const Text('')
                          : Text(
                              '${hongguotvGroupRange(_group, total).start}–${hongguotvGroupRange(_group, total).end}',
                            ),
                    ),
                  ),
                  TextButton(
                    onPressed: _group + 1 < groupCount
                        ? () => setState(() => _group++)
                        : null,
                    child: const Text('下一组 ›'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.6,
                ),
                itemCount: groupCount == 0
                    ? 0
                    : hongguotvGroupRange(_group, total).end -
                        hongguotvGroupRange(_group, total).start +
                        1,
                itemBuilder: (context, index) {
                  final episodeIndex =
                      _group * hongguotvEpisodeGroupSize + index;
                  final episode = widget.detail.episodes[episodeIndex];
                  final current =
                      widget.watchedEpisode == episode.number;
                  return OutlinedButton(
                    key: Key('hongguotv-sheet-episode-$episodeIndex'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: current
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => Navigator.pop(context, episodeIndex),
                    child: Text('${episode.number}'),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class HongguotvOfficialSearchScreen extends StatefulWidget {
  const HongguotvOfficialSearchScreen({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<HongguotvOfficialSearchScreen> createState() =>
      _HongguotvOfficialSearchScreenState();
}

class _HongguotvOfficialSearchScreenState
    extends State<HongguotvOfficialSearchScreen> {
  final _controller = TextEditingController();
  var _items = const <Drama>[];
  var _searching = false;
  String? _error;
  String? _warning;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search([String? keyword]) async {
    final query = (keyword ?? _controller.text).trim();
    if (query.isEmpty) {
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _warning = null;
    });
    try {
      final result = await widget.repository.catalog(
        hongguotvSourceId,
        query: query,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _items = result.items;
        _searching = false;
        if (result.warning.isNotEmpty) {
          _warning = result.warning;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _searching = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: '输入剧名搜索',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _search,
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          if (widget.store.recentSearches.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final term in widget.store.recentSearches)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ActionChip(
                        label: Text(term),
                        onPressed: () {
                          _controller.text = term;
                          _search(term);
                        },
                      ),
                    ),
                ],
              ),
            ),
          if (_warning != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_warning!),
            ),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _items.isEmpty
                ? const Center(child: Text('输入剧名开始搜索'))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.58,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      return _HongguotvStaggeredCard(
                        drama: _items[index],
                        onTap: () {
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  HongguotvOfficialDetailScreen(
                                drama: _items[index],
                                repository: widget.repository,
                                store: widget.store,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class HongguotvOfficialMy extends StatelessWidget {
  const HongguotvOfficialMy({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    final history = store.history;
    final favorites = store.favorites;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '本地记录',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text('不登录账号，只显示本机观看与收藏记录'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '继续观看',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const Text('暂无观看记录')
        else
          for (final entry in history)
            ListTile(
              key: Key('hongguotv-my-history-${entry.drama.id}'),
              title: Text(entry.drama.title),
              subtitle: Text('第${entry.episode}集'),
              onTap: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HongguotvOfficialDetailScreen(
                      drama: entry.drama,
                      repository: repository,
                      store: store,
                    ),
                  ),
                );
              },
            ),
        const SizedBox(height: 16),
        const Text(
          '我的收藏',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (favorites.isEmpty)
          const Text('暂无收藏')
        else
          for (final drama in favorites)
            ListTile(
              key: Key('hongguotv-my-favorite-${drama.id}'),
              title: Text(drama.title),
              onTap: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HongguotvOfficialDetailScreen(
                      drama: drama,
                      repository: repository,
                      store: store,
                    ),
                  ),
                );
              },
            ),
        const SizedBox(height: 16),
        ListTile(
          key: const Key('hongguotv-my-variant'),
          title: const Text('界面切换'),
          subtitle: Text(hongguotvUiLabel(store.hongguotvUi)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final variant = await showDialog<String>(
              context: context,
              builder: (context) => SimpleDialog(
                title: const Text('红果TV 界面'),
                children: [
                  for (final option in const [
                    'existing',
                    'vertical',
                    'official',
                  ])
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, option),
                      child: Text(hongguotvUiLabel(option)),
                    ),
                ],
              ),
            );
            if (variant == null || !context.mounted) {
              return;
            }
            await store.setHongguotvUi(variant);
            if (!context.mounted) {
              return;
            }
            if (variant == 'existing') {
              Navigator.pop(context);
            } else if (variant == 'vertical') {
              Navigator.pushReplacement<void, void>(
                context,
                MaterialPageRoute(
                  builder: (_) => HongguotvVerticalScreen(
                    repository: repository,
                    store: store,
                  ),
                ),
              );
            }
          },
        ),
      ],
    );
  }
}
