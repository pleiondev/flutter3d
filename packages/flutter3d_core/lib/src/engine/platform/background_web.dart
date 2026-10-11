import 'dart:async';
import 'dart:typed_data';

import '../render/panorama_faces.dart';

/// [work] in place: the browser has no isolates.
Future<R> runInBackground<R>(FutureOr<R> Function() work) async => work();

/// A Radiance file's faces and convolved chain; null where the bytes are not
/// a file the reader takes.
Future<PanoramaFaces?> hdrPanoramaFacesInBackground(
  Uint8List bytes, {
  required int size,
  required int levels,
}) async => hdrPanoramaFaces(bytes, size: size, levels: levels);

/// [pixels]' faces and convolved chain; null where they are not
/// `width × height` RGBA8.
Future<PanoramaFaces?> panoramaFacesInBackground(
  ByteData pixels, {
  required int width,
  required int height,
  required int size,
  required int levels,
}) async => panoramaFaces(
  pixels,
  width: width,
  height: height,
  size: size,
  levels: levels,
);
