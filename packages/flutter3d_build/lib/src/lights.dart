import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What `dart run flutter3d_build:lights` prints when it is asked wrongly.
const String lightsUsage = '''
usage: dart run flutter3d_build:lights --optimize <level.json> [options]

Fewer lights that light the level the way it is lit now. Every light is
drawn alone in software from the views; lights others already cover are
removed, close pairs are merged, and the rest are retuned, keeping only
changes whose picture stays close to the original.

  --poses <file.json>   where players stood: a JSON list of poses
                        ({"t", "p": [x, y, z], "y"}), as a game's Recorder
                        writes them while it plays a .f3drun back. May be
                        given more than once. Without one, the views are four
                        headings from every player spawn.
  -o, --out <path>      where to write the level; default: over the input
  --preview <dir>       write before.png and after.png of the first view
  --dry-run             say what would change and write no level
''';

/// The lights command: read a level, optimise its lights, write it back.
///
/// Returns the exit code: 0 when it ran (changed or not), 1 when a file
/// could not be read or written, 2 when the arguments were wrong.
Future<int> runLights(
  List<String> arguments, {
  IOSink? out,
  IOSink? err,
}) async {
  final say = out ?? stdout;
  final complain = err ?? stderr;
  final options = _LightsOptions.parse(arguments);
  if (options == null) {
    complain.writeln(lightsUsage);
    return 2;
  }

  final source = File(options.level);
  if (!source.existsSync()) {
    complain.writeln('No such file: ${options.level}');
    return 1;
  }
  final Editing editing;
  try {
    editing = Editing.parse(source.readAsStringSync(), path: options.level);
  } on FormatException catch (error) {
    complain.writeln('${options.level}: ${error.message}');
    return 1;
  } on LevelFormatException catch (error) {
    complain.writeln('${options.level}: $error');
    return 1;
  }

  final poses = <Pose>[];
  for (final path in options.poses) {
    final read = _posesIn(path);
    if (read == null) {
      complain.writeln('$path: not a list of poses');
      return 1;
    }
    poses.addAll(read);
  }
  final views = poses.isNotEmpty
      ? viewsAlong(poses)
      : defaultLightViews(editing.level);
  if (editing.level.lights.isEmpty) {
    say.writeln('${options.level}: no lights to optimise');
    return 0;
  }
  if (views.isEmpty) {
    complain.writeln(
      '${options.level}: nowhere to look from — give --poses, or put a '
      'player spawn in the level',
    );
    return 1;
  }

  final plan = const LightOptimizer().optimize(editing.level, views: views);
  say.writeln(plan.says);
  for (final move in plan.moves) {
    say.writeln('  $move');
  }
  if (options.preview case final String directory) {
    Directory(directory).createSync(recursive: true);
    final pngs = plan.pngs;
    File('$directory/before.png').writeAsBytesSync(pngs.before);
    File('$directory/after.png').writeAsBytesSync(pngs.after);
  }
  if (!plan.changes || options.dryRun) return 0;

  final to = options.out ?? options.level;
  final elsewhere = to != options.level;
  if (!elsewhere && !editing.mayOverwrite) {
    complain.writeln(
      '${options.level} was written by ${editing.generatedBy} and will not be '
      'overwritten — give --out and the copy takes ownership of itself',
    );
    return 1;
  }
  editing.history.run(SetLights(plan.after, why: plan.says));
  File(to).writeAsStringSync(
    editing.write(claiming: elsewhere ? 'packages/flutter3d_build' : null),
  );
  say.writeln('written to $to');
  return 0;
}

/// The poses in the file at [path]: a JSON list of them, or an object with
/// the list under `poses`. Null when the file holds neither.
List<Pose>? _posesIn(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return null;
  }
  final rows = switch (decoded) {
    final List<Object?> list => list,
    {'poses': final List<Object?> list} => list,
    _ => null,
  };
  if (rows == null) return null;
  return <Pose>[
    for (final row in rows)
      if (row is Map) Pose.fromJson(row.cast<String, Object?>()),
  ];
}

final class _LightsOptions {
  const _LightsOptions({
    required this.level,
    required this.poses,
    required this.out,
    required this.preview,
    required this.dryRun,
  });

  final String level;
  final List<String> poses;
  final String? out;
  final String? preview;
  final bool dryRun;

  static _LightsOptions? parse(List<String> arguments) {
    String? level;
    String? out;
    String? preview;
    var dryRun = false;
    final poses = <String>[];
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      final next = i + 1 < arguments.length ? arguments[i + 1] : null;
      switch (argument) {
        case '--optimize' when next != null:
          level = next;
          i++;
        case '--poses' when next != null:
          poses.add(next);
          i++;
        case '-o' || '--out' when next != null:
          out = next;
          i++;
        case '--preview' when next != null:
          preview = next;
          i++;
        case '--dry-run':
          dryRun = true;
        default:
          return null;
      }
    }
    if (level == null) return null;
    return _LightsOptions(
      level: level,
      poses: poses,
      out: out,
      preview: preview,
      dryRun: dryRun,
    );
  }
}
