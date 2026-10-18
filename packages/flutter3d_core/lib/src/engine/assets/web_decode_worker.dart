/// Where a web build decodes models and panoramas off the page's thread.
library;

/// The browser's decode worker: a Web Worker that decodes models and
/// panoramas for a web build, so the page's thread keeps drawing.
///
/// **A browser has no isolates, and a worker cannot run a closure.**
/// Natively `decodeModelInIsolate` and `EnvironmentMap.fromEncoded` hand
/// their work to an isolate of their own. A Web Worker is the browser's
/// thread, but it runs a script of its own rather than a function from the
/// page's program, so the decoders are compiled into one:
///
///     dart run flutter3d_core:decode_worker web/flutter3d_decode_worker.js
///
/// writes the script beside the app's `index.html`, and
/// `WebDecodeWorker.use(Uri.parse('flutter3d_decode_worker.js'))` at startup
/// sends decodes to it. The page reads the files (a glTF's buffers are asked
/// for back over the worker's messages, as a native decode asks over a port),
/// the worker parses them and answers with the model as an `.f3d` container,
/// which the page reads as views over the bytes it was sent.
///
/// **Where the browser does not allow it, the decode runs in place, as every
/// web decode did before 1.0, and [inPlaceReason] says why.** That is the
/// case without a script ([use] not called), in a browser or a page that
/// will not start one (no `Worker`, a content security policy without
/// `worker-src` for it, a script that is not there), for a request with an
/// application's own `ModelDecoder` (it is a Dart object of the page's
/// program, which the worker's cannot run), for a format the worker does not
/// know, for a model whose `.f3d` would lose something (the writer's
/// warnings: a material with `KHR_texture_transform`, a splat cloud), and
/// for a file the worker could not read (the page reads it again, so the
/// error it throws is the decoder's own). A KTX2 transcode still runs in
/// place in the browser.
///
/// Natively this does nothing: [use] is remembered and never consulted.
abstract final class WebDecodeWorker {
  /// Decodes go to the worker compiled to [script], resolved against the
  /// page's address. The worker starts on the first decode; a running one
  /// for another script is stopped first.
  static void use(Uri script) {
    webDecodeWorkerState
      ..script = script
      ..generation += 1;
  }

  /// Decodes run in place again; a running worker is stopped at the next
  /// decode.
  static void stop() {
    webDecodeWorkerState
      ..script = null
      ..generation += 1;
  }

  /// The script [use] named, or null.
  static Uri? get script => webDecodeWorkerState.script;

  /// Why the last decode in the browser ran in place, or null when it ran
  /// on the worker (or none has run).
  static String? get inPlaceReason => webDecodeWorkerState.inPlaceReason;

  /// How many decodes the worker has answered, for a test and a profiler.
  static int get decoded => webDecodeWorkerState.decoded;
}

/// What [WebDecodeWorker] says and the browser's client of it reads and
/// writes. Not exported.
final class WebDecodeWorkerState {
  /// The script [WebDecodeWorker.use] named, or null.
  Uri? script;

  /// Bumped by [WebDecodeWorker.use] and [WebDecodeWorker.stop], so a
  /// running worker for an older choice is stopped.
  int generation = 0;

  /// Why the last decode in the browser ran in place, or null when it ran on
  /// the worker or none has run.
  String? inPlaceReason;

  /// How many decodes the worker has answered, a count.
  int decoded = 0;
}

/// The one [WebDecodeWorkerState].
final WebDecodeWorkerState webDecodeWorkerState = WebDecodeWorkerState();
