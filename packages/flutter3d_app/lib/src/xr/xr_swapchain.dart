/// The images a runtime shows: what the engine draws a headset's frames
/// into.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// The shape of the images a session is asked for.
final class XrSwapchainRequest {
  /// Images of [width] × [height] with a layer for each of [views], in
  /// [format].
  const XrSwapchainRequest({
    required this.width,
    required this.height,
    this.views = 2,
    this.format,
  });

  /// Pixels across one view.
  final int width;

  /// Pixels down one view.
  final int height;

  /// Layers in each image: one per view of a frame.
  final int views;

  /// The images' format, which the frame's picture must share, since each
  /// view is copied in (`ProjectionLayerNode`); null for the drawing
  /// device's own color format (`GraphicsDevice.defaultColorFormat`),
  /// which `XrDriver` fills in before the session is asked.
  final TextureFormat? format;

  /// This request with [format] in place of its own.
  XrSwapchainRequest withFormat(TextureFormat format) => XrSwapchainRequest(
    width: width,
    height: height,
    views: views,
    format: format,
  );

  /// The texture each image is, as a device would make it: RGBA8 where no
  /// [format] is given.
  TextureDescriptor get descriptor => TextureDescriptor(
    width: width,
    height: height,
    format: format ?? TextureFormat.r8g8b8a8UNormInt,
    dimension: TextureDimension.d2Array,
    depthOrArrayLayers: views,
    usage: TextureUsage.renderTarget,
  );
}

/// A ring of images a runtime shows, one drawn into each frame.
///
/// **Where the runtime's memory meets the engine's device.** A runtime owns
/// its images (`XrSwapchainImageKHR`, an `XRWebGLLayer`'s framebuffer). Where
/// the device can import them (`GraphicsDevice.importTexture`, 2K's
/// `SharedTexture` path), [acquire] hands the image itself and nothing is
/// copied; where it cannot, it hands a texture of the device's own and
/// [release] copies it out through host memory. The engine writes against
/// [acquire] and [release] either way, as it writes against
/// `SharedTexture` without asking which path it took.
abstract base class XrSwapchain {
  /// A swapchain; the runtime made its images.
  XrSwapchain();

  /// The shape of each image.
  TextureDescriptor get descriptor;

  /// The image for this frame, as a texture of [device]: waits until the
  /// runtime has let go of it.
  TextureHandle acquire(GraphicsDevice device);

  /// Hands the image [acquire] gave back to the runtime, once the frame's
  /// work into it is submitted: a fence on the zero-copy path, a copy
  /// through host memory on the other.
  Future<void> release();

  /// Gives the images back to the runtime. Nothing to give by default.
  void dispose() {}
}
