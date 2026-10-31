import 'dart:io';

import 'package:duanju_app/lab_screen.dart';
import 'package:duanju_app/python_binary.dart';
import 'package:duanju_app/python_terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String?> findHostPython() async {
  try {
    final result = await Process.run('python3', ['--version']);
    if (result.exitCode == 0) return 'python3';
  } catch (_) {}
  return null;
}

Future<void> waitForNeedMore(List<bool> events, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (events.length < count) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timeout waiting for repl marker');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('python terminal history navigates within bounds', () {
    final history = PythonTerminalHistory();
    expect(history.previous(), isNull);
    history.push('x = 1');
    history.push('print(x)');
    expect(history.previous(), 'print(x)');
    expect(history.previous(), 'x = 1');
    expect(history.previous(), isNull);
    expect(history.next(), 'print(x)');
    expect(history.next(), '');
    expect(history.next(), isNull);
    history.push('print(x)');
    expect(history.entries, ['x = 1', 'print(x)']);
  });

  test('listPythonScripts only lists py files sorted', () async {
    final dir = await Directory.systemTemp.createTemp('py_term_list');
    try {
      await File('${dir.path}/b.py').writeAsString('print(2)');
      await File('${dir.path}/a.py').writeAsString('print(1)');
      await File('${dir.path}/notes.txt').writeAsString('x');
      final scripts = await listPythonScripts(dir);
      expect(
        scripts.map((file) => file.path.split('/').last).toList(),
        ['a.py', 'b.py'],
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('importPythonScript copies and uniquifies names', () async {
    final base = await Directory.systemTemp.createTemp('py_term_import');
    try {
      final sourceDir = Directory('${base.path}/src');
      final targetDir = Directory('${base.path}/dst');
      await sourceDir.create();
      final source = File('${sourceDir.path}/source.py');
      await source.writeAsString('print(1)');
      final first = await importPythonScript(targetDir, source.path);
      expect(first.path, '${targetDir.path}/source.py');
      final second = await importPythonScript(targetDir, source.path);
      expect(second.path, '${targetDir.path}/source_2.py');
      expect(await second.readAsString(), 'print(1)');
    } finally {
      await base.delete(recursive: true);
    }
  });

  test('repl driver script carries the marker protocol', () {
    expect(pythonReplDriverScript, contains('InteractiveConsole'));
    expect(pythonReplDriverScript, contains("MARKER = '\\x00LAB_REPL'"));
    expect(pythonReplDriverScript, contains('need_more = console.push(line)'));
  });

  test('repl session runs code through the driver process', () async {
    final python = await findHostPython();
    if (python == null) {
      markTestSkipped('host python3 missing');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('py_repl');
    try {
      final driver = File('${dir.path}/driver.py');
      await driver.writeAsString(pythonReplDriverScript);
      final lines = <PythonTerminalLine>[];
      final needMoreEvents = <bool>[];
      final session = await PythonReplSession.start(
        binary: python,
        driverPath: driver.path,
        onLine: lines.add,
        onNeedMore: needMoreEvents.add,
      );
      try {
        await session.send('x = 1');
        await waitForNeedMore(needMoreEvents, 1);
        expect(needMoreEvents[0], isFalse);
        expect(lines, isEmpty);
        await session.send('print(x)');
        await waitForNeedMore(needMoreEvents, 2);
        expect(needMoreEvents[1], isFalse);
        expect(lines.map((line) => line.text).toList(), ['1']);
        await session.send('for i in range(2):');
        await waitForNeedMore(needMoreEvents, 3);
        expect(needMoreEvents[2], isTrue);
        await session.send('    print(i)');
        await waitForNeedMore(needMoreEvents, 4);
        expect(needMoreEvents[3], isTrue);
        await session.send('');
        await waitForNeedMore(needMoreEvents, 5);
        expect(needMoreEvents[4], isFalse);
        expect(
          lines.map((line) => line.text).toList(),
          ['1', '0', '1'],
        );
        await session.send('print(1/0)');
        await waitForNeedMore(needMoreEvents, 6);
        expect(needMoreEvents[5], isFalse);
        final stderrLines =
            lines.where((line) => line.isStderr).map((line) => line.text);
        expect(stderrLines.any((line) => line.contains('ZeroDivisionError')),
            isTrue);
      } finally {
        await session.dispose();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('settings has lab, no proxy, no separate python or shell entry', () {
    final settings = File('lib/settings_screen.dart').readAsStringSync();
    expect("ValueKey('lab-entry')".allMatches(settings).length, 2);
    expect(settings.contains("ValueKey('proxy-kernel-entry')"), isFalse);
    expect(settings.contains("ValueKey('python-terminal-entry')"), isFalse);
    expect(settings.contains("ValueKey('terminal-entry')"), isFalse);
    expect(settings.contains('TerminalScreen'), isFalse);
    expect(settings.contains('LabScreen'), isTrue);
    expect(settings.contains("import 'lab_screen.dart';"), isTrue);
    expect(settings.contains("import 'python_terminal_screen.dart';"), isFalse);
    expect(settings.contains("import 'terminal_screen.dart';"), isFalse);
    expect(settings.contains("import 'proxy_kernel_screen.dart';"), isFalse);
  });

  test('lab screen holds python terminal and mihomo, no shell terminal', () {
    final lab = File('lib/lab_screen.dart').readAsStringSync();
    expect(lab.contains('PythonTerminalScreen'), isTrue);
    expect(lab.contains('ProxyKernelScreen'), isTrue);
    expect(lab.contains('installPython'), isTrue);
    expect(lab.contains('const TerminalScreen()'), isFalse);
    expect(lab.contains("import 'terminal_screen.dart';"), isFalse);
    expect(lab.contains('labSupported'), isTrue);
  });

  test('lab gate is closed off android', () {
    expect(labSupported, isFalse);
  });
}
