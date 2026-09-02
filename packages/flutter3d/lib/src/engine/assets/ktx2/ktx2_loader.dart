import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'basis_universal/etc1s_transcoder.dart';
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

    // Shape checks that apply whichever way the pixels are stored — moved
    // ahead of the format branch below so a texture array or a cube map is
    // refused by the same message whether it is a plain format or Basis
    // Universal.
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

    // `vkFormat == 0` (VK_FORMAT_UNDEFINED) is how a KTX2 file says "this is
    // Basis Universal" — the real format then lives in the supercompression
    // global data below, not in this field.
    if (vkFormat == VkFormat.undefined) {
      if (supercompressionScheme != Ktx2SupercompressionScheme.basisLZ) {
        throw Ktx2FormatException(
          'vkFormat is undefined (Basis Universal), but supercompression '
          'scheme is $supercompressionScheme '
          '(${_supercompressionName(supercompressionScheme)}), not Basis-LZ.',
        );
      }
      if (levelCount != 1) {
        throw const Ktx2FormatException(
          'Basis Universal mip chains (levelCount > 1) are not supported yet.',
        );
      }
      return _parseBasisEtc1s(bytes, view, pixelWidth, pixelHeight);
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

/// The Basis Universal (ETC1S, `supercompressionScheme == basisLZ`) path:
/// reads the ordinary KTX2 level index for level 0's bytes, then the
/// supercompression global data — the codebooks and the one `ImageDesc` a
/// single-level, single-layer, single-face file carries — and transcodes
/// straight to RGBA8.
///
/// Split out of [Ktx2Texture.parse] because it reads a second, unrelated
/// section of the container (the global data, not the per-level index) and
/// hands off to a whole other codec (`etc1s_transcoder.dart`) once it has —
/// keeping it here would make the plain-format path harder to read for a
/// case most call sites never take.
Ktx2Texture _parseBasisEtc1s(
  Uint8List bytes,
  ByteData view,
  int pixelWidth,
  int pixelHeight,
) {
  // Level 0's own bytes, via the same level index every other vkFormat uses.
  final levelEntry = kKtx2LevelIndexOffset;
  final levelByteOffset = _readOffsetOrLength(
    view,
    levelEntry,
    'level 0 offset',
  );
  final levelByteLength = _readOffsetOrLength(
    view,
    levelEntry + 8,
    'level 0 length',
  );
  if (levelByteOffset + levelByteLength > bytes.lengthInBytes) {
    throw Ktx2FormatException(
      'Level 0 runs from $levelByteOffset for $levelByteLength bytes, past '
      'the end of a ${bytes.lengthInBytes}-byte file.',
    );
  }

  final sgdByteOffset = _readOffsetOrLength(
    view,
    kKtx2IndexOffset + Ktx2IndexField.sgdByteOffset,
    'supercompression global data offset',
  );
  final sgdByteLength = _readOffsetOrLength(
    view,
    kKtx2IndexOffset + Ktx2IndexField.sgdByteLength,
    'supercompression global data length',
  );
  if (sgdByteOffset + sgdByteLength > bytes.lengthInBytes) {
    throw Ktx2FormatException(
      'Supercompression global data runs from $sgdByteOffset for '
      '$sgdByteLength bytes, past the end of a ${bytes.lengthInBytes}-byte '
      'file.',
    );
  }
  if (sgdByteLength <
      Ktx2GlobalDataField.headerBytes + Ktx2ImageDescField.bytes) {
    throw Ktx2FormatException(
      'Supercompression global data is $sgdByteLength bytes, too short for '
      'its header and one ImageDesc.',
    );
  }

  int sgd(int field) => view.getUint32(sgdByteOffset + field, Endian.little);
  final endpointCount = view.getUint16(
    sgdByteOffset + Ktx2GlobalDataField.endpointCount,
    Endian.little,
  );
  final selectorCount = view.getUint16(
    sgdByteOffset + Ktx2GlobalDataField.selectorCount,
    Endian.little,
  );
  final endpointsByteLength = sgd(Ktx2GlobalDataField.endpointsByteLength);
  final selectorsByteLength = sgd(Ktx2GlobalDataField.selectorsByteLength);
  final tablesByteLength = sgd(Ktx2GlobalDataField.tablesByteLength);

  final imageDescOffset = sgdByteOffset + Ktx2GlobalDataField.headerBytes;
  int imageDesc(int field) =>
      view.getUint32(imageDescOffset + field, Endian.little);
  final rgbSliceByteOffset = imageDesc(Ktx2ImageDescField.rgbSliceByteOffset);
  final rgbSliceByteLength = imageDesc(Ktx2ImageDescField.rgbSliceByteLength);
  final alphaSliceByteLength = imageDesc(
    Ktx2ImageDescField.alphaSliceByteLength,
  );
  if (alphaSliceByteLength != 0) {
    throw const Ktx2FormatException(
      'ETC1S alpha slices are not supported yet.',
    );
  }
  if (rgbSliceByteOffset + rgbSliceByteLength > levelByteLength) {
    throw Ktx2FormatException(
      'ETC1S RGB slice runs from $rgbSliceByteOffset for $rgbSliceByteLength '
      'bytes, past the end of level 0\'s $levelByteLength-byte data.',
    );
  }

  final codebooksOffset = imageDescOffset + Ktx2ImageDescField.bytes;
  final endpointsData = bytes.buffer.asUint8List(
    bytes.offsetInBytes + codebooksOffset,
    endpointsByteLength,
  );
  final selectorsData = bytes.buffer.asUint8List(
    bytes.offsetInBytes + codebooksOffset + endpointsByteLength,
    selectorsByteLength,
  );
  final tablesData = bytes.buffer.asUint8List(
    bytes.offsetInBytes +
        codebooksOffset +
        endpointsByteLength +
        selectorsByteLength,
    tablesByteLength,
  );
  final sliceData = bytes.buffer.asUint8List(
    bytes.offsetInBytes + levelByteOffset + rgbSliceByteOffset,
    rgbSliceByteLength,
  );

  final rgba8 = transcodeEtc1sSliceToRgba8(
    endpointsData: endpointsData,
    numEndpoints: endpointCount,
    selectorsData: selectorsData,
    numSelectors: selectorCount,
    tableData: tablesData,
    sliceData: sliceData,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    numBlocksX: (pixelWidth + 3) ~/ 4,
    numBlocksY: (pixelHeight + 3) ~/ 4,
  );

  return Ktx2Texture._(
    pixelWidth,
    pixelHeight,
    TextureFormat.r8g8b8a8UNormInt,
    [ByteData.view(rgba8.buffer, 0, rgba8.lengthInBytes)],
  );
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
