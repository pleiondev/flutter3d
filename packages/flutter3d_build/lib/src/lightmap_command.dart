/// `flutter3d lightmap`: bakes a lightmap beside each level named on the
/// command line.
///
///     dart run flutter3d_build:lightmap assets/levels/crypt.json ...
///     dart run flutter3d_build:lightmap --density 4 --bounces 2 \
///         --samples 64 assets/levels/*.json
///     dart run flutter3d_build:lightmap --direct assets/levels/box.json
///
/// Writes `<level>.lightmap.bin` next to each document, the sidecar the
/// level loader reads and `Lightmap` explains. Deterministic, so CI can
/// bake and compare: a map that differs from the committed one means a
/// wall or a light moved and nobody re-baked, which is what the loader
/// would then refuse at run time with a word.
///
/// `--direct` bakes the direct light and its shadows in as well, for looking
/// at the unwrap with the dynamic lights turned off; a shipped map does not
/// want it, since the renderer draws that light itself.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;

import 'cli_contract.dart';
import 'lightmap_bake.dart';

/// Runs `flutter3d lightmap [arguments]` and returns its exit code
/// ([CliExit]): 0 when every level was baked, 1 when one could not be
/// read, 2 for a command line it cannot read.
int runLightmap(List<String> arguments) {
  if (arguments.contains('-h') || arguments.contains('--help')) {
    stdout.writeln(lightmapUsage);
    return CliExit.ok;
  }
  var density = 4.0;
  var bounces = 2;
  var samples = 64;
  var direct = false;
  final paths = <String>[];
  int usage(String why) {
    stderr.writeln('$why\n\n$lightmapUsage');
    return CliExit.usage;
  }

  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    final value = i + 1 < arguments.length ? arguments[i + 1] : null;
    switch (argument) {
      case '--density' when value != null && double.tryParse(value) != null:
        density = double.parse(value);
        i++;
      case '--bounces' when value != null && int.tryParse(value) != null:
        bounces = int.parse(value);
        i++;
      case '--samples' when value != null && int.tryParse(value) != null:
        samples = int.parse(value);
        i++;
      case '--direct':
        direct = true;
      case final String option when option.startsWith('-'):
        return usage('Unknown option or missing value: $option');
      default:
        paths.add(argument);
    }
  }
  if (paths.isEmpty) return usage('No level named.');
  if (bounces < 0 || samples < 1 || density <= 0) {
    return usage('--bounces is at least 0, --samples and --density above 0.');
  }

  final baker = LightmapBaker(
    texelsPerMeter: density,
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
  return failed ? CliExit.failure : CliExit.ok;
}
