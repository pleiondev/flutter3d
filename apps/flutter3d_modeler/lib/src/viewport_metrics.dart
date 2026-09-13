/// Whether a device opened for one viewport size still fits another.
///
/// Only matters where a device owns a fixed-size surface for its whole life —
/// `kFixedResolution` in `flutter3d_backend`, true for `WebGlDevice` — because
/// that is the one backend a resize or a change of screen does not already
/// reach on its own: the canvas keeps the pixels it was created with and CSS
/// stretches them to fit, which is fine until there are fewer of them than the
/// display actually has.
library;

/// True when a device opened at [lastWidth]x[lastHeight] and
/// [lastDevicePixelRatio] should be closed and reopened for a viewport that
/// now measures [width]x[height] at [devicePixelRatio].
///
/// Shrinking is not itself a reason: the surface still has the room, and
/// presenting scales whatever was rendered to fill however much of it is
/// asked for. Growing past what was allocated, or the pixel ratio changing —
/// a window dragged from a retina screen to one that is not, or back — both
/// mean the picture drawn from here on would be upscaled from fewer pixels
/// than the display now has.
bool deviceStaleForViewport({
  required int lastWidth,
  required int lastHeight,
  required double lastDevicePixelRatio,
  required int width,
  required int height,
  required double devicePixelRatio,
}) =>
    devicePixelRatio != lastDevicePixelRatio ||
    width > lastWidth ||
    height > lastHeight;
