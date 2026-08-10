/// What the renderer needs from a backend, over and above what a pass does.
library;

import 'dart:ui' as ui;

import '../graphics/graphics_device.dart';
import '../graphics/texture.dart';

/// A [GraphicsDevice] that can also hand Flutter the finished frame.
///
/// Two names rather than one, and the reason is a rule worth keeping:
/// `graphics/` may not import `dart:ui`, because `dart:ui` exports a
/// `PixelFormat` of its own and the directory is meant to be the engine's
/// vocabulary and nothing else. Turning the last texture into a `ui.Image` is
/// not a drawing operation and no pass ever wants it — only `Renderer.render`
/// does, at the very end, to produce `FrameResult.image`.
///
/// So [GraphicsDevice] is what travels: it is what `NodeFrame` and
/// `ContributorFrame` carry, and it is all an extension is offered. This is the
/// wider type, named once, at `Renderer.create`.
abstract interface class RenderBackend implements GraphicsDevice {
  /// The texture as a Flutter image.
  ///
  /// Also the engine's only readback path: there is no buffer readback in
  /// flutter_gpu at all, so anything that wants to *look* at what a pass wrote
  /// goes through `ui.Image.toByteData`. The MRT probe is the one caller.
  ui.Image imageOf(TextureHandle texture);
}
