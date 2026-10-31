import 'dart:io';

import 'package:duanju_app/python_binary.dart';
import 'package:flutter_test/flutter_test.dart';

import 'python_terminal_test.dart' show findHostPython;

void main() {
  test('python paths follow the termux tree layout', () {
    expect(
      pythonBinaryPath('/root'),
      '/root/python/data/data/com.termux/files/usr/bin/python3',
    );
    expect(
      pythonSitePackagesDir('/root'),
      '/root/python/site-packages',
    );
    expect(
      pythonUsrDir('/root'),
      '/root/python/data/data/com.termux/files/usr',
    );
    expect(pythonLibDir('/root'), '${pythonUsrDir('/root')}/lib');
    expect(pythonDriverPath('/root'), '/root/python/repl_driver.py');
    expect(pythonMetaPath('/root'), '/root/python/meta.json');
  });

  test('pip installs a pure package and import works via PYTHONPATH', () async {
    final python = await findHostPython();
    if (python == null) {
      markTestSkipped('host python3 missing');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('py_pip');
    try {
      final target = Directory('${dir.path}/site-packages');
      await target.create();
      final lines = <String>[];
      final code = await pipInstallPackage(
        python,
        target.path,
        'six',
        Platform.environment,
        onLine: lines.add,
      );
      expect(code, 0, reason: lines.join('\n'));
      expect(await File('${target.path}/six.py').exists(), isTrue);
      final run = await Process.run(python, [
        '-c',
        'import six; print(six.PY3)',
      ], environment: {'PYTHONPATH': target.path});
      expect(run.exitCode, 0);
      expect((run.stdout as String).trim(), 'True');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
