import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'lab_environment.dart';
import 'lab_process.dart';
import 'proxy_kernel_service.dart';
import 'python_binary.dart';

class LabEnvironmentService {
  LabEnvironmentService({
    Future<Directory> Function()? rootDirectory,
    LabProcessRunner? processRunner,
    ProxyKernelService? proxyService,
    Future<String> Function(Uri uri)? packagesDownloader,
    PythonBinaryService? pythonBinary,
  }) : _rootDirectory = rootDirectory ?? _defaultRootDirectory,
       _processRunner = processRunner ?? DefaultLabProcessRunner(),
       _proxyService = proxyService ?? ProxyKernelService(),
       _packagesDownloader = packagesDownloader ?? _defaultPackagesDownloader {
    _pythonBinary =
        pythonBinary ??
        PythonBinaryService(rootDirectory: _rootDirectory);
  }

  static Future<Directory> _defaultRootDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(path.join(docs.path, 'lab'));
  }

  static Future<String> _defaultPackagesDownloader(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'huoyi-lab');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw LabFailure('仓库索引下载失败（HTTP ${response.statusCode}）');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  final Future<Directory> Function() _rootDirectory;
  final LabProcessRunner _processRunner;
  final ProxyKernelService _proxyService;
  final Future<String> Function(Uri uri) _packagesDownloader;
  late final PythonBinaryService _pythonBinary;

  Process? _phpProcess;
  Process? _nodeProcess;
  bool _phpExited = true;
  bool _nodeExited = true;

  Future<Directory> rootDir() => _rootDirectory();

  Future<Map<LabEnvironmentId, LabEnvironmentInfo>> refresh() async {
    final root = await _rootDirectory();
    final infos = <LabEnvironmentId, LabEnvironmentInfo>{};
    infos[LabEnvironmentId.python] = await _pythonInfo();
    infos[LabEnvironmentId.php] = await _binaryInfo(
      root.path,
      LabEnvironmentId.php,
      'PHP',
      _phpProcess,
      _phpExited,
    );
    infos[LabEnvironmentId.node] = await _binaryInfo(
      root.path,
      LabEnvironmentId.node,
      'Node',
      _nodeProcess,
      _nodeExited,
    );
    infos[LabEnvironmentId.mihomo] = await _mihomoInfo();
    return infos;
  }

  Future<LabEnvironmentInfo> _pythonInfo() async {
    try {
      final installed = await _pythonBinary.isInstalled();
      if (!installed) {
        return const LabEnvironmentInfo(
          id: LabEnvironmentId.python,
          name: 'Python',
          version: '',
          status: LabEnvironmentStatus.notInstalled,
          detail: '未安装，按需从 Termux 仓库下载',
        );
      }
      final version = await _pythonBinary.version();
      return LabEnvironmentInfo(
        id: LabEnvironmentId.python,
        name: 'Python',
        version: version,
        status: LabEnvironmentStatus.installed,
        detail: '按需下载的 Termux 构建，依赖装到 python/site-packages',
      );
    } catch (error) {
      return LabEnvironmentInfo(
        id: LabEnvironmentId.python,
        name: 'Python',
        version: '',
        status: LabEnvironmentStatus.notInstalled,
        detail: '$error',
      );
    }
  }

  Future<LabEnvironmentInfo> _binaryInfo(
    String root,
    LabEnvironmentId id,
    String name,
    Process? process,
    bool exited,
  ) async {
    try {
      final meta = await _readMeta(root, id);
      final running = process != null && !exited;
      if (!running && meta.pid != 0) {
        await _reapStale(root, id, meta);
      }
      if (running) {
        final port = meta.port == 0
            ? (id == LabEnvironmentId.php ? labPhpPort : labNodePort)
            : meta.port;
        return LabEnvironmentInfo(
          id: id,
          name: name,
          version: meta.version,
          status: LabEnvironmentStatus.running,
          port: port,
          address: 'http://127.0.0.1:$port',
        );
      }
      final binary = File(labBinaryPath(root, id));
      if (!await binary.exists()) {
        return LabEnvironmentInfo(
          id: id,
          name: name,
          version: meta.version,
          status: LabEnvironmentStatus.notInstalled,
        );
      }
      final head = await _readHead(binary);
      if (elfMachine(head) != labElfAarch64) {
        return LabEnvironmentInfo(
          id: id,
          name: name,
          version: meta.version,
          status: LabEnvironmentStatus.notInstalled,
          detail: '可执行文件不是 aarch64，无法在本机运行',
        );
      }
      return LabEnvironmentInfo(
        id: id,
        name: name,
        version: meta.version,
        status: LabEnvironmentStatus.installed,
      );
    } catch (error) {
      return LabEnvironmentInfo(
        id: id,
        name: name,
        version: '',
        status: LabEnvironmentStatus.notInstalled,
        detail: '$error',
      );
    }
  }

  Future<LabEnvironmentInfo> _mihomoInfo() async {
    try {
      final state = await _proxyService.status();
      if (!state.supported) {
        return const LabEnvironmentInfo(
          id: LabEnvironmentId.mihomo,
          name: 'mihomo',
          version: '',
          status: LabEnvironmentStatus.notInstalled,
          detail: '当前平台不支持代理内核',
        );
      }
      if (!state.installed) {
        return const LabEnvironmentInfo(
          id: LabEnvironmentId.mihomo,
          name: 'mihomo',
          version: '',
          status: LabEnvironmentStatus.notInstalled,
          detail: '内置核缺失，请在管理里更新内核',
        );
      }
      if (state.running) {
        return LabEnvironmentInfo(
          id: LabEnvironmentId.mihomo,
          name: 'mihomo',
          version: state.displayVersion,
          status: LabEnvironmentStatus.running,
          port: state.mixedPort,
          address: state.mixedPort == 0
              ? ''
              : 'http://127.0.0.1:${state.mixedPort}',
        );
      }
      return LabEnvironmentInfo(
        id: LabEnvironmentId.mihomo,
        name: 'mihomo',
        version: state.displayVersion,
        status: LabEnvironmentStatus.installed,
      );
    } catch (error) {
      return LabEnvironmentInfo(
        id: LabEnvironmentId.mihomo,
        name: 'mihomo',
        version: '',
        status: LabEnvironmentStatus.notInstalled,
        detail: '$error',
      );
    }
  }

  Future<void> installPhp({
    void Function(int received, int total)? onProgress,
  }) => _installBinary(LabEnvironmentId.php, 'php', onProgress);

  Future<void> installNode({
    void Function(int received, int total)? onProgress,
  }) => _installBinary(LabEnvironmentId.node, 'nodejs', onProgress);

  Future<void> installPython({
    void Function(int received, int total)? onProgress,
  }) => _installBinary(
    LabEnvironmentId.python,
    'python-pip',
    onProgress,
    versionPackage: 'python',
  );

  Future<void> _installBinary(
    LabEnvironmentId id,
    String packageName,
    void Function(int received, int total)? onProgress, {
    String? versionPackage,
  }) async {
    final root = await _rootDirectory();
    final dir = Directory(labEnvDir(root.path, id));
    await dir.create(recursive: true);
    final indexText = await _packagesDownloader(Uri.parse(termuxPackagesUrl));
    final packages = parseTermuxPackages(indexText);
    final closure = resolveTermuxClosure(packages, packageName);
    final total = closure.fold<int>(0, (sum, item) => sum + item.size);
    var received = 0;
    final debsDir = Directory(path.join(dir.path, 'debs'));
    await debsDir.create(recursive: true);
    for (final package in closure) {
      final debFile = File(path.join(debsDir.path, '${package.name}.deb'));
      final exists =
          await debFile.exists() && await debFile.length() == package.size;
      if (!exists) {
        await _downloadFile(
          Uri.parse('$termuxRepoBase${package.filename}'),
          debFile,
          (chunk) => onProgress?.call(received + chunk, total),
        );
      }
      received += package.size;
      onProgress?.call(received, total);
      final bytes = await debFile.readAsBytes();
      final xz = parseDebDataMember(bytes);
      final xzFile = File(path.join(debsDir.path, '${package.name}.tar.xz'));
      await xzFile.writeAsBytes(xz, flush: true);
      await _extractTarXz(xzFile, dir);
      await xzFile.delete();
      await debFile.delete();
    }
    final binary = File(labBinaryPath(root.path, id));
    if (!await binary.exists()) {
      throw LabFailure('安装后找不到可执行文件');
    }
    final head = await _readHead(binary);
    if (elfMachine(head) != labElfAarch64) {
      throw LabFailure('可执行文件不是 aarch64，无法在本机运行');
    }
    final chmod = await _processRunner.run('chmod', ['+x', binary.path]);
    if (chmod.exitCode != 0) {
      throw LabFailure('chmod 失败：${chmod.stderr}');
    }
    final version = packages[versionPackage ?? packageName]?.version ?? '';
    await _writeMeta(
      root.path,
      id,
      LabMeta(version: version, port: _defaultPort(id)),
    );
  }

  Future<void> startPhp() async {
    final root = await _rootDirectory();
    final binary = labBinaryPath(root.path, LabEnvironmentId.php);
    if (!await File(binary).exists()) {
      throw LabFailure('PHP 未安装，请先安装');
    }
    if (_phpProcess != null && !_phpExited) return;
    final www = Directory(labWwwDir(root.path, LabEnvironmentId.php));
    await www.create(recursive: true);
    final index = File(path.join(www.path, 'index.php'));
    if (!await index.exists()) {
      await index.writeAsString(
        '<?php echo "huoyi lab php service";\n',
        flush: true,
      );
    }
    final meta = await _readMeta(root.path, LabEnvironmentId.php);
    final port = meta.port == 0 ? labPhpPort : meta.port;
    final process = await _processRunner.start(
      binary,
      ['-S', '127.0.0.1:$port', '-t', www.path],
      workingDirectory: www.path,
      environment: {
        'LD_LIBRARY_PATH': labLibDir(root.path, LabEnvironmentId.php),
      },
    );
    _phpProcess = process;
    _phpExited = false;
    process.stdout.listen((_) {});
    process.stderr.listen((_) {});
    unawaited(
      process.exitCode.then((_) {
        _phpExited = true;
      }),
    );
    await _writeMeta(
      root.path,
      LabEnvironmentId.php,
      LabMeta(version: meta.version, port: port, pid: process.pid),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_phpExited) {
      throw LabFailure('PHP 服务启动后立即退出，端口可能被占用');
    }
  }

  Future<void> startNode() async {
    final root = await _rootDirectory();
    final binary = labBinaryPath(root.path, LabEnvironmentId.node);
    if (!await File(binary).exists()) {
      throw LabFailure('Node 未安装，请先安装');
    }
    if (_nodeProcess != null && !_nodeExited) return;
    final www = Directory(labWwwDir(root.path, LabEnvironmentId.node));
    await www.create(recursive: true);
    final index = File(path.join(www.path, 'index.html'));
    if (!await index.exists()) {
      await index.writeAsString(
        'huoyi lab node service',
        flush: true,
      );
    }
    final server = File(labNodeServerPath(root.path));
    if (!await server.exists()) {
      await server.writeAsString(labNodeServerScript, flush: true);
    }
    final meta = await _readMeta(root.path, LabEnvironmentId.node);
    final port = meta.port == 0 ? labNodePort : meta.port;
    final process = await _processRunner.start(
      binary,
      [server.path, www.path],
      workingDirectory: www.path,
      environment: {
        'PORT': '$port',
        'LD_LIBRARY_PATH': labLibDir(root.path, LabEnvironmentId.node),
      },
    );
    _nodeProcess = process;
    _nodeExited = false;
    process.stdout.listen((_) {});
    process.stderr.listen((_) {});
    unawaited(
      process.exitCode.then((_) {
        _nodeExited = true;
      }),
    );
    await _writeMeta(
      root.path,
      LabEnvironmentId.node,
      LabMeta(version: meta.version, port: port, pid: process.pid),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_nodeExited) {
      throw LabFailure('Node 服务启动后立即退出，端口可能被占用');
    }
  }

  Future<void> stopPhp() async {
    await _stopTracked(_phpProcess, LabEnvironmentId.php);
    _phpProcess = null;
    _phpExited = true;
  }

  Future<void> stopNode() async {
    await _stopTracked(_nodeProcess, LabEnvironmentId.node);
    _nodeProcess = null;
    _nodeExited = true;
  }

  Future<void> startMihomo() async {
    await _proxyService.start();
  }

  Future<void> stopMihomo() async {
    await _proxyService.stop();
  }

  Future<void> stopAll() async {
    try {
      await stopPhp();
    } catch (_) {}
    try {
      await stopNode();
    } catch (_) {}
    try {
      await stopMihomo();
    } catch (_) {}
  }

  Future<void> _stopTracked(Process? process, LabEnvironmentId id) async {
    if (process != null) {
      try {
        process.kill();
      } catch (_) {}
    }
    final root = await _rootDirectory();
    final meta = await _readMeta(root.path, id);
    await _writeMeta(
      root.path,
      id,
      LabMeta(version: meta.version, port: meta.port),
    );
  }

  Future<void> _reapStale(String root, LabEnvironmentId id, LabMeta meta) async {
    try {
      final cmdline = File('/proc/${meta.pid}/cmdline');
      if (!await cmdline.exists()) {
        await _writeMeta(
          root,
          id,
          LabMeta(version: meta.version, port: meta.port),
        );
        return;
      }
      final raw = await cmdline.readAsString();
      final binaryName = id == LabEnvironmentId.php ? 'php' : 'node';
      if (raw.contains(binaryName)) {
        await _processRunner.run('kill', ['${meta.pid}']);
      }
      await _writeMeta(
        root,
        id,
        LabMeta(version: meta.version, port: meta.port),
      );
    } catch (_) {}
  }

  Future<LabMeta> _readMeta(String root, LabEnvironmentId id) async {
    try {
      final file = File(labMetaPath(root, id));
      if (!await file.exists()) return const LabMeta();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const LabMeta();
      return LabMeta.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return const LabMeta();
    }
  }

  Future<void> _writeMeta(String root, LabEnvironmentId id, LabMeta meta) async {
    final file = File(labMetaPath(root, id));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(meta.toJson()), flush: true);
  }

  Future<Uint8List> _readHead(File file) async {
    final bytes = await file
        .openRead(0, 64)
        .fold<BytesBuilder>(BytesBuilder(), (builder, chunk) {
          builder.add(chunk);
          return builder;
        })
        .then((builder) => builder.takeBytes());
    return bytes;
  }

  Future<void> _downloadFile(
    Uri uri,
    File target,
    void Function(int chunk) onChunk,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'huoyi-lab');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw LabFailure('下载失败（HTTP ${response.statusCode}）：$uri');
      }
      final sink = target.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        onChunk(chunk.length);
      }
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _extractTarXz(File xzFile, Directory dir) async {
    final first = await _processRunner.run('tar', [
      '-xJf',
      xzFile.path,
      '-C',
      dir.path,
    ]);
    if (first.exitCode == 0) return;
    final second = await _processRunner.run('sh', [
      '-c',
      "xzcat '${xzFile.path}' | tar -x -C '${dir.path}'",
    ]);
    if (second.exitCode == 0) return;
    throw LabFailure(
      '解压失败：本设备缺少 xz 解压工具（tar：${first.stderr}；xzcat：${second.stderr}）',
    );
  }

  int _defaultPort(LabEnvironmentId id) {
    switch (id) {
      case LabEnvironmentId.php:
        return labPhpPort;
      case LabEnvironmentId.node:
        return labNodePort;
      case LabEnvironmentId.python:
      case LabEnvironmentId.mihomo:
        return 0;
    }
  }
}
