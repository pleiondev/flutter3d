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
/// Only the plain case: one 2D texture, no array layers, no cube faces, no
/// depth, an explicit `vkFormat` (not the `0`/undefined that means Basis
/// Universal, whose real format lives in the data format descriptor instead),
/// and `supercompressionScheme` none — the mip bytes are the texture bytes.
/// Everything else — Zstandard or Basis-LZ supercompression, texture arrays,
/// cube maps, 3D textures, runtime-generated mip chains (`levelCount == 0`) —
/// is refused with [Ktx2FormatException] naming what was found, not
/// attempted. Each is a real feature with its own cost (a decompressor, a
/// six-face upload path, a mip generator) and none of this repository's three
/// games needs one yet; the point of refusing loudly is that adding one later
/// is additive; guessing wrong quietly is not.
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
/// Values above `0xFFFF` are reserved for vendor schemes and have no name
/// here; [Ktx2Texture.parse] reports the raw number for those.
abstract final class Ktx2SupercompressionScheme {
  static const int none = 0;
  static const int basisLZ = 1;
  static const int zstandard = 2;
  static const int zlib = 3;
}

/// The subset of Vulkan's `VkFormat` this loader maps to a [TextureFormat] —
/// exactly the values `flutter3d_hardware`'s enum already mirrors.
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
