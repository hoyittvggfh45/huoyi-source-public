import 'package:flutter/material.dart';

import 'local_store.dart';
import 'webdav_client.dart';

class WebdavScreen extends StatefulWidget {
  const WebdavScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<WebdavScreen> createState() => _WebdavScreenState();
}

class _WebdavScreenState extends State<WebdavScreen> {
  static const String fileName = 'backup.json';
  late final TextEditingController _address;
  late final TextEditingController _username;
  late final TextEditingController _password;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    final preferences = widget.store.preferences;
    _address = TextEditingController(
      text: preferences.getString('webdav_base_url') ?? '',
    );
    _username = TextEditingController(
      text: preferences.getString('webdav_username') ?? '',
    );
    _password = TextEditingController(
      text: preferences.getString('webdav_password') ?? '',
    );
  }

  @override
  void dispose() {
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<WebdavClient?> _client() async {
    final preferences = widget.store.preferences;
    await preferences.setString('webdav_base_url', _address.text.trim());
    await preferences.setString('webdav_username', _username.text.trim());
    await preferences.setString('webdav_password', _password.text);
    final error = webdavValidateAddress(_address.text);
    if (error != null) {
      setState(() => _status = error);
      return null;
    }
    return WebdavClient(
      baseUrl: _address.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
    );
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final client = await _client();
      if (client == null) return;
      final content = await widget.store.exportBackup();
      await client.upload(fileName, content);
      if (mounted) setState(() => _status = '已上传到 WebDAV');
    } catch (error) {
      if (mounted) setState(() => _status = '上传失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final client = await _client();
      if (client == null) return;
      final content = await client.download(fileName);
      final data = widget.store.validateBackup(content);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('恢复备份？'),
          content: Text(
            '包含 ${(data['profiles'] as List).length} 个用户。将替换本机的用户、追剧、观看记录和偏好设置；已下载视频保留。恢复后使用备份内的管理员密码登录。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await widget.store.importBackup(content);
      if (mounted) setState(() => _status = '已从 WebDAV 恢复');
    } catch (error) {
      if (mounted) setState(() => _status = '下载恢复失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'WebDAV 地址',
              hintText: 'https://example.com/dav/',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('上传备份'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _download,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('下载恢复'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(_status!),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('备份内容与本地导出一致：用户、追剧、历史和设置，不含视频文件。地址、用户名、密码只存在本机。'),
          ),
        ],
      ),
    );
  }
}
