import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../core_bridge.dart';
import '../local_store.dart';
import 'installer.dart';
import 'manifest.dart';
import 'market.dart';
import 'renderer.dart';
import 'storage.dart';

class PluginCenterScreen extends StatefulWidget {
  const PluginCenterScreen({super.key, required this.store, this.repository});
  final LocalStore store;
  final AppRepository? repository;

  @override
  State<PluginCenterScreen> createState() => _PluginCenterScreenState();
}

class _PluginCenterScreenState extends State<PluginCenterScreen> {
  MiniAppInstaller? _installer;
  List<MiniAppManifest> _apps = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;
  late final TextEditingController _marketUrl = TextEditingController();
  late final MarketSettings _marketSettings;
  List<MarketItem> _marketItems = [];
  bool _marketLoading = false;
  String? _marketError;

  @override
  void initState() {
    super.initState();
    _marketSettings = MarketSettings(widget.store.preferences);
    _marketUrl.text = _marketSettings.url;
    _refresh();
  }

  @override
  void dispose() {
    _marketUrl.dispose();
    super.dispose();
  }

  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/miniapps');
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final installer = MiniAppInstaller(await _root());
      final apps = await installer.list();
      if (!mounted) return;
      setState(() {
        _installer = installer;
        _apps = apps;
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

  Future<void> _open(MiniAppManifest manifest) async {
    final installer = _installer;
    if (installer == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MiniAppScreen(
          manifest: manifest,
          directory: installer.directoryFor(manifest.id),
          storage: MiniAppStorage(widget.store.preferences, manifest.id),
          store: widget.store,
          repository: widget.repository,
        ),
      ),
    );
  }

  String _installedMessage(MiniAppManifest manifest, {String prefix = '已安装'}) {
    final unavailable = manifest.unavailablePermissions;
    if (unavailable.isEmpty) return '$prefix${manifest.name}';
    return '$prefix${manifest.name}；以下权限本版未提供：${unavailable.join('、')}';
  }

  Future<void> _installFromDirectory() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    final directory = Directory(path);
    final manifestFile = File('${directory.path}/manifest.json');
    if (!await manifestFile.exists()) {
      _showMessage('所选目录缺少 manifest.json');
      return;
    }
    try {
      final manifestJson = await manifestFile.readAsString();
      final installer = _installer ?? MiniAppInstaller(await _root());
      final manifest = await installer.install(
        manifestJson: manifestJson,
        files: directory,
      );
      _showMessage(_installedMessage(manifest, prefix: '已安装'));
      await _refresh();
    } catch (error) {
      _showMessage('安装失败：$error');
    }
  }

  Future<void> _installFromZip() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked.isEmpty) return;
    setState(() => _busy = true);
    try {
      final bytes = await picked.single.readAsBytes();
      final installer = _installer ?? MiniAppInstaller(await _root());
      final manifest = await installer.installFromZip(bytes);
      _showMessage(_installedMessage(manifest));
      await _refresh();
    } catch (error) {
      _showMessage('安装失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installExample() async {
    try {
      final manifestJson = await rootBundle.loadString(
        'assets/miniapps/hello/manifest.json',
      );
      final entry = await rootBundle.loadString(
        'assets/miniapps/hello/index.html',
      );
      final temp = await Directory.systemTemp.createTemp('jhminiapp_hello_');
      await File('${temp.path}/manifest.json').writeAsString(manifestJson);
      await File('${temp.path}/index.html').writeAsString(entry);
      final installer = _installer ?? MiniAppInstaller(await _root());
      final manifest = await installer.install(
        manifestJson: manifestJson,
        files: temp,
      );
      await temp.delete(recursive: true);
      _showMessage(_installedMessage(manifest, prefix: '示例已安装'));
      await _refresh();
    } catch (error) {
      _showMessage('安装示例失败：$error');
    }
  }

  Future<void> _remove(MiniAppManifest manifest) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除${manifest.name}？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _installer?.remove(manifest.id);
    await _refresh();
  }

  Future<void> _showImportMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('从压缩包安装'),
              subtitle: const Text('选择含 manifest.json 的 zip 包'),
              onTap: () => Navigator.pop(context, 'zip'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('从目录安装'),
              subtitle: const Text('选择含 manifest.json 的文件夹'),
              onTap: () => Navigator.pop(context, 'dir'),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('安装示例'),
              onTap: () => Navigator.pop(context, 'example'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'zip':
        await _installFromZip();
      case 'dir':
        await _installFromDirectory();
      case 'example':
        await _installExample();
    }
  }

  Future<void> _loadMarket() async {
    final url = _marketUrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _marketLoading = true;
      _marketError = null;
    });
    try {
      await _marketSettings.setUrl(url);
      final items = await MarketClient().fetchItems(url);
      if (!mounted) return;
      setState(() {
        _marketItems = items;
        _marketLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _marketError = error.toString();
        _marketLoading = false;
      });
    }
  }

  Future<void> _installMarketItem(MarketItem item) async {
    if (!item.isZip) {
      _showMessage('该条目为在线站点型，当前版本仅支持压缩包安装');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await MarketClient().downloadPackage(item);
      final installer = _installer ?? MiniAppInstaller(await _root());
      final manifest = await installer.installFromZip(bytes);
      await _marketSettings.recordInstalled(item.appId, manifest.id);
      _showMessage(_installedMessage(manifest));
      await _refresh();
    } catch (error) {
      _showMessage('安装失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('小程序'),
          actions: [
            IconButton(
              key: const ValueKey('miniapp-import'),
              tooltip: '导入小程序',
              onPressed: _busy ? null : () => unawaited(_showImportMenu()),
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 4),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '已安装'),
              Tab(text: '市场'),
            ],
          ),
        ),
        body: TabBarView(children: [_installedTab(), _marketTab()]),
      ),
    );
  }

  Widget _installedTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂无已安装的迷你应用'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _installExample,
              icon: const Icon(Icons.download_outlined),
              label: const Text('安装示例'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _installFromDirectory,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('从目录安装'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _installFromZip,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('从压缩包安装'),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: _apps.length,
      itemBuilder: (context, index) {
        final app = _apps[index];
        final label = app.name.isEmpty ? '?' : app.name.characters.first;
        return InkWell(
          onTap: () => _open(app),
          onLongPress: () => _remove(app),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 8),
              Text(
                app.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (app.unavailablePermissions.isNotEmpty)
                Text(
                  '部分功能受限',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _marketTab() {
    final installedIds = _apps.map((app) => app.id).toSet();
    final installedMap = _marketSettings.installedIdMap;
    bool isInstalled(MarketItem item) {
      if (installedIds.contains(item.appId)) return true;
      final mapped = installedMap[item.appId];
      return mapped != null && installedIds.contains(mapped);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _marketUrl,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '市场地址 (JSON)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _marketLoading ? null : () => unawaited(_loadMarket()),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('加载'),
        ),
        if (_marketLoading) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
        ],
        if (_marketError != null) ...[
          const SizedBox(height: 12),
          Text(
            _marketError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (!_marketLoading && _marketError == null) ...[
          const SizedBox(height: 12),
          if (_marketItems.isEmpty)
            const Text('点加载拉取市场条目')
          else
            for (final item in _marketItems)
              _marketCard(item, isInstalled(item)),
        ],
      ],
    );
  }

  Widget _marketCard(MarketItem item, bool installed) {
    final parts = [
      if (item.version.isNotEmpty) item.version,
      if (item.author.isNotEmpty) item.author,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(item.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (parts.isNotEmpty) Text(parts),
            if (item.description.isNotEmpty) Text(item.description),
          ],
        ),
        trailing: installed
            ? const Text('已安装')
            : FilledButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(_installMarketItem(item)),
                child: const Text('安装'),
              ),
      ),
    );
  }
}
