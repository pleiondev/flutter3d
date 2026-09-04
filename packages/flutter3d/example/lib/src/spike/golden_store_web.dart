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

  // And to the server, so a driver does not have to scrape a page to find out
  // what happened. Fire and forget: a build opened by hand has nothing
  // answering this route, and the line is already on the screen where a person
  // can read it — the post is the machine's copy, not the only one.
  web.window
      .fetch('report'.toJS, web.RequestInit(method: 'POST', body: message.toJS))
      .toDart
      .catchError((Object _) => web.Response());
}

/// The scene named in the page's URL, if any.
///
/// A run-time choice here, where the desktop path takes a compile-time define.
/// The reason is arithmetic: the suite is forty-one scenes, and rebuilding
/// the bundle for each is thirty-nine dart2js runs to compare thirty-nine
/// pictures. One build and thirty-nine navigations is the same information in
/// a fraction of the time.
String? get sceneOverride {
  final name = Uri.base.queryParameters['golden'];
  return (name == null || name.isEmpty) ? null : name;
}

/// Whether this run records rather than compares, from the page's URL.
///
/// A run-time choice for the same reason [sceneOverride] is one: the suite is
/// forty-one scenes and rebuilding for each would be thirty-nine dart2js runs.
/// One build serves both directions, and the URL says which.
bool get updateOverride => Uri.base.queryParameters['update'] == '1';

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
  final response = await web.window.fetch('goldens/$name.png'.toJS).toDart;
  if (!response.ok) return null;
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// Records a reference by handing it back to the server that served the page.
///
/// **A page cannot write a file, so it posts one.** This used to throw, on the
/// grounds that goldens are recorded on the desktop build and only compared
/// here — which was right while the browser had no reference set of its own.
/// It has one now, and it has to be recorded through the backend that will be
/// held to it: a set recorded on Impeller and called WebGL's would be the same
/// tautology as one backend agreeing with itself.
///
/// `tool/golden_web.sh` is the other end. Nothing else answers this route, so a
/// build opened by hand fails here rather than pretending it recorded.
Future<String> writeReference(
  String directory,
  String name,
  Uint8List png,
) async {
  return _post('record/$name.png', png, 'reference');
}

/// The frame as drawn, beside the reference, when they disagree.
Future<String> writeActual(String directory, String name, Uint8List png) async {
  return _post('actual/$name.png', png, 'actual');
}

Future<String> _post(String route, Uint8List png, String what) async {
  final response = await web.window
      .fetch(route.toJS, web.RequestInit(method: 'POST', body: png.toJS))
      .toDart;
  if (!response.ok) {
    return '(not written: the server refused $route with ${response.status}. '
        'A golden is recorded through tool/golden_web.sh, which is what '
        'answers that route.)';
  }
  return '$what written to $route';
}

/// There is no exit code to return, so the run simply stops.
Never finish(int code) => throw _GoldenFinished(code);

/// Thrown to unwind out of a golden run. Caught by the runner's caller, which
/// has already printed the verdict.
final class _GoldenFinished implements Exception {
  const _GoldenFinished(this.code);
  final int code;
  @override
  String toString() => 'golden run finished with code $code';
}

String describe(String directory, String name) => 'goldens/$name.png';
