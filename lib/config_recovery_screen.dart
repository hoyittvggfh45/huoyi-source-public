import 'package:flutter/material.dart';

import 'local_store.dart';

class ConfigRecoveryScreen extends StatefulWidget {
  const ConfigRecoveryScreen({super.key, required this.store});
  final LocalStore store;
  @override
  State<ConfigRecoveryScreen> createState() => _ConfigRecoveryScreenState();
}

class _ConfigRecoveryScreenState extends State<ConfigRecoveryScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.reload();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('恢复本地配置')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('本地配置无法确认', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (widget.store.configurationError != null)
              Text(widget.store.configurationError!),
            const SizedBox(height: 12),
            const Text('可以重新读取配置恢复访问，本地记录不会被覆盖。'),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _reload,
              child: const Text('重新读取配置'),
            ),
          ],
        ),
      ),
    ),
  );
}
