import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'mini_app_builtin.dart';
import 'mini_app_host_page.dart';
import 'mini_app_manifest.dart';
import 'mini_app_runtime.dart';
import 'mini_app_settings.dart';
import 'mini_app_settings_screen.dart';
import 'mini_app_store.dart';

class MiniAppHomePage extends StatefulWidget {
  const MiniAppHomePage({super.key});

  @override
  State<MiniAppHomePage> createState() => _MiniAppHomePageState();
}

class _MiniAppHomePageState extends State<MiniAppHomePage>
    with SingleTickerProviderStateMixin {
  MiniAppSettings? _settings;
  MiniAppRuntime? _runtime;
  List<MiniAppManifest> _installed = const [];
  List<MiniAppMarketItem> _market = const [];
  String _marketState = 'idle';
  String _marketError = '';
  final Set<String> _installing = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    unawaited(_runtime?.stopAll());
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await MiniAppSettings.load();
    final runtime = MiniAppRuntime(
      store: MiniAppStore(),
      settings: settings,
    );
    final seedResult = await MiniAppBuiltin.ensureSeeded(runtime.store);
    final installed = await runtime.store.listInstalled();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _runtime = runtime;
      _installed = installed;
    });
    if (seedResult.hasFailures) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            '部分内置小程序安装失败：${seedResult.failed.map((e) => e.appId).join('、')}',
          ),
        ),
      );
    }
    await _loadMarket();
  }

  Future<void> _refreshInstalled() async {
    final runtime = _runtime;
    if (runtime == null) return;
    final installed = await runtime.store.listInstalled();
    if (mounted) setState(() => _installed = installed);
  }

  Future<void> _loadMarket() async {
    final settings = _settings;
    if (settings == null) return;
    setState(() {
      _marketState = 'loading';
      _marketError = '';
    });
    try {
      final response = await http
          .get(Uri.parse(settings.marketUrl))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final items = parseMiniAppMarketJson(
        utf8.decode(response.bodyBytes),
      );
      if (!mounted) return;
      setState(() {
        _market = items;
        _marketState = items.isEmpty ? 'empty' : 'ready';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _market = const [];
        _marketState = 'error';
        _marketError = error.toString();
      });
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const MiniAppSettingsScreen(),
      ),
    );
    final settings = await MiniAppSettings.load();
    final runtime = _runtime;
    if (runtime != null) runtime.settings = settings;
    if (!mounted) return;
    setState(() => _settings = settings);
    await _loadMarket();
  }

  Future<void> _openApp(MiniAppManifest manifest) async {
    final runtime = _runtime;
    final settings = _settings;
    if (runtime == null || settings == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MiniAppHostPage(
          manifest: manifest,
          runtime: runtime,
          settings: settings,
        ),
      ),
    );
    await _refreshInstalled();
  }

  Future<void> _deleteApp(MiniAppManifest manifest) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除小程序'),
        content: Text('确定删除「${manifest.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final runtime = _runtime;
    if (runtime == null) return;
    await runtime.stop(manifest.appId);
    await runtime.store.deleteApp(manifest.appId);
    await _refreshInstalled();
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('已删除')));
    }
  }

  Future<void> _installFromZip() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;
    await _runInstall(() async {
      final runtime = _runtime!;
      final manifest = await runtime.store.installFromZipFile(File(path));
      return manifest;
    });
  }

  Future<void> _installFromFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择小程序文件夹',
    );
    if (path == null) return;
    await _runInstall(() async {
      final runtime = _runtime!;
      return runtime.store.installFromDirectory(Directory(path));
    });
  }

  Future<void> _installFromLink() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从链接安装'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入 zip 包地址',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('安装'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _runInstall(() async {
      final runtime = _runtime!;
      return runtime.store.installFromUrl(url);
    });
  }

  Future<void> _runInstall(
    Future<MiniAppManifest> Function() install,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final manifest = await install();
      await _refreshInstalled();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('已安装「${manifest.name}」')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('安装失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installMarketItem(MiniAppMarketItem item) async {
    if (_installing.contains(item.appId)) return;
    setState(() => _installing.add(item.appId));
    try {
      final runtime = _runtime!;
      await runtime.store.installFromUrl(
        item.url,
        expectedMd5: item.md5,
        expectedSize: item.size,
      );
      await _refreshInstalled();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('已安装「${item.name}」')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('安装失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _installing.remove(item.appId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('小程序'),
          actions: [
            PopupMenuButton<int>(
              icon: const Icon(Icons.add),
              tooltip: '导入',
              enabled: !_busy,
              onSelected: (value) {
                switch (value) {
                  case 0:
                    _installFromZip();
                  case 1:
                    _installFromFolder();
                  case 2:
                    _installFromLink();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<int>(
                  value: 0,
                  child: Text('导入 zip 包'),
                ),
                PopupMenuItem<int>(
                  value: 1,
                  child: Text('导入文件夹'),
                ),
                PopupMenuItem<int>(
                  value: 2,
                  child: Text('从链接安装'),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '小程序设置',
              onPressed: _settings == null ? null : _openSettings,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '已安装'),
              Tab(text: '市场'),
            ],
          ),
        ),
        body: _settings == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _installedTab(),
                  _marketTab(),
                ],
              ),
      ),
    );
  }

  Widget _installedTab() {
    if (_installed.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('还没有安装小程序')),
          ),
        ],
      );
    }
    return Column(
      children: [
        if (_busy)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: LinearProgressIndicator(),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 8,
              childAspectRatio: 0.72,
            ),
            itemCount: _installed.length,
            itemBuilder: (context, index) {
              final manifest = _installed[index];
              return MiniAppIconTile(
                name: manifest.name,
                appId: manifest.appId,
                status: manifest.version.isEmpty
                    ? ''
                    : 'v${manifest.version}',
                onTap: () => _openApp(manifest),
                onDelete: () => _deleteApp(manifest),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _marketTab() {
    if (_marketState == 'loading') {
      return const Center(child: CircularProgressIndicator());
    }
    if (_marketState == 'error') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('还没有市场数据'),
              const SizedBox(height: 8),
              Text(
                '市场地址拉取失败：$_marketError',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadMarket,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_marketState == 'empty') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('还没有市场数据'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadMarket,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMarket,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 8,
          childAspectRatio: 0.72,
        ),
        itemCount: _market.length,
        itemBuilder: (context, index) {
          final item = _market[index];
          final installed = _installed.any((e) => e.appId == item.appId);
          final installing = _installing.contains(item.appId);
          return MiniAppIconTile(
            name: item.name,
            appId: item.appId,
            status: installed
                ? '已安装'
                : installing
                    ? '安装中…'
                    : '安装',
            onTap: installed
                ? () {
                    final manifest = _installed
                        .where((e) => e.appId == item.appId)
                        .firstOrNull;
                    if (manifest != null) _openApp(manifest);
                  }
                : installing
                    ? null
                    : () => _installMarketItem(item),
          );
        },
      ),
    );
  }
}

class MiniAppIconTile extends StatelessWidget {
  const MiniAppIconTile({
    super.key,
    required this.name,
    required this.appId,
    this.status = '',
    this.onTap,
    this.onDelete,
  });

  final String name;
  final String appId;
  final String status;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  static const List<Color> _palette = [
    Color(0xFF7C4DFF),
    Color(0xFF673AB7),
    Color(0xFF3F51B5),
    Color(0xFF009688),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFFE91E63),
    Color(0xFF1E88E5),
  ];

  static Color tileColor(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final label = name.isEmpty ? appId : name;
    final firstChar = label.isEmpty
        ? '?'
        : String.fromCharCode(label.runes.first);
    return InkWell(
      onTap: onTap,
      onLongPress: onDelete,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: tileColor(appId),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  firstChar,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (onDelete != null)
                Positioned(
                  right: -6,
                  top: -6,
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          if (status.isNotEmpty)
            Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
