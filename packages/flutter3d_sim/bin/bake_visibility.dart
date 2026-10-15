/// Bakes a visibility table beside each level named on the command line.
///
///     dart run flutter3d_sim:bake_visibility assets/levels/crypt.json ...
///     dart run flutter3d_sim:bake_visibility --cell 2.5 assets/levels/*.json
///
/// Writes `<level>.visibility.json` next to each document, the sidecar
/// `LevelLoader` reads and `LevelVisibility` explains. Deterministic, so CI
/// can bake and compare: a table that differs from the committed one means
/// a brush moved and nobody re-baked, which is what the loader would then
/// refuse at run time with a word.
///
/// **The same command as `flutter3d visibility`**, kept here for a project
/// that depends on the simulation and not on `flutter3d_build`: `--cell`,
/// the usage on stdout for `--help`, 2 for a command line it cannot read and
/// 1 for a level it cannot read.
///
/// Imports the level layer directly rather than the package barrel, because
/// the barrel reaches Flutter through the input widgets and this has to run
/// on the plain Dart VM.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_sim/src/level/level.dart';
import 'package:flutter3d_sim/src/level/level_visibility.dart';

const String _usage =
    'usage: dart run flutter3d_sim:bake_visibility [--cell <metres>] '
    '<level.json> ...\n'
    '\n'
    'The same as `flutter3d visibility`. --cell is the side of a cell in '
    'metres, 3 by default.';

void main(List<String> arguments) {
  if (arguments.contains('-h') || arguments.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }
  var cellSize = 3.0;
  final paths = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--cell') {
      final cell = ++i < arguments.length
          ? double.tryParse(arguments[i])
          : null;
      if (cell == null || cell <= 0) {
        stderr.writeln('--cell takes a size in metres above 0.\n\n$_usage');
        exit(2);
      }
      cellSize = cell;
    } else if (argument.startsWith('-')) {
      stderr.writeln('Unknown option $argument.\n\n$_usage');
      exit(2);
    } else {
      paths.add(argument);
    }
  }
  if (paths.isEmpty) {
    stderr.writeln(_usage);
    exit(2);
  }

  var failed = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('$path: not there');
      failed = true;
      continue;
    }
    final Level level;
    try {
      level = Level.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );
    } on FormatException catch (error) {
      stderr.writeln('$path: not a level: ${error.message}');
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
    stdout.writeln(
      '${sidecar.path}: ${table.cellCount} cells of ${cellSize}m, '
      '${stopwatch.elapsedMilliseconds} ms',
    );
  }
  exit(failed ? 1 : 0);
}
