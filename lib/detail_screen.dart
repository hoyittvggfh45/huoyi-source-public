import 'dart:async';

import 'app_page_route.dart';

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:media_kit/media_kit.dart';

import 'app_layout.dart';
import 'atmosphere_background.dart';
import 'detail_inline_player.dart';
import 'ios_dialogs.dart';
import 'liquid_glass.dart';
import 'core_bridge.dart';
import 'download_picker.dart';
import 'downloads_screen.dart';
import 'local_store.dart';
import 'models.dart';
import 'playback_queue.dart';
import 'player_picker.dart';
import 'remote_widgets.dart';
import 'widgets.dart';
import 'sources_screen.dart';
import 'episode_browser.dart';
import 'follow_state.dart';
import 'watchroom/controller.dart';
import 'watchroom/models.dart';
import 'watchroom/room_screen.dart';
import 'hongguo_series.dart';

typedef DetailTagTap =
    void Function(String sourceId, String tagId, String tagName);

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.drama,
    required this.repository,
    required this.store,
    this.resumeOnOpen = false,
    this.downloadOnOpen = false,
    this.onTagTap,
    this.queue,
    this.playerFactory,
    this.videoBuilder,
  });
  final Drama drama;
  final AppRepository repository;
  final LocalStore store;
  final bool resumeOnOpen;
  final bool downloadOnOpen;

  @visibleForTesting
  final Player Function()? playerFactory;

  @visibleForTesting
  final Widget Function(Widget controls)? videoBuilder;

  /// 标签点击回调：以 sourceId + tagId 打开该标签的目录列表。
  /// TODO(shell): 目录侧标签列表入口由壳子代理提供并在构造 DetailScreen 时
  /// 注入；未注入时标签仅展示、点击给未接入提示。
  final DetailTagTap? onTagTap;

  /// 进入播放时透传给播放器的列表上下文队列（单集上下滑切条目用）。
  final PlaybackQueue? queue;
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  DramaDetail? _detail;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  int _episodePage = 0;
  bool _expandedDescription = false;
  bool _episodesExpanded = false;
  final _episodeAnchor = GlobalKey();
  final _detailScroll = ScrollController();
  final _playFocus = FocusNode(debugLabel: 'tv-detail-play');
  bool _initialActionHandled = false;
  int? _inlineIndex;
  double _inlinePosition = 0;
  late final int _profileEpoch;
  Widget? get _sourceDiagnostics => widget.repository.supportsSourceManagement
      ? SourceDiagnosticsButton(
          repository: widget.repository,
          store: widget.store,
          drama: widget.drama,
        )
      : null;

  @override
  void initState() {
    super.initState();
    _profileEpoch = widget.store.profileEpoch;
    widget.store.addListener(_onStoreChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant DetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
  }

  @override
  void dispose() {
    _detailScroll.dispose();
    _playFocus.dispose();
    widget.store.removeListener(_onStoreChanged);
    _generation++;
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.detail(widget.drama);
      if (!mounted ||
          generation != _generation ||
          _profileEpoch != widget.store.profileEpoch) {
        return;
      }
      final merged = widget.repository.catalogUpdates
          .current(widget.drama)
          .merge(detail.drama);
      setState(() {
        _detail = detail.withDrama(merged);
        _loading = false;
        _episodePage =
            resumeEpisodeIndex(
              detail.episodes,
              widget.store.watched(merged.id),
            ) ~/
            episodePageSize;
      });
      widget.repository.catalogUpdates.publish(merged, retryCover: true);
      unawaited(_supplement(merged, generation));
      await saveUserChange(context, () => widget.store.refreshDrama(merged));
      if (mounted &&
          generation == _generation &&
          _profileEpoch == widget.store.profileEpoch &&
          !_initialActionHandled &&
          detail.episodes.isNotEmpty) {
        _initialActionHandled = true;
        if (widget.resumeOnOpen) {
          unawaited(
            _play(
              resumeEpisodeIndex(
                detail.episodes,
                widget.store.watched(merged.id),
              ),
              resume: true,
            ),
          );
        } else if (widget.downloadOnOpen && widget.store.canDownload) {
          unawaited(_download());
        }
      }
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
      widget.repository.catalogUpdates.publish(
        widget.repository.catalogUpdates.current(widget.drama),
        retryCover: true,
      );
    }
  }

  Future<void> _supplement(Drama drama, int generation) async {
    try {
      final fresh = await widget.repository.supplementMetadata(drama);
      if (!mounted ||
          generation != _generation ||
          fresh == null ||
          _detail == null) {
        return;
      }
      final updated = _detail!.drama.merge(fresh);
      setState(() {
        _detail = _detail!.withDrama(updated);
      });
      widget.repository.catalogUpdates.publish(updated);
      await saveUserChange(context, () => widget.store.refreshDrama(updated));
    } catch (_) {}
  }

  Future<void> _download() async {
    final detail = _detail;
    if (detail == null ||
        !widget.store.canDownload ||
        _profileEpoch != widget.store.profileEpoch) {
      return;
    }
    final selection = await Navigator.of(context).push<DownloadSelection>(
      appPageRoute(
        builder: (_) => DownloadPicker(
          detail: detail,
          preferences: widget.store.downloadPreferences,
        ),
      ),
    );
    if (selection == null ||
        !mounted ||
        !widget.store.canDownload ||
        _profileEpoch != widget.store.profileEpoch) {
      return;
    }
    try {
      final added = await widget.repository.enqueueDownloads(
        detail,
        selection.episodes,
        quality: selection.quality,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added == 0 ? '所选集数已在下载列表中' : '已加入 $added 集，已有任务自动跳过'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () {
              Navigator.of(context).push(
                appPageRoute<void>(
                  builder: (_) => DownloadsScreen(
                    repository: widget.repository,
                    store: widget.store,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _play(
    int index, {
    bool resume = false,
    bool fullscreen = false,
  }) async {
    final detail = _detail;
    if (detail == null ||
        index < 0 ||
        index >= detail.episodes.length ||
        _profileEpoch != widget.store.profileEpoch ||
        !widget.store.allowsSource(detail.drama.source)) {
      return;
    }
    if (detail.episodes[index].vip &&
        detail.drama.source != SourceSite.dsd.id) {
      final accepted = await confirmAction(
        context,
        title: '这是一集 VIP 内容',
        message: '站源可能只提供试看或限制播放。',
        confirm: '尝试播放',
      );
      if (!accepted || !mounted) {
        return;
      }
    }
    final saved = widget.store.watched(detail.drama.id);
    final position =
        resume &&
            saved?.episode == detail.episodes[index].number &&
            !saved!.finished
        ? saved.position
        : 0.0;
    if (!mounted || _profileEpoch != widget.store.profileEpoch) {
      return;
    }
    if (fullscreen ||
        AppLayout.isTelevision(context) ||
        MediaQuery.sizeOf(context).width >= 960) {
      await pushPlayer<void>(
        context,
        detail: detail,
        initialIndex: index,
        initialPosition: position,
        repository: widget.repository,
        store: widget.store,
        queue: widget.queue,
        startFullscreen: fullscreen,
      );
      if (mounted) {
        setState(() {});
      }
      return;
    }
    setState(() {
      _inlineIndex = index;
      _inlinePosition = position;
    });
  }

  Widget _inlineArea(Drama drama) {
    final detail = _detail;
    final episodes = detail?.episodes ?? const <Episode>[];
    final inlineIndex = _inlineIndex;
    if (detail != null &&
        inlineIndex != null &&
        inlineIndex >= 0 &&
        inlineIndex < episodes.length) {
      return InlinePlayer(
        key: ValueKey('inline-${drama.id}-${episodes[inlineIndex].number}'),
        detail: detail,
        index: inlineIndex,
        initialPosition: _inlinePosition,
        repository: widget.repository,
        store: widget.store,
        playerFactory: widget.playerFactory,
        videoBuilder: widget.videoBuilder,
      );
    }
    if (episodes.isEmpty) return _hero(drama);
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverHeight = constraints.maxWidth * 9 / 16;
        return Stack(
          children: [
            _hero(drama),
            Positioned(
              top: coverHeight / 2 - 32,
              left: 0,
              right: 0,
              child: Center(
                child: IconButton.filled(
                  key: const ValueKey('inline-play'),
                  tooltip: '播放',
                  onPressed: () => _play(
                    resumeEpisodeIndex(
                      episodes,
                      widget.store.watched(drama.id),
                    ),
                    resume: true,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 40),
                  style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pushToWatchRoom() async {
    final detail = _detail;
    final episodes = detail?.episodes ?? <Episode>[];
    if (detail == null || episodes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂无可推送的剧集')));
      }
      return;
    }
    final drama = detail.drama;
    if (widget.store.profileEpoch != _profileEpoch ||
        !widget.store.allowsSource(drama.source)) {
      return;
    }
    final watched = widget.store.watched(drama.id);
    final index = resumeEpisodeIndex(
      episodes,
      watched,
    ).clamp(0, episodes.length - 1);
    final room = WatchRoomController.instance;
    try {
      if (room.inRoom && !room.isHost) {
        throw StateError('只有房主可以更换房间视频');
      }
      if (!room.inRoom) {
        await room.createRoom(preferences: widget.store.preferences);
      }
      room.setVideo(
        RoomVideo(
          source: drama.source,
          dramaId: drama.id,
          title: drama.title,
          cover: drama.cover,
          sourceId: drama.sourceId,
          episodeIndex: index,
          episodeTitle: episodes[index].title,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      appPageRoute<void>(
        builder: (_) =>
            WatchRoomScreen(repository: widget.repository, store: widget.store),
      ),
    );
  }

  Future<void> _openSeriesDrama(Drama drama) async {
    if (_profileEpoch != widget.store.profileEpoch ||
        drama.id == (_detail?.drama.id ?? widget.drama.id)) {
      return;
    }
    final anchor = _detail?.drama ?? widget.drama;
    if (widget.store.following(anchor.id)?.seriesSeasons[drama.id]?.read ==
        false) {
      await saveUserChange(
        context,
        () => widget.store.markSeriesSeasonRead(anchor.id, drama.id),
      );
      if (!mounted) return;
    }
    await Navigator.of(context).pushReplacement(
      appPageRoute<void>(
        settings: const RouteSettings(name: 'detail'),
        builder: (_) => DetailScreen(
          drama: drama,
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    );
  }

  // _openPeerSource 切换到同一部剧在其它站源的副本继续播放。
  Future<void> _openPeerSource(Drama current, Drama peer) async {
    if (peer.id == current.id) return;
    final peers = <Drama>[
      current.withPeers(const []),
      ...current.peers.where((item) => item.id != peer.id),
    ];
    await Navigator.of(context).pushReplacement(
      appPageRoute<void>(
        settings: const RouteSettings(name: 'detail'),
        builder: (_) => DetailScreen(
          drama: peer.withPeers(peers),
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // _sourceSwitcher 展示同一部剧在其它站源的副本，可一键切换播放源。
  Widget _sourceSwitcher(Drama drama) {
    if (drama.peers.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz_rounded, size: 15, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                '切换播放源',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final peer in drama.peers)
                ActionChip(
                  key: ValueKey('peer-source-${peer.source}'),
                  avatar: Icon(
                    Icons.play_arrow_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  label: Text(
                    peer.episodes > 0
                        ? '${SourceSite.byId(peer.source).name} · ${peer.episodes} 集'
                        : SourceSite.byId(peer.source).name,
                  ),
                  onPressed: () => _openPeerSource(drama, peer),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drama = _detail?.drama ?? widget.drama;
    final watched = widget.store.watched(drama.id);
    final episodes = _detail?.episodes ?? <Episode>[];
    final resumeIndex = resumeEpisodeIndex(episodes, watched);
    final television = AppLayout.isTelevision(context);
    final allowed =
        widget.store.profileEpoch == _profileEpoch &&
        widget.store.allowsSource(drama.source);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.goBack): () =>
            Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: television ? 64 : null,
          title: Text(drama.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: '推送到一起看',
              onPressed: allowed ? () => unawaited(_pushToWatchRoom()) : null,
              icon: const Icon(Icons.meeting_room_rounded),
            ),
            RefreshAction(
              loading: _loading,
              tooltip: '更新剧集信息',
              onPressed: allowed ? _load : null,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!allowed) {
                    return const StatusPanel(
                      title: '当前用户无权访问',
                      message: '请返回剧库后重新选择。',
                    );
                  }
                  if (television || constraints.maxWidth >= 960) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: (constraints.maxWidth * .34).clamp(
                            250.0,
                            360.0,
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _overview(drama),
                                _descriptionSection(drama),
                                _stillsSection(),
                                _relatedSection(drama),
                              ],
                            ),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _loading || _error != null || episodes.isEmpty
                              ? _episodeStatus()
                              : Column(
                                  children: [
                                    _seriesSelector(drama),
                                    Expanded(
                                      child: EpisodeBrowser(
                                        episodes: episodes,
                                        currentNumber: watched?.episode,
                                        onExitDown: () =>
                                            _playFocus.requestFocus(),
                                        onSelected: (index) => _play(index),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    );
                  }
                  final start = _episodePage * episodePageSize;
                  final visible = episodes
                      .skip(start)
                      .take(episodePageSize)
                      .toList();
                  final showEpisodes = _episodesExpanded;
                  final inlineNumber =
                      _inlineIndex != null &&
                          _inlineIndex! >= 0 &&
                          _inlineIndex! < episodes.length
                      ? episodes[_inlineIndex!].number
                      : null;
                  final currentNumber = inlineNumber ?? watched?.episode;
                  return CustomScrollView(
                    controller: _detailScroll,
                    slivers: [
                      SliverToBoxAdapter(child: _inlineArea(drama)),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                          child: _overview(drama),
                        ),
                      ),
                      if (_loading || _error != null || episodes.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _episodeStatus(),
                        )
                      else ...[
                        SliverToBoxAdapter(child: _seriesSelector(drama)),
                        SliverToBoxAdapter(
                          child: _episodeSummary(
                            episodes,
                            currentNumber: currentNumber,
                            expanded: showEpisodes,
                          ),
                        ),
                        if (showEpisodes) ...[
                          SliverToBoxAdapter(
                            child: EpisodeRangeBar(
                              key: _episodeAnchor,
                              episodes: episodes,
                              page: _episodePage,
                              title: '分组',
                              currentNumber: currentNumber,
                              onLocate: _locateEpisode,
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _episodeColumns(
                                      constraints.maxWidth,
                                      episodes,
                                    ),
                                    mainAxisExtent: math.max(
                                      54,
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(20) +
                                          30,
                                    ),
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final episode = visible[index];
                                return RemoteEpisodeButton(
                                  key: ValueKey('episode-${episode.number}'),
                                  number: episode.number,
                                  vip: episode.vip,
                                  current: episode.number == currentNumber,
                                  onPressed: () => _play(start + index),
                                );
                              }, childCount: visible.length),
                            ),
                          ),
                        ],
                      ],
                      if (!_loading) ...[
                        SliverToBoxAdapter(child: _descriptionSection(drama)),
                        SliverToBoxAdapter(child: _stillsSection()),
                        SliverToBoxAdapter(child: _relatedSection(drama)),
                      ],
                      if (glassDesign(context))
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 88 + MediaQuery.paddingOf(context).bottom,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        extendBody: glassDesign(context),
        bottomNavigationBar: glassDesign(context)
            ? _glassPlayBar(allowed, episodes, resumeIndex, watched)
            : Material(
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Row(
                          children: [
                            if (widget.repository.supportsDownloads &&
                                widget.store.canDownload) ...[
                              IconButton.filledTonal(
                                tooltip: '下载选集',
                                onPressed:
                                    allowed && !_loading && episodes.isNotEmpty
                                    ? _download
                                    : null,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(52, 52),
                                ),
                                icon: const Icon(Icons.download_rounded),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: FilledButton.icon(
                                key: const ValueKey('start-play'),
                                autofocus: television,
                                focusNode: _playFocus,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 52),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                onPressed:
                                    !allowed || _loading || episodes.isEmpty
                                    ? null
                                    : () => _play(resumeIndex, resume: true),
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 26,
                                ),
                                label: Text(
                                  watched != null && episodes.isNotEmpty
                                      ? '继续播放 · 第 ${episodes[resumeIndex].number} 集'
                                      : '立即播放',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _glassPlayBar(
    bool allowed,
    List<Episode> episodes,
    int resumeIndex,
    WatchEntry? watched,
  ) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final ready = allowed && !_loading && episodes.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom < 18 ? 12 : bottom - 6),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LiquidGlass(
            borderRadius: const BorderRadius.all(Radius.circular(34)),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Row(
                children: [
                  if (widget.repository.supportsDownloads &&
                      widget.store.canDownload) ...[
                    GlassIconButton(
                      icon: LucideIcons.arrowDownToLine,
                      tooltip: '下载选集',
                      size: 52,
                      onPressed: ready ? _download : null,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: PressableScale(
                      enabled: ready,
                      pressedScale: .97,
                      child: FilledButton.icon(
                        key: const ValueKey('start-play'),
                        focusNode: _playFocus,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        onPressed: ready
                            ? () {
                                HapticFeedback.lightImpact();
                                _play(resumeIndex, resume: true);
                              }
                            : null,
                        icon: const Icon(LucideIcons.play, size: 20),
                        label: Text(
                          watched != null && episodes.isNotEmpty
                              ? '继续播放 · 第 ${episodes[resumeIndex].number} 集'
                              : '立即播放',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero(Drama drama) {
    final detail = _detail;
    final backdrop = detail?.backdrop ?? '';
    final urls = <String>[
      if (backdrop.isNotEmpty) backdrop,
      for (final still in detail?.stills ?? const <String>[])
        if (still.isNotEmpty && still != backdrop) still,
    ];
    if (urls.isEmpty && drama.cover.isNotEmpty) urls.add(drama.cover);
    if (urls.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: DramaCover(
          drama: drama,
          repository: widget.repository,
          radius: 0,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AtmosphereBackground(
                url: urls.first,
                repository: widget.repository,
                drama: Drama(
                  id: '${drama.id}#backdrop',
                  source: drama.source,
                  title: drama.title,
                  cover: urls.first,
                ),
              ),
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DramaCover(
                  key: ValueKey('backdrop-${urls.first}'),
                  drama: Drama(
                    id: '${drama.id}#backdrop',
                    source: drama.source,
                    title: drama.title,
                    cover: urls.first,
                  ),
                  repository: widget.repository,
                  radius: 0,
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black45, Colors.black87],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 104,
                      height: 148,
                      child: DramaCover(
                        drama: drama,
                        repository: widget.repository,
                        radius: 12,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            drama.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (drama.episodes > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '共 ${drama.episodes} 集',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (urls.length > 1)
          SizedBox(
            height: 92,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              itemCount: urls.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 128,
                  child: DramaCover(
                    key: ValueKey('still-$index-${urls[index]}'),
                    drama: Drama(
                      id: '${drama.id}#still$index',
                      source: drama.source,
                      title: drama.title,
                      cover: urls[index],
                    ),
                    repository: widget.repository,
                    radius: 10,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _descriptionSection(Drama drama) {
    if (drama.description.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('简介', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            drama.description,
            maxLines: _expandedDescription ? null : 3,
            overflow: _expandedDescription
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () =>
                  setState(() => _expandedDescription = !_expandedDescription),
              child: Text(_expandedDescription ? '收起简介' : '展开简介'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stillsSection() {
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();
    final backdrop = detail.backdrop;
    final stills = <String>[];
    for (final still in detail.stills) {
      if (still.isNotEmpty && still != backdrop && !stills.contains(still)) {
        stills.add(still);
      }
    }
    if (stills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本片剧照', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: stills.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => SizedBox(
                width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: DramaCover(
                    drama: Drama(
                      id: '${detail.drama.id}#still-$index',
                      source: detail.drama.source,
                      title: detail.drama.title,
                      cover: stills[index],
                    ),
                    repository: widget.repository,
                    radius: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _relatedSection(Drama drama) {
    final related = _detail?.related ?? const <Drama>[];
    if (related.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('相关推荐', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / 150).floor().clamp(2, 6);
              final tileWidth =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: DramaTile.extentFor(context, tileWidth),
                ),
                itemCount: related.length,
                itemBuilder: (context, index) => DramaTile(
                  key: ValueKey('related-${related[index].id}'),
                  drama: related[index],
                  repository: widget.repository,
                  onTap: () => _openRelated(related, related[index]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openRelated(List<Drama> related, Drama target) async {
    if (_profileEpoch != widget.store.profileEpoch ||
        target.id == (_detail?.drama.id ?? widget.drama.id)) {
      return;
    }
    await Navigator.of(context).push(
      appPageRoute<void>(
        settings: const RouteSettings(name: 'detail'),
        builder: (_) => DetailScreen(
          drama: target,
          repository: widget.repository,
          store: widget.store,
          onTagTap: widget.onTagTap,
          queue: PlaybackQueue.around(related, target),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _episodeStatus() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }
    return StatusPanel(
      title: _error != null ? '剧集信息暂时不可用' : '暂时没有可播放的集数',
      message: _error ?? '可以更新剧集信息后重试。',
      onRetry: _load,
      secondaryAction: _sourceDiagnostics,
    );
  }

  Widget _episodeSummary(
    List<Episode> episodes, {
    required int? currentNumber,
    required bool expanded,
  }) {
    final colors = Theme.of(context).colorScheme;
    final current = currentNumber == null ? '' : ' · 当前第 $currentNumber 集';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _episodesExpanded = !expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.grid_view_rounded, color: colors.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '选集 · ${episodes.length} 集$current',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(expanded ? '收起' : '展开'),
                const SizedBox(width: 2),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _locateEpisode(int index) {
    final episodes = _detail!.episodes;
    setState(() {
      _episodePage = index ~/ episodePageSize;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anchor = _episodeAnchor.currentContext;
      if (!mounted || anchor == null || !_detailScroll.hasClients) return;
      final render = anchor.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      final viewport = RenderAbstractViewport.maybeOf(render);
      if (viewport == null) return;
      final start = viewport.getOffsetToReveal(render, 0).offset;
      final extent = math.max(
        54,
        MediaQuery.textScalerOf(context).scale(20) + 30,
      );
      final columns = _episodeColumns(render.size.width, episodes);
      final target =
          start +
          render.size.height +
          (index % episodePageSize ~/ columns) * (extent + 10) -
          _detailScroll.position.viewportDimension * .3;
      _detailScroll.animateTo(
        target.clamp(0.0, _detailScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  int _episodeColumns(double width, List<Episode> episodes) {
    final digits = episodes.fold<int>(
      1,
      (value, episode) => math.max(value, episode.number.toString().length),
    );
    final minimum = math.max(
      82,
      MediaQuery.textScalerOf(context).scale(20) * digits * .65 + 40,
    );
    return ((width - 40) / minimum).floor().clamp(1, 12);
  }

  List<DetailTag> _effectiveTags(Drama drama) {
    final structured = _detail?.tags ?? const <DetailTag>[];
    if (structured.isNotEmpty) return structured;
    return [for (final name in drama.tags) DetailTag(id: name, name: name)];
  }

  void _onTagPressed(Drama drama, DetailTag tag) {
    final onTagTap = widget.onTagTap;
    if (onTagTap != null) {
      onTagTap(drama.source, tag.id, tag.name);
      return;
    }
    // TODO(shell): 标签目录入口未注入时仅提示，接入后走 onTagTap 回调。
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('标签浏览入口待接入')));
  }

  Widget _overview(Drama drama) {
    final colors = Theme.of(context).colorScheme;
    final meta = [
      SourceSite.byId(drama.source).name,
      if (drama.episodes > 0) '共 ${drama.episodes} 集',
      if (drama.releaseStatus.isNotEmpty && drama.releaseStatus != 'unknown')
        drama.releaseLabel,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              height: 138,
              child: DramaCover(drama: drama, repository: widget.repository),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drama.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    meta.join(' · '),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  if (drama.category.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        drama.category,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  if (drama.source == 'huangdou')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        drama.vipStatus == null
                            ? 'VIP 状态待补齐'
                            : drama.vip
                            ? 'VIP 内容'
                            : '免费内容',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _followingControls(drama),
        _sourceSwitcher(drama),
        if (drama.onlineDate.isNotEmpty ||
            drama.heat.isNotEmpty ||
            drama.views.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              [
                if (drama.onlineDate.isNotEmpty) '${drama.onlineDate} 上线',
                if (drama.heat.isNotEmpty) '热度 ${drama.heat}',
                if (drama.views.isNotEmpty) '播放 ${drama.views}',
              ].join(' · '),
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ),
        if (_effectiveTags(drama).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in _effectiveTags(drama).take(12))
                  ActionChip(
                    key: ValueKey('detail-tag-${tag.id}'),
                    label: Text(tag.name),
                    onPressed: () => _onTagPressed(drama, tag),
                  ),
              ],
            ),
          ),
        if (_detail?.warning.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _detail!.warning,
              style: TextStyle(color: colors.error),
            ),
          ),
      ],
    );
  }

  Widget _seriesSelector(Drama drama) {
    final entries = hongguoSeriesEntries(
      drama,
      widget.store.seriesDramasFor(drama),
    );
    if (entries.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final notices = widget.store.following(drama.id)?.seriesSeasons ?? const {};
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('相关推荐', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in entries)
                ChoiceChip(
                  key: ValueKey('series-${entry.drama.id}'),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${entry.label} · ${entry.drama.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (notices[entry.drama.id]?.read == false) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.fiber_new_rounded,
                            size: 18,
                            color: colors.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  selected: entry.drama.id == drama.id,
                  onSelected: entry.drama.id == drama.id
                      ? null
                      : (_) => _openSeriesDrama(entry.drama),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _followingControls(Drama drama) {
    final state = widget.store.following(drama.id);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<String>(
          key: const ValueKey('follow-status'),
          tooltip: '追剧与观看状态',
          onSelected: (value) async {
            if (_profileEpoch != widget.store.profileEpoch) return;
            if (value == 'remove') {
              await saveUserChange(
                context,
                () => widget.store.toggleFavorite(drama),
              );
            } else {
              final status = FollowStatus.values.firstWhere(
                (status) => status.name == value,
              );
              await saveUserChange(
                context,
                () => widget.store.setFollowStatus(drama, status),
              );
            }
          },
          itemBuilder: (_) => [
            for (final status in FollowStatus.values)
              CheckedPopupMenuItem(
                value: status.name,
                checked: state?.status == status,
                child: Text(status.label),
              ),
            if (state != null)
              const PopupMenuItem(value: 'remove', child: Text('取消追剧')),
          ],
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: state == null
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state?.status == FollowStatus.watched
                      ? Icons.check_circle_outline
                      : state == null
                      ? Icons.bookmark_add_outlined
                      : Icons.bookmark_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(state?.label ?? '加入追剧'),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ),
        if (state != null && state.hasUpdates)
          ActionChip(
            label: Text('${state.updateLabel} · 标为已读'),
            onPressed: () => saveUserChange(
              context,
              () => widget.store.markUpdatesRead(drama.id),
            ),
          ),
      ],
    );
  }
}
