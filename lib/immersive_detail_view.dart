import 'package:flutter/material.dart';

import 'episode_browser.dart';
import 'models.dart';

class ImmersiveTopBar extends StatelessWidget {
  const ImmersiveTopBar({
    super.key,
    required this.title,
    required this.onBack,
    this.onPushToWatchRoom,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback? onPushToWatchRoom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('immersive-top-bar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '返回',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onPushToWatchRoom != null) ...[
            const SizedBox(width: 12),
            Tooltip(
              message: '推送到一起看',
              child: InkWell(
                onTap: onPushToWatchRoom,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.meeting_room_rounded,
                    color: Colors.black87,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ImmersiveDetailView extends StatelessWidget {
  const ImmersiveDetailView({
    super.key,
    required this.drama,
    required this.displayEpisodes,
    required this.visibleEpisodes,
    required this.episodeStart,
    required this.episodePage,
    required this.currentNumber,
    required this.reversed,
    required this.isFavorite,
    required this.engineName,
    required this.sourceName,
    required this.peers,
    required this.poster,
    required this.backdrop,
    required this.scrollController,
    required this.episodeSectionKey,
    required this.expandedDescription,
    required this.watchProgress,
    required this.onBack,
    required this.onPlayEpisode,
    required this.onPlayResume,
    required this.onToggleReverse,
    required this.onToggleFavorite,
    required this.onOpenSourcePanel,
    required this.onDownload,
    required this.onSearch,
    required this.onParse,
    required this.onFullscreen,
    required this.onLocateEpisode,
    required this.onToggleDescription,
    this.onPushToWatchRoom,
  });

  final Drama drama;
  final List<Episode> displayEpisodes;
  final List<Episode> visibleEpisodes;
  final int episodeStart;
  final int episodePage;
  final int? currentNumber;
  final bool reversed;
  final bool isFavorite;
  final String engineName;
  final String sourceName;
  final List<Drama> peers;
  final Widget poster;
  final Widget backdrop;
  final ScrollController scrollController;
  final GlobalKey episodeSectionKey;
  final bool expandedDescription;
  final double watchProgress;
  final VoidCallback onBack;
  final ValueChanged<Episode> onPlayEpisode;
  final VoidCallback onPlayResume;
  final VoidCallback onToggleReverse;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenSourcePanel;
  final VoidCallback onDownload;
  final VoidCallback onSearch;
  final VoidCallback onParse;
  final VoidCallback onFullscreen;
  final ValueChanged<int> onLocateEpisode;
  final VoidCallback onToggleDescription;
  final VoidCallback? onPushToWatchRoom;

  String get _updateLabel =>
      drama.releaseStatus.isNotEmpty && drama.releaseStatus != 'unknown'
      ? drama.releaseLabel
      : '暂无';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final margin = width * 0.04;
    return Stack(
      children: [
        Positioned.fill(child: backdrop),
        SafeArea(
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ImmersiveTopBar(
                  title: drama.title,
                  onBack: onBack,
                  onPushToWatchRoom: onPushToWatchRoom,
                ),
                Padding(
                  key: const ValueKey('immersive-player-card'),
                  padding: EdgeInsets.symmetric(horizontal: margin),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: Colors.black,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            poster,
                            Center(
                              child: IconButton.filled(
                                onPressed: onPlayResume,
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 36,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black87,
                                    ],
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      onPressed: onPlayResume,
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            currentNumber != null
                                                ? '第 $currentNumber 集 / 共 ${displayEpisodes.length} 集'
                                                : '共 ${displayEpisodes.length} 集',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(
                                            value: watchProgress.clamp(
                                              0.0,
                                              1.0,
                                            ),
                                            backgroundColor: Colors.white24,
                                            color: Colors.white,
                                            minHeight: 3,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: onFullscreen,
                                      icon: const Icon(
                                        Icons.fullscreen_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(margin, 16, margin, 0),
                  child: Text(
                    drama.title,
                    key: const ValueKey('immersive-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  key: const ValueKey('immersive-meta'),
                  padding: EdgeInsets.fromLTRB(margin, 10, margin, 0),
                  child: Text(
                    '更新：$_updateLabel 来源：$sourceName 年份：暂无',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                Padding(
                  key: const ValueKey('immersive-director'),
                  padding: EdgeInsets.fromLTRB(margin, 6, margin, 0),
                  child: const Text(
                    '导演：暂无',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                Padding(
                  key: const ValueKey('immersive-actor'),
                  padding: EdgeInsets.fromLTRB(margin, 6, margin, 0),
                  child: const Text(
                    '演员：暂无',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                Padding(
                  key: const ValueKey('immersive-synopsis'),
                  padding: EdgeInsets.fromLTRB(margin, 12, margin, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        drama.description.isEmpty
                            ? '简介：暂无'
                            : '简介：${drama.description}',
                        maxLines: expandedDescription ? null : 3,
                        overflow: expandedDescription
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onToggleDescription,
                          child: Text(expandedDescription ? '收起简介' : '展开简介'),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  key: const ValueKey('immersive-engine'),
                  padding: EdgeInsets.fromLTRB(margin, 0, margin, 0),
                  child: Text(
                    '内置 $engineName 播放中',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                Padding(
                  key: const ValueKey('immersive-actions'),
                  padding: EdgeInsets.fromLTRB(margin, 14, margin, 0),
                  child: Row(
                    children: [
                      _actionButton(
                        context,
                        icon: Icons.fullscreen_rounded,
                        label: '全屏',
                        onPressed: onFullscreen,
                      ),
                      _actionButton(
                        context,
                        icon: Icons.search_rounded,
                        label: '搜索',
                        onPressed: onSearch,
                      ),
                      _actionButton(
                        context,
                        icon: Icons.swap_vert_rounded,
                        label: '倒叙',
                        selected: reversed,
                        onPressed: onToggleReverse,
                      ),
                      _actionButton(
                        context,
                        icon: isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        label: '收藏',
                        selected: isFavorite,
                        onPressed: onToggleFavorite,
                      ),
                      _actionButton(
                        context,
                        icon: Icons.swap_horiz_rounded,
                        label: '换源',
                        onPressed: onOpenSourcePanel,
                      ),
                      _actionButton(
                        context,
                        icon: Icons.tune_rounded,
                        label: '解析',
                        onPressed: onParse,
                      ),
                      _actionButton(
                        context,
                        icon: Icons.download_rounded,
                        label: '下载',
                        onPressed: onDownload,
                      ),
                    ],
                  ),
                ),
                Padding(
                  key: const ValueKey('immersive-source'),
                  padding: EdgeInsets.fromLTRB(margin, 18, margin, 0),
                  child: Row(
                    children: [
                      const Text(
                        '视频来源',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        key: const ValueKey('immersive-source-pill'),
                        onTap: onOpenSourcePanel,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            sourceName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  key: episodeSectionKey,
                  padding: EdgeInsets.fromLTRB(margin, 16, margin, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (displayEpisodes.length > episodePageSize)
                        EpisodeRangeBar(
                          episodes: displayEpisodes,
                          page: episodePage,
                          currentNumber: currentNumber,
                          onLocate: onLocateEpisode,
                        ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        key: const ValueKey('immersive-episode-grid'),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              mainAxisExtent: 54,
                            ),
                        itemCount: visibleEpisodes.length,
                        itemBuilder: (context, index) {
                          final episode = visibleEpisodes[index];
                          final selected = episode.number == currentNumber;
                          return InkWell(
                            key: ValueKey(
                              'immersive-episode-${episode.number}',
                            ),
                            onTap: () => onPlayEpisode(episode),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: selected
                                    ? colors.primary
                                    : colors.surfaceContainerHighest.withValues(
                                        alpha: 0.75,
                                      ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '第 ${episode.number} 集',
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : colors.onSurface,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        key: ValueKey('immersive-action-$label'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? colors.primary : Colors.white,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? colors.primary : Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
