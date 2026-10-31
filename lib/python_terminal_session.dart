import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class PythonTerminalLine {
  const PythonTerminalLine(this.text, {this.isStderr = false, this.isInput = false});

  final String text;
  final bool isStderr;
  final bool isInput;
}

class PythonTerminalHistory {
  final List<String> _entries = [];
  int _cursor = 0;

  List<String> get entries => List.unmodifiable(_entries);

  void push(String command) {
    if (command.isEmpty) return;
    if (_entries.isEmpty || _entries.last != command) {
      _entries.add(command);
    }
    _cursor = _entries.length;
  }

  String? previous() {
    if (_entries.isEmpty || _cursor <= 0) return null;
    _cursor--;
    return _entries[_cursor];
  }

  String? next() {
    if (_cursor >= _entries.length) return null;
    _cursor++;
    return _cursor >= _entries.length ? '' : _entries[_cursor];
  }

  void resetCursor() {
    _cursor = _entries.length;
  }
}

class PythonTerminalFailure implements Exception {
  const PythonTerminalFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class PythonReplSession {
  PythonReplSession._(
    this._process,
    this._onLine,
    this._onNeedMore,
    this._onExit,
  );

  static Future<PythonReplSession> start({
    required String binary,
    required String driverPath,
    Map<String, String>? environment,
    String? workingDirectory,
    required void Function(PythonTerminalLine line) onLine,
    required void Function(bool needMore) onNeedMore,
    void Function(int code)? onExit,
  }) async {
    final process = await Process.start(
      binary,
      [driverPath],
      environment: environment,
      workingDirectory: workingDirectory,
    );
    final ready = Completer<PythonReplSession>();
    final session = PythonReplSession._(process, onLine, onNeedMore, onExit);
    session._attach(ready);
    return ready.future;
  }

  static const String _marker = '\x00LAB_REPL';
  static const String _stderrMarker = '\x00LAB_STDERR';

  final Process _process;
  final void Function(PythonTerminalLine line) _onLine;
  final void Function(bool needMore) _onNeedMore;
  final void Function(int code)? _onExit;
  final List<PythonTerminalLine> _pending = [];
  final List<String> _earlyStderr = [];
  bool _stderrMode = false;
  bool _disposed = false;
  Completer<PythonReplSession>? _ready;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  void _attach(Completer<PythonReplSession> ready) {
    _ready = ready;
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onDone: () {
          if (!ready.isCompleted) {
            ready.completeError(
              const PythonTerminalFailure('Python 进程启动失败'),
            );
          }
        });
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!ready.isCompleted) _earlyStderr.add(line);
        });
    unawaited(
      _process.exitCode.then((code) {
        if (!ready.isCompleted) {
          final detail = _earlyStderr.isEmpty
              ? 'Python 进程启动失败'
              : _earlyStderr.join('\n');
          ready.completeError(PythonTerminalFailure(detail));
          return;
        }
        if (!_disposed) _onExit?.call(code);
      }),
    );
  }

  void _handleLine(String line) {
    if (line == '$_marker READY') {
      if (_ready != null && !_ready!.isCompleted) {
        _ready!.complete(this);
      }
      return;
    }
    if (line.startsWith('$_marker ')) {
      final flag = line.split(' ').last == '1';
      for (final pending in _pending) {
        _onLine(pending);
      }
      _pending.clear();
      _stderrMode = false;
      _onNeedMore(flag);
      return;
    }
    if (line == _stderrMarker) {
      _stderrMode = true;
      return;
    }
    _pending.add(PythonTerminalLine(line, isStderr: _stderrMode));
  }

  Future<void> send(String line) async {
    if (_disposed) {
      throw const PythonTerminalFailure('Python 会话已关闭');
    }
    _process.stdin.add(utf8.encode('$line\n'));
    await _process.stdin.flush();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    try {
      await _process.stdin.close();
    } catch (_) {}
    _process.kill();
  }
}

Future<Directory> pythonScriptsDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(path.join(docs.path, 'python'));
}

Future<List<File>> listPythonScripts(Directory dir) async {
  if (!await dir.exists()) return const [];
  final files = <File>[];
  await for (final item in dir.list()) {
    if (item is File && item.path.endsWith('.py')) {
      files.add(item);
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Future<File> importPythonScript(Directory dir, String sourcePath) async {
  await dir.create(recursive: true);
  final base = sourcePath.split('/').last;
  var name = base.isEmpty ? 'script.py' : base;
  if (!name.endsWith('.py')) name = '$name.py';
  var target = File('${dir.path}/$name');
  var index = 1;
  while (await target.exists()) {
    index++;
    final stem = name.substring(0, name.length - 3);
    target = File('${dir.path}/${stem}_$index.py');
  }
  return File(sourcePath).copy(target.path);
}
