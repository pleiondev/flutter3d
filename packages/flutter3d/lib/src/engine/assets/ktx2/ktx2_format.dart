/// The KTX2 container: byte offsets and constants shared by the loader.
///
/// ## Why read this format at all
///
/// A compressed texture (BC7, ETC2, ASTC — `TextureFormat` in
/// `flutter3d_hardware`) is bytes a GPU samples directly, never decoded on the
/// CPU. KTX2 is the container the tools that produce those bytes actually
/// write, and reading it is the whole job: there is no pixel math here, only
/// finding where each mip level's bytes start and what format they are in.
///
/// ## Layout
///
/// Everything is little-endian, per the KTX2 specification
/// (`github.khronos.org/KTX-Specification/ktxspec.v2.html`) — stated rather
/// than inherited, the same reason `.f3d` states it.
///
/// ```
/// Identifier, 12 bytes
///   AB 4B 54 58 20 32 30 BB 0D 0A 1A 0A
///
/// Header, offset 12, 36 bytes
///   u32 vkFormat
///   u32 typeSize
///   u32 pixelWidth
///   u32 pixelHeight
///   u32 pixelDepth
///   u32 layerCount
///   u32 faceCount
///   u32 levelCount
///   u32 supercompressionScheme
///
/// Index, offset 48, 32 bytes
///   u32 dfdByteOffset,  u32 dfdByteLength
///   u32 kvdByteOffset,  u32 kvdByteLength
///   u64 sgdByteOffset,  u64 sgdByteLength
///
/// Level index, offset 80, max(1, levelCount) x 24 bytes
///   u64 byteOffset, u64 byteLength, u64 uncompressedByteLength
/// ```
///
/// Level index entry 0 is level 0 — the base, largest image — regardless of
/// where its bytes physically sit in the file; each entry carries its own
/// absolute `byteOffset`, so nothing here needs to know or assume the
/// physical order.
///
/// ## What this stage reads, and what it refuses
///
/// One 2D texture, no array layers, no cube faces, no depth — that much is
/// common to both shapes it takes. Within it there are two:
///
///  * **A plain format.** An explicit `vkFormat` from the subset
///    [VkFormat] lists, with `supercompressionScheme` none: the mip bytes
///    *are* the texture bytes, and reading the file is finding them.
///  * **Basis Universal ETC1S.** `vkFormat` `0`/undefined — how a KTX2 file
///    says its real format lives elsewhere — with `supercompressionScheme`
///    Basis-LZ. Every mip level is transcoded to RGBA8 on the CPU by
///    `basis_universal/etc1s_transcoder.dart`, which is why the loader reads
///    the supercompression global data below and why a `.ktx2` can cost real
///    time to open.
///
/// Everything else is refused with [Ktx2FormatException] naming what was
/// found, not attempted: Zstandard or ZLIB supercompression, UASTC (an
/// undefined `vkFormat` under any scheme but Basis-LZ — what `toktx --uastc`
/// writes), texture arrays, cube maps, 3D textures, runtime-generated mip
/// chains (`levelCount == 0`). Each is a real feature with its own cost (a
/// decompressor, a second transcoder, a six-face upload path, a mip
/// generator) and none of this repository's three games needs one yet; the
/// point of refusing loudly is that adding one later is additive; guessing
/// wrong quietly is not.
///
/// The key/value section is read for the same reason, and only for the three
/// keys that describe pixels rather than provenance: a bottom-up
/// `KTXorientation`, a `KTXswizzle` that is not `rgba`, and
/// `KTXpremultipliedAlpha` are each refused, because honouring none of them
/// and saying nothing draws a texture upside down, channel-shuffled or twice
/// darkened, which reads as an authoring mistake. `_checkKeyValues` in
/// `ktx2_loader.dart` says the rest.
library;

/// `AB 4B 54 58 20 32 30 BB 0D 0A 1A 0A` — the twelve-byte identifier every
/// KTX2 file starts with.
const List<int> kKtx2Identifier = [
  0xAB,
  0x4B,
  0x54,
  0x58,
  0x20,
  0x32,
  0x30,
  0xBB,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

const int kKtx2HeaderOffset = 12;
const int kKtx2HeaderBytes = 36;
const int kKtx2IndexOffset = kKtx2HeaderOffset + kKtx2HeaderBytes; // 48
const int kKtx2IndexBytes = 32;
const int kKtx2LevelIndexOffset = kKtx2IndexOffset + kKtx2IndexBytes; // 80
const int kKtx2LevelIndexEntryBytes = 24;

/// Byte offsets of the Index section's fields, relative to
/// [kKtx2IndexOffset] — the pointers to the data format descriptor, the
/// key/value data, and (for a Basis Universal file) the supercompression
/// global data this stage now reads.
abstract final class Ktx2IndexField {
  /// Where the data format descriptor is, and how long.
  ///
  /// The loader does not read the descriptor: it takes the format from the
  /// header and the supercompression scheme, which is enough for every file this
  /// engine loads. The two offsets are here for a caller that has to read it —
  /// anybody handling a format this loader rejects, who would otherwise be
  /// counting bytes out of the specification again.
  static const int dfdByteOffset = 0;

  /// How long it is; for the caller [dfdByteOffset] names.
  static const int dfdByteLength = 4;
  static const int kvdByteOffset = 8;
  static const int kvdByteLength = 12;
  static const int sgdByteOffset = 16; // u64
  static const int sgdByteLength = 24; // u64
}

/// The Basis Universal "supercompression global data" a
/// `supercompressionScheme == basisLZ` file carries: the endpoint and
/// selector codebooks, the per-block bitstream's Huffman tables, and one
/// `ImageDesc` per image telling where in the level's own bytes the RGB (and
/// optionally alpha) slice lives.
///
/// Verified against a real encoded file — see
/// `flutter3d_samples/doc/ktx2_fixtures.md` — not only against the
/// specification text, which for this section is thinner than the container
/// layout above.
///
/// ```
/// Global data header, at sgdByteOffset, 20 bytes
///   u16 endpointCount,  u16 selectorCount
///   u32 endpointsByteLength
///   u32 selectorsByteLength
///   u32 tablesByteLength
///   u32 extendedByteLength
///
/// ImageDesc, 20 bytes, one per image — with no layers and one face an
/// image is a mip level, so this stage reads `levelCount` of them, entry 0
/// being level 0, whatever order the levels' bytes sit in the file
///   u32 imageFlags
///   u32 rgbSliceByteOffset,   u32 rgbSliceByteLength
///   u32 alphaSliceByteOffset, u32 alphaSliceByteLength
///
/// Then, back to back: endpointsData, selectorsData, tablesData.
/// ```
///
/// The slice offsets are relative to the *level's* bytes (the ones the
/// ordinary KTX2 level index in `ktx2_loader.dart` already finds) — not to
/// this section — confirmed on the real file: `rgbSliceByteOffset` was `0`
/// and the level's own bytes started elsewhere in the file entirely.
abstract final class Ktx2GlobalDataField {
  static const int endpointCount = 0; // u16
  static const int selectorCount = 2; // u16
  static const int endpointsByteLength = 4;
  static const int selectorsByteLength = 8;
  static const int tablesByteLength = 12;

  /// Where the extended data the transcoder does not use begins.
  ///
  /// This engine transcodes ETC1S, which puts nothing here. It is named for a
  /// caller reading a UASTC file's global data, where the field is the only way
  /// to find the end of the part that is understood.
  static const int extendedByteLength = 16;
  static const int headerBytes = 20;
}

abstract final class Ktx2ImageDescField {
  /// Per-image flags — whether the slice is an I-frame, and the rest.
  ///
  /// The transcoder here treats every image as a key frame, so it never looks.
  /// It is for a caller transcoding a video-like sequence, where an image that
  /// is not a key frame cannot be decoded on its own and this is what says so.
  static const int imageFlags = 0;
  static const int rgbSliceByteOffset = 4;
  static const int rgbSliceByteLength = 8;
  static const int alphaSliceByteOffset = 12;
  static const int alphaSliceByteLength = 16;
  static const int bytes = 20;
}

/// Byte offsets of the header fields, relative to [kKtx2HeaderOffset].
abstract final class Ktx2HeaderField {
  static const int vkFormat = 0;
  static const int typeSize = 4;
  static const int pixelWidth = 8;
  static const int pixelHeight = 12;
  static const int pixelDepth = 16;
  static const int layerCount = 20;
  static const int faceCount = 24;
  static const int levelCount = 28;
  static const int supercompressionScheme = 32;
}

/// `supercompressionScheme` values this format defines.
///
/// Khronos reserves everything up to `0xFFFF` for itself and leaves the rest
/// to vendors, so a number between [zlib] and `0xFFFF` is a scheme this build
/// predates rather than somebody's extension. [Ktx2Texture.parse] reports the
/// raw number either way, and says which of the two it is.
abstract final class Ktx2SupercompressionScheme {
  static const int none = 0;
  static const int basisLZ = 1;
  static const int zstandard = 2;
  static const int zlib = 3;
}

/// The subset of Vulkan's `VkFormat` this loader maps to a [TextureFormat].
///
/// Not one to one: an `_SRGB` value and its `_UNORM` twin carry the same bits
/// and map to the same engine format, because this engine's shaders decode
/// sRGB themselves and a sampler that also decoded would decode twice. See
/// `_engineFormat` in `ktx2_loader.dart`, which says why at length.
///
/// Numbers are Khronos's, not this repository's: taken from
/// `github.com/KhronosGroup/KTX-Software/lib/src/vkformat_enum.h`, the
/// project that defines what a KTX2 file's `vkFormat` field means. Copied
/// rather than derived, for the reason `formats.dart` states about the
/// flutter_gpu mirror — a wrong number here compiles, runs, and renders wrong
/// only for the value a scene happens to use.
abstract final class VkFormat {
  static const int undefined = 0;
  static const int r8g8b8a8UNorm = 37;
  static const int r8g8b8a8Srgb = 43;
  static const int b8g8r8a8UNorm = 44;
  static const int b8g8r8a8Srgb = 50;
  static const int r16g16b16a16Sfloat = 97;
  static const int r32Sfloat = 100;
  static const int r32g32b32a32Sfloat = 109;
  static const int bc1RgbaUNormBlock = 133;
  static const int bc1RgbaSrgbBlock = 134;
  static const int bc3UNormBlock = 137;
  static const int bc3SrgbBlock = 138;
  static const int bc5UNormBlock = 141;
  static const int bc7UNormBlock = 145;
  static const int bc7SrgbBlock = 146;
  static const int etc2R8g8b8UNormBlock = 147;
  static const int etc2R8g8b8SrgbBlock = 148;
  static const int etc2R8g8b8a8UNormBlock = 151;
  static const int etc2R8g8b8a8SrgbBlock = 152;
  static const int astc4x4UNormBlock = 157;
  static const int astc4x4SrgbBlock = 158;
  static const int astc8x8UNormBlock = 171;
  static const int astc8x8SrgbBlock = 172;
  static const int astc4x4SfloatBlock = 1000066000;
  static const int astc8x8SfloatBlock = 1000066007;
}

/// Raised when bytes are not a KTX2 file, are truncated, or use a feature
/// this stage of the loader does not read yet — see the library doc comment
/// for exactly which those are.
///
/// A distinct type rather than [FormatException], so a caller can tell "not
/// our format" from "our format, and a feature we have not built" — the
/// second is a roadmap item, not a broken file.
final class Ktx2FormatException implements Exception {
  const Ktx2FormatException(this.message);

  final String message;

  @override
  String toString() => 'Ktx2FormatException: $message';
}
