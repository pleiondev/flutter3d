/// The engine's own vocabulary for graphics state.
///
/// **Nothing here may import a graphics API, ever.** That is the point of the
/// package and it is checkable: `tool/structure.dart` reads every file and
/// fails if one does.
///
/// The translation to flutter_gpu lives in exactly one file —
/// `src/engine/gpu/gpu_formats.dart` — and in exactly one `switch` per type. A
/// second translation of the same type is how the two drift apart, and drift in
/// this particular code is invisible: a wrong mapping still compiles, still
/// runs, and renders wrong only for scenes that happen to use that value.
///
/// ## Two rules these sets are held to
///
/// **Same values, no more and no fewer.** Every set here has exactly the
/// values `flutter_gpu` has, in the same order, under the same names. A set
/// that is *almost* the same as the one underneath is worse than one that is
/// either identical or deliberately different, because the difference is
/// invisible at the call site. The single deliberate difference is the *type*
/// name [TextureFormat], because `dart:ui` already exports `PixelFormat` and
/// this library is imported alongside `package:flutter/material.dart` in every
/// application that uses it.
///
/// **Identical value names are load-bearing, not cosmetic.** They are what lets
/// `test/gpu_formats_test.dart` assert, for every value of every set here,
/// that the mapping lands on the flutter_gpu value of the *same name*. A test
/// that only checked "distinct" would pass a swapped [CullMode.frontFace] /
/// [CullMode.backFace] pair, which is precisely the mistake worth catching.
///
/// When a second backend arrives, this file does not change; a second
/// translation file appears beside `gpu_formats.dart`.
///
/// ## The one exception, since 0.9
///
/// Three sets grew values flutter_gpu does not have — [TextureFormat],
/// [BlendFactor] and [BlendOperation] — because a contract that promises the
/// whole of a modern GPU cannot stop at what one backend's binding exposes:
/// integer and packed formats a storage texture needs, the depth-only formats,
/// dual-source blending, min and max. **They are appended after every mirrored
/// value, never interleaved**, so the mirrored prefix keeps flutter_gpu's
/// order and the trace codec, which writes enums by name, reads old traces
/// unchanged. [extendedTextureFormats], [extendedBlendFactors] and
/// [extendedBlendOperations] name the appended tail; the Impeller translation
/// skips exactly those in its same-name test and refuses each one by name.
///
/// ## Open sets, since 1.0
///
/// Most of these are classes with constants rather than enums, so a value a
/// later minor release adds (another blend factor, a cull mode for both
/// faces) breaks no backend outside this repository: its `switch` ends with
/// a wildcard that refuses the value by name. The few left as enums are the
/// ones whose members are fixed by what they mean: [CompareFunction],
/// [WindingOrder], [StencilFace] and [FramebufferOrigin].
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
/// here because the two sets must line up one for one, which is what the test
/// asserts and what makes the mapping worth trusting.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class TextureType {
  const TextureType._(this.name);

  static const TextureType texture2D = TextureType._('texture2D');

  static const TextureType texture2DMultisample = TextureType._(
    'texture2DMultisample',
  );

  /// Six square faces, sampled by direction rather than by coordinate. What a
  /// sky, an environment map or a point-light shadow is drawn into.
  static const TextureType textureCube = TextureType._('textureCube');

  static const TextureType textureExternalOES = TextureType._(
    'textureExternalOES',
  );

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<TextureType> values = <TextureType>[
    texture2D,
    texture2DMultisample,
    textureCube,
    textureExternalOES,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static TextureType? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'TextureType.$name';
}

/// Where an allocation lives and how it may be used.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class StorageMode {
  const StorageMode._(this.name);

  /// Mappable into the host's address space and usable by the device.
  static const StorageMode hostVisible = StorageMode._('hostVisible');

  /// Device-only. Optimal for the device; the host must copy through a
  /// host-visible allocation to read it.
  static const StorageMode devicePrivate = StorageMode._('devicePrivate');

  /// Tile memory, for temporary render targets. Higher bandwidth, lower power,
  /// and no separate device allocation — but it cannot be copied to or from,
  /// which is what rules it out for anything a later pass reads. Textures only.
  static const StorageMode deviceTransient = StorageMode._('deviceTransient');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<StorageMode> values = <StorageMode>[
    hostVisible,
    devicePrivate,
    deviceTransient,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static StorageMode? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'StorageMode.$name';
}

/// The layout of one texel.
///
/// Named [TextureFormat] rather than `PixelFormat` because `dart:ui` exports a
/// `PixelFormat` of its own, for image data rather than for textures, and every
/// application on this engine imports both libraries. The values are
/// flutter_gpu's, unchanged.
final class TextureFormat {
  const TextureFormat._(this.index, this.name);

  static const TextureFormat unknown = TextureFormat._(0, 'unknown');

  static const TextureFormat a8UNormInt = TextureFormat._(1, 'a8UNormInt');

  static const TextureFormat r8UNormInt = TextureFormat._(2, 'r8UNormInt');

  static const TextureFormat r8g8UNormInt = TextureFormat._(3, 'r8g8UNormInt');

  static const TextureFormat r8g8b8a8UNormInt = TextureFormat._(
    4,
    'r8g8b8a8UNormInt',
  );

  static const TextureFormat r8g8b8a8UNormIntSRGB = TextureFormat._(
    5,
    'r8g8b8a8UNormIntSRGB',
  );

  static const TextureFormat b8g8r8a8UNormInt = TextureFormat._(
    6,
    'b8g8r8a8UNormInt',
  );

  static const TextureFormat b8g8r8a8UNormIntSRGB = TextureFormat._(
    7,
    'b8g8r8a8UNormIntSRGB',
  );

  static const TextureFormat r32g32b32a32Float = TextureFormat._(
    8,
    'r32g32b32a32Float',
  );

  static const TextureFormat r16g16b16a16Float = TextureFormat._(
    9,
    'r16g16b16a16Float',
  );

  static const TextureFormat r32Float = TextureFormat._(10, 'r32Float');

  // Depth and stencil formats.
  static const TextureFormat s8UInt = TextureFormat._(11, 's8UInt');

  static const TextureFormat d24UnormS8Uint = TextureFormat._(
    12,
    'd24UnormS8Uint',
  );

  static const TextureFormat d32FloatS8UInt = TextureFormat._(
    13,
    'd32FloatS8UInt',
  );

  // Block-compressed formats. Sample-only everywhere: they cannot be render
  // targets, shader-writable, or multisampled, and hardware support varies by
  // family.
  //
  // No asset the engine's own three games ship allocates one of these yet —
  // KTX2 is a decoder for other tools' output, not something
  // `dart run flutter3d_build:convert` produces — but every backend now has an answer
  // for one that arrives: Impeller allocates them (`gpu_device.dart`), WebGL2
  // uploads what its context's extensions allow and names what they do not
  // (`webgl_formats.dart`), and the software rasteriser refuses by name
  // (`cpu_device.dart`) because it samples raw texels and always will. See
  // [TextureFormatCompression.isCompressed], which every backend now reads
  // instead of re-listing this exact tail of the enum for itself.
  static const TextureFormat bc1RGBAUNormInt = TextureFormat._(
    14,
    'bc1RGBAUNormInt',
  );

  static const TextureFormat bc1RGBAUNormIntSRGB = TextureFormat._(
    15,
    'bc1RGBAUNormIntSRGB',
  );

  static const TextureFormat bc3RGBAUNormInt = TextureFormat._(
    16,
    'bc3RGBAUNormInt',
  );

  static const TextureFormat bc3RGBAUNormIntSRGB = TextureFormat._(
    17,
    'bc3RGBAUNormIntSRGB',
  );

  static const TextureFormat bc5RGUNormInt = TextureFormat._(
    18,
    'bc5RGUNormInt',
  );

  static const TextureFormat bc7RGBAUNormInt = TextureFormat._(
    19,
    'bc7RGBAUNormInt',
  );

  static const TextureFormat bc7RGBAUNormIntSRGB = TextureFormat._(
    20,
    'bc7RGBAUNormIntSRGB',
  );

  static const TextureFormat etc2RGB8UNormInt = TextureFormat._(
    21,
    'etc2RGB8UNormInt',
  );

  static const TextureFormat etc2RGB8UNormIntSRGB = TextureFormat._(
    22,
    'etc2RGB8UNormIntSRGB',
  );

  static const TextureFormat etc2RGBA8UNormInt = TextureFormat._(
    23,
    'etc2RGBA8UNormInt',
  );

  static const TextureFormat etc2RGBA8UNormIntSRGB = TextureFormat._(
    24,
    'etc2RGBA8UNormIntSRGB',
  );

  static const TextureFormat astc4x4LDR = TextureFormat._(25, 'astc4x4LDR');

  static const TextureFormat astc4x4LDRSRGB = TextureFormat._(
    26,
    'astc4x4LDRSRGB',
  );

  static const TextureFormat astc8x8LDR = TextureFormat._(27, 'astc8x8LDR');

  static const TextureFormat astc8x8LDRSRGB = TextureFormat._(
    28,
    'astc8x8LDRSRGB',
  );

  static const TextureFormat astc4x4HDR = TextureFormat._(29, 'astc4x4HDR');

  static const TextureFormat astc8x8HDR = TextureFormat._(30, 'astc8x8HDR');

  // ---- Beyond flutter_gpu, since 0.9 — see the library doc. Appended only.
  // What storage textures, packed HDR targets and depth-only attachments
  // need, named in this enum's own spelling. `extendedTextureFormats` lists
  // them; `TextureFormatInfo` describes every value.
  static const TextureFormat r8g8b8a8SNormInt = TextureFormat._(
    31,
    'r8g8b8a8SNormInt',
  );

  static const TextureFormat r8g8b8a8UInt = TextureFormat._(32, 'r8g8b8a8UInt');

  static const TextureFormat r8g8b8a8SInt = TextureFormat._(33, 'r8g8b8a8SInt');

  static const TextureFormat r16Float = TextureFormat._(34, 'r16Float');

  static const TextureFormat r16g16Float = TextureFormat._(35, 'r16g16Float');

  static const TextureFormat r16g16b16a16UInt = TextureFormat._(
    36,
    'r16g16b16a16UInt',
  );

  static const TextureFormat r16g16b16a16SInt = TextureFormat._(
    37,
    'r16g16b16a16SInt',
  );

  static const TextureFormat r32UInt = TextureFormat._(38, 'r32UInt');

  static const TextureFormat r32SInt = TextureFormat._(39, 'r32SInt');

  static const TextureFormat r32g32Float = TextureFormat._(40, 'r32g32Float');

  static const TextureFormat r32g32UInt = TextureFormat._(41, 'r32g32UInt');

  static const TextureFormat r32g32SInt = TextureFormat._(42, 'r32g32SInt');

  static const TextureFormat r32g32b32a32UInt = TextureFormat._(
    43,
    'r32g32b32a32UInt',
  );

  static const TextureFormat r32g32b32a32SInt = TextureFormat._(
    44,
    'r32g32b32a32SInt',
  );

  /// Ten bits per colour channel and two of alpha, unsigned normalised.
  static const TextureFormat r10g10b10a2UNormInt = TextureFormat._(
    45,
    'r10g10b10a2UNormInt',
  );

  /// Packed unsigned floats, 11/11/10 bits: half the bytes of
  /// [r16g16b16a16Float] for an HDR colour target with no alpha. Renderable
  /// only where `DeviceFeature.rg11b10Renderable` says so.
  static const TextureFormat r11g11b10UFloat = TextureFormat._(
    46,
    'r11g11b10UFloat',
  );

  /// Three nine-bit mantissas sharing a five-bit exponent: sample-only HDR.
  static const TextureFormat r9g9b9e5UFloat = TextureFormat._(
    47,
    'r9g9b9e5UFloat',
  );

  /// Depth only, sixteen bits.
  static const TextureFormat d16UNormInt = TextureFormat._(48, 'd16UNormInt');

  /// Depth only, 32-bit float — what reversed-Z wants.
  static const TextureFormat d32Float = TextureFormat._(49, 'd32Float');

  /// Every value this version names, in the order of [index].
  static const List<TextureFormat> values = <TextureFormat>[
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
    s8UInt,
    d24UnormS8Uint,
    d32FloatS8UInt,
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
    r8g8b8a8SNormInt,
    r8g8b8a8UInt,
    r8g8b8a8SInt,
    r16Float,
    r16g16Float,
    r16g16b16a16UInt,
    r16g16b16a16SInt,
    r32UInt,
    r32SInt,
    r32g32Float,
    r32g32UInt,
    r32g32SInt,
    r32g32b32a32UInt,
    r32g32b32a32SInt,
    r10g10b10a2UNormInt,
    r11g11b10UFloat,
    r9g9b9e5UFloat,
    d16UNormInt,
    d32Float,
  ];

  /// The value whose [name] is [wireName], or null when this version names
  /// none (absent) — how a file that names a value is read.
  static TextureFormat? byName(String wireName) {
    for (final value in values) {
      if (value.name == wireName) return value;
    }
    return null;
  }

  /// The position in [values]: stable within a major, appended only.
  final int index;

  /// The stable name, and the wire name: what a file, a report or a
  /// snapshot writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'TextureFormat.$name';
}

/// The [TextureFormat] values flutter_gpu does not have, in declaration
/// order. The Impeller backend refuses each of them by name.
const List<TextureFormat> extendedTextureFormats = <TextureFormat>[
  TextureFormat.r8g8b8a8SNormInt,
  TextureFormat.r8g8b8a8UInt,
  TextureFormat.r8g8b8a8SInt,
  TextureFormat.r16Float,
  TextureFormat.r16g16Float,
  TextureFormat.r16g16b16a16UInt,
  TextureFormat.r16g16b16a16SInt,
  TextureFormat.r32UInt,
  TextureFormat.r32SInt,
  TextureFormat.r32g32Float,
  TextureFormat.r32g32UInt,
  TextureFormat.r32g32SInt,
  TextureFormat.r32g32b32a32UInt,
  TextureFormat.r32g32b32a32SInt,
  TextureFormat.r10g10b10a2UNormInt,
  TextureFormat.r11g11b10UFloat,
  TextureFormat.r9g9b9e5UFloat,
  TextureFormat.d16UNormInt,
  TextureFormat.d32Float,
];

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
/// **The last four read a blend constant, and `PassEncoder.setBlendColor` is
/// how it is set.** [blendColor], [oneMinusBlendColor], [blendAlpha] and
/// [oneMinusBlendAlpha] all multiply by that colour, which is transparent black
/// until a pass says otherwise.
///
/// They used to be the one dead corner of these sets — no setter anywhere, and
/// three backends disagreeing about what that meant: the software rasteriser
/// threw, WebGL2 mapped them to `CONSTANT_COLOR` against a constant nobody had
/// set, and Impeller handed them to flutter_gpu whose default is the same
/// transparent black. Two of the three drew a plausible picture with a term
/// missing from it, which is the failure this type's own doc comment was
/// written to warn about and could not prevent.
///
/// **A backend may still not have the constant, and one here does not.** Ask
/// `features.has(DeviceFeature.blendConstant)` before naming any of these four:
/// flutter_gpu exposes no blend-constant setter at all, so the Impeller backend
/// answers false and *refuses* a [BlendState] naming one rather than drawing
/// the term as zero. That refusal is the promise the false answer carries, and
/// the conformance check `a blend constant reaches the blend, or is refused`
/// holds both halves of it.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class BlendFactor {
  const BlendFactor._(this.name);

  static const BlendFactor zero = BlendFactor._('zero');

  static const BlendFactor one = BlendFactor._('one');

  static const BlendFactor sourceColor = BlendFactor._('sourceColor');

  static const BlendFactor oneMinusSourceColor = BlendFactor._(
    'oneMinusSourceColor',
  );

  static const BlendFactor sourceAlpha = BlendFactor._('sourceAlpha');

  static const BlendFactor oneMinusSourceAlpha = BlendFactor._(
    'oneMinusSourceAlpha',
  );

  static const BlendFactor destinationColor = BlendFactor._('destinationColor');

  static const BlendFactor oneMinusDestinationColor = BlendFactor._(
    'oneMinusDestinationColor',
  );

  static const BlendFactor destinationAlpha = BlendFactor._('destinationAlpha');

  static const BlendFactor oneMinusDestinationAlpha = BlendFactor._(
    'oneMinusDestinationAlpha',
  );

  static const BlendFactor sourceAlphaSaturated = BlendFactor._(
    'sourceAlphaSaturated',
  );

  static const BlendFactor blendColor = BlendFactor._('blendColor');

  static const BlendFactor oneMinusBlendColor = BlendFactor._(
    'oneMinusBlendColor',
  );

  static const BlendFactor blendAlpha = BlendFactor._('blendAlpha');

  static const BlendFactor oneMinusBlendAlpha = BlendFactor._(
    'oneMinusBlendAlpha',
  );

  // ---- Beyond flutter_gpu, since 0.9 — see the library doc. Appended only.
  // The fragment's second colour output, for dual-source blending. Ask
  // `DeviceFeature.dualSourceBlending`; a backend without it refuses a
  // `BlendState` naming one.
  static const BlendFactor source1Color = BlendFactor._('source1Color');

  static const BlendFactor oneMinusSource1Color = BlendFactor._(
    'oneMinusSource1Color',
  );

  static const BlendFactor source1Alpha = BlendFactor._('source1Alpha');

  static const BlendFactor oneMinusSource1Alpha = BlendFactor._(
    'oneMinusSource1Alpha',
  );

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<BlendFactor> values = <BlendFactor>[
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
    source1Color,
    oneMinusSource1Color,
    source1Alpha,
    oneMinusSource1Alpha,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static BlendFactor? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'BlendFactor.$name';
}

/// The [BlendFactor] values flutter_gpu does not have.
const List<BlendFactor> extendedBlendFactors = <BlendFactor>[
  BlendFactor.source1Color,
  BlendFactor.oneMinusSource1Color,
  BlendFactor.source1Alpha,
  BlendFactor.oneMinusSource1Alpha,
];

/// How the two blend terms are combined.
///
/// [min] and [max] are beyond flutter_gpu (see the library doc) and ignore
/// both factors, as every API defines them; ask `DeviceFeature.minMaxBlend`.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class BlendOperation {
  const BlendOperation._(this.name);

  static const BlendOperation add = BlendOperation._('add');

  static const BlendOperation subtract = BlendOperation._('subtract');

  static const BlendOperation reverseSubtract = BlendOperation._(
    'reverseSubtract',
  );

  static const BlendOperation min = BlendOperation._('min');

  static const BlendOperation max = BlendOperation._('max');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<BlendOperation> values = <BlendOperation>[
    add,
    subtract,
    reverseSubtract,
    min,
    max,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static BlendOperation? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'BlendOperation.$name';
}

/// The [BlendOperation] values flutter_gpu does not have.
const List<BlendOperation> extendedBlendOperations = <BlendOperation>[
  BlendOperation.min,
  BlendOperation.max,
];

/// What happens to an attachment's existing contents when a pass begins.
///
/// [load] and [clear] are not interchangeable at the granularity a caller might
/// assume: a clear covers the **whole attachment** however the viewport and
/// scissor are set. The shadow atlas depends on that difference — it loads, and
/// blanks a tile by drawing inside it.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class LoadAction {
  const LoadAction._(this.name);

  static const LoadAction dontCare = LoadAction._('dontCare');

  static const LoadAction load = LoadAction._('load');

  static const LoadAction clear = LoadAction._('clear');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<LoadAction> values = <LoadAction>[dontCare, load, clear];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static LoadAction? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'LoadAction.$name';
}

/// What happens to an attachment's contents when a pass ends.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class StoreAction {
  const StoreAction._(this.name);

  static const StoreAction dontCare = StoreAction._('dontCare');

  static const StoreAction store = StoreAction._('store');

  static const StoreAction multisampleResolve = StoreAction._(
    'multisampleResolve',
  );

  static const StoreAction storeAndMultisampleResolve = StoreAction._(
    'storeAndMultisampleResolve',
  );

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<StoreAction> values = <StoreAction>[
    dontCare,
    store,
    multisampleResolve,
    storeAndMultisampleResolve,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static StoreAction? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'StoreAction.$name';
}

/// Filtering between texels.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class MinMagFilter {
  const MinMagFilter._(this.name);

  static const MinMagFilter nearest = MinMagFilter._('nearest');

  static const MinMagFilter linear = MinMagFilter._('linear');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<MinMagFilter> values = <MinMagFilter>[nearest, linear];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static MinMagFilter? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'MinMagFilter.$name';
}

/// Filtering between mip levels.
///
/// Meaningful only on a texture that *has* a chain — see
/// `GraphicsDevice.createTextureFromPixels`, whose `mipLevels` is the only way
/// one is made here. A sampler asking for [linear] on a texture with one level
/// gets that one level, on every backend.
///
/// This used to say the whole type was inert because generating a chain needed
/// render-to-mip-level support the stable channel did not expose. Both halves
/// of that were wrong by SDK 3.47 and the second half was always beside the
/// point: the chain is generated on the CPU and uploaded level by level, so
/// nothing renders into a mip at all.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class MipFilter {
  const MipFilter._(this.name);

  static const MipFilter nearest = MipFilter._('nearest');

  static const MipFilter linear = MipFilter._('linear');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<MipFilter> values = <MipFilter>[nearest, linear];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static MipFilter? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'MipFilter.$name';
}

/// What sampling outside the 0..1 range does.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class SamplerAddressMode {
  const SamplerAddressMode._(this.name);

  static const SamplerAddressMode clampToEdge = SamplerAddressMode._(
    'clampToEdge',
  );

  static const SamplerAddressMode repeat = SamplerAddressMode._('repeat');

  static const SamplerAddressMode mirror = SamplerAddressMode._('mirror');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<SamplerAddressMode> values = <SamplerAddressMode>[
    clampToEdge,
    repeat,
    mirror,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static SamplerAddressMode? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'SamplerAddressMode.$name';
}

/// The width of one index.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class IndexType {
  const IndexType._(this.name);

  static const IndexType int16 = IndexType._('int16');

  static const IndexType int32 = IndexType._('int32');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<IndexType> values = <IndexType>[int16, int32];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static IndexType? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'IndexType.$name';
}

/// How vertices are assembled into primitives.
///
/// **Two of these are drawn everywhere and three are not.** The engine asks for
/// [triangle] and [line] only — the debug overlay is the one caller of the
/// second — and the software rasteriser implements exactly those two, throwing
/// an [UnsupportedError] from the draw for the rest. There is no capability to
/// ask first and `PassEncoder.setPrimitiveType` says why; what a backend may
/// not do is assemble one of these as another.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class PrimitiveType {
  const PrimitiveType._(this.name);

  static const PrimitiveType triangle = PrimitiveType._('triangle');

  static const PrimitiveType triangleStrip = PrimitiveType._('triangleStrip');

  static const PrimitiveType line = PrimitiveType._('line');

  static const PrimitiveType lineStrip = PrimitiveType._('lineStrip');

  static const PrimitiveType point = PrimitiveType._('point');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<PrimitiveType> values = <PrimitiveType>[
    triangle,
    triangleStrip,
    line,
    lineStrip,
    point,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static PrimitiveType? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'PrimitiveType.$name';
}

/// Which faces the rasteriser discards.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class CullMode {
  const CullMode._(this.name);

  static const CullMode none = CullMode._('none');

  static const CullMode frontFace = CullMode._('frontFace');

  static const CullMode backFace = CullMode._('backFace');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<CullMode> values = <CullMode>[none, frontFace, backFace];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static CullMode? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'CullMode.$name';
}

/// Which winding counts as front-facing, wound in clip space: a transform that
/// mirrors reverses the facing without touching the order the vertices arrived
/// in, and every backend decides after the vertex stage rather than before it.
///
/// **Closed for good**: clockwise or counter-clockwise: the two orientations a
/// triangle has. No member can be added without changing what the type means,
/// so it stays an enum and a `switch` over it may name every case.
enum WindingOrder { clockwise, counterClockwise }

/// Whether primitives are filled or drawn as edges.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class PolygonMode {
  const PolygonMode._(this.name);

  static const PolygonMode fill = PolygonMode._('fill');

  static const PolygonMode line = PolygonMode._('line');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<PolygonMode> values = <PolygonMode>[fill, line];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static PolygonMode? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'PolygonMode.$name';
}

/// The test a depth or stencil comparison performs.
///
/// **Closed for good**: never, always and the six comparisons: every function
/// from less, equal and greater to pass or fail. No member can be added without
/// changing what the type means, so it stays an enum and a `switch` over it may
/// name every case.
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
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class StencilOperation {
  const StencilOperation._(this.name);

  /// Leaves the stored value alone.
  static const StencilOperation keep = StencilOperation._('keep');

  /// Stores zero.
  static const StencilOperation zero = StencilOperation._('zero');

  /// Stores the reference value set by `PassEncoder.setStencilReference`.
  static const StencilOperation setToReferenceValue = StencilOperation._(
    'setToReferenceValue',
  );

  /// Adds one, and stays at the maximum rather than wrapping.
  static const StencilOperation incrementClamp = StencilOperation._(
    'incrementClamp',
  );

  /// Subtracts one, and stays at zero rather than wrapping.
  static const StencilOperation decrementClamp = StencilOperation._(
    'decrementClamp',
  );

  /// Flips every bit.
  static const StencilOperation invert = StencilOperation._('invert');

  /// Adds one, and wraps to zero past the maximum.
  static const StencilOperation incrementWrap = StencilOperation._(
    'incrementWrap',
  );

  /// Subtracts one, and wraps to the maximum past zero.
  static const StencilOperation decrementWrap = StencilOperation._(
    'decrementWrap',
  );

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<StencilOperation> values = <StencilOperation>[
    keep,
    zero,
    setToReferenceValue,
    incrementClamp,
    decrementClamp,
    invert,
    incrementWrap,
    decrementWrap,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static StencilOperation? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'StencilOperation.$name';
}

/// Which side of a triangle a stencil configuration applies to.
///
/// The engine configures both sides alike through `PassEncoder.setStencil`
/// and names a back face only when a caller hands one; this enum is what the
/// Impeller translation maps onto, and is here because every enum
/// flutter_gpu has is mirrored one for one.
///
/// **Closed for good**: front, back or both: every non-empty set of a
/// triangle's two faces. No member can be added without changing what the type
/// means, so it stays an enum and a `switch` over it may name every case.
enum StencilFace { both, front, back }

/// What a backend's clip space maps depth onto.
///
/// Metal and Vulkan put the near plane at 0 and the far plane at 1. OpenGL puts
/// them at -1 and 1, and WebGL2 changes that only where the browser offers
/// `EXT_clip_control` — which the WebGL2 backend asks for, and then answers
/// [zeroToOne].
///
/// Not a detail that can be papered over. A projection built for one and fed to
/// the other does not error: with an OpenGL matrix on Metal roughly half the
/// view volume lands behind the near plane and the model looks eaten; the other
/// way round everything still draws, in the correct order, using half the depth
/// buffer — so it costs precision and shows up as z-fighting on surfaces that
/// were fine on the other backend. The second is worse to diagnose, because
/// nothing looks wrong until something does.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class DepthRange {
  const DepthRange._(this.name);

  /// Near at 0, far at 1. Metal, Vulkan, Impeller.
  static const DepthRange zeroToOne = DepthRange._('zeroToOne');

  /// Near at -1, far at 1. OpenGL, WebGL.
  static const DepthRange negativeOneToOne = DepthRange._('negativeOneToOne');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<DepthRange> values = <DepthRange>[
    zeroToOne,
    negativeOneToOne,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static DepthRange? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'DepthRange.$name';
}

/// Where a render target's first row of pixels is.
///
/// Metal and Impeller, WebGPU and the software rasteriser put it at the top
/// left; OpenGL and WebGL2 put it at the bottom left, and there is no switch
/// for that. So `gl_FragCoord.y` and a rendered texture's `v` run the other
/// way on WebGL2.
///
/// It matters wherever the engine *reads back* what it drew rather than only
/// showing it. A backend can hide the difference when it presents a frame, and
/// cannot when a shader samples a texture the engine rendered: a shadow map is
/// sampled through a matrix, and the matrix has to agree with which end of the
/// texture row zero is.
///
/// **Flip for patterns, never for lookups.** A screen-space pattern (dither,
/// grain, a kernel's rotation) is turned to count rows from the top through
/// `FragCoordFromTop`, so it lands on the same pixels on every backend. A
/// lookup of a texture this backend drew at the fragment's own pixel reads
/// `gl_FragCoord` as it is: flipping it reads the mirrored row. The table of
/// every place the difference shows is in the site's backend guide, under
/// "Which way Y points".
///
/// **Closed for good**: whether row zero is the top or the bottom: the sign of
/// the y axis. No member can be added without changing what the type means, so
/// it stays an enum and a `switch` over it may name every case.
enum FramebufferOrigin { topLeft, bottomLeft }
