/// [textureInfo] — a texture's declared size, format badge and on-device
/// weight, read from its own file header, with no decoder anywhere in the
/// call.
///
/// Builds on [imageDimensions] for the PNG/JPEG case; for KTX2 it reads the
/// header a level further than [imageDimensions] does — `vkFormat` and
/// `levelCount`, not only `pixelWidth`/`pixelHeight` — because a texture slot
/// showing "256×128" also wants to show a format badge and "170 KB" before
/// anything uploads a pixel.
///
/// **Why this does not call the engine's own `Ktx2Texture.parse`.** That
/// loader lives in `flutter3d`, which depends on the Flutter SDK for
/// `dart:ui`; this package does not, by the same choice
/// `flutter3d_editor_core` made for the same reason (`qa-03`). The `vkFormat`
/// numbers and block sizes below are the same ones `ktx2_format.dart` and
/// `flutter3d_hardware`'s `formats.dart` state for the engine's own loader —
/// copied rather than imported, for the reason both of those files give for
/// copying rather than importing across that same boundary: a wrong number
/// here compiles, runs, and is wrong only for the value that hits it.
///
/// **Scope: the "plain format" half of KTX2, same split the engine's own
/// loader makes.** A `vkFormat` this file recognises gets its
/// [TextureInfo.bytesOnDevice] computed from width, height and the format's
/// own block size — exact, because a block-compressed format's bytes on disk
/// are its bytes on the GPU, no transcode between them. Basis Universal
/// (`vkFormat` undefined) and anything else neither this file nor the
/// engine's loader maps falls back to the level index's own stored total,
/// which is the file's number rather than the GPU's — see
/// [TextureFileFormat.other].
library;

import 'dart:typed_data';

import 'image_dimensions.dart';

/// What a texture panel needs before anything decodes a pixel.
final class TextureInfo {
  const TextureInfo({
    required this.width,
    required this.height,
    required this.format,
    required this.bytesOnDevice,
    required this.hasOwnMips,
  });

  final int width;
  final int height;
  final TextureFileFormat format;

  /// How many bytes this costs once uploaded — see the library doc comment
  /// for when this is exact and when it is the file's own stored total
  /// instead.
  final int bytesOnDevice;

  final bool hasOwnMips;

  @override
  bool operator ==(Object other) =>
      other is TextureInfo &&
      other.width == width &&
      other.height == height &&
      other.format == format &&
      other.bytesOnDevice == bytesOnDevice &&
      other.hasOwnMips == hasOwnMips;

  @override
  int get hashCode =>
      Object.hash(width, height, format, bytesOnDevice, hasOwnMips);

  @override
  String toString() =>
      'TextureInfo($width x $height, $format, ${bytesOnDevice}B'
      '${hasOwnMips ? ' +mips' : ''})';
}

/// The badge a texture slot shows for what actually samples on the GPU.
enum TextureFileFormat {
  /// PNG or JPEG, decoded to `RGBA8` on upload — four bytes a texel, no mip
  /// chain of its own.
  rgba8,
  bc1,
  bc3,
  bc7,
  etc2Rgba8,
  astc4x4,

  /// A KTX2 `vkFormat` this reader has no badge for. See the library doc
  /// comment: [TextureInfo.bytesOnDevice] is then the level index's own
  /// stored total, not a block-layout sum.
  other,
}

/// [bytes]' own declared size, format and weight — from a PNG/JPEG header via
/// [imageDimensions], or a KTX2 header read one level further — or null for
/// anything else, or a file too short to hold what it claims to be.
TextureInfo? textureInfo(Uint8List bytes) {
  if (_startsWithKtx2Identifier(bytes)) return _ktx2Info(bytes);
  final dimensions = imageDimensions(bytes);
  if (dimensions == null) return null;
  return TextureInfo(
    width: dimensions.width,
    height: dimensions.height,
    format: TextureFileFormat.rgba8,
    bytesOnDevice: dimensions.width * dimensions.height * 4,
    hasOwnMips: false,
  );
}

const List<int> _ktx2Identifier = <int>[
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

bool _startsWithKtx2Identifier(Uint8List bytes) {
  if (bytes.length < _ktx2Identifier.length) return false;
  for (var i = 0; i < _ktx2Identifier.length; i++) {
    if (bytes[i] != _ktx2Identifier[i]) return false;
  }
  return true;
}

/// The Khronos `vkFormat` numbers this reader maps — a subset of the same
/// subset `ktx2_format.dart`'s own `VkFormat` maps, restricted further to the
/// formats `mat-30`'s encoder actually writes (BC1/BC3/BC7/ETC2/ASTC 4×4).
abstract final class _VkFormat {
  static const int bc1RgbaUNormBlock = 133;
  static const int bc1RgbaSrgbBlock = 134;
  static const int bc3UNormBlock = 137;
  static const int bc3SrgbBlock = 138;
  static const int bc7UNormBlock = 145;
  static const int bc7SrgbBlock = 146;
  static const int etc2R8g8b8a8UNormBlock = 151;
  static const int etc2R8g8b8a8SrgbBlock = 152;
  static const int astc4x4UNormBlock = 157;
  static const int astc4x4SrgbBlock = 158;
}

final class _BlockLayout {
  const _BlockLayout(
    this.format,
    this.blockWidth,
    this.blockHeight,
    this.bytesPerBlock,
  );

  final TextureFileFormat format;
  final int blockWidth;
  final int blockHeight;
  final int bytesPerBlock;
}

_BlockLayout? _blockLayoutFor(int vkFormat) => switch (vkFormat) {
  _VkFormat.bc1RgbaUNormBlock || _VkFormat.bc1RgbaSrgbBlock =>
    const _BlockLayout(TextureFileFormat.bc1, 4, 4, 8),
  _VkFormat.bc3UNormBlock ||
  _VkFormat.bc3SrgbBlock => const _BlockLayout(TextureFileFormat.bc3, 4, 4, 16),
  _VkFormat.bc7UNormBlock ||
  _VkFormat.bc7SrgbBlock => const _BlockLayout(TextureFileFormat.bc7, 4, 4, 16),
  _VkFormat.etc2R8g8b8a8UNormBlock || _VkFormat.etc2R8g8b8a8SrgbBlock =>
    const _BlockLayout(TextureFileFormat.etc2Rgba8, 4, 4, 16),
  _VkFormat.astc4x4UNormBlock || _VkFormat.astc4x4SrgbBlock =>
    const _BlockLayout(TextureFileFormat.astc4x4, 4, 4, 16),
  _ => null,
};

const int _kKtx2HeaderOffset = 12;
const int _kKtx2HeaderBytes = 36;
const int _kKtx2LevelIndexOffset = _kKtx2HeaderOffset + _kKtx2HeaderBytes; // 48
const int _kKtx2LevelIndexEntryBytes = 24;

TextureInfo? _ktx2Info(Uint8List bytes) {
  if (bytes.length < _kKtx2LevelIndexOffset) return null;
  final view = ByteData.sublistView(bytes);
  int header(int field) =>
      view.getUint32(_kKtx2HeaderOffset + field, Endian.little);
  final vkFormat = header(0);
  final pixelWidth = header(8);
  final pixelHeight = header(12);
  final levelCount = header(28);
  final levels = levelCount == 0 ? 1 : levelCount;

  final layout = _blockLayoutFor(vkFormat);
  if (layout != null) {
    return TextureInfo(
      width: pixelWidth,
      height: pixelHeight,
      format: layout.format,
      bytesOnDevice: _compressedBytes(pixelWidth, pixelHeight, levels, layout),
      hasOwnMips: levels > 1,
    );
  }

  final storedBytes = _levelIndexTotal(bytes, levels);
  if (storedBytes == null) return null;
  return TextureInfo(
    width: pixelWidth,
    height: pixelHeight,
    format: TextureFileFormat.other,
    bytesOnDevice: storedBytes,
    hasOwnMips: levels > 1,
  );
}

/// The sum, over [levels] mips starting at [width]×[height] and each halving
/// (never below one pixel), of blocks-per-mip times [layout]'s own
/// `bytesPerBlock` — a block-compressed format's bytes on disk and its bytes
/// on the GPU are the same bytes, so this needs no file read past the header.
int _compressedBytes(int width, int height, int levels, _BlockLayout layout) {
  var total = 0;
  var w = width;
  var h = height;
  for (var i = 0; i < levels; i++) {
    final blocksWide = (w + layout.blockWidth - 1) ~/ layout.blockWidth;
    final blocksHigh = (h + layout.blockHeight - 1) ~/ layout.blockHeight;
    total += blocksWide * blocksHigh * layout.bytesPerBlock;
    w = w > 1 ? w ~/ 2 : 1;
    h = h > 1 ? h ~/ 2 : 1;
  }
  return total;
}

/// The level index's own `byteLength` field, summed over [levels] entries —
/// the fallback for a `vkFormat` [_blockLayoutFor] does not map, where there
/// is no block size to compute from. Null if the file is too short to hold
/// that many entries.
int? _levelIndexTotal(Uint8List bytes, int levels) {
  final needed = _kKtx2LevelIndexOffset + levels * _kKtx2LevelIndexEntryBytes;
  if (bytes.length < needed) return null;
  final view = ByteData.sublistView(bytes);
  var total = 0;
  for (var i = 0; i < levels; i++) {
    final entryOffset = _kKtx2LevelIndexOffset + i * _kKtx2LevelIndexEntryBytes;
    total += view.getUint64(entryOffset + 8, Endian.little);
  }
  return total;
}
