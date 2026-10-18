/// Running the repository's own scripts and keeping what they said.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What a finished command left behind.
final class Ran {
  /// A command that ended with [exitCode] after [duration], having printed
  /// [lines].
  const Ran({
    required this.exitCode,
    required this.lines,
    required this.duration,
    this.timedOut = false,
    this.failedToStart = false,
  });

  /// The process's exit code: 127 when it [failedToStart], and whatever the
  /// killed process returned when it [timedOut].
  final int exitCode;

  /// Standard output and standard error together, in the order they arrived.
  final List<String> lines;

  /// How long the command ran.
  final Duration duration;

  /// Whether the command was killed for running past its timeout.
  final bool timedOut;

  /// Whether the command could not be started at all.
  final bool failedToStart;

  /// Whether the command started, finished in time and exited with zero.
  bool get ok => exitCode == 0 && !timedOut && !failedToStart;

  /// Everything the command printed, as one string.
  String get text => lines.join('\n');

  /// The last [count] lines that say something.
  List<String> tail([int count = 40]) {
    final said = lines.where((String l) => l.trim().isNotEmpty).toList();
    return said.length <= count ? said : said.sublist(said.length - count);
  }
}

/// The most lines kept of any one run: enough to find a rule that went red,
/// bounded so that a script that loops cannot fill the machine.
const int _keptLines = 6000;

/// Runs [command] in [workingDirectory].
///
/// **A command that cannot start is a result, not an exception**, because the
/// dashboard is most needed exactly when something on the machine is missing:
/// no `flutter` on the path, no `gh` signed in. The page shows that as the
/// reason the check is red.
Future<Ran> runCommand(
  List<String> command, {
  required String workingDirectory,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final clock = Stopwatch()..start();
  final Process process;
  try {
    process = await Process.start(
      command.first,
      command.skip(1).toList(),
      workingDirectory: workingDirectory,
    );
  } on ProcessException catch (error) {
    return Ran(
      exitCode: 127,
      lines: <String>[error.message],
      duration: clock.elapsed,
      failedToStart: true,
    );
  }

  final lines = <String>[];
  void keep(String line) {
    if (lines.length < _keptLines) lines.add(line);
  }

  final done = <Future<void>>[
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(keep),
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(keep),
  ];

  var timedOut = false;
  final timer = Timer(timeout, () {
    timedOut = true;
    process.kill();
  });
  final code = await process.exitCode;
  timer.cancel();
  await Future.wait(done);

  return Ran(
    exitCode: code,
    lines: lines,
    duration: clock.elapsed,
    timedOut: timedOut,
  );
}
