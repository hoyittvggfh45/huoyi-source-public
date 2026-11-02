import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'service_center.dart';

List<String> duojuNodeFlags(String startArgs) {
  final flags = <String>[];
  for (final token in startArgs.split(RegExp(r'\s+'))) {
    if (token.startsWith('--')) flags.add(token);
  }
  return flags;
}

Future<void> extractTarGz(List<int> gzBytes, Directory target) async {
  final tarBytes = GZipDecoder().decodeBytes(gzBytes);
  final decoder = TarDecoder()..decodeBytes(tarBytes);
  for (final file in decoder.files) {
    final name = file.filename;
    if (name.isEmpty) continue;
    final base = path.normalize(target.path);
    final resolved = path.normalize(path.join(base, name));
    if (resolved != base &&
        !resolved.startsWith('$base${path.separator}')) {
      continue;
    }
    if (file.typeFlag == TarFile.directory) {
      await Directory(resolved).create(recursive: true);
    } else if (file.isSymLink) {
      final link = Link(resolved);
      try {
        await link.delete();
      } catch (_) {}
      await link.parent.create(recursive: true);
      link.createSync(file.nameOfLinkedFile!);
    } else {
      final out = File(resolved);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(file.contentBytes ?? [], flush: true);
    }
  }
}

int? readPortFile(Directory dataDir) {
  try {
    final raw = File(path.join(dataDir.path, 'port.txt')).readAsStringSync();
    return int.tryParse(raw.trim());
  } catch (_) {
    return null;
  }
}

class DuojuRuntimePaths {
  const DuojuRuntimePaths({
    required this.baseDir,
    required this.nodeBin,
    required this.libDir,
    required this.indexJs,
    required this.dataDir,
    required this.logFile,
  });

  final Directory baseDir;
  final String nodeBin;
  final String libDir;
  final String indexJs;
  final Directory dataDir;
  final File logFile;
}

class DuojuProcessHandle {
  const DuojuProcessHandle({required this.process, required this.actualPort});

  final Process process;
  final int actualPort;
}

class DuojuRuntime {
  DuojuRuntime({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static final DuojuRuntime instance = DuojuRuntime();

  static const int runtimeVersion = 1;
  static const int maxLogBytes = 512 * 1024;
  static const int keepLogBytes = 128 * 1024;

  final Future<Directory> Function() _supportDirectory;
  Process? _current;
  IOSink? _logSink;
  int _logBytes = 0;
  StreamSubscription<List<int>>? _outSub;
  StreamSubscription<List<int>>? _errSub;

  Process? get currentProcess => _current;

  Future<Directory> _baseDir() async {
    final support = await _supportDirectory();
    return Directory(path.join(support.path, 'duoju_runtime'));
  }

  Future<DuojuRuntimePaths> ensureInstalled() async {
    final base = await _baseDir();
    final marker = File(path.join(base.path, 'VERSION'));
    var installed = false;
    try {
      installed = await marker.readAsString() == '$runtimeVersion';
    } catch (_) {
      installed = false;
    }
    if (!installed) {
      if (await base.exists()) await base.delete(recursive: true);
      await base.create(recursive: true);
      final nodeTar = await rootBundle.load('assets/node_runtime.tar.gz');
      await extractTarGz(nodeTar.buffer.asUint8List(), base);
      final duojuTar = await rootBundle.load('assets/duoju-node.tar.gz');
      await extractTarGz(duojuTar.buffer.asUint8List(), base);
      final nodeBin = path.join(base.path, 'bin', 'node');
      await Process.run('chmod', ['755', nodeBin]);
      await marker.writeAsString('$runtimeVersion', flush: true);
    }
    return DuojuRuntimePaths(
      baseDir: base,
      nodeBin: path.join(base.path, 'bin', 'node'),
      libDir: path.join(base.path, 'lib'),
      indexJs: path.join(base.path, 'duoju-node', 'index.js'),
      dataDir: Directory(path.join(base.path, 'jdd-data')),
      logFile: File(path.join(base.path, 'service.log')),
    );
  }

  Future<int?> readKnownPort() async {
    try {
      final base = await _baseDir();
      return readPortFile(Directory(path.join(base.path, 'jdd-data')));
    } catch (_) {
      return null;
    }
  }

  Future<void> _rotateLogIfNeeded(DuojuRuntimePaths paths) async {
    try {
      if (!await paths.logFile.exists()) return;
      final size = await paths.logFile.length();
      if (size <= maxLogBytes) return;
      final bytes = await paths.logFile.readAsBytes();
      final tail = bytes.sublist(bytes.length - keepLogBytes);
      final newline = tail.indexOf(10);
      await paths.logFile.writeAsBytes(
        newline >= 0 ? tail.sublist(newline + 1) : tail,
        flush: true,
      );
    } catch (_) {}
  }

  void _attachLog(Process process, DuojuRuntimePaths paths) {
    _logBytes = 0;
    _logSink = paths.logFile.openWrite(mode: FileMode.append);
    void writeChunk(List<int> chunk) {
      try {
        _logSink?.add(chunk);
        _logBytes += chunk.length;
        if (_logBytes > maxLogBytes) {
          unawaited(_rotateLogSink(paths));
        }
      } catch (_) {}
    }

    _outSub = process.stdout.listen(writeChunk);
    _errSub = process.stderr.listen(writeChunk);
  }

  Future<void> _rotateLogSink(DuojuRuntimePaths paths) async {
    try {
      await _logSink?.close();
    } catch (_) {}
    _logSink = null;
    _logBytes = 0;
    await _rotateLogIfNeeded(paths);
    _logSink = paths.logFile.openWrite(mode: FileMode.append);
  }

  Future<DuojuRuntimePaths?> _pathsIfInstalled() async {
    try {
      final base = await _baseDir();
      final marker = File(path.join(base.path, 'VERSION'));
      if (await marker.readAsString() != '$runtimeVersion') return null;
      return DuojuRuntimePaths(
        baseDir: base,
        nodeBin: path.join(base.path, 'bin', 'node'),
        libDir: path.join(base.path, 'lib'),
        indexJs: path.join(base.path, 'duoju-node', 'index.js'),
        dataDir: Directory(path.join(base.path, 'jdd-data')),
        logFile: File(path.join(base.path, 'service.log')),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> appendAppLog(String text) async {
    try {
      final paths = await _pathsIfInstalled();
      if (paths == null) return;
      final line =
          '[app] ${DateTime.now().toString().substring(0, 19)} $text\n';
      await paths.logFile.writeAsString(line, mode: FileMode.append);
    } catch (_) {}
  }

  Future<List<String>> readServiceLogTail({int maxLines = 200}) async {
    try {
      final paths = await _pathsIfInstalled();
      if (paths == null || !await paths.logFile.exists()) return [];
      final content = await paths.logFile.readAsString();
      final lines = content.split('\n');
      while (lines.isNotEmpty && lines.last.isEmpty) {
        lines.removeLast();
      }
      if (lines.length <= maxLines) return lines;
      return lines.sublist(lines.length - maxLines);
    } catch (_) {
      return [];
    }
  }

  Future<int> _waitForPortOrExit(
    Process process,
    Directory dataDir,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final port = readPortFile(dataDir);
      if (port != null) return port;
      final exited = await Future.any([
        process.exitCode.then((_) => true),
        Future.delayed(const Duration(milliseconds: 200), () => false),
      ]);
      if (exited) return -2;
    }
    return readPortFile(dataDir) ?? -1;
  }

  Future<DuojuProcessHandle> start(DuojuServiceConfig config) async {
    final paths = await ensureInstalled();
    if (!await paths.dataDir.exists()) {
      await paths.dataDir.create(recursive: true);
    }
    await _rotateLogIfNeeded(paths);
    final flags = duojuNodeFlags(config.startArgs);
    Future<Process> spawn(List<String> nodeFlags) => Process.start(
      paths.nodeBin,
      [
        ...nodeFlags,
        paths.indexJs,
        '--port',
        '${config.port}',
        '--data',
        paths.dataDir.path,
      ],
      environment: {
        ...Platform.environment,
        'LD_LIBRARY_PATH': paths.libDir,
      },
      workingDirectory: paths.dataDir.path,
    );
    var process = await spawn(flags);
    var port = await _waitForPortOrExit(
      process,
      paths.dataDir,
      const Duration(seconds: 3),
    );
    if (port == -2 && flags.isNotEmpty) {
      final code = await process.exitCode;
      await appendAppLog('带调优参数启动失败（退出码 $code），改用无参数重试');
      process = await spawn([]);
      port = await _waitForPortOrExit(
        process,
        paths.dataDir,
        const Duration(seconds: 5),
      );
    }
    _current = process;
    _attachLog(process, paths);
    unawaited(
      process.exitCode.then((_) async {
        if (_current == process) _current = null;
        await _outSub?.cancel();
        await _errSub?.cancel();
        await _logSink?.close();
        _logSink = null;
      }),
    );
    return DuojuProcessHandle(
      process: process,
      actualPort: port > 0 ? port : config.port,
    );
  }

  Future<void> stop() async {
    final process = _current;
    if (process == null) return;
    try {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    } finally {
      _current = null;
      await _outSub?.cancel();
      await _errSub?.cancel();
      await _logSink?.close();
      _logSink = null;
    }
  }
}
