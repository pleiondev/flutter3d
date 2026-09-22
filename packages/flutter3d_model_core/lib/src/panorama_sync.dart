/// The project's own panorama, on the scene that draws it — `ux-49`.
///
/// **The other half of `LightingSync`.** That class puts a project's lights
/// on a scene and folds its exposure into a frame's settings; this one puts
/// its panorama on `Scene.environment`, which is the texture every surface
/// gathers indirect light from. Separate because it needs a
/// [GraphicsDevice] and `LightingSync` deliberately does not: a light is six
/// numbers and a cube is an upload.
///
/// **Rebuilt only when the picture changes.** Convolving six faces by
/// roughness is tenths of a second at the sizes worth using, which is a frame
/// budget spent on a sky nobody moved — so the index and the bytes' own
/// identity are remembered, and an ordinary edit costs one comparison.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';

import 'project.dart';

/// How big a cube a panorama is turned into.
///
/// **Thirty-two, the same as a sky.** The cube is a source of *indirect*
/// light rather than a background: what a surface reads off it is a lobe
/// several levels down the chain, and the sharpest level only shows on a
/// mirror. `EnvironmentMap`'s own doc comment gives the cost as
/// O(faces × texels × taps), which at 32 is a fraction of a millisecond and
/// at 512 is not something to do while a viewport is on screen.
const int kPanoramaCubeSize = 32;

/// How many convolved levels follow the base.
const int kPanoramaCubeLevels = 4;

/// Keeps [Scene.environment] in step with [SceneLighting.panorama].
final class PanoramaSync {
  /// Which image is on the scene right now, and how long its bytes were —
  /// enough to notice a different panorama at the same index.
  int? _shownIndex;
  int? _shownLength;

  /// Whether the last [sync] actually rebuilt the cube — for a test, and for
  /// anything that wants to say what a frame cost.
  bool get rebuiltLast => _rebuiltLast;
  bool _rebuiltLast = false;

  /// Puts [project]'s own panorama on [scene], or takes one off.
  ///
  /// Silent about a panorama that will not decode: `SetPanorama` is what
  /// refuses a bad image, with the reason, and by the time a project holds
  /// an index the question has already been answered. A file that rots
  /// afterwards leaves the scene with no environment rather than with a
  /// crash.
  void sync(GraphicsDevice device, Scene scene, ModelProject project) {
    _rebuiltLast = false;
    final int? index = project.lighting.panorama;
    if (index == null || index < 0 || index >= project.images.length) {
      if (_shownIndex == null) return;
      scene
        ..environment = null
        ..environmentLevels = 0;
      _shownIndex = null;
      _shownLength = null;
      _rebuiltLast = true;
      return;
    }

    final EncodedImage image = project.images[index];
    if (_shownIndex == index && _shownLength == image.bytes.length) return;

    final ByteData? pixels = panoramaPixels(image.bytes);
    if (pixels == null) return;
    final ({int width, int height})? size = hdrSizeOf(image.bytes);
    if (size == null) return;

    final built = EnvironmentMap.fromPanorama(
      device,
      pixels,
      width: size.width,
      height: size.height,
      size: kPanoramaCubeSize,
      levels: kPanoramaCubeLevels,
    );
    if (built == null) return;
    scene
      ..environment = built.texture
      ..environmentLevels = built.levels;
    _shownIndex = index;
    _shownLength = image.bytes.length;
    _rebuiltLast = true;
  }
}

/// A Radiance file as the RGBA8 `EnvironmentMap.fromPanorama` reads, or null
/// when it is not one.
///
/// **Clamped rather than tone-mapped.** The cube is eight bits a channel —
/// `EnvironmentMap`'s own doc comment says why, and that this is a real
/// limitation — so a sun four hundred times brighter than the sky around it
/// becomes white either way. Rolling the highlights off first would darken
/// everything else to buy detail in a region the cube cannot hold anyway,
/// and would make the indirect light a panorama gives differ from the
/// indirect light the same picture gives as a PNG.
ByteData? panoramaPixels(Uint8List bytes) {
  final HdrImage image;
  try {
    image = readHdr(bytes);
  } on HdrFormatException {
    return null;
  }
  final ByteData out = ByteData(image.width * image.height * 4);
  for (var i = 0; i < image.width * image.height; i++) {
    out
      ..setUint8(i * 4, _byte(image.rgb[i * 3]))
      ..setUint8(i * 4 + 1, _byte(image.rgb[i * 3 + 1]))
      ..setUint8(i * 4 + 2, _byte(image.rgb[i * 3 + 2]))
      ..setUint8(i * 4 + 3, 255);
  }
  return out;
}

int _byte(double value) => (value * 255.0).round().clamp(0, 255);
