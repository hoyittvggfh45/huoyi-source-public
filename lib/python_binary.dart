import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'lab_environment.dart';

String pythonEnvDir(String root) => path.join(root, 'python');

String pythonUsrDir(String root) => path.join(
  pythonEnvDir(root),
  'data',
  'data',
  'com.termux',
  'files',
  'usr',
);

String pythonBinaryPath(String root) =>
    path.join(pythonUsrDir(root), 'bin', 'python3');

String pythonLibDir(String root) => path.join(pythonUsrDir(root), 'lib');

String pythonSitePackagesDir(String root) =>
    path.join(pythonEnvDir(root), 'site-packages');

String pythonDriverPath(String root) =>
    path.join(pythonEnvDir(root), 'repl_driver.py');

String pythonMetaPath(String root) =>
    path.join(pythonEnvDir(root), 'meta.json');

String pythonPipCacheDir(String root) =>
    path.join(pythonEnvDir(root), 'pip-cache');

String pythonTmpDir(String root) => path.join(pythonEnvDir(root), 'tmp');

const String pythonReplDriverScript = '''
import code
import io
import sys
MARKER = '\\x00LAB_REPL'
STDERR_MARKER = '\\x00LAB_STDERR'
console = code.InteractiveConsole()
sys.stdout.write(MARKER + ' READY\\n')
sys.stdout.flush()
while True:
    raw = sys.stdin.readline()
    if not raw:
        break
    line = raw.rstrip('\\n')
    out = io.StringIO()
    err = io.StringIO()
    old_out = sys.stdout
    old_err = sys.stderr
    try:
        sys.stdout = out
        sys.stderr = err
        need_more = console.push(line)
    except Exception as exc:
        err.write(str(exc))
        need_more = False
    finally:
        sys.stdout = old_out
        sys.stderr = old_err
    text = out.getvalue()
    etext = err.getvalue()
    if text:
        sys.stdout.write(text)
        if not text.endswith('\\n'):
            sys.stdout.write('\\n')
    if etext:
        sys.stdout.write(STDERR_MARKER + '\\n')
        sys.stdout.write(etext)
        if not etext.endswith('\\n'):
            sys.stdout.write('\\n')
    sys.stdout.write(MARKER + ' ' + ('1' if need_more else '0') + '\\n')
    sys.stdout.flush()
''';

Future<int> pipInstallPackage(
  String binary,
  String sitePackagesDir,
  String package,
  Map<String, String> environment, {
  void Function(String line)? onLine,
}) async {
  final process = await Process.start(binary, [
    '-m',
    'pip',
    'install',
    '--target',
    sitePackagesDir,
    '--upgrade',
    '--no-input',
    '--disable-pip-version-check',
    package,
  ], environment: environment);
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onLine, onDone: stdoutDone.complete);
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onLine, onDone: stderrDone.complete);
  final code = await process.exitCode;
  await stdoutDone.future;
  await stderrDone.future;
  return code;
}

class PythonBinaryService {
  PythonBinaryService({Future<Directory> Function()? rootDirectory})
    : _rootDirectory = rootDirectory ?? _defaultRootDirectory;

  static Future<Directory> _defaultRootDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(path.join(docs.path, 'lab'));
  }

  final Future<Directory> Function() _rootDirectory;

  Future<String> rootPath() async => (await _rootDirectory()).path;

  Future<String> binaryPath() async =>
      pythonBinaryPath(await rootPath());

  Future<String> driverPath() async =>
      pythonDriverPath(await rootPath());

  Future<String> sitePackagesPath() async =>
      pythonSitePackagesDir(await rootPath());

  Future<Map<String, String>> environment() async {
    final root = await rootPath();
    return {
      'LD_LIBRARY_PATH': pythonLibDir(root),
      'PYTHONHOME': pythonUsrDir(root),
      'PYTHONPATH': pythonSitePackagesDir(root),
      'PYTHONDONTWRITEBYTECODE': '1',
      'PATH': '/system/bin:/vendor/bin',
      'HOME': path.dirname(root),
      'TMPDIR': pythonTmpDir(root),
      'PIP_CACHE_DIR': pythonPipCacheDir(root),
    };
  }

  Future<void> ensureDirs() async {
    final root = await rootPath();
    await Directory(pythonSitePackagesDir(root)).create(recursive: true);
    await Directory(pythonPipCacheDir(root)).create(recursive: true);
    await Directory(pythonTmpDir(root)).create(recursive: true);
  }

  Future<void> ensureDriver() async {
    final driver = File(await driverPath());
    await driver.parent.create(recursive: true);
    await driver.writeAsString(pythonReplDriverScript, flush: true);
  }

  Future<bool> isInstalled() async {
    try {
      final binary = File(await binaryPath());
      if (!await binary.exists()) return false;
      final head = await binary
          .openRead(0, 64)
          .fold<BytesBuilder>(BytesBuilder(), (builder, chunk) {
            builder.add(chunk);
            return builder;
          })
          .then((builder) => builder.takeBytes());
      return elfMachine(head) == labElfAarch64;
    } catch (_) {
      return false;
    }
  }

  Future<String> version() async {
    try {
      final file = File(pythonMetaPath(await rootPath()));
      if (!await file.exists()) return '';
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return '';
      return '${decoded['version'] ?? ''}';
    } catch (_) {
      return '';
    }
  }

  Future<Process> startReplProcess({String? workingDirectory}) async {
    await ensureDirs();
    await ensureDriver();
    final binary = await binaryPath();
    if (!await File(binary).exists()) {
      throw LabFailure('Python 未安装，请先安装');
    }
    return Process.start(binary, [await driverPath()],
        environment: await environment(), workingDirectory: workingDirectory);
  }

  Future<Process> startScriptProcess(
    String scriptPath, {
    String? workingDirectory,
  }) async {
    await ensureDirs();
    final binary = await binaryPath();
    if (!await File(binary).exists()) {
      throw LabFailure('Python 未安装，请先安装');
    }
    return Process.start(binary, [scriptPath],
        environment: await environment(), workingDirectory: workingDirectory);
  }

  Future<int> pipInstall(
    String package, {
    void Function(String line)? onLine,
  }) async {
    await ensureDirs();
    final binary = await binaryPath();
    if (!await File(binary).exists()) {
      throw LabFailure('Python 未安装，请先安装');
    }
    return pipInstallPackage(
      binary,
      await sitePackagesPath(),
      package,
      await environment(),
      onLine: onLine,
    );
  }
}
