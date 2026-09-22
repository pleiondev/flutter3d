/// The half that runs Godot.
///
/// **A throwaway project per run, and that is the load-bearing part.** An
/// importer that has already cached a file says nothing about it the second
/// time, and what it says the *first* time is where the real faults are: the
/// first run of this check found a 33-byte "PNG" with a zeroed IHDR checksum
/// inside a committed tutorial GLB, and it found it because Godot's importer
/// complained out loud about a file it had never seen.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'reading.dart';

/// Thrown when Godot would not run or would not import — as opposed to
/// running and reading something different from us, which is a finding rather
/// than a failure to have one.
final class GodotRefused implements Exception {
  GodotRefused(this.said);

  final String said;

  @override
  String toString() => said;
}

/// What Godot reads out of each of [fixtures], keyed by [flatName].
Future<Map<String, FileReading>> askGodot(
  String godot,
  List<String> fixtures,
) async {
  final template = await _templateDirectory();
  final project = Directory.systemTemp.createTempSync('godot_check_');
  try {
    File('$template/project.godot').copySync('${project.path}/project.godot');
    File('$template/count.gd').copySync('${project.path}/count.gd');
    for (final fixture in fixtures) {
      File(fixture).copySync('${project.path}/${flatName(fixture)}');
    }

    final imported = await Process.run(godot, <String>[
      '--headless',
      '--path',
      project.path,
      '--import',
    ]);
    final said = _plain('${imported.stdout}\n${imported.stderr}');
    if (imported.exitCode != 0 || _complaints(said).isNotEmpty) {
      // The whole of what the importer said, not only the lines that matched.
      // Godot files the useful half as a warning and the consequence as an
      // error — "IHDR: CRC error" then "Condition !success is true" — and a
      // report carrying only the second is a report nobody can act on.
      throw GodotRefused(
        'Godot would not import these files cleanly:\n'
        '${const LineSplitter().convert(said).where((l) => l.trim().isNotEmpty).map((l) => '  $l').join('\n')}',
      );
    }

    final counted = await Process.run(godot, <String>[
      '--headless',
      '--path',
      project.path,
      '--script',
      'count.gd',
    ]);
    // Only the prefixed line. Godot writes a banner, and on a headless exit a
    // page of "leaked at exit" complaints from the dummy renderer, to the
    // same streams — none of which is an answer to anything asked here.
    final line = const LineSplitter()
        .convert('${counted.stdout}')
        .where((line) => line.startsWith('@@@'))
        .firstOrNull;
    if (line == null) {
      throw GodotRefused(
        'Godot ran but printed no reading.\n'
        '${counted.stdout}\n${counted.stderr}',
      );
    }
    return _parse(line.substring(3));
  } finally {
    project.deleteSync(recursive: true);
  }
}

/// Godot's own version line, for the report — a number two people comparing
/// results need and neither would think to ask for.
String godotVersion(String godot) =>
    (Process.runSync(godot, <String>['--headless', '--version']).stdout
            as String)
        .trim();

/// A name a GLB can have inside a flat Godot project. Two fixtures called
/// `case1.glb` in different directories would otherwise land on each other.
String flatName(String path) => path.replaceAll('/', '_').replaceAll('\\', '_');

Map<String, FileReading> _parse(String json) {
  final decoded = jsonDecode(json) as Map<String, Object?>;
  return decoded.map((key, value) {
    final entry = value! as Map<String, Object?>;
    final error = entry['error'] as String?;
    return MapEntry(
      key,
      FileReading(
        error: error,
        surfaces: <SurfaceReading>[
          for (final surface
              in (entry['surfaces'] as List<Object?>?) ?? const <Object?>[])
            _surface(surface! as Map<String, Object?>),
        ],
      ),
    );
  });
}

SurfaceReading _surface(Map<String, Object?> entry) => SurfaceReading(
  material: entry['material']! as String,
  triangles: entry['triangles']! as int,
  min: _triple(entry['min']!),
  max: _triple(entry['max']!),
);

List<double> _triple(Object value) => <double>[
  for (final number in value as List<Object?>) (number! as num).toDouble(),
];

/// The lines of Godot's own output that are complaints. The marker is matched
/// inside the line rather than at its start: Godot indents the second line of
/// a complaint with the source location it came from.
List<String> _complaints(String output) => const LineSplitter()
    .convert(output)
    .where((line) => line.contains('ERROR:') || line.contains("Couldn't"))
    .toList();

/// Godot colours its complaints with ANSI escapes even when nothing is
/// attached to the terminal, and a CI log full of `[0;91m` is a log nobody
/// reads.
String _plain(String output) =>
    output.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');

/// The Godot project template that ships beside this package's `lib`.
///
/// Resolved through the package URI rather than through `Platform.script`:
/// `dart run` executes a snapshot under `.dart_tool/pub/bin`, so the script's
/// own path says nothing about where the package is.
Future<String> _templateDirectory() async {
  final resolved = await Isolate.resolvePackageUri(
    Uri.parse('package:godot_check/godot_check.dart'),
  );
  if (resolved == null) {
    throw GodotRefused('godot_check is not resolvable as a package');
  }
  return '${File(resolved.toFilePath()).parent.parent.path}/godot';
}
