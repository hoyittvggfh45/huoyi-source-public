import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'app_page_route.dart';
import 'core_bridge.dart';
import 'hongguo_playback_page.dart';
import 'local_store.dart';
import 'models.dart';
import 'tvbox_player_bridge.dart';
import 'watchroom/player.dart';
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

typedef _Channel = ({String key, String label, String? categoryId});

class _HongguoDramaHomeState extends State<HongguoDramaHome> {
  int _tab = 0;
  String _channel = 'recommend';
  bool _didRandomStart = false;
  bool _synopsisExpanded = false;
  late final PageController _pages;
  final RoomPlayerHandle _player = RoomPlayerHandle();
  final Map<String, DramaDetail> _details = {};
  int _index = 0;
  int _episode = 0;
  bool _detailLoading = false;
  String? _detailError;
  int _playToken = 0;
  bool _opening = false;
  bool _pendingPlay = false;
  String _videoKeys = '';

  @override
  void initState() {
    super.initState();
    final videos = _videos;
    _videoKeys = videos.map(_keyFor).join('|');
    if (videos.length > 1) {
      _didRandomStart = true;
      _index = Random().nextInt(videos.length);
      _pages = PageController(initialPage: _index);
    } else {
      _pages = PageController();
    }
    if (videos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _videos.isEmpty) return;
        unawaited(_playCurrent());
        unawaited(_prefetch(_index + 1));
      });
    }
  }

  @override
  void didUpdateWidget(HongguoDramaHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_channel != 'follow') {
      _channel = _channelForCategory(widget.selectedCategory) ?? '';
    }
    final next = _videos;
    final nextKeys = next.map(_keyFor).join('|');
    if (nextKeys == _videoKeys) return;
    _videoKeys = nextKeys;
    _playToken++;
    var target = 0;
    if (!_didRandomStart && next.length > 1) {
      _didRandomStart = true;
      target = Random().nextInt(next.length);
    }
    setState(() {
      _index = target;
      _episode = 0;
      _synopsisExpanded = false;
      _detailError = null;
    });
    if (next.isEmpty) return;
    _scheduleGoTo(target);
  }

  @override
  void dispose() {
    _playToken++;
    _pages.dispose();
    _player.dispose();
    super.dispose();
  }

  String _keyFor(Drama drama) => '${drama.source}|${drama.id}';

  List<Drama> get _videos {
    if (_channel == 'follow') {
      return widget.store.favorites
          .where(
            (drama) =>
                drama.source == 'hongguo' ||
                drama.id.startsWith('hongguo:'),
          )
          .toList();
    }
    return widget.dramas.where((drama) => drama.kind == 'video').toList();
  }

  _Channel _recommendChannel() {
    for (final category in widget.categories) {
      if (category.name == '推荐') {
        return (
          key: 'recommend',
          label: '推荐',
          categoryId: category.id,
        );
      }
    }
    for (final category in widget.categories) {
      if (category.name == '全部' || category.id.isEmpty) {
        return (
          key: 'recommend',
          label: '推荐',
          categoryId: category.id,
        );
      }
    }
    return (
      key: 'recommend',
      label: '推荐',
      categoryId:
          widget.categories.isEmpty ? null : widget.categories.first.id,
    );
  }

  List<_Channel> get _channels {
    final list = <_Channel>[_recommendChannel()];
    final seen = <String>{'recommend'};
    for (final category in widget.categories) {
      if ((category.name == '真人剧' || category.id == 'short_play') &&
          seen.add('real')) {
        list.add(
          (key: 'real', label: '真人剧', categoryId: category.id),
        );
      }
      if ((category.name == '漫剧' || category.id == 'comic_series') &&
          seen.add('comic')) {
        list.add(
          (key: 'comic', label: '漫剧', categoryId: category.id),
        );
      }
    }
    list.add((key: 'follow', label: '关注', categoryId: null));
    return list;
  }

  String? _channelForCategory(String categoryId) {
    for (final channel in _channels) {
      if (channel.categoryId != null &&
          channel.categoryId == categoryId) {
        return channel.key;
      }
    }
    for (final category in widget.categories) {
      if (category.id == categoryId && category.name == '全部') {
        return 'recommend';
      }
    }
    return null;
  }

  void _scheduleGoTo(int index) {
    if (_pages.hasClients) {
      _goToPage(index);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _videos.isEmpty) return;
        _goToPage(index.clamp(0, _videos.length - 1));
      });
    }
  }

  void _goToPage(int index) {
    if (_pages.hasClients && (_pages.page?.round() ?? 0) != index) {
      _pages.jumpToPage(index);
    } else {
      unawaited(_playCurrent());
      unawaited(_prefetch(index + 1));
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _index = index;
      _episode = 0;
      _synopsisExpanded = false;
      _detailError = null;
    });
    unawaited(_playCurrent());
    unawaited(_prefetch(index + 1));
  }

  Future<void> _playCurrent() async {
    final videos = _videos;
    if (videos.isEmpty || !mounted || _tab != 0) return;
    if (_opening) {
      _pendingPlay = true;
      return;
    }
    final token = ++_playToken;
    _opening = true;
    try {
      final index = _index.clamp(0, videos.length - 1);
      final drama = videos[index];
      var detail = _details[_keyFor(drama)];
      if (detail == null) {
        setState(() {
          _detailLoading = true;
          _detailError = null;
        });
        try {
          detail = await widget.repository.detail(drama);
        } catch (error) {
          if (!mounted || token != _playToken) return;
          setState(() {
            _detailLoading = false;
            _detailError = error.toString();
          });
          return;
        }
        if (!mounted || token != _playToken) return;
        _details[_keyFor(drama)] = detail;
        setState(() => _detailLoading = false);
      }
      if (detail.episodes.isEmpty) {
        if (!mounted || token != _playToken) return;
        setState(() => _detailError = '暂无可播剧集');
        return;
      }
      final episodeIndex = _episode.clamp(0, detail.episodes.length - 1);
      if (episodeIndex != _episode) {
        setState(() => _episode = episodeIndex);
      }
      if (!mounted || token != _playToken) return;
      await _player.open(
        detail: detail,
        episodeIndex: episodeIndex,
        startPosition: 0,
        repository: widget.repository,
        store: widget.store,
      );
      if (mounted) setState(() {});
    } finally {
      _opening = false;
      if (_pendingPlay) {
        _pendingPlay = false;
        if (mounted) unawaited(_playCurrent());
      }
    }
  }

  Future<void> _prefetch(int index) async {
    final videos = _videos;
    if (index < 0 || index >= videos.length) return;
    final drama = videos[index];
    if (_details.containsKey(_keyFor(drama))) return;
    try {
      final detail = await widget.repository.detail(drama);
      if (!mounted) return;
      _details[_keyFor(drama)] = detail;
    } catch (_) {}
  }

  Future<void> _togglePlay() async {
    if (!_player.hasVideo) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  void _onCompleted() {
    final videos = _videos;
    if (videos.isEmpty) return;
    if (_index + 1 < videos.length) {
      unawaited(
        _pages.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    } else {
      unawaited(_playCurrent());
    }
  }

  Future<void> _openPlayback(Drama drama) async {
    final wasPlaying = _player.hasVideo && _player.playing;
    if (_player.hasVideo) await _player.pause();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      appPageRoute<void>(
        settings: const RouteSettings(name: 'hongguo-playback'),
        builder: (_) => HongguoPlaybackPage(
          drama: drama,
          repository: widget.repository,
          store: widget.store,
          detail: _details[_keyFor(drama)],
          initialEpisode: _episode,
          startPosition: _player.position,
        ),
      ),
    );
    if (!mounted) return;
    if (wasPlaying && _player.hasVideo) unawaited(_player.play());
  }

  Future<void> _toggleFavorite(Drama drama) async {
    await widget.store.toggleFavorite(drama);
    if (mounted) setState(() {});
  }

  void _note(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _onChannelTap(_Channel channel) {
    setState(() {
      _channel = channel.key;
      _index = 0;
      _episode = 0;
      _synopsisExpanded = false;
      _detailError = null;
    });
    if (channel.key == 'follow') {
      _goToPage(0);
    } else if (channel.categoryId != null &&
        channel.categoryId != widget.selectedCategory) {
      widget.onCategorySelected(channel.categoryId!);
    } else {
      _goToPage(0);
    }
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
    if (index != 0) {
      if (_player.hasVideo) unawaited(_player.pause());
    } else if (_player.hasVideo) {
      if (!_player.playing) unawaited(_player.play());
    } else {
      unawaited(_playCurrent());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _tab == 0 ? Colors.black : null,
      body: switch (_tab) {
        1 => _theater(context),
        2 => _mine(context),
        _ => _feed(context),
      },
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
            surface: Colors.black,
            onSurface: Colors.white,
            onSurfaceVariant: Colors.white70,
            secondary: Colors.white,
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.black,
          indicatorColor: Colors.transparent,
          selectedIndex: _tab,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: Colors.white70),
              selectedIcon: Icon(Icons.home, color: Colors.white),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.theater_comedy_outlined, color: Colors.white70),
              selectedIcon: Icon(Icons.theater_comedy, color: Colors.white),
              label: '剧场',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline, color: Colors.white70),
              selectedIcon: Icon(Icons.person, color: Colors.white),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }

  Widget _feed(BuildContext context) {
    final videos = _videos;
    if (videos.isEmpty) {
      return SafeArea(
        child: StatusPanel(
          title: _channel == 'follow' ? '暂无关注短剧' : '暂无可播短剧',
          message: _channel == 'follow'
              ? '在剧集上点收藏后，这里会显示你关注的短剧。'
              : '可以换个分类或刷新后重试。',
        ),
      );
    }
    return Stack(
      children: [
        PageView.builder(
          scrollDirection: Axis.vertical,
          controller: _pages,
          onPageChanged: _onPageChanged,
          itemCount: videos.length,
          itemBuilder: (context, index) {
            return _buildFeedPage(context, videos[index], index == _index);
          },
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _feedTopBar(),
        ),
      ],
    );
  }

  Widget _feedTopBar() {
    final channels = _channels;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            for (final channel in channels) ...[
              GestureDetector(
                onTap: () => _onChannelTap(channel),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel.label,
                      style: TextStyle(
                        color: _channel == channel.key
                            ? Colors.white
                            : Colors.white70,
                        fontSize: 16,
                        fontWeight: _channel == channel.key
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 20,
                      height: 3,
                      decoration: BoxDecoration(
                        color: _channel == channel.key
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
            ],
            const Spacer(),
            IconButton(
              onPressed: () => _selectTab(1),
              icon: const Icon(Icons.search, color: Colors.white),
              tooltip: '搜索',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedPage(BuildContext context, Drama drama, bool isCurrent) {
    return GestureDetector(
      onTap: isCurrent ? _togglePlay : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _videoArea(context, drama, isCurrent),
          if (isCurrent) ...[
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
            Positioned.fill(
              child: Align(
                alignment: const Alignment(1.0, 0.0),
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _feedAction(
                        icon: widget.store.isFavorite(drama.id)
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        label: '收藏',
                        onTap: () => unawaited(_toggleFavorite(drama)),
                      ),
                      const SizedBox(height: 20),
                      _feedAction(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: '评论',
                        onTap: () => _note('该剧暂无评论数据'),
                      ),
                      const SizedBox(height: 20),
                      _feedAction(
                        icon: Icons.favorite_outline_rounded,
                        label: '点赞',
                        onTap: () => _note('该剧暂无点赞数据'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 72,
              bottom: 24,
              child: _feedInfo(context, drama),
            ),
          ],
        ],
      ),
    );
  }

  Widget _videoArea(BuildContext context, Drama drama, bool isCurrent) {
    if (!isCurrent) {
      return DramaCover(drama: drama, repository: widget.repository);
    }
    return ListenableBuilder(
      listenable: _player,
      builder: (context, _) {
        final keyMatches = _player.videoKey == '${drama.id}|$_episode';
        if (_player.loading ||
            _player.error != null ||
            (keyMatches && _player.hasVideo)) {
          return RoomPlayerView(
            handle: _player,
            viewType: widget.store.player == 'fongmi'
                ? TvboxPlayerController.fongmiViewType
                : TvboxPlayerController.viewType,
            onCompleted: _onCompleted,
            onError: (_) {},
            onRetry: () => unawaited(_playCurrent()),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            DramaCover(drama: drama, repository: widget.repository),
            if (_detailLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (_detailError != null)
              Center(
                child: StatusPanel(
                  title: '加载失败',
                  message: _detailError!,
                  onRetry: () => unawaited(_playCurrent()),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _feedAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _feedInfo(BuildContext context, Drama drama) {
    final detail = _details[_keyFor(drama)];
    final episodeCount = detail?.episodes.length ?? drama.episodes;
    final synopsis =
        detail?.drama.description ?? drama.description;
    final episodeLine = detail != null && _episode < detail.episodes.length
        ? '第${_episode + 1}集 | ${detail.episodes[_episode].title}'
        : null;
    final isComic = _channel == 'comic' ||
        drama.category == 'comic_series' ||
        drama.category.contains('漫') ||
        drama.category.contains('comic');
    final kindLabel = isComic ? '漫剧' : '短剧';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (drama.tags.isNotEmpty)
          Wrap(
            spacing: 6,
            children: drama.tags
                .take(4)
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => unawaited(_openPlayback(drama)),
          child: Text(
            drama.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (episodeLine != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              episodeLine,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
          ),
        if (synopsis.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    synopsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white70),
                    maxLines: _synopsisExpanded ? null : 2,
                    overflow: _synopsisExpanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                ),
                if (synopsis.length > 80)
                  GestureDetector(
                    onTap: () => setState(
                      () => _synopsisExpanded = !_synopsisExpanded,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        _synopsisExpanded ? '收起' : '展开',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (drama.heat.isNotEmpty || drama.views.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              drama.heat.isNotEmpty ? drama.heat : drama.views,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => unawaited(_openPlayback(drama)),
          icon: const Icon(Icons.play_arrow),
          label: Text(
            episodeCount > 0
                ? '观看完整$kindLabel · 全$episodeCount集'
                : '观看完整$kindLabel',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFE2C55),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _theater(BuildContext context) {
    final videos =
        widget.dramas.where((drama) => drama.kind == 'video').toList();
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
                            child: DramaCover(
                              drama: drama,
                              repository: widget.repository,
                            ),
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
