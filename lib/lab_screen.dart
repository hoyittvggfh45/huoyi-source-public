import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'lab_environment.dart';
import 'lab_service.dart';
import 'proxy_kernel_screen.dart';
import 'proxy_kernel_service.dart';
import 'python_terminal_screen.dart';

bool get labSupported => Platform.isAndroid;

class LabScreen extends StatefulWidget {
  const LabScreen({super.key, this.repository});

  final AppRepository? repository;

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> with WidgetsBindingObserver {
  late final LabEnvironmentService _service = LabEnvironmentService();
  late final ProxyKernelService _proxyService = ProxyKernelService();
  Map<LabEnvironmentId, LabEnvironmentInfo> _infos = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_service.stopAll());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_service.stopAll());
    }
  }

  Future<void> _refresh() async {
    try {
      final infos = await _service.refresh();
      if (!mounted) return;
      setState(() {
        _infos = infos;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = '';
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  int get _runningCount => _infos.values
      .where((info) => info.status == LabEnvironmentStatus.running)
      .length;

  @override
  Widget build(BuildContext context) {
    final python = _infos[LabEnvironmentId.python];
    final php = _infos[LabEnvironmentId.php];
    final node = _infos[LabEnvironmentId.node];
    final mihomo = _infos[LabEnvironmentId.mihomo];
    return Scaffold(
      appBar: AppBar(title: const Text('实验室')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Text('运行中 $_runningCount'),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => _service.stopAll()),
                      child: const Text('全部停止'),
                    ),
                  ],
                ),
                if (_progress.isNotEmpty) Text(_progress),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (python != null) _pythonCard(python),
                if (php != null) _binaryCard(php),
                if (node != null) _binaryCard(node),
                if (mihomo != null) _mihomoCard(mihomo),
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    '服务随应用退出而停止，不开机自启；PHP、Node、Python 安装时从 Termux 仓库下载对应架构的软件包与依赖，安装包约 PHP 33MB、Node 24MB、Python 11MB；Python 依赖用终端里的安装依赖装到 python/site-packages。',
                  ),
                ),
              ],
            ),
    );
  }

  String _statusText(LabEnvironmentStatus status) {
    switch (status) {
      case LabEnvironmentStatus.notInstalled:
        return '未安装';
      case LabEnvironmentStatus.installed:
        return '已安装';
      case LabEnvironmentStatus.running:
        return '运行中';
    }
  }

  Widget _cardShell(LabEnvironmentInfo info, List<Widget> buttons) {
    final subtitle = [
      if (info.version.isNotEmpty) info.version,
      _statusText(info.status),
      if (info.address.isNotEmpty) info.address,
      if (info.detail.isNotEmpty) info.detail,
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: buttons),
          ],
        ),
      ),
    );
  }

  Widget _pythonCard(LabEnvironmentInfo info) {
    switch (info.status) {
      case LabEnvironmentStatus.notInstalled:
        return _cardShell(info, [
          ElevatedButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => _service.installPython(
                      onProgress: (received, total) => setState(
                        () => _progress =
                            '下载中 ${(received / 1048576).toStringAsFixed(1)}MB / ${(total / 1048576).toStringAsFixed(1)}MB',
                      ),
                    ),
                  ),
            child: const Text('安装'),
          ),
        ]);
      case LabEnvironmentStatus.installed:
      case LabEnvironmentStatus.running:
        return _cardShell(info, [
          ElevatedButton(
            onPressed: _busy
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const PythonTerminalScreen(),
                      ),
                    );
                    await _refresh();
                  },
            child: const Text('打开 Python 终端'),
          ),
        ]);
    }
  }

  Widget _binaryCard(LabEnvironmentInfo info) {
    final isPhp = info.id == LabEnvironmentId.php;
    Future<void> install() => _run(
      () => isPhp
          ? _service.installPhp(
              onProgress: (received, total) => setState(
                () => _progress =
                    '下载中 ${(received / 1048576).toStringAsFixed(1)}MB / ${(total / 1048576).toStringAsFixed(1)}MB',
              ),
            )
          : _service.installNode(
              onProgress: (received, total) => setState(
                () => _progress =
                    '下载中 ${(received / 1048576).toStringAsFixed(1)}MB / ${(total / 1048576).toStringAsFixed(1)}MB',
              ),
            ),
    );
    switch (info.status) {
      case LabEnvironmentStatus.notInstalled:
        return _cardShell(info, [
          ElevatedButton(
            onPressed: _busy ? null : install,
            child: const Text('安装'),
          ),
        ]);
      case LabEnvironmentStatus.installed:
        return _cardShell(info, [
          ElevatedButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => isPhp ? _service.startPhp() : _service.startNode(),
                  ),
            child: const Text('启动'),
          ),
        ]);
      case LabEnvironmentStatus.running:
        return _cardShell(info, [
          ElevatedButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => isPhp ? _service.stopPhp() : _service.stopNode(),
                  ),
            child: const Text('停止'),
          ),
        ]);
    }
  }

  Widget _mihomoCard(LabEnvironmentInfo info) {
    return _cardShell(info, [
      if (info.status == LabEnvironmentStatus.running)
        ElevatedButton(
          onPressed: _busy ? null : () => _run(() => _service.stopMihomo()),
          child: const Text('停止'),
        )
      else if (info.status == LabEnvironmentStatus.installed)
        ElevatedButton(
          onPressed: _busy ? null : () => _run(() => _service.startMihomo()),
          child: const Text('启动'),
        ),
      OutlinedButton(
        onPressed: _busy
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProxyKernelScreen(
                      service: _proxyService,
                      repository: widget.repository,
                    ),
                  ),
                );
                await _refresh();
              },
        child: const Text('管理'),
      ),
    ]);
  }
}
