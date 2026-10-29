import 'dart:convert';

import 'app_page_route.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'content_http.dart';
import 'core_bridge.dart';
import 'hiker_player_screen.dart';
import 'hiker_rule.dart';

class HikerScreen extends StatefulWidget {
  const HikerScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<HikerScreen> createState() => _HikerScreenState();
}

class _HikerScreenState extends State<HikerScreen> {
  List<HikerRule> _rules = [];
  HikerRule? _selected;
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _busy = false;
  String _busyLabel = '';
  bool _inDetail = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final rules = await HikerStore.load();
    if (mounted) setState(() => _rules = rules);
  }

  List<HikerRule> _rulesFromText(String text) {
    final decoded = jsonDecode(text);
    if (decoded is List) return parseHikerRules(text);
    if (decoded is Map) {
      for (final key in ['rules', 'data', 'records']) {
        final value = decoded[key];
        if (value is List) return parseHikerRules(jsonEncode(value));
      }
      return parseHikerRules(text);
    }
    return [];
  }

  Future<List<HikerRule>> _parsePassword(String text) async {
    final trimmed = text.trim();
    final password = parseHikerPassword(trimmed);
    if (password != null) {
      if (password.identifier == 'home_rule') {
        return _rulesFromText(password.payload);
      }
      if (password.identifier == 'home_rule_url' ||
          password.identifier == 'home_sub') {
        final fetched = await ContentHttp().get(password.payload);
        return _rulesFromText(fetched);
      }
      throw '不支持的口令标识：${password.identifier}';
    }
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return _rulesFromText(trimmed);
    }
    if (trimmed.startsWith('http')) {
      final fetched = await ContentHttp().get(trimmed);
      return _rulesFromText(fetched);
    }
    throw '口令格式不对，示例：海阔视界，名字￥home_rule￥{规则JSON} 或 海阔视界，名字￥home_rule_url￥https://规则地址';
  }

  Future<void> _importPassword() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴口令导入'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '粘贴海阔口令，如：海阔视界，名字￥home_rule￥{...}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) controller.text = data!.text!;
            },
            child: const Text('读取剪贴板'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    try {
      final rules = await _parsePassword(text);
      if (rules.isEmpty) throw '口令里没有解析出规则';
      final merged = await HikerStore.addAll(rules);
      if (mounted) {
        setState(() => _rules = merged);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('口令导入 ${rules.length} 条规则')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('口令导入失败：$e')));
      }
    }
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked.isEmpty) return;
    final file = picked.first;
    final bytes = await file.readAsBytes();
    try {
      final rules = parseHikerRules(utf8.decode(bytes));
      final merged = await HikerStore.addAll(rules);
      if (mounted) {
        setState(() => _rules = merged);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入 ${rules.length} 条海阔规则')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  bool _isVideoUrl(String url) {
    var cleaned = url;
    if (cleaned.startsWith('video://')) {
      cleaned = cleaned.substring('video://'.length);
    }
    final lower = cleaned.toLowerCase();
    if (!lower.startsWith('http')) return false;
    return lower.contains('.m3u8') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm');
  }

  List<HikerEpisode> _videoItems(List<Map<String, dynamic>> items) {
    final out = <HikerEpisode>[];
    for (final item in items) {
      for (final key in ['url', 'playUrl', 'videoUrl', 'play_url']) {
        final raw = (item[key] ?? '').toString();
        if (_isVideoUrl(raw)) {
          var url = raw;
          if (url.startsWith('video://')) {
            url = url.substring('video://'.length);
          }
          out.add(
            HikerEpisode(title: (item['title'] ?? '').toString(), url: url),
          );
          break;
        }
      }
    }
    return out;
  }

  Future<void> _openPlayer(
    String title,
    List<HikerEpisode> episodes, [
    int index = 0,
  ]) async {
    if (!mounted || episodes.isEmpty) return;
    await Navigator.of(context).push(
      appPageRoute<void>(
        builder: (_) => HikerPlayerScreen(
          title: title,
          episodes: episodes,
          initialIndex: index,
        ),
      ),
    );
  }

  Future<void> _run(HikerRule rule, String action, String input) async {
    setState(() {
      _busy = true;
      _busyLabel = '运行中…';
      _error = null;
      _selected = rule;
      _items = [];
      if (action == 'find') _searchController.clear();
    });
    List<HikerEpisode> videoItems = [];
    try {
      final result = await widget.repository.hikerRun(
        jsonEncode(rule.toJson()),
        action,
        input,
      );
      final items = _toItems(result);
      if (action == 'detail') {
        videoItems = _videoItems(items);
        if (mounted && videoItems.isEmpty) {
          setState(() {
            _items = items;
            _inDetail = true;
          });
        }
      } else if (mounted) {
        setState(() {
          _items = items;
          _inDetail = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (videoItems.isNotEmpty) {
      await _openPlayer(rule.title, videoItems);
    }
  }

  List<Map<String, dynamic>> _toItems(dynamic result) {
    if (result is List) {
      return [
        for (final item in result)
          if (item is Map) item.map((k, v) => MapEntry(k.toString(), v)),
      ];
    }
    if (result is Map) {
      final data = result['data'];
      if (data is List) {
        return [
          for (final item in data)
            if (item is Map) item.map((k, v) => MapEntry(k.toString(), v)),
        ];
      }
      return [result.map((k, v) => MapEntry(k.toString(), v))];
    }
    if (result is String) {
      try {
        return _toItems(jsonDecode(result));
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('海阔小程序'),
        actions: [
          IconButton(
            icon: const Icon(Icons.paste_rounded),
            tooltip: '粘贴口令导入',
            onPressed: _importPassword,
          ),
          IconButton(
            icon: const Icon(Icons.file_open_rounded),
            tooltip: '导入海阔 JSON',
            onPressed: _importFile,
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 120,
            child: _rules.isEmpty
                ? const Center(child: Text('右上角导入海阔 JSON 后运行'))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _rules.length,
                    itemBuilder: (context, index) {
                      final rule = _rules[index];
                      final selected = _selected?.id == rule.id;
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: ChoiceChip(
                          label: Text(rule.title),
                          selected: selected,
                          onSelected: (_) => _run(rule, 'find', ''),
                        ),
                      );
                    },
                  ),
          ),
          if (_busy)
            Column(
              children: [const LinearProgressIndicator(), Text(_busyLabel)],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: Builder(
              builder: (context) {
                final searchItems = _items
                    .where((i) => (i['col_type'] ?? '').toString() == 'input')
                    .toList();
                final buttonItems = _items
                    .where(
                      (i) => (i['col_type'] ?? '').toString() == 'flex_button',
                    )
                    .toList();
                final bodyItems = _items.where((i) {
                  final col = (i['col_type'] ?? '').toString();
                  return col != 'input' &&
                      col != 'flex_button' &&
                      col != 'blank_block';
                }).toList();
                return Column(
                  children: [
                    if (_inDetail)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('返回列表'),
                          onPressed: () {
                            final rule = _selected;
                            if (rule != null) _run(rule, 'find', '');
                          },
                        ),
                      ),
                    if (searchItems.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText:
                                (searchItems.first['desc'] ?? '')
                                    .toString()
                                    .isEmpty
                                ? '搜索…'
                                : (searchItems.first['desc'] ?? '').toString(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () {
                                final rule = _selected;
                                final text = _searchController.text.trim();
                                if (rule != null && text.isNotEmpty) {
                                  _run(rule, 'search', text);
                                }
                              },
                            ),
                          ),
                          onSubmitted: (text) {
                            final rule = _selected;
                            if (rule != null && text.trim().isNotEmpty) {
                              _run(rule, 'search', text.trim());
                            }
                          },
                        ),
                      ),
                    if (buttonItems.isNotEmpty)
                      SizedBox(
                        height: 48,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: buttonItems.length,
                          itemBuilder: (context, index) {
                            final item = buttonItems[index];
                            final title = (item['title'] ?? '').toString();
                            if (title.isEmpty) return const SizedBox.shrink();
                            final url = (item['url'] ?? '').toString();
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: ActionChip(
                                label: Text(title),
                                onPressed: () {
                                  final rule = _selected;
                                  if (rule != null && url.isNotEmpty) {
                                    _run(rule, 'list', url);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: bodyItems.length,
                        itemBuilder: (context, index) {
                          final item = bodyItems[index];
                          final title = (item['title'] ?? item['field0'] ?? '')
                              .toString();
                          final desc = (item['desc'] ?? item['field2'] ?? '')
                              .toString();
                          final url = (item['url'] ?? '').toString();
                          final pic = (item['img'] ?? item['pic'] ?? '')
                              .toString();
                          final isListUrl =
                              url.contains('[firstPage=') ||
                              url.contains('/fypage');
                          return ListTile(
                            leading: pic.isEmpty
                                ? null
                                : Image.network(
                                    pic,
                                    width: 56,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox(width: 56),
                                  ),
                            title: Text(title),
                            subtitle: desc.isEmpty ? null : Text(desc),
                            trailing: url.isEmpty
                                ? null
                                : const Icon(Icons.play_circle_outline),
                            onTap: url.isEmpty
                                ? null
                                : () {
                                    final rule = _selected;
                                    if (rule == null) return;
                                    if (_isVideoUrl(url)) {
                                      var playUrl = url;
                                      if (playUrl.startsWith('video://')) {
                                        playUrl = playUrl.substring(
                                          'video://'.length,
                                        );
                                      }
                                      _openPlayer(title, [
                                        HikerEpisode(
                                          title: title,
                                          url: playUrl,
                                        ),
                                      ]);
                                    } else if (isListUrl) {
                                      _run(rule, 'list', url);
                                    } else {
                                      _run(rule, 'detail', url);
                                    }
                                  },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
