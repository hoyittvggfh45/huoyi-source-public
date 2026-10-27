import 'package:flutter/material.dart';

import '../hiker_player_screen.dart';
import '../local_store.dart';
import '../miniapp/plugin_center_screen.dart';
import 'hiker_miniapp_engine.dart';
import 'hiker_miniapp_home.dart';
import 'hiker_miniapp_models.dart';
import 'hiker_miniapp_rule.dart';

enum HikerMiniappTab { ant, hiker }

class HikerCategoryShell extends StatefulWidget {
  const HikerCategoryShell({
    super.key,
    required this.store,
    required this.hikerRun,
    this.hikerRules = const [],
    this.onPlay,
    this.initialTab = HikerMiniappTab.ant,
  });

  final LocalStore store;
  final HikerRunFn hikerRun;
  final List<HikerMiniappRule> hikerRules;
  final HikerPlayCallback? onPlay;
  final HikerMiniappTab initialTab;

  @override
  State<HikerCategoryShell> createState() => _HikerCategoryShellState();
}

class _HikerCategoryShellState extends State<HikerCategoryShell> {
  late var _tab = widget.initialTab;

  void _play(String title, List<HikerMiniappEpisode> episodes, int index) {
    final callback = widget.onPlay;
    if (callback != null) {
      callback(title, episodes, index);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => HikerPlayerScreen(
          title: title,
          episodes: [
            for (final episode in episodes)
              HikerEpisode(title: episode.title, url: episode.url),
          ],
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小程序')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<HikerMiniappTab>(
              segments: const [
                ButtonSegment<HikerMiniappTab>(
                  value: HikerMiniappTab.ant,
                  label: Text('蚂蚁'),
                ),
                ButtonSegment<HikerMiniappTab>(
                  value: HikerMiniappTab.hiker,
                  label: Text('海阔'),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (selected) {
                setState(() => _tab = selected.first);
              },
            ),
          ),
          Expanded(
            child: _tab == HikerMiniappTab.ant
                ? PluginCenterScreen(store: widget.store)
                : _hikerTab(),
          ),
        ],
      ),
    );
  }

  Widget _hikerTab() {
    final rules = widget.hikerRules;
    if (rules.isEmpty) return const Center(child: Text('暂无海阔规则'));
    return ListView.builder(
      itemCount: rules.length,
      itemBuilder: (context, index) {
        final rule = rules[index];
        return ListTile(
          title: Text(rule.title.isEmpty ? rule.url : rule.title),
          subtitle: Text(rule.type),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => HikerMiniappHomeScreen(
                  engine: HikerMiniappEngine(rule: rule, run: widget.hikerRun),
                  onPlay: _play,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
