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
  r32Float,
  // Depth and stencil formats.
  s8UInt,
  d24UnormS8Uint,
  d32FloatS8UInt,
  // Block-compressed formats. Sample-only everywhere: they cannot be render
  // targets, shader-writable, or multisampled, and hardware support varies by
  // family.
  //
  // **No pass in this engine allocates one**, and by the rule in
  // `command_encoder.dart` a member with no user would be absent. That rule
  // governs *methods* — an interface member is a guess about a backend. This
  // enum is governed by the opposite rule, three paragraphs up: mirror
  // flutter_gpu value for value. The two are not in conflict because they are
  // about different things. A partial mirror would break the property the
  // mapping tests actually check — that a value lands on the flutter_gpu value
  // of the same name — and would put the backends' `switch` statements one
  // silent step away from mapping the wrong texel layout.
  bc1RGBAUNormInt,
  bc1RGBAUNormIntSRGB,
  bc3RGBAUNormInt,
  bc3RGBAUNormIntSRGB,
  bc5RGUNormInt,
  bc7RGBAUNormInt,
  bc7RGBAUNormIntSRGB,
  etc2RGB8UNormInt,
  etc2RGB8UNormIntSRGB,
  etc2RGBA8UNormInt,
  etc2RGBA8UNormIntSRGB,
  astc4x4LDR,
  astc4x4LDRSRGB,
  astc8x8LDR,
  astc8x8LDRSRGB,
  astc4x4HDR,
  astc8x8HDR,
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

/// What a backend's clip space maps depth onto.
///
/// Metal and Vulkan put the near plane at 0 and the far plane at 1. OpenGL puts
/// them at -1 and 1, and WebGL2 has no way to change that — `glClipControl` is
/// not exposed there.
///
/// Not a detail that can be papered over. A projection built for one and fed to
/// the other does not error: with an OpenGL matrix on Metal roughly half the
/// view volume lands behind the near plane and the model looks eaten; the other
/// way round everything still draws, in the correct order, using half the depth
/// buffer — so it costs precision and shows up as z-fighting on surfaces that
/// were fine on the other backend. The second is worse to diagnose, because
/// nothing looks wrong until something does.
enum DepthRange {
  /// Near at 0, far at 1. Metal, Vulkan, Impeller.
  zeroToOne,

  /// Near at -1, far at 1. OpenGL, WebGL.
  negativeOneToOne,
}

/// Where a render target's first row of pixels is.
///
/// Metal and Impeller put it at the top left; OpenGL and WebGL put it at the
/// bottom left, and there is no switch for that.
///
/// It matters wherever the engine *reads back* what it drew rather than only
/// showing it. A backend can hide the difference when it presents a frame, and
/// cannot when a shader samples a texture the engine rendered: a shadow map is
/// sampled through a matrix, and the matrix has to agree with which end of the
/// texture row zero is.
enum FramebufferOrigin { topLeft, bottomLeft }
