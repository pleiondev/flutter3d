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
/// Imports the level layer directly rather than the package barrel, because
/// the barrel reaches Flutter through the input widgets and this has to run
/// on the plain Dart VM.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_sim/src/level/level.dart';
import 'package:flutter3d_sim/src/level/level_visibility.dart';

void main(List<String> arguments) {
  var cellSize = 3.0;
  final paths = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--cell' && i + 1 < arguments.length) {
      cellSize = double.parse(arguments[++i]);
    } else if (argument.startsWith('-')) {
      stderr.writeln('unknown option: $argument');
      exit(2);
    } else {
      paths.add(argument);
    }
  }
  if (paths.isEmpty) {
    stderr.writeln('usage: bake_visibility [--cell METRES] level.json ...');
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
    final level = Level.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
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
