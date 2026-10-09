import 'dart:typed_data';

// `Ktx2Texture` hidden: this package's own thin wrapper of the same name,
// imported below from `ktx2/ktx2.dart`, is the one that maps to a
// `TextureFormat` — see that file's doc comment for why the two exist.
import 'package:flutter3d_core/formats.dart' hide Ktx2Texture;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../platform/background.dart';
import 'image_decoder.dart';
import 'ktx2/ktx2.dart';

export 'image_decoder.dart';

/// Whether this build has no isolates in it — see `model_loader.dart`'s own
/// copy of this constant for why it replaces `kIsWeb` here (mcp-03n).
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// The cap [uploadEncodedImage] decodes [device]'s images to: [maxDimension]
/// when one is given, and never more than the device's own largest 2D
/// texture.
///
/// **Per call, since 1.0.** The process-wide `maxDecodedTextureDimension`
/// went with the other global settings (API review A.4): an engine that
/// loads for a phone passes the cap down from its own settings, and a second
/// engine in the same isolate is not capped by the first's.
int textureDecodeCap(GraphicsDevice device, {int? maxDimension}) {
  final limit = device.limits.maxTextureDimension2D;
  final asked = maxDimension;
  return asked == null || asked > limit ? limit : asked;
}

/// [image] scaled down to fit [maxDimension] on its longer side, keeping its
/// aspect ([cappedImageSize]), or [image] itself when it already fits.
///
/// An area average: each output texel is the mean of the source texels its
/// footprint covers, which is the filter a mip level is built with and the
/// one that does not alias a fine pattern into a coarse one. The fallback for
/// a decoder that could not scale while decoding — the browser and the
/// native codec both do, and never reach this with a large image.
Rgba8Image fitRgba8Image(Rgba8Image image, {required int maxDimension}) {
  final target = cappedImageSize(
    image.width,
    image.height,
    maxDimension: maxDimension,
  );
  final sw = image.width;
  final sh = image.height;
  final dw = target.width;
  final dh = target.height;
  if (dw == sw && dh == sh) return image;
  final src = image.pixels;
  final out = Uint8List(dw * dh * 4);
  for (var y = 0; y < dh; y++) {
    final y0 = y * sh ~/ dh;
    final y1 = ((y + 1) * sh ~/ dh).clamp(y0 + 1, sh);
    for (var x = 0; x < dw; x++) {
      final x0 = x * sw ~/ dw;
      final x1 = ((x + 1) * sw ~/ dw).clamp(x0 + 1, sw);
      var r = 0, g = 0, b = 0, a = 0;
      for (var sy = y0; sy < y1; sy++) {
        var i = (sy * sw + x0) * 4;
        for (var sx = x0; sx < x1; sx++, i += 4) {
          r += src[i];
          g += src[i + 1];
          b += src[i + 2];
          a += src[i + 3];
        }
      }
      final n = (y1 - y0) * (x1 - x0);
      final half = n >> 1;
      final o = (y * dw + x) * 4;
      out[o] = (r + half) ~/ n;
      out[o + 1] = (g + half) ~/ n;
      out[o + 2] = (b + half) ~/ n;
      out[o + 3] = (a + half) ~/ n;
    }
  }
  return Rgba8Image(width: dw, height: dh, pixels: out);
}

/// Decodes an encoded image (PNG, JPEG, KTX2, …) and uploads it through
/// [device].
///
/// **[decodeImage] is required, and asks nothing about how.** PNG/JPEG
/// decoding used to go straight through `dart:ui`, here in this file — which
/// is exactly the one call that could not survive mcp-03n's split, since a
/// flat package cannot name `dart:ui` and stay flat. `flutter3d`'s own
/// `defaultImageDecoder` supplies it for every existing caller reaching this
/// through `ModelAsset.fromDocument` or `bindMaterial`; a `dart run` caller
/// with no Flutter SDK passes one of its own. KTX2 is sniffed and routed to
/// [Ktx2Texture] before [decodeImage] ever sees the bytes — see
/// [_uploadKtx2] — so a headless caller with no PNG decoder at all can still
/// upload every KTX2 asset a build ships.
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
/// samples it.** Basis Universal (`flutter3d_formats`'s
/// `ktx2/basis_universal/`) transcodes to plain RGBA8, so it costs what a
/// PNG of the same dimensions always cost;
/// a file carrying BC, ETC2 or ASTC blocks is uploaded as those blocks —
/// the upload that actually shrinks device memory — after
/// [GraphicsDevice.textureFormatSupport] has said yes, and left out with a
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
///
/// **On the web the browser decodes it — `A4.16`.** A device that is an
/// [EncodedImageUpload] (WebGL2 and WebGPU) is handed the encoded bytes
/// first: the browser's decoder runs off the main thread, the pixels go
/// straight into the texture without passing through Dart, and the chain is
/// built on the GPU. [decodeImage] is the fallback for a file the browser
/// refuses. [platformDecode] false skips the device and always decodes with
/// [decodeImage] — for a caller whose decoder is the point, such as a test
/// that wants the same bytes on every backend.
///
/// **[maxDimension] caps the size at decode — `A4.17`.** An image whose longer
/// side is larger is scaled down while it is decoded, keeping its aspect: by
/// the browser's resize options on the web, by `dart:ui`'s target size
/// through a [SizedImageDecoder], and on the CPU ([fitRgba8Image]) for a
/// decoder that cannot. Null takes [maxDecodedTextureDimension]; either way
/// the device's own largest texture is the ceiling ([textureDecodeCap]). A
/// KTX2 file is not rescaled — its blocks were encoded at their size — but
/// one that carries a chain starts at the first level that fits.
Future<TextureHandle?> uploadEncodedImage(
  GraphicsDevice device,
  Uint8List encoded, {
  required ImageDecoder decodeImage,
  TextureSampling sampling = const TextureSampling(),
  void Function(String message)? report,
  int? maxDimension,
  bool platformDecode = true,
}) async {
  if (encoded.isEmpty) return null;
  final cap = textureDecodeCap(device, maxDimension: maxDimension);

  if (isKtx2File(encoded)) {
    return _uploadKtx2(device, sampling, encoded, report, cap);
  }

  if (platformDecode && device is EncodedImageUpload) {
    try {
      final uploaded = await device.decodeTexture(
        encoded,
        mipmaps:
            sampling.useMipmaps &&
            device.features.has(DeviceFeature.manualMipmaps),
        maxDimension: cap,
      );
      if (uploaded != null) return uploaded;
    } catch (_) {
      // The browser's refusal is a fallback, like its null: the CPU decoder
      // below may read what it would not.
    }
  }

  final Rgba8Image? decoded;
  try {
    decoded = decodeImage is SizedImageDecoder
        ? await decodeImage(encoded, maxDimension: cap)
        : await decodeImage(encoded);
  } catch (_) {
    // An unsupported or corrupt image should degrade to "no texture", not take
    // the whole model down with it.
    return null;
  }
  if (decoded == null) return null;
  // A decoder that ignored the cap is held to it here.
  final image = fitRgba8Image(decoded, maxDimension: cap);

  // Built here, from the bytes that were just decoded, rather than anywhere
  // downstream: this is the one place in the engine that holds an image's
  // pixels and its dimensions at the same moment, and building the chain
  // elsewhere would mean decoding the PNG twice. `ModelAsset` caches by image
  // index, so each distinct image pays for its chain once.
  return _uploadRgba8(
    device,
    sampling,
    image.width,
    image.height,
    ByteData.sublistView(image.pixels),
  );
}

/// [image] uploaded through [device], with a mip chain when [sampling] asks
/// for one — [uploadEncodedImage]'s own tail, for pixels that never were an
/// encoded file: a map packed from several (`packed_maps.dart`).
TextureHandle? uploadRgba8(
  GraphicsDevice device,
  Rgba8Image image, {
  TextureSampling sampling = const TextureSampling(),
}) => _uploadRgba8(
  device,
  sampling,
  image.width,
  image.height,
  ByteData.sublistView(image.pixels),
);

/// The tail [uploadEncodedImage] shares between a [decodeImage] result and an
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
  // The device refuses with a `DeviceResourceException` since 1.0; a loader
  // keeps its rule that one texture costs a texture, not the model.
  try {
    return device.createTextureFromPixels(
      width: width,
      height: height,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: pixels,
      mipLevels: levels,
    );
  } on DeviceResourceException {
    return null;
  }
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
///
/// **A universal-block file is the fifth outcome — `gfx-83n`.** It is one
/// cooked asset for every device family, so which GPU format it becomes is
/// decided here, from what this device says it samples, and carried into the
/// transcode.
Future<TextureHandle?> _uploadKtx2(
  GraphicsDevice device,
  TextureSampling sampling,
  Uint8List encoded,
  void Function(String message)? report,
  int cap,
) async {
  final Ktx2Texture texture;
  try {
    // **A universal-block file needs its target chosen here — `gfx-83n`.**
    // The block layout is device-agnostic on purpose, so the one thing it
    // cannot carry is which GPU format it becomes; that comes from the
    // device, and the device is not reachable from the isolate the transcode
    // runs on.
    final universal = universalBlockFormat(encoded);
    final UniversalTarget? universalTarget;
    if (universal != null) {
      universalTarget = chooseUniversalTarget(
        device,
        hasAlpha: universal.hasAlpha,
      );
      if (universalTarget == null) {
        report?.call(
          'KTX2 texture left out: it holds universal blocks with alpha, and '
          'this device samples no format that carries it.',
        );
        return null;
      }
    } else {
      universalTarget = null;
    }

    texture = _isWeb || !isBasisUniversalKtx2(encoded)
        ? Ktx2Texture.parse(encoded, universalTarget: universalTarget)
        : await runInBackground(
            () => Ktx2Texture.parse(encoded, universalTarget: universalTarget),
          );
  } on Ktx2FormatException catch (error) {
    report?.call('KTX2 file left out: ${error.message}');
    return null;
  }

  final format = texture.format;
  // A file with a chain starts at its first level that fits the cap — the
  // one rescale a block format allows, since each level was encoded at its
  // own size. A single level larger than the cap is uploaded as it is.
  final skip = _levelsAboveCap(
    texture.pixelWidth,
    texture.pixelHeight,
    texture.levels.length,
    cap,
  );
  final levels = skip == 0 ? texture.levels : texture.levels.sublist(skip);
  final width = _halved(texture.pixelWidth, skip);
  final height = _halved(texture.pixelHeight, skip);
  if (format == TextureFormat.r8g8b8a8UNormInt && levels.length == 1) {
    return _uploadRgba8(device, sampling, width, height, levels.single);
  }

  if (!device.textureFormatSupport(format).sampled) {
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
      sampling.useMipmaps &&
          device.features.has(DeviceFeature.manualMipmaps) &&
          levels.length > 1
      ? levels.sublist(1)
      : null;
  try {
    return device.createTextureFromPixels(
      width: width,
      height: height,
      format: format,
      pixels: levels.first,
      mipLevels: chain,
    );
  } on DeviceResourceException catch (refused) {
    report?.call('KTX2 texture left out: ${refused.reason}.');
    return null;
  }
}

/// How many leading levels of a [levelCount]-level chain on a [width] by
/// [height] base are larger than [cap] — never all of them.
int _levelsAboveCap(int width, int height, int levelCount, int cap) {
  var skip = 0;
  while (skip < levelCount - 1 &&
      (_halved(width, skip) > cap || _halved(height, skip) > cap)) {
    skip++;
  }
  return skip;
}

/// [size] at mip level [level].
int _halved(int size, int level) {
  final halved = size >> level;
  return halved < 1 ? 1 : halved;
}

/// Whether an image of this size, sampled this way, gets a mip chain.
///
/// Three conditions, and each rules out a real failure rather than a
/// hypothetical one:
///
///  * The asset has to want one. A sampler that asks for single-level
///    minification is usually a UI atlas or a lookup table, where a blended
///    lower level is wrong rather than merely soft.
///  * The device has to sample one correctly. [DeviceFeature.manualMipmaps]
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
    device.features.has(DeviceFeature.manualMipmaps) &&
    MipChain.levelsFor(width, height) > 0;

/// Maps decoded sampling settings onto the engine's sampler description.
///
/// [MipFilter] is set from [TextureSampling.useMipmaps], and that pairing is
/// the whole of why this function takes the same argument the upload does: a
/// chain uploaded and then sampled with `MipFilter.nearest` — the default — is
/// memory spent on levels nothing blends between, which looks exactly like
/// having built no chain at all. The two decisions have to be made from one
/// input or they drift.
SamplerDescriptor samplerOptionsFor(TextureSampling info) {
  SamplerAddressMode address(TextureWrap wrap) => switch (wrap) {
    TextureWrap.repeat => SamplerAddressMode.repeat,
    TextureWrap.clampToEdge => SamplerAddressMode.clampToEdge,
    TextureWrap.mirroredRepeat => SamplerAddressMode.mirror,
  };

  return SamplerDescriptor(
    minFilter: info.minLinear ? MinMagFilter.linear : MinMagFilter.nearest,
    magFilter: info.magLinear ? MinMagFilter.linear : MinMagFilter.nearest,
    mipFilter: info.useMipmaps ? MipFilter.linear : MipFilter.nearest,
    widthAddressMode: address(info.wrapS),
    heightAddressMode: address(info.wrapT),
  );
}
