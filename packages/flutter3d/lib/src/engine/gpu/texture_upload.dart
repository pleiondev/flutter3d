import 'dart:typed_data';
import 'dart:ui' as ui;

import '../assets/model_document.dart';
import '../graphics/formats.dart';
import '../graphics/sampler.dart';
import '../graphics/texture.dart';
import 'gpu_texture.dart';

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
Future<TextureHandle?> uploadEncodedImage(Uint8List encoded) async {
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

    final texture = createGpuTexture(
      StorageMode.hostVisible,
      image.width,
      image.height,
      format: TextureFormat.r8g8b8a8UNormInt,
      coordinateSystem: TextureCoordinateSystem.uploadFromHost,
    );

    // overwrite() demands exactly the base mip size and throws otherwise, so a
    // mismatch here means the decoder disagreed about dimensions. Bytes per
    // texel is a backend question, so this is one of the few places that
    // reaches through the handle for something other than a bind.
    final expected = texture.gpuTexture.getBaseMipLevelSizeInBytes();
    if (data.lengthInBytes != expected) return null;

    texture.gpuTexture.overwrite(data);
    return texture;
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
