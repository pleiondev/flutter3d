/// The engine's own vocabulary for graphics state.
///
/// **Nothing here may import a graphics API, ever.** That is the point of the
/// package and it is checkable: `tool/structure.dart` reads every file and
/// fails if one does.
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

/// What shape a texture is.
///
/// Names and order follow flutter_gpu's own `TextureType` value for value, for
/// the reason the library docstring gives: `gpu_formats_test.dart` checks that
/// each maps onto the value of the same name, and a test that only checked
/// "distinct" would pass a swapped pair.
///
/// Only two of these are reachable through this package today.
/// [texture2DMultisample] is expressed by `sampleCount` on the handle rather
/// than by this, and [textureExternalOES] has no call site at all — both are
/// here because the enums must line up one for one, which is what the test
/// asserts and what makes the mapping worth trusting.
enum TextureType {
  texture2D,
  texture2DMultisample,

  /// Six square faces, sampled by direction rather than by coordinate. What a
  /// sky, an environment map or a point-light shadow is drawn into.
  textureCube,

  textureExternalOES,
}

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
  // No asset the engine's own three games ship allocates one of these yet —
  // KTX2 is a decoder for other tools' output, not something
  // `tool/convert_asset.dart` produces — but every backend now has an answer
  // for one that arrives: Impeller allocates them (`gpu_device.dart`), WebGL2
  // uploads what its context's extensions allow and names what they do not
  // (`webgl_formats.dart`), and the software rasteriser refuses by name
  // (`cpu_device.dart`) because it samples raw texels and always will. See
  // [TextureFormatCompression.isCompressed], which every backend now reads
  // instead of re-listing this exact tail of the enum for itself.
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

/// Whether a [TextureFormat] carries an eight-bit stencil beside its depth.
///
/// Asked by a backend when it opens a pass: a stencil test against an
/// attachment that has no stencil is specified to pass always on GL and to be
/// an invalid descriptor on Metal, and neither answer is what a caller who
/// configured one meant. Every depth format this engine names carries one,
/// which is why nothing above the backends has ever had to ask.
extension TextureFormatStencil on TextureFormat {
  bool get hasStencil => switch (this) {
    TextureFormat.s8UInt ||
    TextureFormat.d24UnormS8Uint ||
    TextureFormat.d32FloatS8UInt => true,
    _ => false,
  };
}

/// The block footprint and byte cost of a compressed [TextureFormat] —
/// [blockWidth] by [blockHeight] pixels, [bytesPerBlock] bytes, however many
/// channels or bits per channel the format packs into that block.
///
/// Not derived from flutter_gpu's own `PixelFormatProperties` — that lives
/// behind `flutter_gpu.dart`, which `flutter3d_hardware` may never import —
/// so this is a second, independent statement of the same numbers.
/// `flutter3d_impeller/test/gpu_formats_test.dart` checks the two against
/// each other for every value; a second implementation that only ever agrees
/// with the first is worth less than the discrepancy it exists to catch.
final class TextureBlockLayout {
  const TextureBlockLayout(
    this.blockWidth,
    this.blockHeight,
    this.bytesPerBlock,
  );

  final int blockWidth;
  final int blockHeight;
  final int bytesPerBlock;
}

/// Whether a [TextureFormat] is stored in fixed-size blocks rather than one
/// value per texel, and — for the formats where it is — how big those blocks
/// are.
extension TextureFormatCompression on TextureFormat {
  /// Sample-only everywhere: cannot be a render target, cannot be written by
  /// a shader, cannot be multisampled. See the doc comment on the enum's
  /// block-compressed tail for what every backend does with one instead.
  bool get isCompressed => switch (this) {
    TextureFormat.bc1RGBAUNormInt ||
    TextureFormat.bc1RGBAUNormIntSRGB ||
    TextureFormat.bc3RGBAUNormInt ||
    TextureFormat.bc3RGBAUNormIntSRGB ||
    TextureFormat.bc5RGUNormInt ||
    TextureFormat.bc7RGBAUNormInt ||
    TextureFormat.bc7RGBAUNormIntSRGB ||
    TextureFormat.etc2RGB8UNormInt ||
    TextureFormat.etc2RGB8UNormIntSRGB ||
    TextureFormat.etc2RGBA8UNormInt ||
    TextureFormat.etc2RGBA8UNormIntSRGB ||
    TextureFormat.astc4x4LDR ||
    TextureFormat.astc4x4LDRSRGB ||
    TextureFormat.astc8x8LDR ||
    TextureFormat.astc8x8LDRSRGB ||
    TextureFormat.astc4x4HDR ||
    TextureFormat.astc8x8HDR => true,
    _ => false,
  };

  /// The block this format is stored in.
  ///
  /// Throws for a format [isCompressed] says is false: answering with a made-up
  /// 1x1 block would let block-rounded arithmetic run silently on a format that
  /// was never meant to need it, which is exactly the kind of "compiles, runs,
  /// wrong only for the value that hits it" mistake this file's own library
  /// comment warns about.
  TextureBlockLayout get blockLayout => switch (this) {
    TextureFormat.bc1RGBAUNormInt ||
    TextureFormat.bc1RGBAUNormIntSRGB ||
    TextureFormat.etc2RGB8UNormInt ||
    TextureFormat.etc2RGB8UNormIntSRGB => const TextureBlockLayout(4, 4, 8),
    TextureFormat.bc3RGBAUNormInt ||
    TextureFormat.bc3RGBAUNormIntSRGB ||
    TextureFormat.bc5RGUNormInt ||
    TextureFormat.bc7RGBAUNormInt ||
    TextureFormat.bc7RGBAUNormIntSRGB ||
    TextureFormat.etc2RGBA8UNormInt ||
    TextureFormat.etc2RGBA8UNormIntSRGB ||
    TextureFormat.astc4x4LDR ||
    TextureFormat.astc4x4LDRSRGB ||
    TextureFormat.astc4x4HDR => const TextureBlockLayout(4, 4, 16),
    TextureFormat.astc8x8LDR ||
    TextureFormat.astc8x8LDRSRGB ||
    TextureFormat.astc8x8HDR => const TextureBlockLayout(8, 8, 16),
    _ => throw StateError(
      'TextureFormat.$name is not compressed; it has no block layout.',
    ),
  };
}

/// One term of a blend equation.
///
/// **The last four read a blend constant this interface has no way to set**, and
/// they are the one dead corner of these enums. [blendColor],
/// [oneMinusBlendColor], [blendAlpha] and [oneMinusBlendAlpha] all multiply by
/// a colour a caller would set with something like `setBlendColor` —
/// `PassEncoder` has no such member, because no pass in this engine has ever
/// wanted one, and this file's own rule is that the values mirror flutter_gpu's
/// one for one rather than being pruned to what is reachable.
///
/// So they are here and they cannot be used, and the three backends disagree
/// about what that means: the software rasteriser throws an [UnsupportedError]
/// naming the reason, WebGL2 maps them to `CONSTANT_COLOR` and friends against
/// a constant nobody ever set — which GL defines as transparent black, so the
/// term silently evaluates to zero — and Impeller hands them to flutter_gpu,
/// whose own default is the same. Two of the three therefore draw a plausible
/// picture with a term missing from it.
///
/// A `BlendState` built from one of these is a mistake in every case today.
/// Adding the setter, or refusing them in all three backends, are both real
/// answers; what is not an answer is the current arrangement, and it is written
/// down here so a fourth backend does not have to work out which of the three
/// to copy.
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
/// Meaningful only on a texture that *has* a chain — see
/// `GraphicsDevice.createTextureFromPixels`, whose `mipLevels` is the only way
/// one is made here. A sampler asking for [linear] on a texture with one level
/// gets that one level, on every backend.
///
/// This used to say the whole enum was inert because generating a chain needed
/// render-to-mip-level support the stable channel did not expose. Both halves
/// of that were wrong by SDK 3.47 and the second half was always beside the
/// point: the chain is generated on the CPU and uploaded level by level, so
/// nothing renders into a mip at all.
enum MipFilter { nearest, linear }

/// What sampling outside the 0..1 range does.
enum SamplerAddressMode { clampToEdge, repeat, mirror }

/// The width of one index.
enum IndexType { int16, int32 }

/// How vertices are assembled into primitives.
///
/// **Two of these are drawn everywhere and three are not.** The engine asks for
/// [triangle] and [line] only — the debug overlay is the one caller of the
/// second — and the software rasteriser implements exactly those two, throwing
/// an [UnsupportedError] from the draw for the rest. There is no capability to
/// ask first and `PassEncoder.setPrimitiveType` says why; what a backend may
/// not do is assemble one of these as another.
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

/// What happens to a stencil value once the stencil and depth tests have
/// decided a fragment's fate.
///
/// One operation is chosen for each of the three outcomes — see
/// `StencilState` — and the value it produces is masked by the write mask
/// before it lands. Names and order are flutter_gpu's, for the reason the
/// library docstring gives.
enum StencilOperation {
  /// Leaves the stored value alone.
  keep,

  /// Stores zero.
  zero,

  /// Stores the reference value set by `PassEncoder.setStencilReference`.
  setToReferenceValue,

  /// Adds one, and stays at the maximum rather than wrapping.
  incrementClamp,

  /// Subtracts one, and stays at zero rather than wrapping.
  decrementClamp,

  /// Flips every bit.
  invert,

  /// Adds one, and wraps to zero past the maximum.
  incrementWrap,

  /// Subtracts one, and wraps to the maximum past zero.
  decrementWrap,
}

/// Which side of a triangle a stencil configuration applies to.
///
/// The engine configures both sides alike through `PassEncoder.setStencil`
/// and names a back face only when a caller hands one; this enum is what the
/// Impeller translation maps onto, and is here because every enum
/// flutter_gpu has is mirrored one for one.
enum StencilFace { both, front, back }

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
