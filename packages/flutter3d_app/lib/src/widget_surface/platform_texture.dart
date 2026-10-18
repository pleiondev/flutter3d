/// A rasterised widget as a texture, by the shortest road the device has.
///
/// **The one place in `widget_surface/` that reads an image's pixels back.**
/// A device that is `PlatformTextures<ui.Image>` — Impeller, through
/// flutter_gpu's `Texture.fromImage` — wraps the image's own GPU texture and
/// nothing crosses to the host; every other device is handed the pixels
/// `toByteData` brings back, which is the round trip `WidgetTexture` and
/// `WidgetSurface` used to pay on every backend. `tool/structure.dart` holds
/// the folder to it: a file here that calls `toByteData` asks the device
/// first.
library;

import 'dart:ui' as ui;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show PlatformTextures;

/// [image] as a sampled texture of [device], or null when the image has no
/// pixels to give.
///
/// Wrapped with no copy where [device] takes platform images, and where it
/// refuses this one (an image with no GPU texture of its own yet) or takes
/// none, read back and uploaded as `r8g8b8a8UNormInt`. A wrapped texture
/// is in the image's own format, which on Metal is BGRA; a sampler reads
/// the same colour from either. The caller still owns [image] and may
/// dispose it once this completes: a wrapped texture shares the image's
/// storage and outlives it.
Future<TextureHandle?> textureFromImage(
  GraphicsDevice device,
  ui.Image image,
) async {
  if (device is PlatformTextures<ui.Image>) {
    try {
      return device.textureFromPlatformImage(image);
    } on DeviceResourceException {
      // This image, not this device: the copy below still works.
    }
  }
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (pixels == null) return null;
  return device.createTextureFromPixels(
    width: image.width,
    height: image.height,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: pixels,
  );
}
