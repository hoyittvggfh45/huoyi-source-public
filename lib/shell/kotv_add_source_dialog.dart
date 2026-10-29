import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core_bridge.dart';
import '../import_center.dart';
import '../jar_import.dart';
import '../local_store.dart';
import '../tvbox_config.dart';
import 'kotv_theme.dart';

enum _KotvAddMode { single, multi, local, json }

class KotvAddSourceDialog extends StatefulWidget {
  const KotvAddSourceDialog({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<KotvAddSourceDialog> createState() => _KotvAddSourceDialogState();
}

class _KotvAddSourceDialogState extends State<KotvAddSourceDialog> {
  final _input = TextEditingController();
  _KotvAddMode _mode = _KotvAddMode.single;
  bool _busy = false;
  bool _done = false;
  bool _bannerVisible = false;
  String _result = '';

  String get _modeLabel => switch (_mode) {
    _KotvAddMode.single => '单线路',
    _KotvAddMode.multi => '多仓索引',
    _KotvAddMode.local => '本地路径',
    _KotvAddMode.json => 'JSON',
  };

  String get _modeNote => switch (_mode) {
    _KotvAddMode.single => '单线路：一条 TVBox 配置地址，导入后按配置分组。',
    _KotvAddMode.multi => '多仓索引：多仓合集的配置地址，导入后站点按配置分组共存。',
    _KotvAddMode.local => '本地路径：选择本机文件，支持 py、js、json、jar 或 TVBox 配置。',
    _KotvAddMode.json => 'JSON：粘贴 TVBox 配置 JSON，或自定义源 JSON、TXT 内容。',
  };

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _pickLocal() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null || file.path == null || !mounted) return;
    setState(() {
      _mode = _KotvAddMode.local;
      _input.text = file.path!;
    });
  }

  Future<void> _load() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _result = '请先填写内容或选择本地文件';
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
      final outcome = switch (_mode) {
        _KotvAddMode.single || _KotvAddMode.multi => await _loadFromUrl(text),
        _KotvAddMode.local => await _loadFromFile(text),
        _KotvAddMode.json => await _loadFromJson(text),
      };
      if (mounted) {
        setState(() {
          _result = outcome;
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

  Future<String> _loadFromUrl(String url) async {
    final report = await TvBoxImporter(widget.repository).importFromUrl(url);
    return '已导入「${report.name}」：${report.summary}';
  }

  Future<String> _loadFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) throw StateError('本地文件不存在：$path');
    final name = path.split(Platform.pathSeparator).last;
    final lower = name.toLowerCase();
    if (lower.endsWith('.py') || lower.endsWith('.js')) {
      final bytes = await file.readAsBytes();
      if (lower.endsWith('.py') && bytes.length > 32 * 1024 * 1024) {
        throw const FormatException('文件过大，无法导入');
      }
      final report = await ImportEngine(
        store: widget.store,
        repository: widget.repository,
      ).importAll([ImportCandidate(name: name, bytes: bytes)]);
      return report.summary;
    }
    if (lower.endsWith('.jar')) {
      final jarId =
          'jar-${md5.convert(utf8.encode(path)).toString().substring(0, 8)}';
      final classes = await JarImport.scanAndRegister(
        jarId: jarId,
        jarUrl: path,
      );
      final usable = classes.where((info) => info.instantiable).length;
      return '识别到 ${classes.length} 个 Spider 类，已注册 $usable 个站点';
    }
    final size = await file.length();
    if (size > 8 * 1024 * 1024) throw const FormatException('文件过大，无法导入');
    final text = utf8.decode(await file.readAsBytes());
    var isTvBox = false;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map &&
          (decoded.containsKey('sites') || decoded.containsKey('spider'))) {
        isTvBox = true;
      }
    } catch (_) {}
    if (!isTvBox) {
      throw const FormatException('该文件不是 TVBox 配置（含 sites 或 spider）');
    }
    final report = await TvBoxImporter(
      widget.repository,
    ).importFromText(text, sourceIdentity: 'file:$name:${text.length}');
    return '已导入「${report.name}」：${report.summary}';
  }

  Future<String> _loadFromJson(String text) async {
    var isTvBox = false;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map &&
          (decoded.containsKey('sites') || decoded.containsKey('spider'))) {
        isTvBox = true;
      }
    } catch (_) {}
    if (isTvBox) {
      final report = await TvBoxImporter(
        widget.repository,
      ).importFromText(text, sourceIdentity: 'text:${text.length}');
      return '已导入「${report.name}」：${report.summary}';
    }
    final result = await widget.repository.importCustomSources(text);
    final added = (result['added'] as List? ?? const []).length;
    final updated = (result['updated'] as List? ?? const []).length;
    final skipped = (result['skipped'] as List? ?? const []).length;
    final failed = (result['failed'] as List? ?? const []).length;
    return '新增 $added 个，更新 $updated 个，跳过 $skipped 个，失败 $failed 个';
  }

  @override
  Widget build(BuildContext context) {
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
                '添加点播源',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in _KotvAddMode.values)
                    ChoiceChip(
                      label: Text(switch (mode) {
                        _KotvAddMode.single => '单线路',
                        _KotvAddMode.multi => '多仓索引',
                        _KotvAddMode.local => '本地路径',
                        _KotvAddMode.json => 'JSON',
                      }),
                      selected: _mode == mode,
                      selectedColor: KotvTokens.primary,
                      labelStyle: TextStyle(
                        color: _mode == mode
                            ? Colors.white
                            : KotvTokens.unselectedColor,
                      ),
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _mode = mode),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _modeNote,
                style: const TextStyle(
                  fontSize: 13,
                  color: KotvTokens.unselectedColor,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _input,
                enabled: !_busy,
                maxLines: _mode == _KotvAddMode.json ? 6 : 1,
                minLines: _mode == _KotvAddMode.json ? 4 : 1,
                keyboardType: _mode == _KotvAddMode.json
                    ? TextInputType.multiline
                    : TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: _modeLabel,
                  border: const OutlineInputBorder(),
                  hintText: _mode == _KotvAddMode.local
                      ? '点“选择本地”选取文件'
                      : _mode == _KotvAddMode.json
                      ? '粘贴配置 JSON 或自定义源内容'
                      : '粘贴配置地址',
                ),
              ),
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_busy) const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickLocal,
                      icon: const Icon(Icons.folder_open_rounded, size: 20),
                      label: const Text('选择本地'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy || _done ? null : _load,
                      child: const Text('加载'),
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

Future<void> showKotvAddSourceDialog({
  required BuildContext context,
  required AppRepository repository,
  required LocalStore store,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        KotvAddSourceDialog(repository: repository, store: store),
  );
}
