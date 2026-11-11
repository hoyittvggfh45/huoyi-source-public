import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'ranking_models.dart';
import 'widgets.dart';

const List<({String id, String label})> hongguoRankBoards = [
  (id: 'hongguo-hot', label: '综合'),
  (id: 'hongguo-real', label: '真人剧'),
  (id: 'hongguo-comic', label: '漫剧'),
  (id: 'hongguo-ai', label: 'AI剧'),
];

class HongguoRankSnapshot {
  const HongguoRankSnapshot({
    required this.boardId,
    required this.items,
    required this.updatedText,
    required this.fetchedAt,
  });

  final String boardId;
  final List<RankingItem> items;
  final String updatedText;
  final DateTime fetchedAt;

  List<String> get topics => hongguoRankTopics(items);

  List<RankingItem> filtered(String topic) =>
      hongguoRankFiltered(items, topic);
}

List<String> hongguoRankTopics(List<RankingItem> items) {
  final counts = <String, int>{};
  for (final item in items) {
    for (final tag in item.drama.tags) {
      final token = tag.trim();
      if (token.isEmpty) continue;
      if (token.runes.every((rune) => rune >= 48 && rune <= 57)) continue;
      counts[token] = (counts[token] ?? 0) + 1;
    }
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return [for (final entry in entries) entry.key];
}

List<RankingItem> hongguoRankFiltered(
  List<RankingItem> items,
  String topic,
) {
  if (topic.isEmpty) return items;
  return items.where((item) => item.drama.tags.contains(topic)).toList();
}

String hongguoRankHeat(RankingItem item) =>
    item.drama.heat.isNotEmpty ? item.drama.heat : item.metric;

class HongguoRankCache {
  HongguoRankCache({this.ttl = const Duration(minutes: 10)});

  final Duration ttl;
  final Map<String, HongguoRankSnapshot> snapshots = {};
  final Set<String> _refreshing = {};

  bool isFresh(String boardId, {DateTime? now}) {
    final snapshot = snapshots[boardId];
    if (snapshot == null) return false;
    return (now ?? DateTime.now()).difference(snapshot.fetchedAt) < ttl;
  }

  bool isRefreshing(String boardId) => _refreshing.contains(boardId);

  bool beginRefresh(String boardId) => _refreshing.add(boardId);

  void endRefresh(String boardId, HongguoRankSnapshot? snapshot) {
    _refreshing.remove(boardId);
    if (snapshot != null) snapshots[boardId] = snapshot;
  }
}

class HongguoRankingScreen extends StatefulWidget {
  const HongguoRankingScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.onOpenDrama,
  });

  final AppRepository repository;
  final LocalStore store;
  final ValueChanged<Drama> onOpenDrama;

  @override
  State<HongguoRankingScreen> createState() => _HongguoRankingScreenState();
}

class _HongguoRankingScreenState extends State<HongguoRankingScreen> {
  final _cache = HongguoRankCache();
  final _scroll = ScrollController();
  String _boardId = hongguoRankBoards.first.id;
  String _topic = '';
  int _page = 1;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _generation = 0;

  HongguoRankSnapshot? get _snapshot => _cache.snapshots[_boardId];

  List<RankingItem> get _items =>
      hongguoRankFiltered(_snapshot?.items ?? const [], _topic);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _maybeRefresh(_boardId);
  }

  @override
  void dispose() {
    _generation++;
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_hasMore || _loading || _loadingMore) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter >
        (_scroll.position.viewportDimension * 1.2).clamp(260.0, 720.0)) {
      return;
    }
    _loadMore();
  }

  Future<void> _maybeRefresh(String boardId, {bool force = false}) async {
    if (!force && _cache.isFresh(boardId)) {
      setState(() {});
      return;
    }
    if (!_cache.beginRefresh(boardId)) return;
    final generation = ++_generation;
    setState(() {
      _loading = _snapshot == null;
      _error = null;
    });
    try {
      final result = await widget.repository.rankings(
        boardId,
        page: 1,
        force: force || !_cache.isFresh(boardId),
      );
      if (!mounted || generation != _generation) {
        _cache.endRefresh(boardId, null);
        return;
      }
      final snapshot = HongguoRankSnapshot(
        boardId: boardId,
        items: result.items,
        updatedText: result.updatedText,
        fetchedAt: DateTime.now(),
      );
      _cache.endRefresh(boardId, snapshot);
      setState(() {
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
        if (result.warning.isNotEmpty) _error = result.warning;
      });
    } catch (error) {
      if (!mounted || generation != _generation) {
        _cache.endRefresh(boardId, null);
        return;
      }
      _cache.endRefresh(boardId, null);
      setState(() {
        _loading = false;
        if (_snapshot == null) _error = error.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    final boardId = _boardId;
    if (!_cache.beginRefresh('$boardId-page')) return;
    final generation = ++_generation;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.repository.rankings(
        boardId,
        page: _page + 1,
      );
      if (!mounted || generation != _generation) {
        _cache.endRefresh('$boardId-page', null);
        return;
      }
      final previous = _cache.snapshots[boardId];
      final merged = <String, RankingItem>{
        if (previous != null)
          for (final item in previous.items) item.drama.id: item,
        for (final item in result.items) item.drama.id: item,
      };
      final items = merged.values.toList()
        ..sort((a, b) => a.rank.compareTo(b.rank));
      _cache.endRefresh(
        '$boardId-page',
        HongguoRankSnapshot(
          boardId: boardId,
          items: items,
          updatedText: previous?.updatedText ?? result.updatedText,
          fetchedAt: previous?.fetchedAt ?? DateTime.now(),
        ),
      );
      setState(() {
        _page = result.page;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) {
        _cache.endRefresh('$boardId-page', null);
        return;
      }
      _cache.endRefresh('$boardId-page', null);
      setState(() {
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  void _selectBoard(String boardId) {
    if (boardId == _boardId) return;
    setState(() {
      _boardId = boardId;
      _topic = '';
      _page = 1;
      _hasMore = false;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _maybeRefresh(boardId);
  }

  void _selectTopic(String topic) {
    setState(() => _topic = topic);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String get _subtitle {
    final snapshot = _snapshot;
    final boardLabel = hongguoRankBoards
        .firstWhere(
          (board) => board.id == _boardId,
          orElse: () => hongguoRankBoards.first,
        )
        .label;
    if (snapshot == null) return '选择榜单，发现下一部好剧';
    final total = snapshot.items.length;
    final shown = _items.length;
    final updated = snapshot.updatedText.isNotEmpty
        ? snapshot.updatedText
        : '来源：红果官网热播榜';
    final age = DateTime.now().difference(snapshot.fetchedAt);
    final freshText = age.inMinutes < 1
        ? '刚刚更新'
        : '${age.inMinutes}分钟前更新';
    final topicText = _topic.isEmpty
        ? '筛选覆盖本榜全部作品'
        : '$_topic $shown部（保留原榜名次）';
    final refreshing = _cache.isRefreshing(_boardId) ? ' · 正在后台更新…' : '';
    return '$boardLabel热播榜 · $updated · $total部 · $topicText · $freshText$refreshing';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final topics = snapshot?.topics ?? const [];
    final items = _items;
    final refreshing = _cache.isRefreshing(_boardId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('红果热播榜'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: refreshing
                ? null
                : () => _maybeRefresh(_boardId, force: true),
            icon: refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final board in hongguoRankBoards)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: ChoiceChip(
                        label: Text(board.label),
                        selected: board.id == _boardId,
                        onSelected: (_) => _selectBoard(board.id),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            if (topics.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('全部题材 · ${snapshot!.items.length}部'),
                        selected: _topic.isEmpty,
                        onSelected: (_) => _selectTopic(''),
                      ),
                    ),
                    for (final topic in topics)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            '$topic · ${hongguoRankFiltered(snapshot.items, topic).length}部',
                          ),
                          selected: _topic == topic,
                          onSelected: (_) => _selectTopic(topic),
                        ),
                      ),
                  ],
                ),
              ),
            if (_loading && items.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2),
            if (_error != null && items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _maybeRefresh(_boardId, force: true),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading && items.isEmpty
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : items.isEmpty
                  ? StatusPanel(
                      title: _error == null ? '暂无榜单内容' : '榜单暂时无法加载',
                      message: _error ?? '当前站源暂无可显示的榜单。',
                      onRetry: () => _maybeRefresh(_boardId, force: true),
                    )
                  : RefreshIndicator.adaptive(
                      onRefresh: () => _maybeRefresh(_boardId, force: true),
                      child: ListView.builder(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: items.length + 1,
                        itemBuilder: (context, index) {
                          if (index == items.length) {
                            return Center(
                              child: _loadingMore
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child:
                                          CircularProgressIndicator.adaptive(),
                                    )
                                  : _hasMore
                                  ? OutlinedButton(
                                      onPressed: _loadMore,
                                      child: const Text('加载更多'),
                                    )
                                  : const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('已显示全部榜单'),
                                    ),
                            );
                          }
                          final item = items[index];
                          final heat = hongguoRankHeat(item);
                          return Card(
                            child: InkWell(
                              key: ValueKey(
                                'hongguo-rank-${item.rank}-${item.drama.id}',
                              ),
                              borderRadius: BorderRadius.circular(12),
                              onTap: () =>
                                  widget.onOpenDrama(item.drama),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 36,
                                      child: Text(
                                        '${item.rank}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: item.rank <= 3
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 72,
                                      height: 108,
                                      child: DramaCover(
                                        drama: item.drama,
                                        repository: widget.repository,
                                        radius: 8,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.drama.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                          if (item.drama.category.isNotEmpty)
                                            Text(
                                              item.drama.category,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          if (heat.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 8,
                                              ),
                                              child: Text(
                                                heat,
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
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
    );
  }
}
