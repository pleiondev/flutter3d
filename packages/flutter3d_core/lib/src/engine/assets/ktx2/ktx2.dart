/// The engine's own view of a KTX2 texture: everything
/// `flutter3d_formats`'s container reader finds, plus the one thing it
/// cannot answer without a window — which `TextureFormat` a `vkFormat`
/// number is.
///
/// **This wraps `flutter3d_formats`'s `Ktx2Texture` rather than reading the
/// container itself.** `ap-01` in `doc/asset-pipeline-plan.md` moved the
/// header, the level index and the ETC1S transcoder below this package
/// because none of them need `flutter3d_hardware`'s `TextureFormat` or the
/// Flutter SDK it drags in — a modeller's document layer, an agent's `dart
/// run`, and a plain `dart test` all want to read a `.ktx2` and none of them
/// can resolve that SDK to do it. What is left here is the part that
/// genuinely does need it: `TextureFormat` itself.
///
/// **The exact same wrapping act is not new to this session.** `flutter3d`
/// already wraps `flutter3d_formats`'s `ModelDocument`, `GltfDocument` and
/// the rest for the same reason — a document layer with no window, and an
/// engine that fetches bytes and draws them. A KTX2 reader that named
/// `TextureFormat` was always the odd one out; it stayed only because
/// nothing before `ap-01` needed it to move.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart' as formats;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

export 'package:flutter3d_core/formats.dart'
    show
        Ktx2FormatException,
        Ktx2HeaderField,
        Ktx2SupercompressionScheme,
        VkFormat,
        isBasisUniversalKtx2,
        isKtx2File,
        kKtx2HeaderOffset,
        kKtx2Identifier,
        kKtx2IndexOffset,
        kKtx2LevelIndexEntryBytes,
        kKtx2LevelIndexOffset;

/// A KTX2 file, read down to what a texture upload needs: dimensions, an
/// engine [TextureFormat], and each mip level's bytes.
final class Ktx2Texture {
  const Ktx2Texture._(
    this.pixelWidth,
    this.pixelHeight,
    this.format,
    this.levels,
  );

  final int pixelWidth;
  final int pixelHeight;
  final TextureFormat format;

  /// Level 0 (the base, largest image) first.
  final List<ByteData> levels;

  /// Reads [bytes] as a KTX2 file and maps its `vkFormat` to a [TextureFormat].
  ///
  /// Throws [formats.Ktx2FormatException] rather than returning null: a
  /// caller that picked this decoder has already decided the bytes are a
  /// `.ktx2`, and a silent null would surface later as a missing texture with
  /// no reason. The container itself is `flutter3d_formats.Ktx2Texture.parse`
  /// — everything this factory adds is [_engineFormat].
  factory Ktx2Texture.parse(Uint8List bytes) {
    final texture = formats.Ktx2Texture.parse(bytes);
    final format = _engineFormat(texture.vkFormat);
    if (format == null) {
      throw formats.Ktx2FormatException(
        'Unsupported vkFormat ${texture.vkFormat}.',
      );
    }
    return Ktx2Texture._(
      texture.pixelWidth,
      texture.pixelHeight,
      format,
      texture.levels,
    );
  }
}

/// The engine format [vkFormat] means, or null for anything this stage does
/// not map.
///
/// No `default`-free exhaustiveness check is possible here the way
/// `gpu_formats_resources.dart` gets one for enum-to-enum mappings — `int` has
/// no finite set of values the analyser can enumerate — so the safety instead
/// comes from the caller: an unmapped value throws by name rather than
/// silently falling through to a wrong format.
///
/// **An sRGB `vkFormat` maps to the linear-sampling engine format with the
/// same bits**, which is a deliberate reinterpretation and not an oversight.
/// The two differ only in whether the *sampler* decodes; the payload of a
/// `BC7_SRGB` block and a `BC7_UNORM` one is identical, as it is for ETC2,
/// ASTC and RGBA8. This engine's shaders decode themselves —
/// `SrgbToLinear(texel.rgb)` in `surface.glsl`, `toLinear` in
/// `cpu_shaders_surface.dart` — for the same reason `color.glsl` says the
/// render target is a plain UNorm format: the decode belongs where the code
/// can see it, and the software rasteriser has no hardware sampler to
/// delegate it to. Handing Impeller or WebGL2 a real sRGB format decoded the
/// texture twice and drew it dark, on the two backends only, from a file the
/// third read correctly.
///
/// It also puts the decision where it belongs. Whether a texture is colour is
/// a property of the *slot*, not of the file: `surface.glsl` decodes the base
/// colour and the emissive map and leaves the normal and metallic-roughness
/// maps alone. A normal map an encoder happened to write as `BC7_SRGB` was
/// decoded anyway while the sampler made the choice.
TextureFormat? _engineFormat(int vkFormat) => switch (vkFormat) {
  formats.VkFormat.r8g8b8a8UNorm ||
  formats.VkFormat.r8g8b8a8Srgb => TextureFormat.r8g8b8a8UNormInt,
  formats.VkFormat.b8g8r8a8UNorm ||
  formats.VkFormat.b8g8r8a8Srgb => TextureFormat.b8g8r8a8UNormInt,
  formats.VkFormat.r16g16b16a16Sfloat => TextureFormat.r16g16b16a16Float,
  formats.VkFormat.r32Sfloat => TextureFormat.r32Float,
  formats.VkFormat.r32g32b32a32Sfloat => TextureFormat.r32g32b32a32Float,
  formats.VkFormat.bc1RgbaUNormBlock ||
  formats.VkFormat.bc1RgbaSrgbBlock => TextureFormat.bc1RGBAUNormInt,
  formats.VkFormat.bc3UNormBlock ||
  formats.VkFormat.bc3SrgbBlock => TextureFormat.bc3RGBAUNormInt,
  formats.VkFormat.bc5UNormBlock => TextureFormat.bc5RGUNormInt,
  formats.VkFormat.bc7UNormBlock ||
  formats.VkFormat.bc7SrgbBlock => TextureFormat.bc7RGBAUNormInt,
  formats.VkFormat.etc2R8g8b8UNormBlock ||
  formats.VkFormat.etc2R8g8b8SrgbBlock => TextureFormat.etc2RGB8UNormInt,
  formats.VkFormat.etc2R8g8b8a8UNormBlock ||
  formats.VkFormat.etc2R8g8b8a8SrgbBlock => TextureFormat.etc2RGBA8UNormInt,
  formats.VkFormat.astc4x4UNormBlock ||
  formats.VkFormat.astc4x4SrgbBlock => TextureFormat.astc4x4LDR,
  formats.VkFormat.astc8x8UNormBlock ||
  formats.VkFormat.astc8x8SrgbBlock => TextureFormat.astc8x8LDR,
  formats.VkFormat.astc4x4SfloatBlock => TextureFormat.astc4x4HDR,
  formats.VkFormat.astc8x8SfloatBlock => TextureFormat.astc8x8HDR,
  _ => null,
};
