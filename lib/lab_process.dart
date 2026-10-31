import 'dart:io';

abstract class LabProcessRunner {
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  Future<LabCommandResult> run(String executable, List<String> arguments);
}

class LabCommandResult {
  const LabCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class DefaultLabProcessRunner implements LabProcessRunner {
  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );

  @override
  Future<LabCommandResult> run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    return LabCommandResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }
}
