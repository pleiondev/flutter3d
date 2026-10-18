/// `flutter3d visibility`: bakes a visibility table beside each level named
/// on the command line.
///
///     flutter3d visibility assets/levels/crypt.json ...
///     flutter3d visibility --cell 2.5 assets/levels/*.json
///
/// Writes `<level>.visibility.json` next to each document, the sidecar
/// `LevelLoader` reads and `LevelVisibility` explains. Deterministic, so CI
/// can bake and compare: a table that differs from the committed one means
/// a brush moved and nobody re-baked, which the loader would then refuse
/// at run time with a word. `dart run flutter3d_sim:bake_visibility` is the
/// same command under its old name.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_sim/flutter3d_sim.dart' show Level, LevelVisibility;

import 'cli_contract.dart';

/// Runs `flutter3d visibility [arguments]` and returns its exit code
/// ([CliExit]): 0 when every level was baked, 1 when one could not be
/// read, 2 for a command line it cannot read.
int runVisibility(List<String> arguments, {IOSink? out, IOSink? err}) {
  final say = out ?? stdout;
  final complain = err ?? stderr;
  if (arguments.contains('-h') || arguments.contains('--help')) {
    say.writeln(visibilityUsage);
    return CliExit.ok;
  }
  int usage(String why) {
    complain.writeln('$why\n\n$visibilityUsage');
    return CliExit.usage;
  }

  if (cliOptions['visibility']!.unknownIn(arguments) case final String bad) {
    return usage(unknownOption(bad));
  }
  final cells = <double>[];
  final paths = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--cell' || argument.startsWith('--cell=')) {
      final text = argument == '--cell'
          ? (++i < arguments.length ? arguments[i] : '')
          : argument.substring('--cell='.length);
      final cell = double.tryParse(text);
      if (cell == null || cell <= 0) {
        return usage('--cell takes a size in metres above 0');
      }
      cells.add(cell);
    } else {
      paths.add(argument);
    }
  }
  if (paths.isEmpty) return usage('No level named.');
  final cellSize = cells.lastOrNull ?? 3.0;

  var failed = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      complain.writeln('$path: not there');
      failed = true;
      continue;
    }
    final Level level;
    try {
      level = Level.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );
    } on FormatException catch (error) {
      complain.writeln('$path: not a level: ${error.message}');
      failed = true;
      continue;
    }
    final stopwatch = Stopwatch()..start();
    final table = LevelVisibility.bake(level, cellSize: cellSize);
    stopwatch.stop();
    final sidecar = File(
      path.endsWith('.json')
          ? '${path.substring(0, path.length - 5)}.visibility.json'
          : '$path.visibility.json',
    );
    sidecar.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(table.toJson())}\n',
    );
    say.writeln(
      '${sidecar.path}: ${table.cellCount} cells of ${cellSize}m, '
      '${stopwatch.elapsedMilliseconds} ms',
    );
  }
  return failed ? CliExit.failure : CliExit.ok;
}
