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

import 'picked_file.dart';

export 'picked_file.dart';

/// Asks for a model and reads it.
///
/// Null when the person dismissed the picker — which a browser reports by
/// never firing `change` at all, so this also resolves to null when the input
/// is closed by other means. See the note on the timeout below.
Future<PickedFile?> openModel() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.glb,.gltf,.obj,.f3d,.f3dproj';

  final completer = Completer<PickedFile?>();
  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files.item(0)!;
    // `arrayBuffer()` rather than a `FileReader`: the promise is one await,
    // and the reader is three callbacks and an error path.
    file.arrayBuffer().toDart.then((JSArrayBuffer buffer) {
      if (completer.isCompleted) return;
      completer.complete(
        PickedFile(name: file.name, bytes: buffer.toDart.asUint8List()),
      );
    });
  }.toJS;

  // **A cancel is silence.** No browser fires an event when the file dialogue
  // is dismissed, and the newer `cancel` event is not in every engine this has
  // to run in. So the click happens and the caller waits; a caller that needs
  // to move on regardless treats a pending future as "still choosing", which
  // is what the modeller's own screen does.
  input.click();
  return completer.future;
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
