import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'hongguotv_official_screen.dart';
import 'local_store.dart';
import 'models.dart';
import 'player_picker.dart';

const hongguotvSourceId = 'hongguotv';
const hongguotvEpisodeGroupSize = 20;

int hongguotvGroupCount(int total) {
  if (total <= 0) {
    return 0;
  }
  return (total + hongguotvEpisodeGroupSize - 1) ~/ hongguotvEpisodeGroupSize;
}

({int start, int end}) hongguotvGroupRange(int group, int total) {
  final start = group * hongguotvEpisodeGroupSize + 1;
  var end = (group + 1) * hongguotvEpisodeGroupSize;
  if (end > total) {
    end = total;
  }
  return (start: start, end: end);
}

String hongguotvUiLabel(String variant) {
  return switch (variant) {
    'vertical' => '竖版界面',
    'official' => '官方界面',
    _ => '现有界面',
  };
}

class HongguotvVerticalScreen extends StatefulWidget {
  const HongguotvVerticalScreen({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<HongguotvVerticalScreen> createState() =>
      _HongguotvVerticalScreenState();
}

class _HongguotvVerticalScreenState extends State<HongguotvVerticalScreen> {
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

  Future<void> _pickVariant(String variant) async {
    if (variant == 'vertical') {
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
        builder: (_) => HongguotvOfficialScreen(
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    );
  }

  void _openDetail(Drama drama) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => HongguotvVerticalDetailScreen(
          drama: drama,
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
          IconButton(
            key: const Key('hongguotv-search'),
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => HongguotvSearchScreen(
                    repository: widget.repository,
                    store: widget.store,
                  ),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            key: const Key('hongguotv-variant-menu'),
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
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final category in _categories)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      key: Key('hongguotv-category-${category.id}'),
                      label: Text(category.name),
                      selected: _category == category.id,
                      onSelected: (_) => _pickCategory(category.id),
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
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.62,
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
                      return _HongguotvPosterCard(
                        drama: _items[index],
                        onTap: () => _openDetail(_items[index]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _HongguotvPosterCard extends StatelessWidget {
  const _HongguotvPosterCard({required this.drama, required this.onTap});

  final Drama drama;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (drama.episodes > 0) '全${drama.episodes}集',
      if (drama.releaseLabel != '状态未知') drama.releaseLabel,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: drama.cover.isEmpty
                  ? Container(color: Colors.black12)
                  : Image.network(
                      drama.cover,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, _, _) =>
                          Container(color: Colors.black12),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            drama.title,
            maxLines: 2,
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
        ],
      ),
    );
  }
}

class HongguotvVerticalDetailScreen extends StatefulWidget {
  const HongguotvVerticalDetailScreen({
    super.key,
    required this.drama,
    required this.repository,
    required this.store,
  });

  final Drama drama;
  final AppRepository repository;
  final LocalStore store;

  @override
  State<HongguotvVerticalDetailScreen> createState() =>
      _HongguotvVerticalDetailScreenState();
}

class _HongguotvVerticalDetailScreenState
    extends State<HongguotvVerticalDetailScreen> {
  DramaDetail? _detail;
  String? _error;
  var _expanded = false;
  var _group = 0;

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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: detail.drama.cover.isEmpty
                            ? Container(
                                width: 110,
                                height: 146,
                                color: Colors.black12,
                              )
                            : Image.network(
                                detail.drama.cover,
                                width: 110,
                                height: 146,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 110,
                                  height: 146,
                                  color: Colors.black12,
                                ),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail.drama.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              detail.drama.description,
                              maxLines: _expanded ? null : 2,
                              overflow:
                                  _expanded ? null : TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                FilledButton(
                                  onPressed: detail.episodes.isEmpty
                                      ? null
                                      : () => _play(_resumeIndex),
                                  child: Text(
                                    widget.store
                                                .watched(detail.drama.id) !=
                                            null &&
                                        !widget.store
                                            .watched(detail.drama.id)!
                                            .finished
                                        ? '继续观看'
                                        : '开始播放',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () => setState(
                                    () => _expanded = !_expanded,
                                  ),
                                  child: Text(_expanded ? '收起简介' : '完整简介'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '选集 · ${detail.episodes.length}集',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var group = 0;
                          group < hongguotvGroupCount(detail.episodes.length);
                          group++)
                        ChoiceChip(
                          key: Key('hongguotv-group-$group'),
                          label: Text(
                            '${hongguotvGroupRange(group, detail.episodes.length).start}–${hongguotvGroupRange(group, detail.episodes.length).end}',
                          ),
                          selected: _group == group,
                          onSelected: (_) => setState(() => _group = group),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0;
                          i < detail.episodes.length &&
                              i >= _group * hongguotvEpisodeGroupSize &&
                              i < (_group + 1) * hongguotvEpisodeGroupSize;
                          i++)
                        SizedBox(
                          width: 64,
                          child: OutlinedButton(
                            key: Key('hongguotv-episode-$i'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor:
                                  widget.store.watched(detail.drama.id)?.episode ==
                                      detail.episodes[i].number
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : null,
                            ),
                            onPressed: () => _play(i),
                            child: Text('${detail.episodes[i].number}'),
                          ),
                        ),
                    ],
                  ),
                  if (detail.warning.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(detail.warning),
                  ],
                ],
              ),
            ),
    );
  }
}

class HongguotvSearchScreen extends StatefulWidget {
  const HongguotvSearchScreen({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<HongguotvSearchScreen> createState() => _HongguotvSearchScreenState();
}

class _HongguotvSearchScreenState extends State<HongguotvSearchScreen> {
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
                      childAspectRatio: 0.62,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      return _HongguotvPosterCard(
                        drama: _items[index],
                        onTap: () {
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  HongguotvVerticalDetailScreen(
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
