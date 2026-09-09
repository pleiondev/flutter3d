import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter3d_formats/flutter3d_formats.dart';

export 'package:flutter3d_formats/flutter3d_formats.dart'
    show
        ModelDecoder,
        ModelFormat,
        ModelLoadRequest,
        decodeModel,
        decodeModelBytes,
        sniffModelFormat;

// **What is left here is the isolate**, and that is the whole of what this file
// still owes Flutter: `kIsWeb` for the platform with no isolates, and an asset
// bundle at the other end of the port. Deciding *which* decoder reads a file
// and running it is `flutter3d_formats` — `ModelFormat`, `ModelDecoder`,
// `decodeModel`, `decodeModelBytes` and `sniffModelFormat` — because a
// modeller, a server and a plain `dart test` all want that half and none of
// them can resolve a Flutter SDK to get it.
export 'asset_source.dart';

/// Decodes a model on a background isolate.
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
  // The web has no isolates. `dart:isolate` compiles there — it is a stub — so
  // this fails at run time rather than at build time, with
  // `ReceivePort.listen` unsupported, several seconds into loading a model.
  //
  // Decoding on the main thread instead, which is what the name promises not to
  // do and the only thing available. A parse that janks is worse than one that
  // does not; a parse that throws is worse than both.
  if (kIsWeb) return decodeModel(request);

  // An async span, not startSync/finishSync: the read and the isolate round trip
  // both suspend, and a synchronous span would close on the first await and
  // report a fraction of the real cost.
  final task = developer.TimelineTask()
    ..start(
      'decodeModelInIsolate',
      arguments: <String, Object?>{'source': request.source.key},
    );
  try {
    return await _decodeModelInIsolate(request, task);
  } finally {
    task.finish();
  }
}

Future<ModelDocument> _decodeModelInIsolate(
  ModelLoadRequest request,
  developer.TimelineTask task,
) async {
  task.instant('read');
  final primary = await request.source.read();
  final resolve = request.source.resolveUri;

  final requests = ReceivePort();
  final subscription = requests.listen((Object? message) async {
    final envelope = message! as List<Object?>;
    final uri = envelope[0]! as String;
    final reply = envelope[1]! as SendPort;
    try {
      reply.send(await resolve(AssetRequest(uri)));
    } catch (error) {
      // Errors cannot be thrown across a port, so they travel as a value and are
      // rethrown on the far side.
      reply.send(<Object?>['error', error.toString()]);
    }
  });

  final servicePort = requests.sendPort;
  try {
    task.instant('decode');
    return await Isolate.run(
      () => decodeModelBytes(request, primary, _portResolver(servicePort)),
    );
  } finally {
    await subscription.cancel();
    requests.close();
  }
}

/// A resolver that asks the spawning isolate to read a file.
AssetUriResolver _portResolver(SendPort servicePort) {
  return (request) async {
    // **The string, not the request.** What goes over the port is read by an
    // isolate that expects a path, and `send` takes `Object?` — so handing it
    // the whole object compiles, says nothing, and fails at the other end.
    final uri = request.uri;
    final reply = ReceivePort();
    try {
      servicePort.send(<Object?>[uri, reply.sendPort]);
      final response = await reply.first;
      if (response is Uint8List) return response;
      if (response is List && response.length == 2 && response[0] == 'error') {
        throw StateError('Could not read "$uri": ${response[1]}');
      }
      throw StateError('Unexpected reply reading "$uri": $response');
    } finally {
      reply.close();
    }
  };
}
