/// Files on a machine that has a file system, sandbox and all.
///
/// **The macOS sandbox is what shapes this file**, and the level editor beside
/// it took the other road: it turned the sandbox off, because it opens a
/// document that lives beside the repository and writes it back, and under the
/// sandbox that is `PathAccessException` on a path that is plainly there. A
/// modeller is meant to be handed to somebody else, so it keeps the sandbox and
/// works within what that grants — the file a person chose, this run.
///
/// The measured part is [saveAs], and `p0-13n` is why it looks like this: see
/// the note on it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'picked_file.dart';

export 'picked_file.dart';

/// The formats this can open, as the picker's own vocabulary.
const XTypeGroup _models = XTypeGroup(
  label: 'models',
  extensions: <String>['glb', 'gltf', 'obj', 'f3d', 'f3dproj'],
);

/// Asks for a model and reads it.
///
/// Null when the person dismissed the picker.
Future<PickedFile?> openModel() async {
  final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[_models]);
  if (file == null) return null;
  return PickedFile(
    name: file.name,
    bytes: await file.readAsBytes(),
    path: file.path,
  );
}

/// Writes [bytes] to a file the person chooses, offering [suggestedName].
///
/// **Straight into the chosen path, and not through a temporary file.** The
/// obvious way to write a document safely is to write a sibling and rename it
/// over the target, so a crash halfway leaves the old file intact. Under
/// `com.apple.security.files.user-selected.read-write` that does not work: the
/// grant covers the file that came back from the panel and not its directory,
/// so creating `model.f3d.tmp` beside it is refused before the rename is even
/// reached. `p0-13n` measured all three candidates; this is the one that
/// writes.
///
/// What that costs is honest to state: a crash during the write leaves a
/// truncated file. The alternative that keeps atomicity is a security-scoped
/// bookmark for the *directory*, which is a second panel and a second grant to
/// explain — `ui-20`'s question, not this one's, and not worth it before there
/// is a document big enough for the window to matter.
Future<SaveResult> saveAs(
  Uint8List bytes, {
  required String suggestedName,
}) async {
  final location = await getSaveLocation(suggestedName: suggestedName);
  if (location == null) return SaveResult.cancelled;
  try {
    await File(location.path).writeAsBytes(bytes, flush: true);
    return SaveResult(SaveOutcome.written, path: location.path);
  } on FileSystemException catch (error) {
    return SaveResult(
      SaveOutcome.refused,
      // The message rather than the exception: `PathAccessException: Operation
      // not permitted, path = '...'` read by somebody who did not write this
      // is a bug report about a missing file.
      said: 'the system refused to write ${location.path}: ${error.message}',
    );
  }
}

/// Writes [bytes] beside [original], the way "Save" rather than "Save as" does.
///
/// Refuses rather than guesses when there is no original — a browser's
/// [PickedFile] has no path, and neither has a project that was never saved.
Future<SaveResult> saveOver(PickedFile original, Uint8List bytes) async {
  final path = original.path;
  if (path == null) {
    return const SaveResult(
      SaveOutcome.refused,
      said: 'this project has no file yet; use Save as',
    );
  }
  try {
    await File(path).writeAsBytes(bytes, flush: true);
    return SaveResult(SaveOutcome.written, path: path);
  } on FileSystemException catch (error) {
    return SaveResult(
      SaveOutcome.refused,
      said: 'the system refused to write $path: ${error.message}',
    );
  }
}

/// Whether writing a temporary file beside [path] and renaming it over the
/// target is allowed here.
///
/// **Exposed because it is a measurement, not a helper.** `p0-13n` asks which
/// of three ways of writing survives the sandbox, and this is the one that
/// does not on macOS — the answer belongs in a document with a date on it
/// rather than in somebody's memory. The modeller's own writes go through
/// [saveAs] and [saveOver]; this is what the spike calls to find out why.
Future<String?> whyAtomicWriteFails(String path) async {
  final temporary = File('$path.tmp');
  try {
    await temporary.writeAsBytes(<int>[0], flush: true);
    await temporary.rename(path);
    return null;
  } on FileSystemException catch (error) {
    return '${error.runtimeType}: ${error.message}';
  } finally {
    if (temporary.existsSync()) {
      try {
        temporary.deleteSync();
      } on FileSystemException {
        // Nothing to do about it, and nothing worth saying: the file is in a
        // directory this process was refused in the first place.
      }
    }
  }
}
