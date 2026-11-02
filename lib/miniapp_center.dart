import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_store.dart';

class MiniAppModule {
  const MiniAppModule({
    required this.name,
    required this.fileName,
    required this.version,
    required this.description,
    required this.builtin,
    this.assetPath,
    this.text,
  });

  final String name;
  final String fileName;
  final String version;
  final String description;
  final bool builtin;
  final String? assetPath;
  final String? text;

  Map<String, dynamic> toJson() => {
        'name': name,
        'fileName': fileName,
        'text': text ?? '',
      };

  static MiniAppModule fromJson(Map<String, dynamic> json) {
    final fileName = (json['fileName'] ?? '') as String;
    final text = (json['text'] ?? '') as String;
    final meta = parseMiniAppMeta(text, fileName);
    return MiniAppModule(
      name: (json['name'] as String?) ?? meta.name,
      fileName: fileName,
      version: meta.version,
      description: meta.description,
      builtin: false,
      text: text,
    );
  }
}

class MiniAppMeta {
  const MiniAppMeta({
    required this.name,
    required this.version,
    required this.description,
  });

  final String name;
  final String version;
  final String description;
}

MiniAppMeta parseMiniAppMeta(String text, String fileName) {
  final base = fileName
      .split('/')
      .last
      .split('\\')
      .last
      .replaceAll(RegExp(r'\.js$', caseSensitive: false), '');
  var name = base;
  var version = '';
  final versionMatch =
      RegExp(r'var version\s*=\s*(\d+)').firstMatch(text) ??
          RegExp(r'@version\s+(\d+)').firstMatch(text);
  if (versionMatch != null) version = versionMatch.group(1) ?? '';
  final nameMatch = RegExp(r'@name\s+(.+)').firstMatch(text);
  if (nameMatch != null) {
    final candidate = nameMatch.group(1)!.trim();
    if (candidate.isNotEmpty) name = candidate;
  }
  var description = '';
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('/**')) {
    final end = trimmed.indexOf('*/');
    if (end > 0) {
      final block = trimmed.substring(3, end);
      final lines = block
          .split('\n')
          .map((line) {
            var cleaned = line.trim();
            if (cleaned.startsWith('*')) {
              cleaned = cleaned.substring(1).trim();
            }
            return cleaned;
          })
          .where(
            (line) => line.isNotEmpty && !line.startsWith('@'),
          )
          .toList();
      description = lines.join('\n');
    }
  } else {
    final lines = <String>[];
    for (final line in text.split('\n')) {
      final cleaned = line.trim();
      if (!cleaned.startsWith('//')) break;
      final body = cleaned.substring(2).trim();
      if (body.isNotEmpty) lines.add(body);
    }
    description = lines.join('\n');
  }
  if (description.length > 600) {
    description = description.substring(0, 600);
  }
  return MiniAppMeta(name: name, version: version, description: description);
}

class MiniAppStore {
  static const String importsKey = 'miniapp_imports';

  static const List<(String, String)> builtins = [
    ('assets/miniapp/磁力君.简.js', '磁力君.简.js'),
    ('assets/miniapp/Hikerurl.js', 'Hikerurl.js'),
  ];

  static List<MiniAppModule> loadImports(SharedPreferences prefs) {
    final raw = prefs.getString(importsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MiniAppModule.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveImports(
    SharedPreferences prefs,
    List<MiniAppModule> modules,
  ) async {
    final encoded = jsonEncode([
      for (final module in modules)
        if (!module.builtin) module.toJson(),
    ]);
    await prefs.setString(importsKey, encoded);
  }

  static Future<List<MiniAppModule>> addImport(
    SharedPreferences prefs,
    String fileName,
    String text,
  ) async {
    final meta = parseMiniAppMeta(text, fileName);
    final modules = loadImports(prefs)
        .where((module) => module.fileName != fileName)
        .toList();
    modules.add(
      MiniAppModule(
        name: meta.name,
        fileName: fileName,
        version: meta.version,
        description: meta.description,
        builtin: false,
        text: text,
      ),
    );
    await saveImports(prefs, modules);
    return modules;
  }

  static Future<List<MiniAppModule>> removeImport(
    SharedPreferences prefs,
    String fileName,
  ) async {
    final modules = loadImports(prefs)
        .where((module) => module.fileName != fileName)
        .toList();
    await saveImports(prefs, modules);
    return modules;
  }
}

class MiniAppCenterScreen extends StatefulWidget {
  const MiniAppCenterScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<MiniAppCenterScreen> createState() => _MiniAppCenterScreenState();
}

class _MiniAppCenterScreenState extends State<MiniAppCenterScreen> {
  List<MiniAppModule> _modules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final modules = <MiniAppModule>[];
    for (final builtin in MiniAppStore.builtins) {
      try {
        final text = await rootBundle.loadString(builtin.$1);
        final meta = parseMiniAppMeta(text, builtin.$2);
        modules.add(
          MiniAppModule(
            name: meta.name,
            fileName: builtin.$2,
            version: meta.version,
            description: meta.description,
            builtin: true,
            assetPath: builtin.$1,
          ),
        );
      } catch (_) {
        modules.add(
          MiniAppModule(
            name: builtin.$2.replaceAll(
              RegExp(r'\.js$', caseSensitive: false),
              '',
            ),
            fileName: builtin.$2,
            version: '',
            description: '内置文件读取失败',
            builtin: true,
            assetPath: builtin.$1,
          ),
        );
      }
    }
    modules.addAll(MiniAppStore.loadImports(widget.store.preferences));
    if (mounted) {
      setState(() {
        _modules = modules;
        _loading = false;
      });
    }
  }

  Future<void> _import() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['js'],
      );
    } on PlatformException catch (e) {
      if (e.code != 'unknown_path') rethrow;
      picked = await FilePicker.pickFile(type: FileType.any);
      final ext = picked?.extension?.toLowerCase();
      if (picked != null && ext != 'js') {
        _showMessage('不是 js 规则文件');
        return;
      }
    } catch (e) {
      _showMessage('导入失败：$e');
      return;
    }
    if (picked == null) return;
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) throw const FormatException('空文件');
      final text = utf8.decode(bytes, allowMalformed: true);
      await MiniAppStore.addImport(
        widget.store.preferences,
        picked.name.split('/').last.split('\\').last,
        text,
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已导入')),
        );
      }
    } catch (e) {
      _showMessage('导入失败：$e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('小程序'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _openDetail(MiniAppModule module) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MiniAppDetailScreen(
          module: module,
          store: widget.store,
          onDeleted: _reload,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('小程序'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: '导入规则',
            onPressed: _import,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已收录 ${_modules.length} 个规则模块',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '执行需海阔引擎接入，当前版本仅做模块管理：查看规则、导入导出。',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final module in _modules)
                  Card(
                    child: ListTile(
                      title: Text(module.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              if (module.version.isNotEmpty)
                                '版本 ${module.version}',
                              module.builtin ? '内置' : '导入',
                              module.fileName,
                            ].join(' · '),
                          ),
                          if (module.description.isNotEmpty)
                            Text(
                              module.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openDetail(module),
                    ),
                  ),
              ],
            ),
    );
  }
}

class MiniAppDetailScreen extends StatefulWidget {
  const MiniAppDetailScreen({
    super.key,
    required this.module,
    required this.store,
    required this.onDeleted,
  });

  final MiniAppModule module;
  final LocalStore store;
  final VoidCallback onDeleted;

  @override
  State<MiniAppDetailScreen> createState() => _MiniAppDetailScreenState();
}

class _MiniAppDetailScreenState extends State<MiniAppDetailScreen> {
  late Future<String> _textFuture;

  @override
  void initState() {
    super.initState();
    _textFuture = _loadText();
  }

  Future<String> _loadText() async {
    if (widget.module.text != null) return widget.module.text!;
    if (widget.module.assetPath != null) {
      return rootBundle.loadString(widget.module.assetPath!);
    }
    return '';
  }

  Future<void> _export() async {
    final text = await _textFuture;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('规则全文已复制到剪贴板')),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模块'),
        content: Text('确定删除 ${widget.module.name} 吗？内置模块不能删除。'),
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
    if (confirmed != true || !mounted) return;
    await MiniAppStore.removeImport(
      widget.store.preferences,
      widget.module.fileName,
    );
    widget.onDeleted();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    return Scaffold(
      appBar: AppBar(
        title: Text(module.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: '导出全文',
            onPressed: _export,
          ),
          if (!module.builtin)
            IconButton(
              icon: const Icon(Icons.delete_rounded),
              tooltip: '删除',
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                if (module.version.isNotEmpty) '版本 ${module.version}',
                module.builtin ? '内置' : '导入',
                module.fileName,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (module.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(module.description),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            FutureBuilder<String>(
              future: _textFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                return SelectableText(
                  snapshot.data!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
