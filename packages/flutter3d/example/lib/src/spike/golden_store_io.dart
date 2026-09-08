/// Golden storage on a platform with files and an exit code.
library;

import 'dart:io';
import 'dart:typed_data';

/// Nothing extra: the console is where the harness script reads.
void reportLine(String message) {}

/// The scene this run should draw, from the process environment.
///
/// **A run-time choice, and it is what lets one build serve the whole suite.**
/// It used to be only a `--dart-define`, which is a compile-time input: the
/// scene name lands in the build fingerprint, so forty-three scenes meant
/// forty-three kernel compiles and forty-three directories under
/// `example/.dart_tool/flutter_build` — about forty-six megabytes of `app.dill`
/// apiece, and nothing ever deletes them. Seven hundred of them, sixteen
/// gigabytes, had collected in this checkout before anybody measured, and a
/// full run of the suite could not finish on a machine with room for a third of
/// it. Read from the environment, the application is built once and launched
/// once per scene with a different variable set, which is the shape the browser
/// stand already had with its query parameter.
///
/// The define still answers when the variable is unset, so a `flutter run`
/// driven by hand keeps working exactly as it did.
String? get sceneOverride => _environment('FLUTTER3D_GOLDEN');

/// Whether this run records rather than compares, from the environment.
///
/// Run-time for the same reason [sceneOverride] is: a direction baked into the
/// build is a second build. Null when the variable is unset, which leaves the
/// compile-time define to answer.
bool? get updateOverride => switch (_environment('FLUTTER3D_GOLDEN_UPDATE')) {
  null => null,
  final asked => asked == 'true' || asked == '1',
};

/// Where the references live, from the environment, for the same reason again.
///
/// The reference directory differs per backend — Impeller's set and the
/// software rasteriser's are separate — so leaving it a define would have cost
/// a build per backend on top of a build per scene.
String? get directoryOverride => _environment('FLUTTER3D_GOLDEN_DIR');

/// An environment variable, treating empty as absent: a shell that exports a
/// variable it did not set hands over an empty string, and "unset" is the
/// answer that lets the compile-time define speak.
String? _environment(String name) {
  final value = Platform.environment[name];
  return (value == null || value.isEmpty) ? null : value;
}

/// Whether a run has to be told where the references live.
///
/// True here: a macOS application bundle runs with its working directory at
/// the root of the filesystem, so a relative path resolves somewhere
/// unwritable and the failure arrives as a permission error three seconds into
/// a render.
const bool needsReferenceDirectory = true;

/// The recorded reference, or null if there is none.
Future<Uint8List?> readReference(String directory, String name) async {
  final file = File('$directory/$name.png');
  if (!file.existsSync()) return null;
  return file.readAsBytesSync();
}

/// Records a reference, creating the directory if needed.
Future<String> writeReference(
  String directory,
  String name,
  Uint8List png,
) async {
  final file = File('$directory/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png);
  return file.path;
}

/// Writes the frame that disagreed, beside its reference.
Future<String> writeActual(String directory, String name, Uint8List png) async {
  final path = '$directory/$name.actual.png';
  File(path).writeAsBytesSync(png);
  return path;
}

/// How a golden run ends: an exit code the harness script reads.
Never finish(int code) => exit(code);

/// Where a reference lives, in words, for a message.
String describe(String directory, String name) => '$directory/$name.png';
