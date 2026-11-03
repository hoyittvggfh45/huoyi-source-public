import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'midnight_zone.dart';
import 'rss_article_screens.dart';
import 'rss_model.dart';
import 'rss_store.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  List<RssSource> _sources = [];
  bool _midnight = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sources = await RssSourceStore.loadSources();
      final midnight = await loadMidnightActivated();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _midnight = midnight;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<RssSource> get _visible {
    if (_midnight) return _sources;
    return [
      for (final source in _sources)
        if (!isAdultSourceName(source.name)) source,
    ];
  }

  Future<void> _import() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      final text = utf8.decode(bytes);
      final source = await RssSourceStore.importJson(text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 ${source.name}')),
      );
      await _reload();
    } on RssFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：${error.message}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
  }

  Future<void> _remove(RssSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除订阅源'),
        content: Text('确定删除 ${source.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await RssSourceStore.remove(source.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final hidden = _sources.length - visible.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '导入订阅源',
            onPressed: _import,
          ),
        ],
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
                  FilledButton(
                    onPressed: _reload,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : visible.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('暂无订阅源'),
                  if (hidden > 0) ...[
                    const SizedBox(height: 8),
                    Text('另有 $hidden 个成人源已隐藏（午夜未开启）'),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _import,
                    child: const Text('导入订阅源'),
                  ),
                ],
              ),
            )
          : ListView(
              children: [
                if (hidden > 0)
                  ListTile(
                    title: Text('另有 $hidden 个成人源已隐藏（午夜未开启）'),
                  ),
                for (final source in visible)
                  ListTile(
                    leading: const Icon(Icons.rss_feed_rounded),
                    title: Text(source.name),
                    subtitle: Text(source.sourceUrl),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _remove(source),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RssItemListScreen(source: source),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
