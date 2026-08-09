import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;

import '../assets/model_document.dart';

/// Decodes an encoded image (PNG, JPEG, …) and uploads it as a GPU texture.
///
/// Decoding goes through `dart:ui`, which is why it lives here rather than in
/// the glTF layer: keeping the parser free of `dart:ui` is what lets it be unit
/// tested without a Flutter binding.
///
/// Two flutter_gpu limitations shape this:
///
///  * There are no compressed pixel formats, so everything lands as RGBA8. A
///    2048² texture costs 16 MB of device memory regardless of how small its
///    PNG was.
///  * There are no mip levels, so minified surfaces alias. Nothing here can fix
///    that; it needs render-to-mip-level support.
Future<gpu.Texture?> uploadEncodedImage(Uint8List encoded) async {
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

    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      image.width,
      image.height,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
      coordinateSystem: gpu.TextureCoordinateSystem.uploadFromHost,
    );

    // overwrite() demands exactly the base mip size and throws otherwise, so a
    // mismatch here means the decoder disagreed about dimensions.
    final expected = texture.getBaseMipLevelSizeInBytes();
    if (data.lengthInBytes != expected) return null;

    texture.overwrite(data);
    return texture;
  } finally {
    image.dispose();
  }
}

/// Maps decoded sampling settings onto flutter_gpu sampler options.
///
/// Mip filtering is dropped: assets almost always request mipmapped
/// minification, and flutter_gpu has no mip levels to filter between.
gpu.SamplerOptions samplerOptionsFor(TextureSampling info) {
  gpu.SamplerAddressMode address(TextureWrap wrap) => switch (wrap) {
        TextureWrap.repeat => gpu.SamplerAddressMode.repeat,
        TextureWrap.clampToEdge => gpu.SamplerAddressMode.clampToEdge,
        TextureWrap.mirroredRepeat => gpu.SamplerAddressMode.mirror,
      };

  return gpu.SamplerOptions(
    minFilter:
        info.minLinear ? gpu.MinMagFilter.linear : gpu.MinMagFilter.nearest,
    magFilter:
        info.magLinear ? gpu.MinMagFilter.linear : gpu.MinMagFilter.nearest,
    widthAddressMode: address(info.wrapS),
    heightAddressMode: address(info.wrapT),
  );
}
