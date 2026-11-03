import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'rss_engine.dart';
import 'rss_model.dart';

class RssItemListScreen extends StatefulWidget {
  const RssItemListScreen({super.key, required this.source, this.engine});

  final RssSource source;
  final RssEngineApi? engine;

  @override
  State<RssItemListScreen> createState() => _RssItemListScreenState();
}

class _RssItemListScreenState extends State<RssItemListScreen> {
  final _items = <RssItem>[];
  String? _nextPageUrl;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  RssEngineApi get _engine => widget.engine ?? const RssEngine();

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _engine.fetchItems(widget.source);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _nextPageUrl = result.nextPageUrl;
        _loading = false;
      });
    } on RssFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
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

  Future<void> _loadMore() async {
    final url = _nextPageUrl;
    if (url == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _engine.fetchPageUrl(widget.source, url);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _nextPageUrl = result.nextPageUrl;
        _loadingMore = false;
      });
    } on RssFailure catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      if (error.scriptUnsupported) {
        _nextPageUrl = null;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.source.name)),
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
                    onPressed: _loadFirst,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _items.length + (_nextPageUrl == null ? 0 : 1),
              itemBuilder: (context, index) {
                if (index >= _items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: _loadingMore
                          ? const CircularProgressIndicator()
                          : FilledButton(
                              onPressed: _loadMore,
                              child: const Text('加载更多'),
                            ),
                    ),
                  );
                }
                final item = _items[index];
                return ListTile(
                  leading: item.imageUrl.isEmpty
                      ? const Icon(Icons.article_outlined)
                      : Image.network(
                          item.imageUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.article_outlined),
                        ),
                  title: Text(item.title.isEmpty ? '无标题' : item.title),
                  subtitle: item.date.isEmpty ? null : Text(item.date),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RssArticleScreen(
                          source: widget.source,
                          item: item,
                          engine: widget.engine,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class RssArticleScreen extends StatefulWidget {
  const RssArticleScreen({
    super.key,
    required this.source,
    required this.item,
    this.engine,
  });

  final RssSource source;
  final RssItem item;
  final RssEngineApi? engine;

  @override
  State<RssArticleScreen> createState() => _RssArticleScreenState();
}

class _RssArticleScreenState extends State<RssArticleScreen> {
  List<RssContentBlock> _blocks = [];
  bool _loading = true;
  String? _error;

  RssEngineApi get _engine => widget.engine ?? const RssEngine();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _engine.fetchArticle(widget.source, widget.item);
      if (!mounted) return;
      setState(() {
        _blocks = result.blocks;
        _loading = false;
      });
    } on RssFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
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

  void _openOriginal() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RssWebViewScreen(url: widget.item.link),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title.isEmpty ? '无标题' : widget.item.title),
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
                  FilledButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : _blocks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.item.title),
                  if (widget.item.date.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(widget.item.date),
                  ],
                  const SizedBox(height: 12),
                  const Text('该源没有正文规则，可打开原文阅读'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _openOriginal,
                    child: const Text('打开原文'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.item.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (widget.item.date.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(widget.item.date),
                ],
                const SizedBox(height: 16),
                for (final block in _blocks)
                  block.isImage
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Image.network(
                            block.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.broken_image_outlined,
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(block.text),
                        ),
              ],
            ),
    );
  }
}

class RssWebViewScreen extends StatefulWidget {
  const RssWebViewScreen({super.key, required this.url});

  final String url;

  @override
  State<RssWebViewScreen> createState() => _RssWebViewScreenState();
}

class _RssWebViewScreenState extends State<RssWebViewScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('原文')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
