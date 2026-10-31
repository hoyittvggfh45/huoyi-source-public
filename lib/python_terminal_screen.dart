import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'python_binary.dart';
import 'python_terminal_session.dart';

class PythonTerminalScreen extends StatefulWidget {
  const PythonTerminalScreen({super.key});

  @override
  State<PythonTerminalScreen> createState() => _PythonTerminalScreenState();
}

class _PythonTerminalScreenState extends State<PythonTerminalScreen> {
  final PythonBinaryService _binary = PythonBinaryService();
  PythonReplSession? _repl;
  final List<PythonTerminalLine> _lines = [];
  final PythonTerminalHistory _history = PythonTerminalHistory();
  final TextEditingController _input = TextEditingController();
  final TextEditingController _package = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  List<File> _scripts = [];
  String _version = '';
  bool _busy = false;
  bool _pipBusy = false;
  bool _needMore = false;
  bool _available = false;
  String? _error;

  String get _prompt => _needMore ? '... ' : '>>> ';

  @override
  void initState() {
    super.initState();
    _inputFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          final previous = _history.previous();
          if (previous != null) {
            _input.text = previous;
            _input.selection = TextSelection.fromPosition(
              TextPosition(offset: _input.text.length),
            );
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          final next = _history.next();
          if (next != null) {
            _input.text = next;
            _input.selection = TextSelection.fromPosition(
              TextPosition(offset: _input.text.length),
            );
          }
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
    _load();
  }

  @override
  void dispose() {
    _repl?.dispose();
    _input.dispose();
    _package.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dir = await pythonScriptsDirectory();
    final scripts = await listPythonScripts(dir);
    if (!mounted) return;
    setState(() => _scripts = scripts);
    final installed = await _binary.isInstalled();
    if (!mounted) return;
    if (!installed) {
      setState(() {
        _lines.add(
          const PythonTerminalLine(
            'Python 未安装，请先在实验室安装',
            isStderr: true,
          ),
        );
      });
      return;
    }
    final version = await _binary.version();
    if (!mounted) return;
    setState(() => _version = version);
    await _startRepl(dir);
  }

  Future<void> _startRepl(Directory scriptsDir) async {
    try {
      final repl = await PythonReplSession.start(
        binary: await _binary.binaryPath(),
        driverPath: await _binary.driverPath(),
        environment: await _binary.environment(),
        workingDirectory: scriptsDir.path,
        onLine: _appendLine,
        onNeedMore: (needMore) {
          if (!mounted) return;
          setState(() {
            _needMore = needMore;
            _busy = false;
          });
          _inputFocus.requestFocus();
        },
        onExit: (code) {
          if (!mounted) return;
          setState(() {
            _available = false;
            _busy = false;
            _lines.add(PythonTerminalLine('--- 会话已结束 (exit $code) ---'));
          });
        },
      );
      if (!mounted) {
        await repl.dispose();
        return;
      }
      setState(() {
        _repl = repl;
        _available = true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _appendLine(PythonTerminalLine line) {
    if (!mounted) return;
    setState(() => _lines.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final raw = _input.text;
    final repl = _repl;
    if (_busy || repl == null || !_available) return;
    if (raw.isEmpty && !_needMore) return;
    final prompt = _prompt;
    _history.push(raw);
    _history.resetCursor();
    _input.clear();
    _appendLine(PythonTerminalLine('$prompt$raw', isInput: true));
    setState(() => _busy = true);
    try {
      await repl.send(raw);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
          _needMore = false;
        });
      }
    }
  }

  Future<void> _runScript(File script) async {
    if (_busy) return;
    final name = script.path.split('/').last;
    _appendLine(PythonTerminalLine('--- $name ---', isInput: true));
    setState(() => _busy = true);
    try {
      final dir = await pythonScriptsDirectory();
      final process = await _binary.startScriptProcess(
        script.path,
        workingDirectory: dir.path,
      );
      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _appendLine(PythonTerminalLine(line)));
      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _appendLine(PythonTerminalLine(line, isStderr: true)),
          );
      final code = await process.exitCode;
      await stdoutDone.asFuture<void>();
      await stderrDone.asFuture<void>();
      if (mounted) {
        _appendLine(PythonTerminalLine('--- exit $code ---'));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importScript() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['py'],
      );
      final source = picked.isEmpty ? null : picked.single.path;
      if (source != null) {
        final dir = await pythonScriptsDirectory();
        await importPythonScript(dir, source);
        final scripts = await listPythonScripts(dir);
        if (mounted) setState(() => _scripts = scripts);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installPackage() async {
    final package = _package.text.trim();
    if (_pipBusy || package.isEmpty) return;
    setState(() {
      _pipBusy = true;
      _error = null;
    });
    _appendLine(PythonTerminalLine('--- pip install $package ---', isInput: true));
    try {
      final code = await _binary.pipInstall(
        package,
        onLine: (line) => _appendLine(PythonTerminalLine(line)),
      );
      _appendLine(PythonTerminalLine('--- pip exit $code ---'));
      if (code != 0 && mounted) {
        setState(() => _error = 'pip 安装失败（exit $code），请检查包名与网络');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _pipBusy = false);
    }
  }

  Future<void> _resetSession() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repl?.dispose();
      if (!mounted) return;
      setState(() {
        _repl = null;
        _available = false;
        _lines.clear();
        _needMore = false;
        _lines.add(const PythonTerminalLine('会话已重置'));
      });
      final dir = await pythonScriptsDirectory();
      await _startRepl(dir);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Python 终端'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all_rounded),
            tooltip: '清屏',
            onPressed: () => setState(() => _lines.clear()),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: '重置会话',
            onPressed: _busy ? null : _resetSession,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Python $_version'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final script in _scripts)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(script.path.split('/').last),
                              onPressed: _busy
                                  ? null
                                  : () => _runScript(script),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _importScript,
                  child: const Text('导入脚本'),
                ),
              ],
            ),
          ),
          if (_scripts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '还没有脚本：点导入脚本选一个 .py 文件，或把 .py 文件放进应用文件目录的 python/ 下。',
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _package,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: '依赖包名，如 requests',
                    ),
                    onSubmitted: (_) => _installPackage(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _pipBusy ? null : _installPackage,
                  child: const Text('安装依赖'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '依赖装到 lab/python/site-packages，装完即可在终端 import；纯 Python 包可装，需编译的包本机没有编译器，装不上。',
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final line = _lines[index];
                return SelectableText(
                  line.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: line.isStderr
                        ? Colors.red
                        : line.isInput
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text(_prompt, style: const TextStyle(fontFamily: 'monospace')),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    enabled: _available && !_busy,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: (_busy || !_available) ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
