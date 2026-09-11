/// [TextureBudget] — how big a texture may be and what it should end up
/// encoded as on one export target — and [measure], which weighs a
/// project's images against one.
///
/// **A different question from `ProjectProfile`'s existing
/// `maxTextureSize`/`maxTextureBytes`.** Those two are a flat number
/// `doc-14`'s `ExportReadiness` already reads against a texture as it sits in
/// the project today. [measure] answers "how big will this be once it is
/// actually exported as [TextureBudget.targetFormat]" — the number `mat-05`'s
/// texture panel wants before anyone has run an encoder, and the one
/// `ExportReadiness` will read once `mat-22`'s still-blocked "texture over
/// budget" rule has this to read from.
///
/// **Presets are Ж5's own numbers** (`doc/model-editor-plan.md`, closed
/// 2026-09-09): desktop 2048px/256MB, mobile 1024px/64MB, web 2048px/128MB.
/// The decision closed the size and the byte figure only — which format each
/// target encodes to is this file's own choice, not the plan's: BC7 for
/// desktop (the widest-supported high-quality block format on the GPUs a
/// desktop build ships to), ASTC 4×4 for mobile (the one every GPU family
/// `mat-30`'s own encoder list serves actually carries on a phone), ETC2
/// RGBA8 for web (the one WebGL2's compressed-texture extensions can assume
/// broadly, desktop and mobile browsers alike).
library;

import 'image_dimensions.dart';
import 'project.dart';
import 'texture_info.dart';

/// A preset for how big a texture may be on one export target, and what
/// format it should end up encoded as.
final class TextureBudget {
  const TextureBudget({
    required this.maxSide,
    required this.maxBytesOnDevice,
    required this.targetFormat,
    this.requirePowerOfTwo = false,
  });

  /// The widest or tallest a single texture may be — checked against each
  /// image's own `pixelWidth`/`pixelHeight`, the per-image half of the
  /// budget. [TextureUsage.overs] is built from this.
  final int maxSide;

  /// How many bytes a project's textures may cost in total once every image
  /// is recomputed under [targetFormat] — the aggregate half, checked against
  /// [TextureUsage.totalBytes] the same way `ProjectProfile.maxTriangles` is
  /// checked against a project's summed triangle count.
  final int maxBytesOnDevice;

  final TextureFileFormat targetFormat;
  final bool requirePowerOfTwo;

  /// Ж5's desktop figures: 2048px, 256MB, BC7.
  static const TextureBudget desktop = TextureBudget(
    maxSide: 2048,
    maxBytesOnDevice: 256 * 1024 * 1024,
    targetFormat: TextureFileFormat.bc7,
  );

  /// Ж5's mobile figures: 1024px, 64MB, ASTC 4×4.
  static const TextureBudget mobile = TextureBudget(
    maxSide: 1024,
    maxBytesOnDevice: 64 * 1024 * 1024,
    targetFormat: TextureFileFormat.astc4x4,
  );

  /// Ж5's web figures: 2048px, 128MB, ETC2 RGBA8.
  static const TextureBudget web = TextureBudget(
    maxSide: 2048,
    maxBytesOnDevice: 128 * 1024 * 1024,
    targetFormat: TextureFileFormat.etc2Rgba8,
  );

  @override
  bool operator ==(Object other) =>
      other is TextureBudget &&
      other.maxSide == maxSide &&
      other.maxBytesOnDevice == maxBytesOnDevice &&
      other.targetFormat == targetFormat &&
      other.requirePowerOfTwo == requirePowerOfTwo;

  @override
  int get hashCode =>
      Object.hash(maxSide, maxBytesOnDevice, targetFormat, requirePowerOfTwo);

  @override
  String toString() =>
      'TextureBudget(${maxSide}px, ${maxBytesOnDevice}B, $targetFormat)';
}

/// What [measure] found: the project's images, recomputed under one
/// [TextureBudget].
final class TextureUsage {
  const TextureUsage({required this.totalBytes, required this.overs});

  /// The sum of every image in `project.images`, each counted once no matter
  /// how many materials sample it — `project.images` is itself the
  /// deduplicated table `mat-01`'s `AddImage` builds, so summing it directly
  /// already cannot count one picture twice — recomputed as if each were
  /// encoded to the budget's own `targetFormat` rather than left as it was
  /// read in.
  final int totalBytes;

  /// Indices into `project.images` whose own width or height is wider than
  /// the budget's `maxSide` — the per-image half; `totalBytes` against
  /// `maxBytesOnDevice` is the aggregate half, and is not folded in here for
  /// the same reason `ExportReadiness`' triangle budget is one issue rather
  /// than one per object: a project is over or it is not, but a single
  /// texture that will not even decode to the size a sampler expects is a
  /// fault of its own, worth naming by index.
  final List<int> overs;
}

/// Weighs [project]'s images against [budget]: what they would cost in total
/// if every one of them were encoded to `budget.targetFormat`, and which of
/// them are individually wider or taller than `budget.maxSide` regardless of
/// weight.
///
/// An image whose own header cannot be read (not a format [imageDimensions]
/// recognises, or truncated) contributes nothing to `totalBytes` and never
/// appears in `overs` — there is no size to measure it against, the same
/// answer `textureInfo` gives for the same bytes.
TextureUsage measure(ModelProject project, TextureBudget budget) {
  var totalBytes = 0;
  final overs = <int>[];
  for (var i = 0; i < project.images.length; i++) {
    final dimensions = imageDimensions(project.images[i].bytes);
    if (dimensions == null) continue;
    totalBytes += _bytesUnder(
      dimensions.width,
      dimensions.height,
      budget.targetFormat,
    );
    if (dimensions.width > budget.maxSide ||
        dimensions.height > budget.maxSide) {
      overs.add(i);
    }
  }
  return TextureUsage(totalBytes: totalBytes, overs: overs);
}

/// [width]×[height] recomputed as if encoded to [format]: a block-layout sum
/// for a compressed format, or four bytes a texel — the same number
/// `textureInfo` gives a plain PNG/JPEG — for [TextureFileFormat.rgba8] and
/// [TextureFileFormat.other], neither of which [blockLayoutFor] names a block
/// for. No mip chain: a source image on its way into the project has not been
/// baked with one yet, matching `textureInfo`'s own `hasOwnMips: false` for
/// the same two formats.
int _bytesUnder(int width, int height, TextureFileFormat format) {
  final layout = blockLayoutFor(format);
  if (layout == null) return width * height * 4;
  final blocksWide = (width + layout.blockWidth - 1) ~/ layout.blockWidth;
  final blocksHigh = (height + layout.blockHeight - 1) ~/ layout.blockHeight;
  return blocksWide * blocksHigh * layout.bytesPerBlock;
}
