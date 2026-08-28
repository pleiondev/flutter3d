/// Golden storage on a platform with files and an exit code.
library;

import 'dart:io';
import 'dart:typed_data';

/// Nothing extra: the console is where the harness script reads.
void reportLine(String message) {}

/// No run-time override here: the harness script passes a define per scene and
/// reads an exit code, which is the shape a shell can drive.
String? get sceneOverride => null;

/// Whether this run records, from the URL. There is no URL here: the desktop
/// build takes it as a compile-time define, which `tool/golden.sh` passes.
const bool? updateOverride = null;

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
