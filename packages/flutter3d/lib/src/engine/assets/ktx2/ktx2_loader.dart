import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'ktx2_format.dart';

/// A KTX2 file, read down to what a texture upload needs: dimensions, an
/// engine [TextureFormat], and each mip level's bytes.
///
/// See `ktx2_format.dart` for the layout and for exactly which files this
/// stage refuses rather than misreads.
///
/// [levels] are views over the bytes passed to [parse] — `ByteData.view` has
/// no alignment requirement, unlike `Uint32List.view`/`Float32List.view`, so
/// unlike `.f3d`'s loader this needs no copying fallback for an odd offset.
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

  /// Reads [bytes] as a KTX2 file.
  ///
  /// Throws [Ktx2FormatException] rather than returning null: a caller that
  /// picked this decoder has already decided the bytes are a `.ktx2`, and a
  /// silent null would surface later as a missing texture with no reason.
  factory Ktx2Texture.parse(Uint8List bytes) {
    if (bytes.lengthInBytes < kKtx2LevelIndexOffset) {
      throw Ktx2FormatException(
        'File is ${bytes.lengthInBytes} bytes, too short for a KTX2 header.',
      );
    }
    for (var i = 0; i < kKtx2Identifier.length; i++) {
      if (bytes[i] != kKtx2Identifier[i]) {
        throw Ktx2FormatException(
          'Not a KTX2 file: byte $i is 0x${bytes[i].toRadixString(16)}, '
          'expected 0x${kKtx2Identifier[i].toRadixString(16)}.',
        );
      }
    }

    final view = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    int header(int field) =>
        view.getUint32(kKtx2HeaderOffset + field, Endian.little);

    final vkFormat = header(Ktx2HeaderField.vkFormat);
    final pixelWidth = header(Ktx2HeaderField.pixelWidth);
    final pixelHeight = header(Ktx2HeaderField.pixelHeight);
    final pixelDepth = header(Ktx2HeaderField.pixelDepth);
    final layerCount = header(Ktx2HeaderField.layerCount);
    final faceCount = header(Ktx2HeaderField.faceCount);
    final levelCount = header(Ktx2HeaderField.levelCount);
    final supercompressionScheme = header(
      Ktx2HeaderField.supercompressionScheme,
    );

    // `vkFormat == 0` (VK_FORMAT_UNDEFINED) is how a KTX2 file says "this is
    // Basis Universal" — the real format then lives in the data format
    // descriptor, which this stage does not read. Checked before the format
    // lookup so the message names what is actually going on rather than
    // reporting "unsupported vkFormat 0", which would be true and useless.
    if (vkFormat == VkFormat.undefined) {
      throw const Ktx2FormatException(
        'vkFormat is undefined, which means this file is Basis Universal '
        '(ETC1S/UASTC) — transcoding that is not implemented yet.',
      );
    }
    final format = _engineFormat(vkFormat);
    if (format == null) {
      throw Ktx2FormatException('Unsupported vkFormat $vkFormat.');
    }
    if (supercompressionScheme != Ktx2SupercompressionScheme.none) {
      throw Ktx2FormatException(
        'Unsupported supercompression scheme $supercompressionScheme '
        '(${_supercompressionName(supercompressionScheme)}) — not '
        'implemented yet.',
      );
    }
    if (pixelDepth != 0) {
      throw Ktx2FormatException(
        '3D textures (pixelDepth=$pixelDepth) are not supported yet.',
      );
    }
    if (layerCount != 0) {
      throw Ktx2FormatException(
        'Texture arrays (layerCount=$layerCount) are not supported yet.',
      );
    }
    if (faceCount != 1) {
      throw Ktx2FormatException(
        'Cube maps (faceCount=$faceCount) are not supported yet.',
      );
    }
    if (levelCount == 0) {
      throw const Ktx2FormatException(
        'levelCount is 0, which asks the loader to generate mip levels at '
        'load time — not implemented yet.',
      );
    }

    final levelIndexEnd =
        kKtx2LevelIndexOffset + levelCount * kKtx2LevelIndexEntryBytes;
    if (levelIndexEnd > bytes.lengthInBytes) {
      throw Ktx2FormatException(
        'Level index claims $levelCount entries, which runs past the end of '
        'a ${bytes.lengthInBytes}-byte file.',
      );
    }

    final levels = <ByteData>[];
    for (var i = 0; i < levelCount; i++) {
      final entry = kKtx2LevelIndexOffset + i * kKtx2LevelIndexEntryBytes;
      final byteOffset = _readOffsetOrLength(view, entry, 'level $i offset');
      final byteLength = _readOffsetOrLength(
        view,
        entry + 8,
        'level $i length',
      );
      if (byteOffset + byteLength > bytes.lengthInBytes) {
        throw Ktx2FormatException(
          'Level $i runs from $byteOffset for $byteLength bytes, past the '
          'end of a ${bytes.lengthInBytes}-byte file.',
        );
      }
      levels.add(
        ByteData.view(
          bytes.buffer,
          bytes.offsetInBytes + byteOffset,
          byteLength,
        ),
      );
    }

    return Ktx2Texture._(pixelWidth, pixelHeight, format, levels);
  }
}

/// Reads one of the format's 64-bit fields as a Dart `int`.
///
/// The field is genuinely `u64` in the spec, so a file could in principle
/// claim an offset or length past what fits in 32 bits. Nothing this engine
/// loads is anywhere near that — this reads the low and high 32-bit halves
/// separately (`getUint64` is not read here at all, because it is not
/// reliably available once compiled for the web) and refuses rather than
/// silently truncating if the high half is ever non-zero.
int _readOffsetOrLength(ByteData view, int byteOffset, String what) {
  final low = view.getUint32(byteOffset, Endian.little);
  final high = view.getUint32(byteOffset + 4, Endian.little);
  if (high != 0) {
    throw Ktx2FormatException(
      '$what is larger than 4 GiB, which this loader does not address.',
    );
  }
  return low;
}

/// The engine format [vkFormat] means, or null for anything this stage does
/// not map.
///
/// No `default`-free exhaustiveness check is possible here the way
/// `gpu_formats_resources.dart` gets one for enum-to-enum mappings — `int` has
/// no finite set of values the analyser can enumerate — so the safety instead
/// comes from the caller: an unmapped value throws by name rather than
/// silently falling through to a wrong format.
TextureFormat? _engineFormat(int vkFormat) => switch (vkFormat) {
  VkFormat.r8g8b8a8UNorm => TextureFormat.r8g8b8a8UNormInt,
  VkFormat.r8g8b8a8Srgb => TextureFormat.r8g8b8a8UNormIntSRGB,
  VkFormat.b8g8r8a8UNorm => TextureFormat.b8g8r8a8UNormInt,
  VkFormat.b8g8r8a8Srgb => TextureFormat.b8g8r8a8UNormIntSRGB,
  VkFormat.r16g16b16a16Sfloat => TextureFormat.r16g16b16a16Float,
  VkFormat.r32Sfloat => TextureFormat.r32Float,
  VkFormat.r32g32b32a32Sfloat => TextureFormat.r32g32b32a32Float,
  VkFormat.bc1RgbaUNormBlock => TextureFormat.bc1RGBAUNormInt,
  VkFormat.bc1RgbaSrgbBlock => TextureFormat.bc1RGBAUNormIntSRGB,
  VkFormat.bc3UNormBlock => TextureFormat.bc3RGBAUNormInt,
  VkFormat.bc3SrgbBlock => TextureFormat.bc3RGBAUNormIntSRGB,
  VkFormat.bc5UNormBlock => TextureFormat.bc5RGUNormInt,
  VkFormat.bc7UNormBlock => TextureFormat.bc7RGBAUNormInt,
  VkFormat.bc7SrgbBlock => TextureFormat.bc7RGBAUNormIntSRGB,
  VkFormat.etc2R8g8b8UNormBlock => TextureFormat.etc2RGB8UNormInt,
  VkFormat.etc2R8g8b8SrgbBlock => TextureFormat.etc2RGB8UNormIntSRGB,
  VkFormat.etc2R8g8b8a8UNormBlock => TextureFormat.etc2RGBA8UNormInt,
  VkFormat.etc2R8g8b8a8SrgbBlock => TextureFormat.etc2RGBA8UNormIntSRGB,
  VkFormat.astc4x4UNormBlock => TextureFormat.astc4x4LDR,
  VkFormat.astc4x4SrgbBlock => TextureFormat.astc4x4LDRSRGB,
  VkFormat.astc8x8UNormBlock => TextureFormat.astc8x8LDR,
  VkFormat.astc8x8SrgbBlock => TextureFormat.astc8x8LDRSRGB,
  VkFormat.astc4x4SfloatBlock => TextureFormat.astc4x4HDR,
  VkFormat.astc8x8SfloatBlock => TextureFormat.astc8x8HDR,
  _ => null,
};

String _supercompressionName(int scheme) => switch (scheme) {
  Ktx2SupercompressionScheme.basisLZ => 'Basis-LZ',
  Ktx2SupercompressionScheme.zstandard => 'Zstandard',
  Ktx2SupercompressionScheme.zlib => 'ZLIB',
  _ => 'vendor scheme $scheme',
};

/// True when [bytes] begins with the KTX2 identifier.
///
/// Cheap enough to call before committing to a decoder — the same role
/// `isF3dFile` plays for `.f3d`.
bool isKtx2File(Uint8List bytes) {
  if (bytes.lengthInBytes < kKtx2Identifier.length) return false;
  for (var i = 0; i < kKtx2Identifier.length; i++) {
    if (bytes[i] != kKtx2Identifier[i]) return false;
  }
  return true;
}
