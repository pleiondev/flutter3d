import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'model_document.dart';

/// Decodes an encoded image (PNG, JPEG, …) and uploads it through [device].
///
/// Decoding goes through `dart:ui`, which is why this sits beside the decoders
/// rather than in the glTF layer: keeping the parser free of `dart:ui` is what
/// lets it be unit tested without a Flutter binding.
///
/// It used to live in the backend directory, because uploading needed the
/// backend context. Nothing about decoding a PNG was ever backend-specific;
/// what was, was one call, and that call is now
/// [GraphicsDevice.createTextureFromPixels].
///
/// [sampling] decides whether a mip chain is built — see [buildsMipChain]. It
/// is the decoded glTF sampler, so an asset that asks for mipmapped
/// minification gets a chain and one that asks for a single level does not.
///
/// One limitation of the current backend still shapes this, and it is not
/// expressed in the seam because it is not a decision anybody makes: there are
/// no compressed pixel formats, so everything lands as RGBA8. A 2048² texture
/// costs 16 MB of device memory regardless of how small its PNG was, and a mip
/// chain adds a third of that again.
///
/// **The chain is not a memory saving.** It is an aliasing fix: without it a
/// minified surface samples one texel out of every several and crawls as the
/// camera moves. Paying 33% more memory for it is the trade, and the way out of
/// the trade is compressed formats, which nothing here has.
Future<TextureHandle?> uploadEncodedImage(
  GraphicsDevice device,
  Uint8List encoded, {
  TextureSampling sampling = const TextureSampling(),
}) async {
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

    // Built here, from the bytes that were just decoded, rather than anywhere
    // downstream: this is the one place in the engine that holds an image's
    // pixels and its dimensions at the same moment, and building the chain
    // elsewhere would mean decoding the PNG twice. `ModelAsset` caches by image
    // index, so each distinct image pays for its chain once.
    final levels = buildsMipChain(device, sampling, image.width, image.height)
        ? MipChain.build(data, image.width, image.height)
        : null;

    // Null when the decoder and the device disagree about how many bytes that
    // image is — which degrades to "no texture" rather than taking the whole
    // model down with it. The size the device wants is the device's to know.
    return device.createTextureFromPixels(
      width: image.width,
      height: image.height,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: data,
      mipLevels: levels,
    );
  } finally {
    image.dispose();
  }
}

/// Whether an image of this size, sampled this way, gets a mip chain.
///
/// Three conditions, and each rules out a real failure rather than a
/// hypothetical one:
///
///  * The asset has to want one. A sampler that asks for single-level
///    minification is usually a UI atlas or a lookup table, where a blended
///    lower level is wrong rather than merely soft.
///  * The device has to sample one correctly. [GraphicsDevice.supportsMipmaps]
///    is asked rather than assumed because a hand-built chain on an OpenGL ES 2
///    device without `GL_APPLE_texture_max_level` **samples as black** — not
///    blurrier, black.
///  * There has to be a level below the base. A 1×1 image has none, and asking
///    for an empty chain would allocate a texture claiming levels it has not
///    got.
///
/// Public because it is the predicate a test wants to state directly, and
/// because a caller uploading pixels it decoded itself needs the same answer.
bool buildsMipChain(
  GraphicsDevice device,
  TextureSampling sampling,
  int width,
  int height,
) =>
    sampling.useMipmaps &&
    device.supportsMipmaps &&
    MipChain.levelsFor(width, height) > 0;

/// Maps decoded sampling settings onto the engine's sampler description.
///
/// [MipFilter] is set from [TextureSampling.useMipmaps], and that pairing is
/// the whole of why this function takes the same argument the upload does: a
/// chain uploaded and then sampled with `MipFilter.nearest` — the default — is
/// memory spent on levels nothing blends between, which looks exactly like
/// having built no chain at all. The two decisions have to be made from one
/// input or they drift.
SamplerOptions samplerOptionsFor(TextureSampling info) {
  SamplerAddressMode address(TextureWrap wrap) => switch (wrap) {
    TextureWrap.repeat => SamplerAddressMode.repeat,
    TextureWrap.clampToEdge => SamplerAddressMode.clampToEdge,
    TextureWrap.mirroredRepeat => SamplerAddressMode.mirror,
  };

  return SamplerOptions(
    minFilter: info.minLinear ? MinMagFilter.linear : MinMagFilter.nearest,
    magFilter: info.magLinear ? MinMagFilter.linear : MinMagFilter.nearest,
    mipFilter: info.useMipmaps ? MipFilter.linear : MipFilter.nearest,
    widthAddressMode: address(info.wrapS),
    heightAddressMode: address(info.wrapT),
  );
}
