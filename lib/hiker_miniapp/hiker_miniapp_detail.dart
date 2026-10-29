import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'hiker_detail_backdrop.dart';
import 'hiker_miniapp_engine.dart';
import 'hiker_miniapp_models.dart';

class HikerMiniappDetailScreen extends StatefulWidget {
  const HikerMiniappDetailScreen({
    super.key,
    required this.engine,
    required this.card,
    required this.onPlay,
  });

  final HikerMiniappEngine engine;
  final HikerMiniappCard card;
  final HikerPlayCallback onPlay;

  @override
  State<HikerMiniappDetailScreen> createState() =>
      _HikerMiniappDetailScreenState();
}

class _HikerMiniappDetailScreenState extends State<HikerMiniappDetailScreen> {
  HikerMiniappDetail? _detail;
  var _loading = true;
  var _resolving = false;
  String? _error;
  HikerPlayLine? _footprintLine;
  var _footprintIndex = 0;
  var _footprintLabel = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.engine.detail(widget.card.url);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _playEpisode(
    HikerMiniappDetail detail,
    HikerPlayLine line,
    int index,
  ) async {
    final episode = line.episodes[index];
    var episodes = line.episodes;
    if (widget.engine.rule.lastChapterRule.trim().isNotEmpty) {
      setState(() => _resolving = true);
      try {
        final resolved = await widget.engine.resolvePlayUrl(episode.url);
        if (resolved != episode.url) {
          episodes = [
            for (var i = 0; i < line.episodes.length; i++)
              if (i == index)
                HikerMiniappEpisode(
                  title: line.episodes[i].title,
                  url: resolved,
                  desc: line.episodes[i].desc,
                  img: line.episodes[i].img,
                )
              else
                line.episodes[i],
          ];
        }
      } finally {
        if (mounted) setState(() => _resolving = false);
      }
    }
    if (!mounted) return;
    widget.onPlay(detail.title, episodes, index);
    if (!mounted) return;
    setState(() {
      _footprintLine = line;
      _footprintIndex = index;
      _footprintLabel = '${line.name} · ${episode.title}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(widget.card.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => unawaited(_load()),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : _detailBody(_detail!),
    );
  }

  Widget _backdrop(HikerMiniappDetail detail) {
    final url = hikerDetailBackdropUrl(
      stills: detail.stills,
      poster: detail.poster,
    );
    return Container(
      key: const ValueKey('hiker-detail-backdrop'),
      color: Colors.black,
      child: url.isEmpty
          ? null
          : Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
              ],
            ),
    );
  }

  Widget _detailBody(HikerMiniappDetail detail) {
    final children = <Widget>[];
    final posterUrl = hikerDetailPosterUrl(
      stills: detail.stills,
      poster: detail.poster,
    );
    children.add(
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (posterUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  posterUrl,
                  key: const ValueKey('hiker-detail-poster'),
                  width: 110,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Container(width: 110, height: 150, color: Colors.black26),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (detail.actress.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(detail.actress),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (detail.synopsis.isNotEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('剧情简介', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(detail.synopsis),
        ),
      );
    }
    if (detail.tags.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            children: [for (final tag in detail.tags) Chip(label: Text(tag))],
          ),
        ),
      );
    }
    for (final line in detail.lines) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text(
            '播放线路：${line.name}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: line.episodes.asMap().entries.map((entry) {
              return ActionChip(
                label: Text(entry.value.title),
                onPressed: () =>
                    unawaited(_playEpisode(detail, line, entry.key)),
              );
            }).toList(),
          ),
        ),
      );
    }
    if (detail.unavailable.isNotEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text('暂不可播选集', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final episode in detail.unavailable)
                Chip(label: Text(episode.title)),
            ],
          ),
        ),
      );
    }
    if (detail.stills.isNotEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text('本片剧照', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
      children.add(
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: detail.stills.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Image.network(
                detail.stills[index],
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(width: 100, color: Colors.black12),
              ),
            ),
          ),
        ),
      );
    }
    final playableLines = [
      for (final line in detail.lines)
        if (line.episodes.isNotEmpty) line,
    ];
    if (playableLines.isNotEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text('播放地址', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < playableLines.length; i++)
                FilledButton.tonal(
                  onPressed: () =>
                      unawaited(_playEpisode(detail, playableLines[i], 0)),
                  child: Text(
                    playableLines[i].name.isEmpty
                        ? '线路${i + 1}'
                        : playableLines[i].name,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final footprintLine = _footprintLine;
    if (footprintLine != null) {
      children.add(const SizedBox(height: 64));
    }
    return Stack(
      children: [
        Positioned.fill(child: _backdrop(detail)),
        SafeArea(
          top: true,
          bottom: false,
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: ListView(
              padding: const EdgeInsets.only(top: kToolbarHeight),
              children: children,
            ),
          ),
        ),
        if (footprintLine != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              elevation: 4,
              child: InkWell(
                onTap: () => unawaited(
                  _playEpisode(detail, footprintLine, _footprintIndex),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Text(
                    '▶ $_footprintLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        if (_resolving) ...[
          const ModalBarrier(dismissible: false, color: Colors.black38),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }
}
