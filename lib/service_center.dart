import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'duoju_runtime.dart';
import 'local_store.dart';

class DuojuServiceConfig {
  const DuojuServiceConfig({
    required this.name,
    required this.port,
    required this.bind,
    required this.runtime,
    required this.environment,
    required this.executable,
    required this.startArgs,
    required this.description,
    required this.autoStart,
    required this.followApp,
  });

  factory DuojuServiceConfig.defaults() => const DuojuServiceConfig(
    name: 'duoju',
    port: 5689,
    bind: '127.0.0.1',
    runtime: 'Node.js',
    environment: 'Linux 沙盒运行时 (PRoot)',
    executable: '__plugin:nodejs__/bin/node24-arm64',
    startArgs:
        'interval=2000 --incremental-marking --concurrent-marking '
        '--parallel-scavenge __sdcard__dslayer/server/node/duoju-node/index.js',
    description: '',
    autoStart: false,
    followApp: true,
  );

  factory DuojuServiceConfig.fromJson(Map<String, dynamic> json) {
    final fallback = DuojuServiceConfig.defaults();
    final name = '${json['name'] ?? ''}'.trim();
    final port = int.tryParse('${json['port'] ?? ''}');
    return DuojuServiceConfig(
      name: name.isNotEmpty ? name : fallback.name,
      port: port != null && port >= 1 && port <= 65535
          ? port
          : fallback.port,
      bind: '${json['bind'] ?? fallback.bind}',
      runtime: '${json['runtime'] ?? fallback.runtime}',
      environment: '${json['environment'] ?? fallback.environment}',
      executable: '${json['executable'] ?? fallback.executable}',
      startArgs: '${json['startArgs'] ?? fallback.startArgs}',
      description: '${json['description'] ?? ''}',
      autoStart: json['autoStart'] == true,
      followApp: json['followApp'] != false,
    );
  }

  final String name;
  final int port;
  final String bind;
  final String runtime;
  final String environment;
  final String executable;
  final String startArgs;
  final String description;
  final bool autoStart;
  final bool followApp;

  String get host => bind == '0.0.0.0' ? '127.0.0.1' : bind;
  String get webUrl => 'http://127.0.0.1:$port/';
  String get startCommand => 'node $startArgs';
  String get lifecycleLabel => followApp ? '跟随 app' : '常驻前台';

  Map<String, dynamic> toJson() => {
    'name': name,
    'port': port,
    'bind': bind,
    'runtime': runtime,
    'environment': environment,
    'executable': executable,
    'startArgs': startArgs,
    'description': description,
    'autoStart': autoStart,
    'followApp': followApp,
  };

  DuojuServiceConfig copyWith({
    String? name,
    int? port,
    String? bind,
    String? runtime,
    String? environment,
    String? executable,
    String? startArgs,
    String? description,
    bool? autoStart,
    bool? followApp,
  }) => DuojuServiceConfig(
    name: name ?? this.name,
    port: port ?? this.port,
    bind: bind ?? this.bind,
    runtime: runtime ?? this.runtime,
    environment: environment ?? this.environment,
    executable: executable ?? this.executable,
    startArgs: startArgs ?? this.startArgs,
    description: description ?? this.description,
    autoStart: autoStart ?? this.autoStart,
    followApp: followApp ?? this.followApp,
  );
}

class DuojuLogEntry {
  const DuojuLogEntry({required this.time, required this.text});

  factory DuojuLogEntry.fromJson(Map<String, dynamic> json) => DuojuLogEntry(
    time: (json['time'] as String?) ?? '',
    text: (json['text'] as String?) ?? '',
  );

  factory DuojuLogEntry.now(String text) => DuojuLogEntry(
    time: DateTime.now().toString().substring(0, 19),
    text: text,
  );

  final String time;
  final String text;

  Map<String, dynamic> toJson() => {'time': time, 'text': text};
}

class DuojuServiceStore {
  static const String configKey = 'duoju_service_config';
  static const String logKey = 'duoju_service_log';
  static const int maxLogEntries = 100;

  static DuojuServiceConfig readConfig(SharedPreferences prefs) {
    final raw = prefs.getString(configKey);
    if (raw == null || raw.isEmpty) return DuojuServiceConfig.defaults();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DuojuServiceConfig.fromJson(decoded);
      }
    } catch (_) {}
    return DuojuServiceConfig.defaults();
  }

  static Future<void> writeConfig(
    SharedPreferences prefs,
    DuojuServiceConfig config,
  ) => prefs.setString(configKey, jsonEncode(config.toJson()));

  static List<DuojuLogEntry> readLog(SharedPreferences prefs) {
    final raw = prefs.getString(logKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(DuojuLogEntry.fromJson)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> appendLog(SharedPreferences prefs, String text) async {
    final entries = readLog(prefs)
      ..add(DuojuLogEntry.now(text));
    while (entries.length > maxLogEntries) {
      entries.removeAt(0);
    }
    await prefs.setString(
      logKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  static Future<void> clearLog(SharedPreferences prefs) =>
      prefs.remove(logKey);
}

class DuojuProbeResult {
  const DuojuProbeResult({required this.running, this.state});

  final bool running;
  final String? state;
}

Future<DuojuProbeResult> probeDuojuService({
  required String host,
  required int port,
}) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
  } catch (_) {
    return const DuojuProbeResult(running: false);
  }
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final request = await client.getUrl(
      Uri.parse('http://$host:$port/__jdd/state'),
    );
    final response = await request.close().timeout(const Duration(seconds: 3));
    final body = await response.transform(utf8.decoder).join();
    client.close();
    if (response.statusCode == 200 && body.isNotEmpty) {
      return DuojuProbeResult(running: true, state: body);
    }
  } catch (_) {}
  return const DuojuProbeResult(running: true);
}

class ServiceCenterScreen extends StatefulWidget {
  const ServiceCenterScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<ServiceCenterScreen> createState() => _ServiceCenterScreenState();
}

class _ServiceCenterScreenState extends State<ServiceCenterScreen> {
  late DuojuServiceConfig _config;
  bool? _running;
  String? _probeNote;
  bool _probing = false;
  bool _starting = false;
  int? _effectivePort;

  SharedPreferences get _prefs => widget.store.preferences;

  @override
  void initState() {
    super.initState();
    _config = DuojuServiceStore.readConfig(_prefs);
    _effectivePort = _config.port;
    unawaited(_probeThenMaybeAutoStart());
  }

  Future<void> _probeThenMaybeAutoStart() async {
    await _probe(silent: true);
    if (!mounted) return;
    if (_config.autoStart && _running != true && !_starting) {
      await _startService();
    }
  }

  Future<void> _probe({bool silent = false}) async {
    if (_probing) return;
    setState(() => _probing = true);
    var port = _effectivePort ?? _config.port;
    var result = await probeDuojuService(host: _config.host, port: port);
    if (!result.running && port == _config.port) {
      final known = await DuojuRuntime.instance.readKnownPort();
      if (known != null && known != port) {
        result = await probeDuojuService(host: _config.host, port: known);
        if (result.running) port = known;
      }
    }
    if (!mounted) return;
    setState(() {
      _running = result.running;
      _effectivePort = port;
      _probeNote = result.running ? 'TCP 探活 :$port 已通' : 'TCP 探活 :$port 未通';
      _probing = false;
    });
    if (!silent) {
      await DuojuServiceStore.appendLog(
        _prefs,
        result.running ? '探活 :$port 已通' : '探活 :$port 未通',
      );
    }
  }

  Future<void> _openEdit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ServiceEditScreen(
          store: widget.store,
          initial: _config,
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _config = DuojuServiceStore.readConfig(_prefs);
      });
      await DuojuServiceStore.appendLog(_prefs, '配置已保存');
      await _probe();
    }
  }

  Future<void> _openLog() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ServiceLogScreen(store: widget.store),
      ),
    );
  }

  Future<void> _openWeb() async {
    await DuojuServiceStore.appendLog(_prefs, '打开 Web ${_config.webUrl}');
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ServiceWebScreen(
          title: _config.name,
          url: _config.webUrl,
        ),
      ),
    );
  }

  Future<void> _export() async {
    final text = const JsonEncoder.withIndent('  ').convert(_config.toJson());
    await Clipboard.setData(ClipboardData(text: text));
    await DuojuServiceStore.appendLog(_prefs, '配置已导出到剪贴板');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出配置'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _startService() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final handle = await DuojuRuntime.instance.start(_config);
      if (!mounted) return;
      setState(() => _effectivePort = handle.actualPort);
      await DuojuServiceStore.appendLog(
        _prefs,
        '服务已启动（端口 ${handle.actualPort}）',
      );
      await DuojuRuntime.instance.appendAppLog(
        '服务已启动（端口 ${handle.actualPort}）',
      );
    } catch (error) {
      await DuojuServiceStore.appendLog(_prefs, '启动失败：$error');
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('启动失败'),
            content: Text('$error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
      await _probe();
    }
  }

  Future<void> _stopService() async {
    if (DuojuRuntime.instance.currentProcess != null) {
      await DuojuRuntime.instance.stop();
      await DuojuServiceStore.appendLog(_prefs, '服务已停止');
      await DuojuRuntime.instance.appendAppLog('服务已停止');
      await _probe();
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('停止服务'),
        content: Text(
          '${_config.name} 正在运行，但不是本 App 拉起的进程，本 App 停不掉它。请到运行它的地方停止。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    await _probe();
  }

  Future<void> _onToggle(bool value) async {
    if (value == _running) return;
    if (value) {
      await _startService();
    } else {
      await _stopService();
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _running == true;
    final runningCount = running ? 1 : 0;
    final displayPort = _effectivePort ?? _config.port;
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务中心'),
        actions: [
          IconButton(
            tooltip: '探活',
            icon: _probing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: () => _probe(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '运行中 $runningCount · 共 1',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: running ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _config.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(':$displayPort'),
                      ),
                      Switch(
                        value: running,
                        onChanged: _starting ? null : _onToggle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '引用插件 nodejs · TCP 探活 :$displayPort · ${_config.lifecycleLabel}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    running
                        ? '${_config.name} 服务运行中 · 端口 $displayPort'
                        : '${_config.name} 服务未运行 · 端口 $displayPort',
                  ),
                  if (displayPort != _config.port) ...[
                    const SizedBox(height: 4),
                    Text('端口 ${_config.port} 被占，实际用 $displayPort'),
                  ],
                  if (_probeNote != null) ...[
                    const SizedBox(height: 4),
                    Text(_probeNote!),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _config.startArgs,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('编辑配置'),
                        onPressed: _openEdit,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.article_rounded, size: 18),
                        label: const Text('查看日志'),
                        onPressed: _openLog,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.language_rounded, size: 18),
                        label: const Text('打开 Web'),
                        onPressed: _openWeb,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('导出'),
                        onPressed: _export,
                      ),
                      TextButton.icon(
                        icon: Icon(
                          running
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                        label: Text(running ? '停止服务' : '启动服务'),
                        onPressed: _starting
                            ? null
                            : () => _onToggle(!running),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '服务由本 App 内置的 Node 环境运行；首次启动会解压环境（约 40MB 资源），端口被占时自动顺延，实际端口以卡片和日志为准。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class ServiceEditScreen extends StatefulWidget {
  const ServiceEditScreen({
    super.key,
    required this.store,
    required this.initial,
  });

  final LocalStore store;
  final DuojuServiceConfig initial;

  @override
  State<ServiceEditScreen> createState() => _ServiceEditScreenState();
}

class _ServiceEditScreenState extends State<ServiceEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _portController;
  late final TextEditingController _argsController;
  late final TextEditingController _descController;
  late String _environment;
  late bool _autoStart;
  late bool _followApp;
  String? _nameError;
  String? _portError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial.name);
    _portController = TextEditingController(text: '${initial.port}');
    _argsController = TextEditingController(text: initial.startArgs);
    _descController = TextEditingController(text: initial.description);
    _environment = initial.environment;
    _autoStart = initial.autoStart;
    _followApp = initial.followApp;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _portController.dispose();
    _argsController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    setState(() {
      _nameError = name.isEmpty ? '名称必填' : null;
      _portError = port == null || port < 1 || port > 65535 ? '端口填 1-65535' : null;
    });
    if (_nameError != null || _portError != null) return;
    final config = widget.initial.copyWith(
      name: name,
      port: port,
      environment: _environment,
      startArgs: _argsController.text,
      description: _descController.text,
      autoStart: _autoStart,
      followApp: _followApp,
    );
    await DuojuServiceStore.writeConfig(widget.store.preferences, config);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('编辑服务 · ${widget.initial.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('基本配置'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: '名称',
              hintText: '必填',
              errorText: _nameError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          const Text('唯一，导入时用于去重'),
          const SizedBox(height: 16),
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '服务端口',
              errorText: _portError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          const Text('填了端口启动后会自动用端口探活，「打开 Web」也依赖它'),
          const SizedBox(height: 16),
          const Text('运行时插件'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Node.js'),
                selected: true,
                onSelected: (_) {},
              ),
              const ChoiceChip(label: Text('PHP'), selected: false),
              const ChoiceChip(label: Text('Python'), selected: false),
            ],
          ),
          const SizedBox(height: 4),
          const Text('duoju 是 Node 服务，运行时固定'),
          const SizedBox(height: 16),
          const Text('运行环境'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Linux 沙盒运行时 (PRoot)'),
                selected: _environment == 'Linux 沙盒运行时 (PRoot)',
                onSelected: (_) => setState(
                  () => _environment = 'Linux 沙盒运行时 (PRoot)',
                ),
              ),
              ChoiceChip(
                label: const Text('自定义'),
                selected: _environment == '自定义',
                onSelected: (_) =>
                    setState(() => _environment = '自定义'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('已自动填写可执行文件'),
          const SizedBox(height: 4),
          Text(widget.initial.executable),
          const SizedBox(height: 16),
          TextField(
            controller: _argsController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '启动参数',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          const Text('App 内运行时只取其中 -- 开头的调优参数，脚本路径固定用内置 duoju'),
          const SizedBox(height: 16),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: '描述',
              hintText: '选填，方便自己记',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('自启动'),
            subtitle: const Text('只记录意愿，进程仍由插件中心或终端托管'),
            value: _autoStart,
            onChanged: (value) => setState(() => _autoStart = value),
          ),
          SwitchListTile(
            title: const Text('跟随 App'),
            subtitle: const Text('关掉则卡片显示为常驻前台'),
            value: _followApp,
            onChanged: (value) => setState(() => _followApp = value),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}

class ServiceLogScreen extends StatefulWidget {
  const ServiceLogScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<ServiceLogScreen> createState() => _ServiceLogScreenState();
}

class _ServiceLogScreenState extends State<ServiceLogScreen> {
  List<DuojuLogEntry> _entries = [];
  List<String> _output = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final entries = DuojuServiceStore.readLog(widget.store.preferences);
    if (mounted) {
      setState(() => _entries = entries);
    }
    final output = await DuojuRuntime.instance.readServiceLogTail();
    if (mounted) {
      setState(() => _output = output);
    }
  }

  Future<void> _probe() async {
    final config = DuojuServiceStore.readConfig(widget.store.preferences);
    final result = await probeDuojuService(host: config.host, port: config.port);
    await DuojuServiceStore.appendLog(
      widget.store.preferences,
      result.running
          ? '探活 :${config.port} 已通'
          : '探活 :${config.port} 未通',
    );
    await _load();
  }

  Future<void> _clear() async {
    await DuojuServiceStore.clearLog(widget.store.preferences);
    if (mounted) {
      setState(() => _entries = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务日志'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          IconButton(
            tooltip: '探活',
            icon: const Icon(Icons.radar_rounded),
            onPressed: _probe,
          ),
          IconButton(
            tooltip: '清空操作记录',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _clear,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '服务输出（最新 200 行）',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_output.isEmpty)
            const Text('暂无服务输出，启动服务后这里会显示它的运行日志')
          else
            Container(
              padding: const EdgeInsets.all(8),
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              child: SelectableText(
                _output.join('\n'),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            '操作记录',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_entries.isEmpty)
            const Text('暂无记录，点右上角探活会记一条')
          else
            ..._entries.reversed.map(
              (entry) => ListTile(
                title: Text(entry.text),
                subtitle: Text(entry.time),
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }
}

class ServiceWebScreen extends StatefulWidget {
  const ServiceWebScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<ServiceWebScreen> createState() => _ServiceWebScreenState();
}

class _ServiceWebScreenState extends State<ServiceWebScreen> {
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
      appBar: AppBar(
        title: Text('${widget.title} · Web'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
