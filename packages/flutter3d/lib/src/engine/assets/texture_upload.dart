import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'model_document.dart';

/// Decodes an encoded image (PNG, JPEG, …) and uploads it through [device].
///
/// Decoding goes through `dart:ui`, which is why this sits beside the decoders
/// rather than in the glTF layer: keeping the parser free of `dart:ui` is what
/// lets it be unit tested without a Flutter binding.
///
/// It used to live in the backend directory, because uploading needed the
/// flutter_gpu context. Nothing about decoding a PNG was ever backend-specific;
/// what was, was one call, and that call is now
/// [GraphicsDevice.createTextureFromPixels].
///
/// Two limitations of the current backend shape this, and neither is expressed
/// in the seam because neither is a decision anybody makes:
///
///  * There are no compressed pixel formats, so everything lands as RGBA8. A
///    2048² texture costs 16 MB of device memory regardless of how small its
///    PNG was.
///  * There are no mip levels, so minified surfaces alias. Nothing here can fix
///    that; it needs render-to-mip-level support.
Future<TextureHandle?> uploadEncodedImage(
  GraphicsDevice device,
  Uint8List encoded,
) async {
  if (encoded.isEmpty) return null;

  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(encoded);
  } catch (_) {
    // An unsupported or corrupt image should degrade to "no texture", not take
    // the whole model down with it.
    return null;
  }

  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    // Straight, not premultiplied: base-colour textures are sampled and then
    // multiplied by the material factor, so premultiplied alpha would darken
    // translucent texels twice.
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) return null;

    // Null when the decoder and the device disagree about how many bytes that
    // image is — which degrades to "no texture" rather than taking the whole
    // model down with it. The size the device wants is the device's to know.
    return device.createTextureFromPixels(
      width: image.width,
      height: image.height,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: data,
    );
  } finally {
    image.dispose();
  }
}

/// Maps decoded sampling settings onto the engine's sampler description.
///
/// Mip filtering is dropped: assets almost always request mipmapped
/// minification, and there are no mip levels to filter between.
SamplerOptions samplerOptionsFor(TextureSampling info) {
  SamplerAddressMode address(TextureWrap wrap) => switch (wrap) {
        TextureWrap.repeat => SamplerAddressMode.repeat,
        TextureWrap.clampToEdge => SamplerAddressMode.clampToEdge,
        TextureWrap.mirroredRepeat => SamplerAddressMode.mirror,
      };

  return SamplerOptions(
    minFilter: info.minLinear ? MinMagFilter.linear : MinMagFilter.nearest,
    magFilter: info.magLinear ? MinMagFilter.linear : MinMagFilter.nearest,
    widthAddressMode: address(info.wrapS),
    heightAddressMode: address(info.wrapT),
  );
}
