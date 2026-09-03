/// What `GraphicsDevice.readback` may be asked for, decided in one place.
///
/// **Nothing here may import a graphics API** — `tool/structure.dart` holds it.
///
/// Three backends implement the readback and every one of them has to refuse
/// the same requests for the same reasons: tile memory holds nothing after the
/// pass, a multisampled texture has no pixels to copy until it is resolved, a
/// cube has six pictures and the interface names one, a region past the edge
/// of the texture is a driver error on one backend and a silent short read on
/// another, and a texture that is not eight-bit RGBA has no bytes of the shape
/// the contract promises. Written three times those checks would drift, and
/// the first place they would drift is the message — which is the part a
/// caller reads.
library;

import 'formats.dart';
import 'render_pass_descriptor.dart';
import 'texture.dart';

/// The formats a readback hands back as they are: four bytes per pixel, one
/// per channel, which is what `GraphicsDevice.readback` promises.
///
/// **Any other format is refused rather than converted, and the refusal is
/// what keeps three backends answering alike.** Asked for a half-float target
/// — the engine's own HDR colour — WebGL2's `readPixels(RGBA, UNSIGNED_BYTE)`
/// is an `INVALID_OPERATION` that leaves the pack buffer at the zeros it was
/// made with, so the future completes successfully with a black picture;
/// flutter_gpu would convert through `toByteData` and answer with the picture;
/// the software rasteriser would clamp its floats and answer with a third
/// thing. A caller with a float texture reads it back through `readPixels`,
/// which is allowed to be slow, or draws it into an eight-bit target first,
/// which is what the luminance pass does.
///
/// **Two layouts and not four**, which is the same argument applied a second
/// time. The sRGB twins were in here on the grounds that they are eight bits
/// per channel too, and that is the wrong test: the question is whether three
/// backends hand back the same *bytes*, and for an sRGB texture nothing said
/// they would. flutter_gpu reads through `asImage().toByteData(rawRgba)`,
/// which is entitled to hand back the linear values the encoding stands for;
/// WebGL2's `readPixels` hands back the encoded bytes as they sit; the
/// software rasteriser rounds its own linear floats. Nothing in this
/// repository asked — every readback target the engine declares is
/// `r8g8b8a8UNormInt` — so a format admitted here was a promise no check ever
/// made and no caller ever tested. BGRA stays because it is the default colour
/// format of a backend that has one, and because a swizzle is a layout rather
/// than a conversion: the same four bytes in a different order.
const Set<TextureFormat> readbackFormats = <TextureFormat>{
  TextureFormat.r8g8b8a8UNormInt,
  TextureFormat.b8g8r8a8UNormInt,
};

/// The sRGB twins of [readbackFormats], refused with a reason of their own.
///
/// A separate message because the caller's next move is different: a caller
/// with a half-float target has to draw it into an eight-bit one, and a caller
/// with an sRGB target has the bytes already and only needs a view of the same
/// texture in the `UNormInt` layout — a different mistake and a different fix,
/// which the one message could not say.
const Set<TextureFormat> _srgbReadbackFormats = <TextureFormat>{
  TextureFormat.r8g8b8a8UNormIntSRGB,
  TextureFormat.b8g8r8a8UNormIntSRGB,
};

/// The region a readback of [texture] will copy, or an [ArgumentError] saying
/// why there is none.
///
/// Null [region] means the whole texture. A backend calls this first and then
/// copies exactly what comes back, so the refusal is the interface's rather
/// than a property of whichever backend happened to be running.
ScreenRect readbackRegionOf(TextureHandle texture, ScreenRect? region) {
  if (_srgbReadbackFormats.contains(texture.format)) {
    throw ArgumentError.value(
      texture,
      'texture',
      'is ${texture.format.name}, and a readback of an sRGB texture is not '
          'the same bytes on every backend: one hands back what is stored and '
          'another is entitled to decode it to linear on the way out. Read '
          'the texture back through its r8g8b8a8UNormInt or b8g8r8a8UNormInt '
          'layout, and decode the bytes yourself if that is what you want',
    );
  }
  if (!readbackFormats.contains(texture.format)) {
    throw ArgumentError.value(
      texture,
      'texture',
      'is ${texture.format.name}, and a readback hands back eight-bit RGBA — '
          'on one backend a readPixels of a float target is an error that '
          'leaves zeros, on another a conversion, and those are not the same '
          'answer. Read back an r8g8b8a8UNormInt or b8g8r8a8UNormInt '
          'texture, or draw this one into such a target first',
    );
  }
  if (texture.storageMode == StorageMode.deviceTransient) {
    throw ArgumentError.value(
      texture,
      'texture',
      'lives in tile memory (deviceTransient), which holds nothing once the '
          'pass that wrote it has ended. Read back a devicePrivate or '
          'hostVisible texture',
    );
  }
  if (texture.sampleCount != 1) {
    throw ArgumentError.value(
      texture,
      'texture',
      'is multisampled (x${texture.sampleCount}) and has no pixels to copy '
          'until a pass resolves it. Read back the resolve target',
    );
  }
  if (texture.type != TextureType.texture2D) {
    throw ArgumentError.value(
      texture,
      'texture',
      'is a ${texture.type.name}, and a readback reads one picture. Only a '
          'texture2D can be read back',
    );
  }
  final resolved = region ?? ScreenRect.of(texture);
  if (resolved.width <= 0 ||
      resolved.height <= 0 ||
      resolved.x < 0 ||
      resolved.y < 0 ||
      resolved.x + resolved.width > texture.width ||
      resolved.y + resolved.height > texture.height) {
    throw ArgumentError.value(
      resolved,
      'region',
      'does not lie inside the ${texture.width}x${texture.height} texture',
    );
  }
  return resolved;
}
