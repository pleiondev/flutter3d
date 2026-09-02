/// What `GraphicsDevice.readback` may be asked for, decided in one place.
///
/// **Nothing here may import a graphics API** — `tool/structure.dart` holds it.
///
/// Three backends implement the readback and every one of them has to refuse
/// the same requests for the same reasons: tile memory holds nothing after the
/// pass, a multisampled texture has no pixels to copy until it is resolved, a
/// cube has six pictures and the interface names one, and a region past the
/// edge of the texture is a driver error on one backend and a silent short read
/// on another. Written three times those checks would drift, and the first
/// place they would drift is the message — which is the part a caller reads.
library;

import 'formats.dart';
import 'render_pass_descriptor.dart';
import 'texture.dart';

/// The region a readback of [texture] will copy, or an [ArgumentError] saying
/// why there is none.
///
/// Null [region] means the whole texture. A backend calls this first and then
/// copies exactly what comes back, so the refusal is the interface's rather
/// than a property of whichever backend happened to be running.
ScreenRect readbackRegionOf(TextureHandle texture, ScreenRect? region) {
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
