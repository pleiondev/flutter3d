/// Capturing the viewport's own canvas, in a browser — `tut-19`'s own
/// preview capture, the real half.
///
/// The same `web.window.fetch` with the page's own cookies
/// `cabinet_save_web.dart` beside this file already sends a save-back with;
/// what is new here is finding the canvas at all, since nothing before this
/// stage ever needed to read pixels back out of one.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

/// The bytes at `/api/v1/models/<modelId>/preview`, carrying [sourceSha] and
/// [csrf] the way `cloud/server`'s own handler needs them — see this
/// package's own `preview_capture.dart` for the contract every caller of
/// this function relies on.
///
/// **Quiet on every failure.** Nothing here throws past its own `catch` —
/// a viewer who came to look at a model never sees a dialog about a
/// background picture that did not make it; `debugPrint` is where the reason
/// goes instead, the same channel `screen/files.dart`'s own sandbox-probe
/// line and `measurement_runs.dart`'s own report already use for something
/// worth knowing but not worth a person's attention.
Future<void> capturePreview({
  required int modelId,
  required String sourceSha,
  required String csrf,
}) async {
  try {
    final canvas = _findViewportCanvas();
    if (canvas == null) {
      debugPrint('preview capture: no viewport canvas found in the page');
      return;
    }

    final blob = await _toPngBlob(canvas);
    if (blob == null) {
      debugPrint('preview capture: the browser produced no PNG blob');
      return;
    }
    final buffer = await blob.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();

    final headers = web.Headers()
      ..set('content-type', 'image/png')
      ..set('x-csrf', csrf)
      ..set('x-source-sha256', sourceSha);
    final url = Uri.base.resolve('/api/v1/models/$modelId/preview').toString();
    final response = await web.window
        .fetch(
          url.toJS,
          web.RequestInit(
            method: 'POST',
            credentials: 'same-origin',
            headers: headers,
            body: bytes.toJS,
          ),
        )
        .toDart;
    if (!response.ok) {
      final text = (await response.text().toDart).toDart;
      debugPrint(
        'preview capture: the server answered ${response.status}: $text',
      );
    }
  } catch (error) {
    debugPrint('preview capture: $error');
  }
}

/// The canvas the 3D viewport draws into, best guess.
///
/// **The one signal this application controls: `flt-platform-view` is the
/// element the Flutter web engine wraps every `HtmlElementView` in**, and
/// `WebGlDevice`/`WebGpuDevice` are the only two things in this build that
/// ever register one — every other pixel on this page is Flutter's own
/// CanvasKit surface, which draws into a canvas of its own outside that
/// wrapper. Where that selector finds nothing — an engine version that wraps
/// platform views differently, say — the last `<canvas>` in document order is
/// the fallback, since the viewport's own `HtmlElementView` is built after
/// everything already on screen around it.
///
/// **Unverifiable here.** Nothing in `flutter test` runs a real browser
/// engine with a real platform-view-wrapped canvas to check this selector
/// against; see `preview_capture_test.dart`'s own doc comment for what is and
/// is not tested about this file.
web.HTMLCanvasElement? _findViewportCanvas() {
  final scoped = web.document.querySelector('flt-platform-view canvas');
  if (scoped != null) return scoped as web.HTMLCanvasElement;
  final all = web.document.querySelectorAll('canvas');
  if (all.length == 0) return null;
  return all.item(all.length - 1) as web.HTMLCanvasElement?;
}

/// [canvas] re-encoded as a PNG blob — `HTMLCanvasElement.toBlob`'s own
/// callback wrapped in a [Completer], since the browser API is a callback
/// rather than a promise. Null when the browser calls back with nothing,
/// which `toBlob` does when the canvas has no pixels to encode at all — a
/// zero-sized canvas, say.
Future<web.Blob?> _toPngBlob(web.HTMLCanvasElement canvas) {
  final completer = Completer<web.Blob?>();
  canvas.toBlob(
    ((web.Blob? blob) => completer.complete(blob)).toJS,
    'image/png',
  );
  return completer.future;
}
