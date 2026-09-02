import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
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
/// **A KTX2 file reaches the device in its own format when the device
/// samples it.** Basis Universal (`ktx2/basis_universal/`) transcodes to
/// plain RGBA8, so it costs what a PNG of the same dimensions always cost;
/// a file carrying BC, ETC2 or ASTC blocks is uploaded as those blocks —
/// the upload that actually shrinks device memory — after
/// [GraphicsDevice.supportsTextureFormat] has said yes, and left out with a
/// reason through [report] when it says no. Nothing is substituted: a device
/// without BC7 gets no texture rather than a guess at one, because the guess
/// would be a decoder this engine does not have.
///
/// [report] hears why an image was left out, in a sentence naming the
/// format or the feature — a refused supercompression scheme, a family the
/// device does not sample, a size that is not whole blocks. Null loses the
/// sentence, which is what every caller did before there was one to lose.
///
/// **The chain is not a memory saving.** It is an aliasing fix: without it a
/// minified surface samples one texel out of every several and crawls as the
/// camera moves. Paying 33% more memory for it is the trade. A KTX2 file
/// that carries its own chain is uploaded with it, and one that does not gets
/// a chain built here only when its pixels are plain RGBA8 — a block cannot
/// be halved on the CPU without the encoder the file already went through.
Future<TextureHandle?> uploadEncodedImage(
  GraphicsDevice device,
  Uint8List encoded, {
  TextureSampling sampling = const TextureSampling(),
  void Function(String message)? report,
}) async {
  if (encoded.isEmpty) return null;

  if (isKtx2File(encoded)) {
    return _uploadKtx2(device, sampling, encoded, report);
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
/// Four outcomes. A parse failure — a supercompression scheme with no Dart
/// decompressor, a texture array, a truncated file — is a texture left out
/// with its reason [report]ed, the same degradation a corrupt PNG gets with
/// a sentence attached. A single-level RGBA8 result, which is what a Basis
/// file without a chain transcodes to, goes through [_uploadRgba8] and earns
/// a built chain like a PNG. Anything else — a Basis file with its own chain,
/// or a file in one of the block-compressed formats — is uploaded as it is,
/// levels and all, once the device has said it samples the format; a device
/// that does not is the fourth outcome, and it is a reason, not a guess.
///
/// A transcode is a pass over every block of every level in Dart, so on a
/// platform with isolates it runs on one: a 2048² Basis texture is a quarter
/// of a million blocks, and the frame that loads it should not stall for
/// them. The web has no isolates and decodes where it stands, as the model
/// loader does. A plain file's parse is a handful of reads and stays here.
Future<TextureHandle?> _uploadKtx2(
  GraphicsDevice device,
  TextureSampling sampling,
  Uint8List encoded,
  void Function(String message)? report,
) async {
  final Ktx2Texture texture;
  try {
    texture = kIsWeb || !isBasisUniversalKtx2(encoded)
        ? Ktx2Texture.parse(encoded)
        : await Isolate.run(() => Ktx2Texture.parse(encoded));
  } on Ktx2FormatException catch (error) {
    report?.call('KTX2 file left out: ${error.message}');
    return null;
  }

  final format = texture.format;
  final levels = texture.levels;
  final width = texture.pixelWidth;
  final height = texture.pixelHeight;
  if (format == TextureFormat.r8g8b8a8UNormInt && levels.length == 1) {
    return _uploadRgba8(device, sampling, width, height, levels.single);
  }

  if (!device.supportsTextureFormat(format)) {
    report?.call(
      'KTX2 texture left out: it is ${format.name}, which this device does '
      'not sample.',
    );
    return null;
  }
  if (format.isCompressed) {
    // flutter_gpu's rule for an allocation, applied before one is attempted
    // on any backend: a block-compressed texture is whole blocks. The other
    // backends round up and would take it, but a texture that loads on two
    // backends out of three is the kind of difference this seam exists to
    // keep out.
    final block = format.blockLayout;
    if (width % block.blockWidth != 0 || height % block.blockHeight != 0) {
      report?.call(
        'KTX2 texture left out: ${width}x$height is not whole '
        '${block.blockWidth}x${block.blockHeight} blocks of ${format.name}.',
      );
      return null;
    }
  }

  final chain =
      sampling.useMipmaps && device.supportsMipmaps && levels.length > 1
      ? levels.sublist(1)
      : null;
  return device.createTextureFromPixels(
    width: width,
    height: height,
    format: format,
    pixels: levels.first,
    mipLevels: chain,
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
