import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'ktx2/ktx2.dart';
import 'model_document.dart';

/// Decodes an encoded image (PNG, JPEG, KTX2, …) and uploads it through
/// [device].
///
/// PNG/JPEG decoding goes through `dart:ui`, which is why this sits beside the
/// decoders rather than in the glTF layer: keeping the parser free of
/// `dart:ui` is what lets it be unit tested without a Flutter binding. KTX2 is
/// sniffed and routed to [Ktx2Texture] before `dart:ui` ever sees the bytes —
/// see [_uploadKtx2].
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
/// **Compressed formats exist here now, for exactly one path.** Basis
/// Universal (`ktx2/basis_universal/`) transcodes to plain RGBA8, so it costs
/// what a PNG of the same dimensions always cost and pays for its mip chain
/// the same way. A KTX2 file's *own* block-compressed pixels — the ones that
/// would actually shrink device memory — are read correctly by
/// [Ktx2Texture.parse] but refused here rather than uploaded: no backend has
/// agreed yet what happens when one reaches it, and WebGL2's format table
/// (`webgl_formats.dart`) throws outright for one today. Wiring that in is a
/// backend-capability decision, not an asset-loading one.
///
/// **The chain is not a memory saving.** It is an aliasing fix: without it a
/// minified surface samples one texel out of every several and crawls as the
/// camera moves. Paying 33% more memory for it is the trade.
Future<TextureHandle?> uploadEncodedImage(
  GraphicsDevice device,
  Uint8List encoded, {
  TextureSampling sampling = const TextureSampling(),
}) async {
  if (encoded.isEmpty) return null;

  if (isKtx2File(encoded)) {
    return _uploadKtx2(device, sampling, encoded);
  }

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
    return _uploadRgba8(device, sampling, image.width, image.height, data);
  } finally {
    // Both halves of the decode: the frame image, and the codec it came from.
    // The codec is a native decoder instance, and leaking one per texture is
    // exactly the kind of leak the image's own dispose was added to prevent.
    image.dispose();
    codec.dispose();
  }
}

/// The tail [uploadEncodedImage] shares between a `dart:ui` decode and an
/// ETC1S transcode: both end up holding straight RGBA8 bytes and a
/// width/height at the same moment, which is exactly what [buildsMipChain]
/// and [MipChain.build] want, and a second call site building the chain
/// differently is how two loaders end up with two answers.
///
/// Null when the source and the device disagree about how many bytes that
/// image is — which degrades to "no texture" rather than taking the whole
/// model down with it. The size the device wants is the device's to know.
TextureHandle? _uploadRgba8(
  GraphicsDevice device,
  TextureSampling sampling,
  int width,
  int height,
  ByteData pixels,
) {
  final levels = buildsMipChain(device, sampling, width, height)
      ? MipChain.build(pixels, width, height)
      : null;
  return device.createTextureFromPixels(
    width: width,
    height: height,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: pixels,
    mipLevels: levels,
  );
}

/// Routes a KTX2 file to [Ktx2Texture] rather than `dart:ui`, which does not
/// read the format at all.
///
/// Two outcomes reach RGBA8 the same way a PNG does: a parse failure (a
/// feature stage 1 or 2 refuses — a mip chain, an alpha slice, a
/// supercompression scheme with no Dart decompressor) degrades to "no
/// texture" exactly like a corrupt PNG does, and a Basis Universal file
/// reaches [_uploadRgba8] once transcoded. A file that parses into one of its
/// *own* block-compressed formats is the one outcome this does not forward —
/// see the doc comment on [uploadEncodedImage] for why.
TextureHandle? _uploadKtx2(
  GraphicsDevice device,
  TextureSampling sampling,
  Uint8List encoded,
) {
  final Ktx2Texture texture;
  try {
    texture = Ktx2Texture.parse(encoded);
  } on Ktx2FormatException {
    return null;
  }

  if (texture.format != TextureFormat.r8g8b8a8UNormInt) {
    return null;
  }
  return _uploadRgba8(
    device,
    sampling,
    texture.pixelWidth,
    texture.pixelHeight,
    texture.levels.single,
  );
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
