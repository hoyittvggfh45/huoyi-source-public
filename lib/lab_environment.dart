import 'dart:typed_data';

import 'package:path/path.dart' as path;

const String termuxPackagesUrl =
    'https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-aarch64/Packages';
const String termuxRepoBase = 'https://packages.termux.dev/apt/termux-main/';
const int labPhpPort = 18080;
const int labNodePort = 18081;
const int labElfAarch64 = 183;

const String labNodeServerScript = '''
const http = require('http');
const fs = require('fs');
const path = require('path');
const root = process.argv[2] || process.cwd();
const port = parseInt(process.env.PORT || '18081', 10);
const types = {'.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.txt': 'text/plain'};
http.createServer((req, res) => {
  let urlPath = decodeURIComponent(req.url.split('?')[0]);
  if (urlPath === '/') urlPath = '/index.html';
  const file = path.join(root, urlPath);
  if (!file.startsWith(root)) {
    res.writeHead(403);
    res.end();
    return;
  }
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('not found');
      return;
    }
    res.writeHead(200, {'content-type': types[path.extname(file)] || 'application/octet-stream'});
    res.end(data);
  });
}).listen(port, '127.0.0.1');
''';

class LabFailure implements Exception {
  LabFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

enum LabEnvironmentId { python, php, node, mihomo }

enum LabEnvironmentStatus { notInstalled, installed, running }

class LabEnvironmentInfo {
  const LabEnvironmentInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.status,
    this.port = 0,
    this.address = '',
    this.detail = '',
  });

  final LabEnvironmentId id;
  final String name;
  final String version;
  final LabEnvironmentStatus status;
  final int port;
  final String address;
  final String detail;
}

class TermuxPackage {
  const TermuxPackage({
    required this.name,
    required this.version,
    required this.filename,
    required this.depends,
    required this.size,
  });

  final String name;
  final String version;
  final String filename;
  final List<String> depends;
  final int size;
}

Map<String, TermuxPackage> parseTermuxPackages(String text) {
  final packages = <String, TermuxPackage>{};
  var fields = <String, String>{};
  void flush() {
    final name = fields['Package'];
    if (name == null || name.isEmpty) return;
    packages[name] = TermuxPackage(
      name: name,
      version: fields['Version'] ?? '',
      filename: fields['Filename'] ?? '',
      depends: parseTermuxDepends(fields['Depends'] ?? ''),
      size: int.tryParse(fields['Size'] ?? '') ?? 0,
    );
  }

  for (final line in text.split('\n')) {
    if (line.isEmpty) {
      flush();
      fields = <String, String>{};
      continue;
    }
    if (line.startsWith(' ')) continue;
    final index = line.indexOf(': ');
    if (index <= 0) continue;
    fields[line.substring(0, index)] = line.substring(index + 2);
  }
  flush();
  return packages;
}

List<String> parseTermuxDepends(String raw) {
  final depends = <String>[];
  for (final part in raw.split(',')) {
    var item = part.trim();
    if (item.isEmpty) continue;
    item = item.split('|').first.trim();
    item = item.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    item = item.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '').trim();
    if (item.isNotEmpty) depends.add(item);
  }
  return depends;
}

List<TermuxPackage> resolveTermuxClosure(
  Map<String, TermuxPackage> packages,
  String root,
) {
  final resolved = <TermuxPackage>[];
  final seen = <String>{};
  final missing = <String>[];
  void visit(String name) {
    if (seen.contains(name)) return;
    seen.add(name);
    final package = packages[name];
    if (package == null) {
      missing.add(name);
      return;
    }
    for (final dep in package.depends) {
      visit(dep);
    }
    resolved.add(package);
  }

  visit(root);
  if (missing.isNotEmpty) {
    throw LabFailure('Termux 仓库缺少依赖：${missing.join('、')}');
  }
  return resolved;
}

Uint8List parseDebDataMember(Uint8List bytes) {
  const magic = '!<arch>\n';
  if (bytes.length < magic.length) {
    throw LabFailure('deb 文件过小');
  }
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic.codeUnitAt(i)) {
      throw LabFailure('不是 ar 归档');
    }
  }
  var offset = magic.length;
  while (offset + 60 <= bytes.length) {
    final header = bytes.sublist(offset, offset + 60);
    if (header[58] != 0x60 || header[59] != 0x0A) {
      throw LabFailure('ar 成员头无效');
    }
    final name = String.fromCharCodes(header.sublist(0, 16)).trim();
    final size = int.tryParse(
      String.fromCharCodes(header.sublist(48, 58)).trim(),
    );
    if (size == null) {
      throw LabFailure('ar 成员大小无效');
    }
    final bodyStart = offset + 60;
    final bodyEnd = bodyStart + size;
    if (bodyEnd > bytes.length) {
      throw LabFailure('ar 成员越界');
    }
    if (name == 'data.tar.xz' || name == 'data.tar.xz/') {
      return bytes.sublist(bodyStart, bodyEnd);
    }
    offset = bodyEnd + (size.isOdd ? 1 : 0);
  }
  throw LabFailure('deb 里没有 data.tar.xz');
}

int? elfMachine(Uint8List bytes) {
  if (bytes.length < 20) return null;
  if (bytes[0] != 0x7F ||
      bytes[1] != 0x45 ||
      bytes[2] != 0x4C ||
      bytes[3] != 0x46) {
    return null;
  }
  final littleEndian = bytes[5] != 2;
  if (littleEndian) {
    return bytes[18] | (bytes[19] << 8);
  }
  return (bytes[18] << 8) | bytes[19];
}

String elfMachineName(int? machine) {
  switch (machine) {
    case 183:
      return 'aarch64';
    case 62:
      return 'x86_64';
    case 40:
      return 'arm';
    case 3:
      return 'x86';
    default:
      return 'unknown';
  }
}

String labEnvDir(String root, LabEnvironmentId id) =>
    path.join(root, id.name);

String labBinaryPath(String root, LabEnvironmentId id) {
  switch (id) {
    case LabEnvironmentId.php:
      return path.join(
        labEnvDir(root, id),
        'data',
        'data',
        'com.termux',
        'files',
        'usr',
        'bin',
        'php',
      );
    case LabEnvironmentId.node:
      return path.join(
        labEnvDir(root, id),
        'data',
        'data',
        'com.termux',
        'files',
        'usr',
        'bin',
        'node',
      );
    case LabEnvironmentId.python:
      return path.join(
        labEnvDir(root, id),
        'data',
        'data',
        'com.termux',
        'files',
        'usr',
        'bin',
        'python3',
      );
    case LabEnvironmentId.mihomo:
      return '';
  }
}

String labLibDir(String root, LabEnvironmentId id) => path.join(
  labEnvDir(root, id),
  'data',
  'data',
  'com.termux',
  'files',
  'usr',
  'lib',
);

String labWwwDir(String root, LabEnvironmentId id) =>
    path.join(labEnvDir(root, id), 'www');

String labMetaPath(String root, LabEnvironmentId id) =>
    path.join(labEnvDir(root, id), 'meta.json');

String labNodeServerPath(String root) =>
    path.join(labEnvDir(root, LabEnvironmentId.node), 'server.js');

class LabMeta {
  const LabMeta({this.version = '', this.port = 0, this.pid = 0});

  final String version;
  final int port;
  final int pid;

  Map<String, dynamic> toJson() => {
    'version': version,
    'port': port,
    'pid': pid,
  };

  factory LabMeta.fromJson(Map<String, dynamic> json) => LabMeta(
    version: '${json['version'] ?? ''}',
    port: (json['port'] as num?)?.toInt() ?? 0,
    pid: (json['pid'] as num?)?.toInt() ?? 0,
  );
}
