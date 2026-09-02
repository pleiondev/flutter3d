/// Bakes a lightmap beside each level named on the command line.
///
///     dart run flutter3d_sim:bake_lightmap assets/levels/crypt.json ...
///     dart run flutter3d_sim:bake_lightmap --density 4 --bounces 2 \
///         --samples 64 assets/levels/*.json
///     dart run flutter3d_sim:bake_lightmap --direct assets/levels/box.json
///
/// Writes `<level>.lightmap.bin` next to each document, the sidecar
/// `LevelLoader` reads and `Lightmap` explains. Deterministic, so CI can
/// bake and compare: a map that differs from the committed one means a
/// wall or a light moved and nobody re-baked, which is what the loader
/// would then refuse at run time with a word.
///
/// `--direct` bakes the direct light and its shadows in as well, for looking
/// at the unwrap with the dynamic lights turned off; a shipped map does not
/// want it, since the renderer draws that light itself.
///
/// Imports the level layer directly rather than the package barrel, because
/// the barrel reaches Flutter through the input widgets and this has to run
/// on the plain Dart VM.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_sim/src/level/level.dart';
import 'package:flutter3d_sim/src/level/lightmap_baker.dart';

void main(List<String> arguments) {
  var density = 4.0;
  var bounces = 2;
  var samples = 64;
  var direct = false;
  final paths = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--density' && i + 1 < arguments.length) {
      density = double.parse(arguments[++i]);
    } else if (argument == '--bounces' && i + 1 < arguments.length) {
      bounces = int.parse(arguments[++i]);
    } else if (argument == '--samples' && i + 1 < arguments.length) {
      samples = int.parse(arguments[++i]);
    } else if (argument == '--direct') {
      direct = true;
    } else if (argument.startsWith('-')) {
      stderr.writeln('unknown option: $argument');
      exit(2);
    } else {
      paths.add(argument);
    }
  }
  if (paths.isEmpty) {
    stderr.writeln(
      'usage: bake_lightmap [--density TEXELS_PER_METRE] [--bounces N] '
      '[--samples N] [--direct] level.json ...',
    );
    exit(2);
  }

  final baker = LightmapBaker(
    texelsPerMetre: density,
    bounces: bounces,
    samples: samples,
    includeDirect: direct,
  );
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
    final map = baker.bake(
      level,
      log: (message) =>
          stdout.writeln('  $message (${stopwatch.elapsedMilliseconds} ms)'),
    );
    final out = path.endsWith('.json')
        ? '${path.substring(0, path.length - 5)}.lightmap.bin'
        : '$path.lightmap.bin';
    final bytes = map.toBytes();
    File(out).writeAsBytesSync(bytes);
    stdout.writeln(
      '$out: ${map.width}x${map.height}, ${(bytes.length / 1024).round()} KB',
    );
  }
  exit(failed ? 1 : 0);
}
