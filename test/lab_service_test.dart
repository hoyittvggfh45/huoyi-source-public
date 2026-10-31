import 'dart:convert';
import 'dart:io';

import 'package:duanju_app/lab_environment.dart';
import 'package:duanju_app/lab_service.dart';
import 'package:duanju_app/proxy_kernel_service.dart';
import 'package:duanju_app/python_binary.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lab_environment_test.dart' show buildElf;

class FakeProxyController implements ProxyKernelController {
  FakeProxyController(this.statusMap);

  final Map<String, dynamic> statusMap;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    if (method == 'status') return statusMap;
    return {};
  }
}

LabEnvironmentService buildService(Directory root) {
  return LabEnvironmentService(
    rootDirectory: () async => root,
    proxyService: ProxyKernelService(
      controller: FakeProxyController({
        'supported': true,
        'installed': true,
        'running': false,
        'builtinVersion': 'v1.19.32',
        'mixedPort': 7890,
      }),
      store: MemoryProxyKernelStore(),
      supportDirectory: () async => root,
    ),
  );
}

void main() {
  test('fresh root reports php, node and python not installed', () async {
    final root = await Directory.systemTemp.createTemp('lab_fresh');
    try {
      final service = buildService(root);
      final infos = await service.refresh();
      expect(infos[LabEnvironmentId.php]!.status,
          LabEnvironmentStatus.notInstalled);
      expect(infos[LabEnvironmentId.node]!.status,
          LabEnvironmentStatus.notInstalled);
      expect(infos[LabEnvironmentId.python]!.status,
          LabEnvironmentStatus.notInstalled);
      expect(infos[LabEnvironmentId.mihomo]!.status,
          LabEnvironmentStatus.installed);
      expect(infos[LabEnvironmentId.mihomo]!.version, 'v1.19.32');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('python binary with meta reports installed with version', () async {
    final root = await Directory.systemTemp.createTemp('lab_py');
    try {
      final service = buildService(root);
      final binary = File(pythonBinaryPath(root.path));
      await binary.parent.create(recursive: true);
      await binary.writeAsBytes(buildElf(183));
      final meta = File(pythonMetaPath(root.path));
      await meta.writeAsString('{"version":"3.14.8","port":0,"pid":0}');
      final infos = await service.refresh();
      expect(infos[LabEnvironmentId.python]!.status,
          LabEnvironmentStatus.installed);
      expect(infos[LabEnvironmentId.python]!.version, '3.14.8');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('aarch64 elf binary reports installed', () async {
    final root = await Directory.systemTemp.createTemp('lab_elf');
    try {
      final service = buildService(root);
      final binary = File(labBinaryPath(root.path, LabEnvironmentId.node));
      await binary.parent.create(recursive: true);
      await binary.writeAsBytes(buildElf(183));
      final infos = await service.refresh();
      expect(infos[LabEnvironmentId.node]!.status,
          LabEnvironmentStatus.installed);
      final x86 = File(labBinaryPath(root.path, LabEnvironmentId.php));
      await x86.parent.create(recursive: true);
      await x86.writeAsBytes(buildElf(62));
      final infos2 = await service.refresh();
      expect(infos2[LabEnvironmentId.php]!.status,
          LabEnvironmentStatus.notInstalled);
      expect(infos2[LabEnvironmentId.php]!.detail, contains('aarch64'));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('php start reports running and stop kills the process', () async {
    final root = await Directory.systemTemp.createTemp('lab_run');
    try {
      final service = buildService(root);
      final binary = File(labBinaryPath(root.path, LabEnvironmentId.php));
      await binary.parent.create(recursive: true);
      await binary.writeAsString('#!/bin/sh\nexec sleep 30\n');
      await Process.run('chmod', ['+x', binary.path]);
      await service.startPhp();
      final running = await service.refresh();
      expect(running[LabEnvironmentId.php]!.status,
          LabEnvironmentStatus.running);
      expect(running[LabEnvironmentId.php]!.address,
          'http://127.0.0.1:18080');
      final metaFile = File(labMetaPath(root.path, LabEnvironmentId.php));
      final metaBefore =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final pid = (metaBefore['pid'] as num).toInt();
      expect(pid, isNot(0));
      await service.stopPhp();
      final metaAfter =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      expect((metaAfter['pid'] as num).toInt(), 0);
      expect(await File('/proc/$pid/cmdline').exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('stopAll on a fresh service is a no-op', () async {
    final root = await Directory.systemTemp.createTemp('lab_stopall');
    try {
      final service = buildService(root);
      await service.stopAll();
    } finally {
      await root.delete(recursive: true);
    }
  });
}
