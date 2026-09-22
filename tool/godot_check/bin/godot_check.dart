/// The command `.github/workflows/ci.yml` runs. Everything it does is in
/// `lib/godot_check.dart`; this is the arguments, the clock and the exit code.
///
///     dart run godot_check:godot_check
///     dart run godot_check:godot_check --godot=/path/to/Godot a.glb b.glb
library;

import 'dart:io';

import 'package:godot_check/godot_check.dart';

Future<void> main(List<String> arguments) async {
  final godot = _resolveGodot(arguments);
  if (godot == null) return;

  final named = arguments.where((a) => !a.startsWith('--')).toList();
  final fixtures = named.isEmpty ? committedFixtures : named;
  final missing = fixtures.where((f) => !File(f).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('no such file: ${missing.join(', ')}');
    exitCode = 1;
    return;
  }

  final started = DateTime.now();
  final List<String> problems;
  try {
    problems = await checkWithGodot(godot: godot, fixtures: fixtures);
  } on GodotRefused catch (refusal) {
    stderr.writeln(refusal.said);
    exitCode = 1;
    return;
  }
  final seconds = DateTime.now().difference(started).inMilliseconds / 1000;

  if (problems.isEmpty) {
    stdout.writeln(
      'Godot ${godotVersion(godot)} reads the same surfaces, triangles, '
      'materials and bounds out of all ${fixtures.length} files '
      '(${seconds.toStringAsFixed(1)}s)',
    );
    return;
  }
  stderr.writeln('Godot and this repository disagree:');
  for (final problem in problems) {
    stderr.writeln('  $problem');
  }
  exitCode = 1;
}

/// The path to a Godot binary, or null after saying on stderr why there is
/// none. `--godot=`, then `$GODOT`, then whatever is on the PATH — the same
/// order `tool/validate_gltf.dart` uses for its own external tool.
String? _resolveGodot(List<String> arguments) {
  for (final argument in arguments) {
    if (argument.startsWith('--godot=')) {
      return argument.substring('--godot='.length);
    }
  }
  final named = Platform.environment['GODOT'];
  if (named != null && named.isNotEmpty) return named;
  final found = Process.runSync('sh', <String>['-c', 'command -v godot']);
  if (found.exitCode == 0) return (found.stdout as String).trim();

  stderr.writeln(
    'no Godot here.\n'
    '\n'
    "This step opens the repository's exported GLBs in a second engine — see "
    'package:godot_check/godot_check.dart for why a validator is not the '
    'same question. .github/workflows/ci.yml downloads a pinned release; on '
    'a developer\'s machine, pass --godot=/path/to/Godot or set GODOT.',
  );
  exitCode = 1;
  return null;
}
