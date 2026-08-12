/// Golden storage in a browser: fetched references, no files, no exit code.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Writes a line where a person and a tool can both read it.
///
/// Into the document, not the console. A release web build's `print` does not
/// reach the browser console reliably, and a verdict nobody can read is the
/// same as no verdict — which is the failure this suite exists to prevent, and
/// which it has already had once today in a different disguise.
void reportLine(String message) {
  var log = web.document.getElementById('golden-log') as web.HTMLElement?;
  if (log == null) {
    log = web.document.createElement('pre') as web.HTMLElement
      ..id = 'golden-log'
      ..setAttribute(
        'style',
        'position:fixed;left:0;top:0;right:0;z-index:99999;margin:0;'
        'padding:8px;background:#000;color:#0f0;font:13px monospace;'
        'white-space:pre-wrap',
      );
    web.document.body!.append(log);
  }
  log.textContent = '${log.textContent ?? ''}$message\n';
}

/// The scene named in the page's URL, if any.
///
/// A run-time choice here, where the desktop path takes a compile-time define.
/// The reason is arithmetic: the suite is twenty-three scenes, and rebuilding
/// the bundle for each is twenty-three dart2js runs to compare twenty-three
/// pictures. One build and twenty-three navigations is the same information in
/// a fraction of the time.
String? get sceneOverride {
  final name = Uri.base.queryParameters['golden'];
  return (name == null || name.isEmpty) ? null : name;
}

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
