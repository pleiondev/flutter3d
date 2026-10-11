/// What a panorama becomes before its upload, worked out where no frame waits.
///
/// Internal: `EnvironmentMap.fromEncoded` runs these on an isolate natively
/// and the browser's decode worker runs them on its own thread, so both
/// halves call one function rather than two copies of it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

import 'environment_map.dart';

/// Six faces cut from a panorama and the chain convolved from them: all the
/// CPU work an environment cube costs, with only the upload left.
final class PanoramaFaces {
  const PanoramaFaces({
    required this.size,
    required this.faces,
    required this.chain,
  });

  /// The edge of a face of the base level.
  final int size;

  /// The base level, +X, −X, +Y, −Y, +Z, −Z.
  final List<ByteData> faces;

  /// The convolved levels after it, each six faces.
  final List<List<ByteData>> chain;
}

/// [pixels], `width × height` RGBA8, as faces of [size] and [levels]
/// convolved levels; null where either does not describe a cube
/// `EnvironmentMap.fromPanorama` would build.
PanoramaFaces? panoramaFaces(
  ByteData pixels, {
  required int width,
  required int height,
  required int size,
  required int levels,
}) {
  final faces = EnvironmentMap.equirectToCubeFaces(
    pixels,
    width: width,
    height: height,
    size: size,
  );
  if (faces == null) return null;
  final chain = EnvironmentMap.prefilter(faces, size: size, levels: levels);
  if (chain == null) return null;
  return PanoramaFaces(size: size, faces: faces, chain: chain);
}

/// A Radiance file as [panoramaFaces] reads it, or null where [bytes] are
/// not one this reader takes.
PanoramaFaces? hdrPanoramaFaces(
  Uint8List bytes, {
  required int size,
  required int levels,
}) {
  final HdrImage image;
  try {
    image = readHdr(bytes);
  } on HdrFormatException {
    return null;
  }
  return panoramaFaces(
    EnvironmentMap.hdrToRgba8(image),
    width: image.width,
    height: image.height,
    size: size,
    levels: levels,
  );
}
