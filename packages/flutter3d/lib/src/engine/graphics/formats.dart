/// The engine's own vocabulary for graphics state.
///
/// **Nothing in `graphics/` may import `flutter_gpu`, ever.** That is the point
/// of the directory and it is checkable:
/// `test/graphics_is_backend_free_test.dart` reads every file here and fails if
/// one does. `gpu/` already means "the files that talk to flutter_gpu", so a
/// backend-free vocabulary could not live there without inverting that
/// meaning.
///
/// The translation to flutter_gpu lives in exactly one file —
/// `src/engine/gpu/gpu_formats.dart` — and in exactly one `switch` per enum. A
/// second translation of the same enum is how the two drift apart, and drift in
/// this particular code is invisible: a wrong mapping still compiles, still
/// runs, and renders wrong only for scenes that happen to use that value.
///
/// ## Two rules these enums are held to
///
/// **Same values, no more and no fewer.** Every enum here has exactly the
/// values `flutter_gpu` has, in the same order, under the same names. An enum
/// that is *almost* the same as the one underneath is worse than one that is
/// either identical or deliberately different, because the difference is
/// invisible at the call site. The single deliberate difference is the *type*
/// name [TextureFormat], because `dart:ui` already exports `PixelFormat` and
/// this library is imported alongside `package:flutter/material.dart` in every
/// application that uses it.
///
/// **Identical value names are load-bearing, not cosmetic.** They are what lets
/// `test/gpu_formats_test.dart` assert, for every value of every enum here,
/// that the mapping lands on the flutter_gpu value of the *same name*. A test
/// that only checked "distinct" would pass a swapped [CullMode.frontFace] /
/// [CullMode.backFace] pair, which is precisely the mistake worth catching.
///
/// When a second backend arrives, this file does not change; a second
/// translation file appears beside `gpu_formats.dart`.
library;

/// Where an allocation lives and how it may be used.
enum StorageMode {
  /// Mappable into the host's address space and usable by the device.
  hostVisible,

  /// Device-only. Optimal for the device; the host must copy through a
  /// host-visible allocation to read it.
  devicePrivate,

  /// Tile memory, for temporary render targets. Higher bandwidth, lower power,
  /// and no separate device allocation — but it cannot be copied to or from,
  /// which is what rules it out for anything a later pass reads. Textures only.
  deviceTransient,
}

/// The layout of one texel.
///
/// Named [TextureFormat] rather than `PixelFormat` because `dart:ui` exports a
/// `PixelFormat` of its own, for image data rather than for textures, and every
/// application on this engine imports both libraries. The values are
/// flutter_gpu's, unchanged.
enum TextureFormat {
  unknown,
  a8UNormInt,
  r8UNormInt,
  r8g8UNormInt,
  r8g8b8a8UNormInt,
  r8g8b8a8UNormIntSRGB,
  b8g8r8a8UNormInt,
  b8g8r8a8UNormIntSRGB,
  r32g32b32a32Float,
  r16g16b16a16Float,
  b10g10r10XR,
  b10g10r10XRSRGB,
  b10g10r10a10XR,
  // Depth and stencil formats.
  s8UInt,
  d24UnormS8Uint,
  d32FloatS8UInt,
}

/// Which corner a texture's origin is in.
enum TextureCoordinateSystem {
  /// (0, 0) is the bottom-left with +Y going up. Used when uploading texture
  /// data from the host.
  uploadFromHost,

  /// (0, 0) is the top-left with +Y going down. The default.
  renderToTexture,
}

/// One term of a blend equation.
enum BlendFactor {
  zero,
  one,
  sourceColor,
  oneMinusSourceColor,
  sourceAlpha,
  oneMinusSourceAlpha,
  destinationColor,
  oneMinusDestinationColor,
  destinationAlpha,
  oneMinusDestinationAlpha,
  sourceAlphaSaturated,
  blendColor,
  oneMinusBlendColor,
  blendAlpha,
  oneMinusBlendAlpha,
}

/// How the two blend terms are combined.
enum BlendOperation { add, subtract, reverseSubtract }

/// What happens to an attachment's existing contents when a pass begins.
///
/// [load] and [clear] are not interchangeable at the granularity a caller might
/// assume: a clear covers the **whole attachment** however the viewport and
/// scissor are set. The shadow atlas depends on that difference — it loads, and
/// blanks a tile by drawing inside it.
enum LoadAction { dontCare, load, clear }

/// What happens to an attachment's contents when a pass ends.
enum StoreAction {
  dontCare,
  store,
  multisampleResolve,
  storeAndMultisampleResolve,
}

/// Filtering between texels.
enum MinMagFilter { nearest, linear }

/// Filtering between mip levels.
///
/// Present for completeness and currently inert: this engine has no mip chain,
/// because generating one needs render-to-mip-level support that the stable
/// channel does not expose.
enum MipFilter { nearest, linear }

/// What sampling outside the 0..1 range does.
enum SamplerAddressMode { clampToEdge, repeat, mirror }

/// The width of one index.
enum IndexType { int16, int32 }

/// How vertices are assembled into primitives.
enum PrimitiveType { triangle, triangleStrip, line, lineStrip, point }

/// Which faces the rasteriser discards.
enum CullMode { none, frontFace, backFace }

/// Which winding counts as front-facing.
enum WindingOrder { clockwise, counterClockwise }

/// Whether primitives are filled or drawn as edges.
enum PolygonMode { fill, line }

/// The test a depth or stencil comparison performs.
enum CompareFunction {
  /// Never passes.
  never,

  /// Always passes.
  always,

  /// Passes if new_value < current_value.
  less,

  /// Passes if new_value == current_value.
  equal,

  /// Passes if new_value <= current_value.
  lessEqual,

  /// Passes if new_value > current_value.
  greater,

  /// Passes if new_value != current_value.
  notEqual,

  /// Passes if new_value >= current_value.
  greaterEqual,
}
