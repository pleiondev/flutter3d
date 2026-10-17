import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../render/panorama_faces.dart';

/// [work] on an isolate of its own, as `Isolate.run`.
Future<R> runInBackground<R>(FutureOr<R> Function() work) => Isolate.run(work);

/// A Radiance file's faces and convolved chain, worked out on an isolate of
/// its own; null where the bytes are not a file the reader takes.
Future<PanoramaFaces?> hdrPanoramaFacesInBackground(
  Uint8List bytes, {
  required int size,
  required int levels,
}) => Isolate.run(() => hdrPanoramaFaces(bytes, size: size, levels: levels));

/// [pixels]' faces and convolved chain, worked out on an isolate of its own;
/// null where they are not `width × height` RGBA8.
Future<PanoramaFaces?> panoramaFacesInBackground(
  ByteData pixels, {
  required int width,
  required int height,
  required int size,
  required int levels,
}) => Isolate.run(
  () => panoramaFaces(
    pixels,
    width: width,
    height: height,
    size: size,
    levels: levels,
  ),
);
