import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../clipboard_detect/clipboard_import_popup.dart';
import '../clipboard_detect/clipboard_rule_match.dart';
import '../core_bridge.dart';
import '../hiker_player_screen.dart';
import '../hiker_rule.dart';
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
    this.repository,
  });

  final LocalStore store;
  final HikerRunFn hikerRun;
  final List<HikerMiniappRule> hikerRules;
  final HikerPlayCallback? onPlay;
  final HikerMiniappTab initialTab;
  final AppRepository? repository;

  @override
  State<HikerCategoryShell> createState() => _HikerCategoryShellState();
}

class _HikerCategoryShellState extends State<HikerCategoryShell>
    with WidgetsBindingObserver {
  late var _tab = widget.initialTab;
  late List<HikerMiniappRule> _rules;
  bool _clipboardAutoChecked = false;
  bool _clipboardBusy = false;
  int _antNonce = 0;

  @override
  void initState() {
    super.initState();
    _rules = List.of(widget.hikerRules);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkClipboard(auto: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (ModalRoute.of(context)?.isCurrent != true) return;
      _clipboardAutoChecked = false;
      _checkClipboard(auto: true);
    }
  }

  void _showHikerMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importHikerRule() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'hiker'],
    );
    if (picked.isEmpty) return;
    try {
      final bytes = await picked.single.readAsBytes();
      var text = utf8.decode(bytes);
      final match = matchClipboardRule(text);
      if (match != null && match.kind == ClipboardMatchKind.hikerRuleText) {
        text = match.payload;
      }
      final imported = parseHikerMiniappRules(text);
      if (imported.isEmpty) {
        _showHikerMessage('文件里没有解析出规则');
        return;
      }
      final merged = await HikerStore.addAll([
        for (final rule in imported) HikerRule.fromJson(rule.toJson()),
      ]);
      if (!mounted) return;
      setState(() {
        _rules = [
          for (final stored in merged)
            HikerMiniappRule.fromJson(stored.toJson()),
        ];
      });
      _showHikerMessage('已导入 ${imported.length} 条海阔规则');
    } catch (error) {
      _showHikerMessage('导入失败：$error');
    }
  }

  void _applyMergedRules(List<HikerRule> merged) {
    if (!mounted) return;
    setState(() {
      _rules = [
        for (final stored in merged) HikerMiniappRule.fromJson(stored.toJson()),
      ];
    });
  }

  Future<void> _importClipboardHikerText(String text) async {
    try {
      final result = await importHikerRulesFromText(text);
      _applyMergedRules(result.merged);
      _showHikerMessage('导入 ${result.imported} 条规则');
    } on ClipboardImportFailure catch (failure) {
      _showHikerMessage('导入失败：${failure.message}');
    } catch (error) {
      _showHikerMessage('导入失败：$error');
    }
  }

  Future<void> _importClipboardRemoteRule(String url) async {
    try {
      final result = await importHikerRulesFromUrl(url);
      _applyMergedRules(result.merged);
      _showHikerMessage('导入 ${result.imported} 条规则');
    } on ClipboardImportFailure catch (failure) {
      _showHikerMessage(
        failure.network ? '导入失败，网络连接错误' : '导入失败：${failure.message}',
      );
    } catch (error) {
      _showHikerMessage('导入失败：$error');
    }
  }

  Future<void> _installClipboardAntPackage(String url) async {
    try {
      final manifest = await installAntPackageFromUrl(url);
      if (!mounted) return;
      setState(() => _antNonce++);
      _showHikerMessage('已安装${manifest.name}');
    } catch (error) {
      _showHikerMessage('安装失败：$error');
    }
  }

  Future<void> _checkClipboard({required bool auto}) async {
    if (auto) {
      if (_clipboardAutoChecked) return;
      _clipboardAutoChecked = true;
    }
    if (_clipboardBusy) return;
    _clipboardBusy = true;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.trim().isEmpty) return;
      final match = matchClipboardRule(text);
      if (match == null) return;
      if (auto && await isClipboardPrompted(text)) return;
      if (!mounted) return;
      final confirmed = await showClipboardImportDialog(context, match);
      if (confirmed || match.kind == ClipboardMatchKind.cloudCode) {
        await markClipboardPrompted(text);
      }
      if (!confirmed || !mounted) return;
      switch (match.kind) {
        case ClipboardMatchKind.hikerRuleText:
          await _importClipboardHikerText(match.payload);
        case ClipboardMatchKind.remoteRule:
          await _importClipboardRemoteRule(match.payload);
        case ClipboardMatchKind.antPackageLink:
          await _installClipboardAntPackage(match.payload);
        case ClipboardMatchKind.cloudCode:
          break;
      }
    } catch (_) {
    } finally {
      _clipboardBusy = false;
    }
  }

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
                ? PluginCenterScreen(
                    key: ValueKey('ant-$_antNonce'),
                    store: widget.store,
                    repository: widget.repository,
                  )
                : _hikerTab(),
          ),
        ],
      ),
    );
  }

  Widget _hikerTab() {
    final rules = _rules;
    if (rules.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂无海阔规则'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _importHikerRule,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('导入规则文件'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _checkClipboard(auto: false),
              icon: const Icon(Icons.content_paste_outlined),
              label: const Text('检测剪贴板'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _checkClipboard(auto: false),
                icon: const Icon(Icons.content_paste_outlined),
                label: const Text('检测剪贴板'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _importHikerRule,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('导入规则'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final rule = rules[index];
              return InkWell(
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => HikerMiniappHomeScreen(
                        engine: HikerMiniappEngine(
                          rule: rule,
                          run: widget.hikerRun,
                        ),
                        onPlay: _play,
                      ),
                    ),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      rule.title.isEmpty ? rule.url : rule.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    if (rule.type.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        rule.type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
