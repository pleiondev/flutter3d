import 'dart:developer' as developer;

import 'package:flutter3d_core/formats.dart';

import 'model_isolate.dart';

export 'package:flutter3d_core/formats.dart'
    show
        ModelDecoder,
        ModelFormat,
        ModelLoadRequest,
        decodeModel,
        decodeModelBytes,
        sniffModelFormat;

// **What is left here is the isolate**, and mcp-03n was the question of
// whether that owed Flutter anything: only `kIsWeb`, for the platform with no
// isolates, which is a compile-time constant naming no SDK —
// `bool.fromEnvironment('dart.library.js_interop')` is the same fact asked
// the way a flat package can ask it, and `flutter3d_mesh`/`flutter3d_model_core`
// already answer the identical question this way. Deciding *which* decoder
// reads a file and running it is `flutter3d_formats` — `ModelFormat`,
// `ModelDecoder`, `decodeModel`, `decodeModelBytes` and `sniffModelFormat` —
// because a modeller, a server and a plain `dart test` all want that half and
// none of them can resolve a Flutter SDK to get it.
export 'asset_source.dart';

/// Decodes a model on a background isolate — in the browser, on the decode
/// worker where one is running (`WebDecodeWorker`) and in place where not.
///
/// The asset layer was kept free of the graphics backend, `dart:ui` and direct file access
/// precisely so this would be possible: the decoders are pure Dart and take their
/// sibling files through a callback.
///
/// Why it matters: decoding the 71 KB Utah teapot costs 5.39 ms of CPU, a third of
/// a 60 Hz frame, and a real model runs into tens of milliseconds. That is jank on
/// the UI isolate however fast the parser is — which is also why FFI would not have
/// fixed it (see ARCHITECTURE.md §14).
///
/// **File reads stay on this isolate.** The obvious alternative — wire the platform
/// channel into the background isolate with `BackgroundIsolateBinaryMessenger` —
/// does not work for assets: it grants a channel but creates no `ServicesBinding`,
/// so `rootBundle` throws "Binding has not yet been initialized", and routing the
/// `flutter/assets` channel by hand makes Flutter's own reply handler fail a cast.
/// Reading here is also the better split: I/O is cheap, parsing is what blocks.
///
/// Sibling files are requested back over a port, so a `.gltf` referencing an
/// external `.bin` works exactly as it does synchronously.
Future<ModelDocument> decodeModelInIsolate(ModelLoadRequest request) async {
  // The web has no isolates: `decodeOnIsolate` there is the browser's decode
  // worker where one is running (`WebDecodeWorker`), and the page itself
  // where not — see `model_isolate_web.dart`.
  //
  // An async span, not startSync/finishSync: the read and the isolate round trip
  // both suspend, and a synchronous span would close on the first await and
  // report a fraction of the real cost.
  final task = developer.TimelineTask()
    ..start(
      'decodeModelInIsolate',
      arguments: <String, Object?>{'source': request.source.key},
    );
  try {
    return await decodeOnIsolate(request, task);
  } finally {
    task.finish();
  }
}
