/// Facts about each [TextureFormat] that hold on every device: texel size,
/// what a shader reads from it, whether it is depth, integer or sRGB.
///
/// Its own file rather than `formats.dart`, whose enums are a promise counted
/// in ARCHITECTURE.md §7.1 and mirrored from flutter_gpu; [TextureSampleKind]
/// is neither.
library;

import 'formats.dart';

/// What kind of value a [TextureFormat]'s texels hold.
enum TextureSampleKind {
  /// Read as floats in a shader: float, normalised and compressed formats.
  float,

  /// Read as signed integers; never filtered or blended.
  sint,

  /// Read as unsigned integers; never filtered or blended.
  uint,

  /// A depth value.
  depth,

  /// A stencil value only.
  stencil,
}

/// Facts about every [TextureFormat] that do not depend on a device.
///
/// **One statement, for every backend.** Before 0.9 each backend that needed
/// a texel size or "is this depth" answered it in its own switch, and those
/// switches are where a format added to the enum goes missing. Asked here,
/// a new format is described once.
extension TextureFormatInfo on TextureFormat {
  /// Bytes per texel, or zero for a compressed format (see
  /// [TextureFormatCompression.blockLayout]) and for [TextureFormat.unknown].
  int get bytesPerTexel => switch (this) {
    TextureFormat.unknown => 0,
    TextureFormat.a8UNormInt ||
    TextureFormat.r8UNormInt ||
    TextureFormat.s8UInt => 1,
    TextureFormat.r8g8UNormInt ||
    TextureFormat.r16Float ||
    TextureFormat.d16UNormInt => 2,
    TextureFormat.r8g8b8a8UNormInt ||
    TextureFormat.r8g8b8a8UNormIntSRGB ||
    TextureFormat.b8g8r8a8UNormInt ||
    TextureFormat.b8g8r8a8UNormIntSRGB ||
    TextureFormat.r8g8b8a8SNormInt ||
    TextureFormat.r8g8b8a8UInt ||
    TextureFormat.r8g8b8a8SInt ||
    TextureFormat.r16g16Float ||
    TextureFormat.r32Float ||
    TextureFormat.r32UInt ||
    TextureFormat.r32SInt ||
    TextureFormat.r10g10b10a2UNormInt ||
    TextureFormat.r11g11b10UFloat ||
    TextureFormat.r9g9b9e5UFloat ||
    TextureFormat.d24UnormS8Uint ||
    TextureFormat.d32Float => 4,
    TextureFormat.d32FloatS8UInt => 5,
    TextureFormat.r16g16b16a16Float ||
    TextureFormat.r16g16b16a16UInt ||
    TextureFormat.r16g16b16a16SInt ||
    TextureFormat.r32g32Float ||
    TextureFormat.r32g32UInt ||
    TextureFormat.r32g32SInt => 8,
    TextureFormat.r32g32b32a32Float ||
    TextureFormat.r32g32b32a32UInt ||
    TextureFormat.r32g32b32a32SInt => 16,
    _ => 0, // compressed: counted in blocks
  };

  /// What a shader reads from it.
  TextureSampleKind get sampleKind => switch (this) {
    TextureFormat.s8UInt => TextureSampleKind.stencil,
    TextureFormat.d24UnormS8Uint ||
    TextureFormat.d32FloatS8UInt ||
    TextureFormat.d16UNormInt ||
    TextureFormat.d32Float => TextureSampleKind.depth,
    TextureFormat.r8g8b8a8UInt ||
    TextureFormat.r16g16b16a16UInt ||
    TextureFormat.r32UInt ||
    TextureFormat.r32g32UInt ||
    TextureFormat.r32g32b32a32UInt => TextureSampleKind.uint,
    TextureFormat.r8g8b8a8SInt ||
    TextureFormat.r16g16b16a16SInt ||
    TextureFormat.r32SInt ||
    TextureFormat.r32g32SInt ||
    TextureFormat.r32g32b32a32SInt => TextureSampleKind.sint,
    _ => TextureSampleKind.float,
  };

  /// Whether it is a depth, stencil or depth-stencil format.
  bool get isDepthOrStencil =>
      sampleKind == TextureSampleKind.depth ||
      sampleKind == TextureSampleKind.stencil;

  /// Whether a shader reads it as integers.
  bool get isInteger =>
      sampleKind == TextureSampleKind.uint ||
      sampleKind == TextureSampleKind.sint;

  /// Whether its stored bytes are sRGB-encoded.
  bool get isSrgb => switch (this) {
    TextureFormat.r8g8b8a8UNormIntSRGB ||
    TextureFormat.b8g8r8a8UNormIntSRGB ||
    TextureFormat.bc1RGBAUNormIntSRGB ||
    TextureFormat.bc3RGBAUNormIntSRGB ||
    TextureFormat.bc7RGBAUNormIntSRGB ||
    TextureFormat.etc2RGB8UNormIntSRGB ||
    TextureFormat.etc2RGBA8UNormIntSRGB ||
    TextureFormat.astc4x4LDRSRGB ||
    TextureFormat.astc8x8LDRSRGB => true,
    _ => false,
  };

  /// Whether flutter_gpu has this value — false for
  /// [extendedTextureFormats].
  bool get isMirrored => !extendedTextureFormats.contains(this);
}

/// The two 0.9 blend capabilities a [BlendState]-shaped value can need.
///
/// For a backend's `setBlend`, as `BlendState.usesBlendColor` is for the
/// constant: one place decides which values those are.
extension BlendFactorInfo on BlendFactor {
  /// Whether this reads the fragment's second output —
  /// `DeviceFeature.dualSourceBlending`.
  bool get isDualSource => extendedBlendFactors.contains(this);
}
