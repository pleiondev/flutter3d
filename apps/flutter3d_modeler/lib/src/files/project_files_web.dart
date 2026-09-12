/// Files in a browser, where there is no file system to have them in.
///
/// **Two things a desktop takes for granted are missing, and both change the
/// interface rather than its implementation.** A browser hands over bytes with
/// no path, so nothing can be written back over what was opened; and a "save"
/// is a download, which the person then files wherever they file downloads —
/// there is no confirmation, no destination and no way to ask afterwards
/// whether it worked. So [saveOver] refuses here, and [saveAs] reports
/// `written` as soon as the download has been started, which is the strongest
/// claim a browser lets anybody make.
///
/// `package:web` and `dart:js_interop` rather than a plugin: what this needs is
/// an `<input type="file">` and an anchor with a `download` attribute, which is
/// ten lines either way — and a plugin would be a dependency whose own web
/// implementation is these same ten lines.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'gltf_siblings.dart';
import 'picked_file.dart';

export 'picked_file.dart';

/// Reads every file [input] came back with, name to bytes.
///
/// **A cancel is silence.** No browser fires an event when the file dialogue
/// is dismissed, and the newer `cancel` event is not in every engine this has
/// to run in. So the click happens and the caller waits; a caller that needs
/// to move on regardless treats a pending future as "still choosing", which
/// is what the modeller's own screen does.
Future<Map<String, Uint8List>> _pickFiles(web.HTMLInputElement input) {
  final completer = Completer<Map<String, Uint8List>>();
  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(const <String, Uint8List>{});
      return;
    }
    final reads = <Future<void>>[];
    final byName = <String, Uint8List>{};
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i)!;
      // `arrayBuffer()` rather than a `FileReader`: the promise is one
      // await, and the reader is three callbacks and an error path.
      reads.add(
        file.arrayBuffer().toDart.then((JSArrayBuffer buffer) {
          byName[file.name] = buffer.toDart.asUint8List();
        }),
      );
    }
    Future.wait(reads).then((_) {
      if (!completer.isCompleted) completer.complete(byName);
    });
  }.toJS;
  input.click();
  return completer.future;
}

/// Asks for a model and reads it.
///
/// Null when the person dismissed the picker.
///
/// **A `.gltf` naming an external `.bin` or texture gets a second dialogue,
/// not a guess.** A browser hands over bytes with no folder behind them at
/// all — there is nothing here even resembling the sandboxed grant `project_
/// files_io.dart`'s own note describes, only ever what a person picked. So
/// the second dialogue asks for however many files the `.gltf` itself names,
/// selected together. `ui-36n`'s own row.
Future<PickedFile?> openModel() async {
  final byName = await _pickFiles(
    web.HTMLInputElement()
      ..type = 'file'
      ..accept = '.glb,.gltf,.obj,.f3d,.f3dproj',
  );
  if (byName.isEmpty) return null;
  final name = byName.keys.single;
  final bytes = byName.values.single;

  final needed = gltfSiblingUris(bytes);
  if (needed.isEmpty) {
    return PickedFile(name: name, bytes: bytes);
  }
  final siblings = await _pickFiles(
    web.HTMLInputElement()
      ..type = 'file'
      ..multiple = true,
  );
  return PickedFile(name: name, bytes: embedGltfSiblings(bytes, siblings));
}

/// Hands [bytes] to the browser as a download named [suggestedName].
Future<SaveResult> saveAs(
  Uint8List bytes, {
  required String suggestedName,
}) async {
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = suggestedName;
  // Attached before the click and removed after: Firefox ignores a click on an
  // anchor that is not in the document.
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Revoked on the next turn of the event loop rather than immediately —
  // revoking in the same task cancels the download in Safari.
  Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));

  return SaveResult(SaveOutcome.written, path: suggestedName);
}

/// There is nothing to save over: a browser gave no path.
Future<SaveResult> saveOver(PickedFile original, Uint8List bytes) async =>
    const SaveResult(
      SaveOutcome.refused,
      said:
          'a browser has no file to write back to; use Save as, which '
          'downloads',
    );

/// Not a question a browser has: there is no directory to write beside.
Future<String?> whyAtomicWriteFails(String path) async =>
    'a browser has no file system to rename within';

/// A browser's own [PickedFile] never carries a path, so nothing is ever
/// written into [RecentModels] here in the first place — this is never
/// actually called, and returns null rather than asserting so a caller
/// shared with the io build does not need its own web branch.
Future<Uint8List?> readRecentModel(String path) async => null;

/// See [readRecentModel] — nothing here is ever a path worth asking about.
bool pathExists(String path) => false;
