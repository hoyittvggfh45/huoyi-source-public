import 'package:flutter/material.dart';

import '../lan_controller.dart';
import 'kotv_theme.dart';

class KotvSendToDeviceDialog extends StatefulWidget {
  const KotvSendToDeviceDialog({super.key});

  @override
  State<KotvSendToDeviceDialog> createState() =>
      _KotvSendToDeviceDialogState();
}

class _KotvSendToDeviceDialogState extends State<KotvSendToDeviceDialog> {
  final _address = TextEditingController();
  bool _busy = false;
  bool _done = false;
  bool _bannerVisible = false;
  String _result = '';

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final link = LanController.current;
    if (link == null) {
      setState(() {
        _result = '设备互联尚未就绪';
        _bannerVisible = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _bannerVisible = false;
      _result = '';
    });
    try {
      final address = _address.text.trim();
      if (address.isEmpty && link.connection != null) {
        await link.synchronize();
      } else {
        if (address.isEmpty) throw StateError('请填写对方本机地址');
        await link.ensureEnabled();
        final peer = await link.probe(address);
        await link.connect(peer);
        await link.synchronize();
      }
      if (mounted) {
        setState(() {
          _result = link.syncMessage.isEmpty ? '已同步' : link.syncMessage;
          _bannerVisible = true;
          _done = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _result = error.toString();
          _bannerVisible = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = LanController.current;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '发送到设备',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (link == null)
                const Text('设备互联尚未就绪，无法发送。')
              else ...[
                if (link.connection != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '已连接 · ${link.connection!.peer.name}，地址留空则直接同步到已连接设备。',
                      style: const TextStyle(
                        fontSize: 13,
                        color: KotvTokens.unselectedColor,
                      ),
                    ),
                  ),
                if (_bannerVisible && _result.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: KotvTokens.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(_result)),
                        IconButton(
                          tooltip: '关闭提示',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () =>
                              setState(() => _bannerVisible = false),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: _address,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '对方本机地址',
                    hintText: '192.168.1.8:53120',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '发送追剧与观看进度到对方设备，需对方已开启设备互联并保持应用在前台。',
                  style: TextStyle(
                    fontSize: 13,
                    color: KotvTokens.unselectedColor,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_busy) const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy || _done || link == null
                          ? null
                          : _send,
                      child: const Text('发送'),
                    ),
                  ),
                ],
              ),
              if (_done) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showKotvSendToDeviceDialog({required BuildContext context}) {
  return showDialog<void>(
    context: context,
    builder: (_) => const KotvSendToDeviceDialog(),
  );
}
