/// Images the platform already holds on the GPU, handed to a device as
/// textures without a trip through host memory.
///
/// **The platform's image is a type parameter, because this layer may not
/// name it.** On Flutter it is `dart:ui`'s `Image` — what a `RepaintBoundary`
/// rasterises a widget into — and a backend that can wrap one says so with
/// `with PlatformTextures<ui.Image>`; the caller asks with
/// `device is PlatformTextures<ui.Image>`, the `EncodedImageUpload` pattern.
/// The HAL stays free of Flutter and the question stays typed.
///
/// **Every member has a refusing body**, so a backend that mixes this in
/// overrides what it can and refuses the rest, and a member a minor adds
/// (a video frame, a camera image) breaks no backend written against this
/// one: an old backend inherits the refusal.
library;

import 'graphics_device.dart';
import 'texture.dart';

/// A device that can take a platform image of type [I] as a texture it
/// samples, with no copy through the host.
///
/// Optional, and asked with `is`: a device that is not one is still a whole
/// [GraphicsDevice], and its caller reads the image's pixels back and calls
/// [GraphicsDevice.createTextureFromPixels], as it always did. The Impeller
/// backend is one, for `dart:ui`'s `Image`.
base mixin PlatformTextures<I extends Object> on GraphicsDevice {
  /// [image] as a sampled `TextureHandle` of this device, sharing the
  /// image's own GPU storage rather than copying it.
  ///
  /// The texture stays valid while either it or [image] is alive, so the
  /// caller may dispose [image] once this returns; it is released with
  /// [GraphicsDevice.releaseTexture] like any other. It is for sampling: it
  /// is not promised to be usable as an attachment or a copy destination.
  ///
  /// **Throws a `DeviceResourceException` when this image cannot be
  /// wrapped** — by default always, and on a backend that overrides this
  /// for an image that has no GPU texture of its own yet (an image from
  /// `toImageSync`) or one in a format the device does not sample. The
  /// caller catches it and takes the copy through the host instead.
  TextureHandle textureFromPlatformImage(I image, {String? label}) =>
      throw refuseResource(
        'textureFromPlatformImage',
        'this device wraps no platform image; read its pixels back and call '
            'createTextureFromPixels',
      );
}
