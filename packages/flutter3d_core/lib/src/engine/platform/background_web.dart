import 'dart:async';
import 'dart:typed_data';

import '../render/panorama_faces.dart';
import 'decode_worker_web.dart';

/// [work] in place: the browser has no isolates, and a Web Worker runs a
/// script of its own rather than a closure from this program. The work that
/// does leave the page goes by name to the decode worker
/// (`WebDecodeWorker`): a model's decode and a panorama's convolution, below.
Future<R> runInBackground<R>(FutureOr<R> Function() work) async => work();

/// A Radiance file's faces and convolved chain, worked out on the decode
/// worker where one is running and in place where not; null where the bytes
/// are not a file the reader takes.
Future<PanoramaFaces?> hdrPanoramaFacesInBackground(
  Uint8List bytes, {
  required int size,
  required int levels,
}) async =>
    switch (await panoramaOnWorker(hdr: bytes, size: size, levels: levels)) {
      (final faces,) => faces,
      null => hdrPanoramaFaces(bytes, size: size, levels: levels),
    };

/// [pixels]' faces and convolved chain, worked out on the decode worker
/// where one is running and in place where not; null where they are not
/// `width × height` RGBA8.
Future<PanoramaFaces?> panoramaFacesInBackground(
  ByteData pixels, {
  required int width,
  required int height,
  required int size,
  required int levels,
}) async => switch (await panoramaOnWorker(
  pixels: pixels,
  width: width,
  height: height,
  size: size,
  levels: levels,
)) {
  (final faces,) => faces,
  null => panoramaFaces(
    pixels,
    width: width,
    height: height,
    size: size,
    levels: levels,
  ),
};
