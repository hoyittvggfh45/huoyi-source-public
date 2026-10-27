import 'dart:async';

import 'package:flutter/material.dart';

import 'hiker_col_type.dart';
import 'hiker_miniapp_detail.dart';
import 'hiker_miniapp_engine.dart';
import 'hiker_miniapp_models.dart';

class HikerMiniappHomeScreen extends StatefulWidget {
  const HikerMiniappHomeScreen({
    super.key,
    required this.engine,
    required this.onPlay,
  });

  final HikerMiniappEngine engine;
  final HikerPlayCallback onPlay;

  @override
  State<HikerMiniappHomeScreen> createState() => _HikerMiniappHomeScreenState();
}

class _HikerMiniappHomeScreenState extends State<HikerMiniappHomeScreen> {
  var _categoryIndex = 0;
  var _page = 1;
  var _loading = true;
  var _loadingMore = false;
  String? _error;
  var _cards = <HikerMiniappCard>[];
  var _searchMode = false;
  var _searching = false;
  var _searchCards = <HikerMiniappCard>[];
  late final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }
    try {
      final page = reset ? 1 : _page + 1;
      final cards = await widget.engine.home(
        categoryIndex: _categoryIndex,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _cards = reset ? cards : [..._cards, ...cards];
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final cards = await widget.engine.search(query);
      if (!mounted) return;
      setState(() {
        _searchCards = cards;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _searching = false;
      });
    }
  }

  Future<void> _openDetail(HikerMiniappCard card) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => HikerMiniappDetailScreen(
          engine: widget.engine,
          card: card,
          onPlay: widget.onPlay,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rule = widget.engine.rule;
    final categories = rule.categories;
    final layout = hikerColLayout(rule.colType);
    final shown = _searchMode ? _searchCards : _cards;
    return Scaffold(
      appBar: AppBar(
        title: _searchMode
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索',
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
              )
            : Text(rule.title.isEmpty ? '海阔' : rule.title),
        actions: [
          IconButton(
            icon: Icon(
              _searchMode ? Icons.close_rounded : Icons.search_rounded,
            ),
            onPressed: () {
              setState(() {
                _searchMode = !_searchMode;
                if (!_searchMode) _searchCards = [];
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (categories.length > 1)
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final selected = index == _categoryIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(categories[index].name),
                      selected: selected,
                      onSelected: (_) {
                        if (_categoryIndex == index) return;
                        setState(() => _categoryIndex = index);
                        unawaited(_load(reset: true));
                      },
                    ),
                  );
                },
              ),
            ),
          Expanded(child: _buildBody(layout, shown)),
          if (!_searchMode && _cards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: () => unawaited(_load()),
                      child: const Text('下一页'),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(HikerColLayout layout, List<HikerMiniappCard> shown) {
    if (_loading && !_searchMode) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => unawaited(_load(reset: true)),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (shown.isEmpty) return const Center(child: Text('暂无内容'));
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: layout.columns,
        childAspectRatio: hikerColAspect(layout.kind),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: shown.length,
      itemBuilder: (context, index) {
        final card = shown[index];
        return InkWell(
          onTap: () => unawaited(_openDetail(card)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _cover(card.pic)),
              const SizedBox(height: 4),
              Text(card.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (card.desc.isNotEmpty)
                Text(card.desc, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }

  Widget _cover(String pic) {
    if (pic.isEmpty) return Container(color: Colors.black12);
    return Image.network(
      pic,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, _, _) => Container(color: Colors.black12),
    );
  }
}
