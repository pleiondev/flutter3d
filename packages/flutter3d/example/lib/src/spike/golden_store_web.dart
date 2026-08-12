/// Golden storage in a browser: fetched references, no files, no exit code.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Whether a run has to be told where the references live.
///
/// False: there is no path here to resolve one against. The references are
/// fetched relative to the page.
const bool needsReferenceDirectory = false;

/// Fetches the reference from the server that served this page.
///
/// [directory] is ignored: a browser has no path to resolve it against. The
/// references are expected beside the build at `goldens/<name>.png`, which is
/// what the serving script arranges.
Future<Uint8List?> readReference(String directory, String name) async {
  final response =
      await web.window.fetch('goldens/$name.png'.toJS).toDart;
  if (!response.ok) return null;
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// Not available here, and saying so is better than pretending.
///
/// Recording a reference means writing a file, and a page cannot. Goldens are
/// recorded on the desktop build and *compared* here, which is the useful
/// direction anyway: the question a browser run answers is whether this backend
/// agrees with the one that recorded them.
Future<String> writeReference(
    String directory, String name, Uint8List png) async {
  throw UnsupportedError(
    'a browser cannot record a golden. Record on the desktop build with '
    'tool/golden.sh --update, then compare here.',
  );
}

/// Also not available, for the same reason. The verdict carries the numbers.
Future<String> writeActual(String directory, String name, Uint8List png) async =>
    '(not written: a browser has no filesystem)';

/// There is no exit code to return, so the run simply stops.
Never finish(int code) =>
    throw _GoldenFinished(code);

/// Thrown to unwind out of a golden run. Caught by the runner's caller, which
/// has already printed the verdict.
final class _GoldenFinished implements Exception {
  const _GoldenFinished(this.code);
  final int code;
  @override
  String toString() => 'golden run finished with code $code';
}

String describe(String directory, String name) => 'goldens/$name.png';
