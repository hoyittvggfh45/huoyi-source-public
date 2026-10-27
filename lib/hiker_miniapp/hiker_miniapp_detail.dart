import 'dart:async';

import 'package:flutter/material.dart';

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
  String? _error;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.card.title)),
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

  Widget _detailBody(HikerMiniappDetail detail) {
    final children = <Widget>[];
    children.add(
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (detail.poster.isNotEmpty)
              Image.network(
                detail.poster,
                width: 110,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(width: 110, color: Colors.black12),
              ),
            if (detail.poster.isNotEmpty) const SizedBox(width: 12),
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
                    widget.onPlay(detail.title, line.episodes, entry.key),
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
    return ListView(children: children);
  }
}
