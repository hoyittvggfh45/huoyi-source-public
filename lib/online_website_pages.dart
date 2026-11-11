import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_page_route.dart';
import 'core_bridge.dart';
import 'local_store.dart';
import 'miniapp/mini_app_ad_filter.dart';
import 'online_website.dart';
import 'online_website_auto_parse.dart';
import 'online_website_clearance.dart';
import 'playback_sniffer.dart';
import 'player_picker.dart';

bool get onlineWebsiteWebViewSupported => Platform.isAndroid || Platform.isIOS;

String _normalizeOnlineWebsiteUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return 'https://$trimmed';
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

Widget _onlineWebsiteCoverPlaceholder(BuildContext context, double iconSize) {
  final colors = Theme.of(context).colorScheme;
  return Center(
    child: Icon(
      Icons.movie_creation_outlined,
      size: iconSize,
      color: colors.onSurfaceVariant,
    ),
  );
}

Widget _onlineWebsiteCoverImage(
  BuildContext context,
  String cover, {
  double iconSize = 32,
}) {
  final colors = Theme.of(context).colorScheme;
  if (cover.isEmpty) {
    return Container(
      color: colors.surfaceContainerHighest,
      child: _onlineWebsiteCoverPlaceholder(context, iconSize),
    );
  }
  return Image.network(
    cover,
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    errorBuilder: (_, _, _) => Container(
      color: colors.surfaceContainerHighest,
      child: _onlineWebsiteCoverPlaceholder(context, iconSize),
    ),
  );
}

class OnlineWebsiteListPage extends StatefulWidget {
  const OnlineWebsiteListPage({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<OnlineWebsiteListPage> createState() => _OnlineWebsiteListPageState();
}

class _OnlineWebsiteListPageState extends State<OnlineWebsiteListPage> {
  var _sites = <OnlineWebsite>[];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final sites = await OnlineWebsiteStore.load();
    if (!mounted) return;
    setState(() {
      _sites = sites;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await OnlineWebsiteStore.save(_sites);
  }

  Future<void> _showSiteForm({OnlineWebsite? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final urlController = TextEditingController(text: existing?.url ?? '');
    var autoMode = existing?.autoMode ?? true;
    var pureMode = existing?.pureMode ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? '添加在线网站' : '编辑在线网站'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '站名',
                    hintText: '不填用网址里的域名',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '网址',
                    hintText: '例如 https://www.example.com',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  activeTrackColor: Theme.of(context).colorScheme.tertiary,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动模式'),
                  subtitle: const Text('自动识别列表、详情和选集'),
                  value: autoMode,
                  onChanged: (value) => setDialogState(() => autoMode = value),
                ),
                SwitchListTile(
                  activeTrackColor: Theme.of(context).colorScheme.tertiary,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('纯净化'),
                  subtitle: const Text('打开网页时拦截广告地址'),
                  value: pureMode,
                  onChanged: (value) => setDialogState(() => pureMode = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final url = _normalizeOnlineWebsiteUrl(urlController.text);
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入网址')));
      return;
    }
    final name = nameController.text.trim();
    if (existing == null) {
      setState(() {
        _sites = [
          ..._sites,
          OnlineWebsite(
            id: OnlineWebsiteStore.newId(),
            name: name,
            url: url,
            autoMode: autoMode,
            pureMode: pureMode,
          ),
        ];
      });
    } else {
      final index = _sites.indexWhere((site) => site.id == existing.id);
      if (index < 0) return;
      setState(() {
        _sites = [
          for (var i = 0; i < _sites.length; i++)
            if (i == index)
              existing.copyWith(
                name: name,
                url: url,
                autoMode: autoMode,
                pureMode: pureMode,
              )
            else
              _sites[i],
        ];
      });
    }
    await _save();
  }

  Future<void> _confirmDelete(OnlineWebsite site) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除在线网站'),
        content: Text('确定删除「${site.displayName}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _sites = [
        for (final item in _sites)
          if (item.id != site.id) item,
      ];
    });
    await _save();
  }

  void _openSite(OnlineWebsite site) {
    unawaited(
      Navigator.push<void>(
        context,
        appPageRoute<void>(
          builder: (_) => OnlineWebsiteBrowserPage(
            site: site,
            repository: widget.repository,
            store: widget.store,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('在线网站')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_showSiteForm()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加网站'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sites.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.public_rounded,
                      size: 48,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '还没有在线网站',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '点右下角添加一个视频站网址，不用写蜘蛛就能看',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _sites.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final site = _sites[index];
                return Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF2E9E6B),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      child: SizedBox.square(
                        dimension: 40,
                        child: Icon(
                          Icons.public_rounded,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    title: Text(
                      site.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _ModeChip(label: site.autoMode ? '自动' : '手动'),
                            const SizedBox(width: 6),
                            _ModeChip(label: site.pureMode ? '纯净' : '不过滤'),
                          ],
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: '更多操作',
                      onSelected: (value) {
                        if (value == 'edit') {
                          unawaited(_showSiteForm(existing: site));
                        } else if (value == 'delete') {
                          unawaited(_confirmDelete(site));
                        }
                      },
                      itemBuilder: (menuContext) => const [
                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                    onTap: () => _openSite(site),
                  ),
                );
              },
            ),
    );
  }
}

class _OnlineWebsiteWebView extends StatefulWidget {
  const _OnlineWebsiteWebView({
    required this.controller,
    required this.site,
    required this.initialUrl,
    required this.onParsed,
    required this.onParseStarted,
    required this.onDirectMedia,
    required this.onUrlChanged,
    required this.onShieldChanged,
  });

  final WebViewController controller;
  final OnlineWebsite site;
  final String initialUrl;
  final void Function(
    List<OnlineWebsiteCard> cards,
    List<OnlineWebsiteEpisode> episodes,
    OnlineWebsiteDetailInfo info,
  )
  onParsed;
  final VoidCallback onParseStarted;
  final void Function(String url) onDirectMedia;
  final void Function(String url) onUrlChanged;
  final ValueChanged<bool> onShieldChanged;

  @override
  State<_OnlineWebsiteWebView> createState() => _OnlineWebsiteWebViewState();
}

class _OnlineWebsiteWebViewState extends State<_OnlineWebsiteWebView> {
  final _cookieManager = WebViewCookieManager();
  var _parseGeneration = 0;
  Timer? _reparseTimer;
  Timer? _shieldTimer;
  var _currentUrl = '';
  var _challenged = false;
  var _shieldHost = '';
  var _checkingShield = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    widget.controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => _decideNavigation(request.url),
          onPageFinished: (url) {
            _currentUrl = url;
            widget.onUrlChanged(url);
            unawaited(_checkShieldAndParse());
          },
        ),
      );
    unawaited(_start());
    _shieldTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_challenged) unawaited(_checkShieldAndParse());
    });
  }

  @override
  void dispose() {
    _reparseTimer?.cancel();
    _shieldTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    await _preseedClearance(widget.initialUrl);
    if (!mounted) return;
    await widget.controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _preseedClearance(String url) async {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return;
    try {
      final stored = await OnlineWebsiteClearanceStore.loadForHost(host);
      if (stored == null || stored.isStale) return;
      await _cookieManager.setCookie(
        WebViewCookie(
          name: 'cf_clearance',
          value: stored.clearance,
          domain: host,
          path: '/',
        ),
      );
    } catch (_) {}
  }

  Future<void> _checkShieldAndParse() async {
    if (!mounted || _checkingShield) return;
    _checkingShield = true;
    try {
      final host = Uri.tryParse(_currentUrl)?.host.toLowerCase() ?? '';
      if (host.isEmpty) return;
      if (host != _shieldHost) {
        _shieldHost = host;
        _setChallenged(false);
      }
      final challenged = await _detectShield();
      if (!challenged) {
        if (_challenged) {
          await _tryHarvestClearance(host);
          if (mounted) _setChallenged(false);
        }
        _scheduleParse();
        return;
      }
      _setChallenged(true);
      if (await _tryHarvestClearance(host) && mounted) {
        _setChallenged(false);
        await widget.controller.reload();
      }
    } finally {
      _checkingShield = false;
    }
  }

  Future<bool> _detectShield() async {
    try {
      final raw = await widget.controller.runJavaScriptReturningResult(
        onlineWebsiteShieldScript,
      );
      return parseOnlineWebsiteShield(raw).challenged;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryHarvestClearance(String host) async {
    try {
      final cookies = await _cookieManager.getCookies(
        domain: Uri.parse(_currentUrl),
      );
      final clearance = [
        for (final cookie in cookies)
          if (cookie.name == 'cf_clearance' &&
              _domainMatches(cookie.domain, host))
            cookie,
      ];
      if (clearance.isEmpty) return false;
      var userAgent = '';
      try {
        final raw = await widget.controller.runJavaScriptReturningResult(
          'navigator.userAgent',
        );
        if (raw is String) {
          var value = raw;
          if (value.length >= 2 && value.startsWith('"')) {
            try {
              value = jsonDecode(value) as String;
            } catch (_) {}
          }
          userAgent = value;
        }
      } catch (_) {}
      await OnlineWebsiteClearanceStore.save(
        OnlineWebsiteClearance(
          host: host,
          clearance: clearance.first.value,
          userAgent: userAgent,
          updatedAt: DateTime.now(),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _domainMatches(String domain, String host) {
    final normalized = domain.startsWith('.') ? domain.substring(1) : domain;
    return host == normalized || host.endsWith('.$normalized');
  }

  void _setChallenged(bool value) {
    if (_challenged == value) return;
    _challenged = value;
    widget.onShieldChanged(value);
  }

  void _scheduleParse() {
    if (!widget.site.autoMode) return;
    unawaited(_parseCurrentPage());
    _reparseTimer?.cancel();
    _reparseTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && widget.site.autoMode && !_challenged) {
        unawaited(_parseCurrentPage());
      }
    });
  }

  Future<NavigationDecision> _decideNavigation(String url) async {
    if (widget.site.pureMode && miniAppShouldBlockUrl(url)) {
      return NavigationDecision.prevent;
    }
    if (MediaSniffer.isMediaUrl(url)) {
      widget.onDirectMedia(url);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _parseCurrentPage() async {
    if (!mounted) return;
    final generation = ++_parseGeneration;
    widget.onParseStarted();
    Object? cardsResult;
    try {
      cardsResult = await widget.controller.runJavaScriptReturningResult(
        onlineWebsiteListScript,
      );
    } catch (_) {}
    final cards = parseOnlineWebsiteCards(cardsResult);
    Object? detailResult;
    try {
      detailResult = await widget.controller.runJavaScriptReturningResult(
        onlineWebsiteDetailScript,
      );
    } catch (_) {}
    final detail = parseOnlineWebsiteDetail(detailResult);
    if (!mounted || generation != _parseGeneration) return;
    widget.onParsed(cards, detail.episodes, detail.info);
  }

  @override
  Widget build(BuildContext context) =>
      WebViewWidget(controller: widget.controller);
}

class OnlineWebsiteBrowserPage extends StatefulWidget {
  const OnlineWebsiteBrowserPage({
    super.key,
    required this.site,
    required this.repository,
    required this.store,
  });

  final OnlineWebsite site;
  final AppRepository repository;
  final LocalStore store;

  @override
  State<OnlineWebsiteBrowserPage> createState() =>
      _OnlineWebsiteBrowserPageState();
}

class _OnlineWebsiteBrowserPageState extends State<OnlineWebsiteBrowserPage> {
  late final WebViewController _controller;
  var _cards = <OnlineWebsiteCard>[];
  var _episodes = <OnlineWebsiteEpisode>[];
  var _info = const OnlineWebsiteDetailInfo();
  var _parsing = false;
  var _currentUrl = '';
  var _canGoBack = false;
  var _challenged = false;
  String _lastDirectPlayUrl = '';
  DateTime _lastDirectPlayAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.site.url;
    if (onlineWebsiteWebViewSupported) {
      _controller = WebViewController();
    }
  }

  Future<void> _onParsed(
    List<OnlineWebsiteCard> cards,
    List<OnlineWebsiteEpisode> episodes,
    OnlineWebsiteDetailInfo info,
  ) async {
    if (!mounted || _challenged) return;
    setState(() {
      _cards = cards;
      _episodes = episodes;
      _info = info;
      _parsing = false;
    });
  }

  void _onShieldChanged(bool challenged) {
    if (!mounted) return;
    setState(() {
      _challenged = challenged;
      if (challenged) {
        _cards = [];
        _episodes = [];
        _info = const OnlineWebsiteDetailInfo();
      }
    });
  }

  void _onParseStarted() {
    if (!mounted) return;
    setState(() => _parsing = true);
  }

  void _onUrlChanged(String url) {
    _currentUrl = url;
    unawaited(
      _controller.canGoBack().then((value) {
        if (mounted) setState(() => _canGoBack = value);
      }),
    );
  }

  void _onDirectMedia(String url) {
    unawaited(_playDirectMedia(url));
  }

  Future<void> _playDirectMedia(String url) async {
    final now = DateTime.now();
    if (url == _lastDirectPlayUrl &&
        now.difference(_lastDirectPlayAt).inSeconds < 3) {
      return;
    }
    _lastDirectPlayUrl = url;
    _lastDirectPlayAt = now;
    if (!mounted) return;
    final detail = onlineWebsiteDetail(
      site: widget.site,
      pageUrl: _currentUrl.isEmpty ? widget.site.url : _currentUrl,
      title: _info.title.isEmpty ? widget.site.displayName : _info.title,
      cover: _info.cover,
      episodes: [OnlineWebsiteEpisode(title: '直链播放', url: url)],
    );
    await pushPlayer<void>(
      context,
      detail: detail,
      initialIndex: 0,
      repository: widget.repository,
      store: widget.store,
    );
  }

  Future<void> _playEpisode(int index) async {
    if (index < 0 || index >= _episodes.length || !mounted) return;
    final detail = onlineWebsiteDetail(
      site: widget.site,
      pageUrl: _currentUrl.isEmpty ? widget.site.url : _currentUrl,
      title: _info.title.isEmpty ? widget.site.displayName : _info.title,
      cover: _info.cover,
      episodes: _episodes,
    );
    await pushPlayer<void>(
      context,
      detail: detail,
      initialIndex: index,
      repository: widget.repository,
      store: widget.store,
    );
  }

  Future<void> _playCurrentPage() async {
    if (!mounted) return;
    final pageUrl = _currentUrl.isEmpty ? widget.site.url : _currentUrl;
    final detail = onlineWebsiteDetail(
      site: widget.site,
      pageUrl: pageUrl,
      title: _info.title.isEmpty ? widget.site.displayName : _info.title,
      cover: _info.cover,
      episodes: [OnlineWebsiteEpisode(title: '正片', url: pageUrl)],
    );
    await pushPlayer<void>(
      context,
      detail: detail,
      initialIndex: 0,
      repository: widget.repository,
      store: widget.store,
    );
  }

  Future<void> _showCardsSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (sheetContext, scrollController) => GridView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.68,
          ),
          itemCount: _cards.length,
          itemBuilder: (gridContext, index) {
            final card = _cards[index];
            return _OnlineWebsiteCardTile(
              card: card,
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(
                  Navigator.push<void>(
                    context,
                    appPageRoute<void>(
                      builder: (_) => OnlineWebsiteDetailPage(
                        site: widget.site,
                        card: card,
                        repository: widget.repository,
                        store: widget.store,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showEpisodesSheet() async {
    if (!mounted) return;
    final title = _info.title.isEmpty ? widget.site.displayName : _info.title;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (sheetContext, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '导演：${_info.director.isEmpty ? '暂无' : _info.director}  ·  演员：${_info.actors.isEmpty ? '暂无' : _info.actors}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _episodes.length; i++)
                  ActionChip(
                    label: Text(_episodes[i].title),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(_playEpisode(i));
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final colors = Theme.of(context).colorScheme;
    final status = _challenged
        ? '正在过网站验证…如需点一下验证，请在页面上点一下'
        : _parsing
        ? '正在识别页面…'
        : !widget.site.autoMode
        ? '手动模式：点下面直接嗅探播放本页'
        : _cards.isEmpty && _episodes.isEmpty
        ? '本页未识别到视频列表或选集'
        : '已识别 ${_cards.length} 个视频 · ${_episodes.length} 集';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              status,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (!_challenged) const SizedBox(height: 8),
            if (!_challenged)
              Row(
                children: [
                  if (_cards.isNotEmpty)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _showCardsSheet,
                        child: Text('视频列表（${_cards.length}）'),
                      ),
                    ),
                  if (_cards.isNotEmpty && _episodes.isNotEmpty)
                    const SizedBox(width: 8),
                  if (_episodes.isNotEmpty)
                    Expanded(
                      child: FilledButton(
                        onPressed: _showEpisodesSheet,
                        child: Text('选集（${_episodes.length}）'),
                      ),
                    ),
                  if (_cards.isEmpty && _episodes.isEmpty)
                    Expanded(
                      child: FilledButton(
                        onPressed: _playCurrentPage,
                        child: const Text('嗅探播放本页'),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!onlineWebsiteWebViewSupported) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.site.displayName)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '在线网站需要在手机上打开，当前平台不支持内置网页',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.site.displayName),
        actions: [
          if (_canGoBack)
            IconButton(
              tooltip: '后退',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () async {
                await _controller.goBack();
              },
            ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              unawaited(_controller.reload());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _OnlineWebsiteWebView(
              controller: _controller,
              site: widget.site,
              initialUrl: widget.site.url,
              onParsed: _onParsed,
              onParseStarted: _onParseStarted,
              onDirectMedia: _onDirectMedia,
              onUrlChanged: _onUrlChanged,
              onShieldChanged: _onShieldChanged,
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }
}

class OnlineWebsiteDetailPage extends StatefulWidget {
  const OnlineWebsiteDetailPage({
    super.key,
    required this.site,
    required this.card,
    required this.repository,
    required this.store,
  });

  final OnlineWebsite site;
  final OnlineWebsiteCard card;
  final AppRepository repository;
  final LocalStore store;

  @override
  State<OnlineWebsiteDetailPage> createState() =>
      _OnlineWebsiteDetailPageState();
}

class _OnlineWebsiteDetailPageState extends State<OnlineWebsiteDetailPage> {
  late final WebViewController _controller;
  var _episodes = <OnlineWebsiteEpisode>[];
  var _info = const OnlineWebsiteDetailInfo();
  var _parsing = false;
  var _currentUrl = '';
  var _challenged = false;
  String _lastDirectPlayUrl = '';
  DateTime _lastDirectPlayAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.card.url;
    _info = OnlineWebsiteDetailInfo(
      title: widget.card.title,
      cover: widget.card.cover,
    );
    if (onlineWebsiteWebViewSupported) {
      _controller = WebViewController();
    }
  }

  void _onUrlChanged(String url) {
    _currentUrl = url;
  }

  void _onParseStarted() {
    if (!mounted) return;
    setState(() => _parsing = true);
  }

  void _onParsed(
    List<OnlineWebsiteCard> cards,
    List<OnlineWebsiteEpisode> episodes,
    OnlineWebsiteDetailInfo info,
  ) {
    if (!mounted || _challenged) return;
    setState(() {
      _episodes = episodes;
      _info = info;
      _parsing = false;
    });
  }

  void _onShieldChanged(bool challenged) {
    if (!mounted) return;
    setState(() {
      _challenged = challenged;
      if (challenged) _episodes = [];
    });
  }

  void _onDirectMedia(String url) {
    unawaited(_playDirectMedia(url));
  }

  Future<void> _playDirectMedia(String url) async {
    final now = DateTime.now();
    if (url == _lastDirectPlayUrl &&
        now.difference(_lastDirectPlayAt).inSeconds < 3) {
      return;
    }
    _lastDirectPlayUrl = url;
    _lastDirectPlayAt = now;
    if (!mounted) return;
    final detail = onlineWebsiteDetail(
      site: widget.site,
      pageUrl: _currentUrl.isEmpty ? widget.card.url : _currentUrl,
      title: _info.title.isEmpty ? widget.card.title : _info.title,
      cover: _info.cover,
      episodes: [OnlineWebsiteEpisode(title: '直链播放', url: url)],
    );
    await pushPlayer<void>(
      context,
      detail: detail,
      initialIndex: 0,
      repository: widget.repository,
      store: widget.store,
    );
  }

  Future<void> _playEpisode(int index) async {
    if (index < 0 || index >= _episodes.length || !mounted) return;
    final detail = onlineWebsiteDetail(
      site: widget.site,
      pageUrl: _currentUrl.isEmpty ? widget.card.url : _currentUrl,
      title: _info.title.isEmpty ? widget.card.title : _info.title,
      cover: _info.cover,
      episodes: _episodes,
    );
    await pushPlayer<void>(
      context,
      detail: detail,
      initialIndex: index,
      repository: widget.repository,
      store: widget.store,
    );
  }

  Future<void> _playCurrentPage() async {
    if (!mounted) return;
    final pageUrl = _currentUrl.isEmpty ? widget.card.url : _currentUrl;
    final detail = onlineWebsiteDetail(
      site: widget.site,
      pageUrl: pageUrl,
      title: _info.title.isEmpty ? widget.card.title : _info.title,
      cover: _info.cover,
      episodes: [OnlineWebsiteEpisode(title: '正片', url: pageUrl)],
    );
    await pushPlayer<void>(
      context,
      detail: detail,
      initialIndex: 0,
      repository: widget.repository,
      store: widget.store,
    );
  }

  Widget _episodePanel() {
    final colors = Theme.of(context).colorScheme;
    final title = _info.title.isEmpty ? widget.card.title : _info.title;
    final cover = _info.cover.isEmpty ? widget.card.cover : _info.cover;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 76,
                    child: _onlineWebsiteCoverImage(context, cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '导演：${_info.director.isEmpty ? '暂无' : _info.director}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '演员：${_info.actors.isEmpty ? '暂无' : _info.actors}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_challenged)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text('正在过网站验证…如需点一下验证，请在页面上点一下')),
                    )
                  else if (_parsing && _episodes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text('正在识别选集…')),
                    )
                  else if (_episodes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        widget.site.autoMode
                            ? '未识别到选集，可以直接嗅探播放本页'
                            : '手动模式：直接嗅探播放本页',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < _episodes.length; i++)
                          ActionChip(
                            label: Text(_episodes[i].title),
                            onPressed: () => unawaited(_playEpisode(i)),
                          ),
                      ],
                    ),
                  if (!_challenged) const SizedBox(height: 12),
                  if (!_challenged)
                    FilledButton(
                      onPressed: _playCurrentPage,
                      child: const Text('嗅探播放本页'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!onlineWebsiteWebViewSupported) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.card.title)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '在线网站需要在手机上打开，当前平台不支持内置网页',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _info.title.isEmpty ? widget.card.title : _info.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              unawaited(_controller.reload());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: _OnlineWebsiteWebView(
              controller: _controller,
              site: widget.site,
              initialUrl: widget.card.url,
              onParsed: _onParsed,
              onParseStarted: _onParseStarted,
              onDirectMedia: _onDirectMedia,
              onUrlChanged: _onUrlChanged,
              onShieldChanged: _onShieldChanged,
            ),
          ),
          Expanded(flex: 2, child: _episodePanel()),
        ],
      ),
    );
  }
}

class _OnlineWebsiteCardTile extends StatelessWidget {
  const _OnlineWebsiteCardTile({required this.card, required this.onTap});

  final OnlineWebsiteCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _onlineWebsiteCoverImage(context, card.cover),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            card.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
