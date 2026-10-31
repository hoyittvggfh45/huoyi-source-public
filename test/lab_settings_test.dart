import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings has lab entries and no proxy or terminal entries', () {
    final settings = File('lib/settings_screen.dart').readAsStringSync();
    expect(settings.contains("ValueKey('proxy-kernel-entry')"), isFalse);
    expect(settings.contains("ValueKey('terminal-entry')"), isFalse);
    expect(settings.contains("ValueKey('python-terminal-entry')"), isFalse);
    expect(settings.contains('TerminalScreen'), isFalse);
    expect(settings.contains('ProxyKernelScreen'), isFalse);
    expect("ValueKey('lab-entry')".allMatches(settings).length, 2);
    expect(settings.contains("import 'lab_screen.dart';"), isTrue);
  });

  test('lab screen wires python terminal and proxy screen', () {
    final lab = File('lib/lab_screen.dart').readAsStringSync();
    expect(lab.contains('PythonTerminalScreen'), isTrue);
    expect(lab.contains('ProxyKernelScreen'), isTrue);
    expect(lab.contains('const TerminalScreen()'), isFalse);
    expect(lab.contains("import 'terminal_screen.dart';"), isFalse);
  });
}
