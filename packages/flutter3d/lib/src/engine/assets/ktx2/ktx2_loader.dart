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
    _checkKeyValues(bytes, view);

    // `vkFormat == 0` (VK_FORMAT_UNDEFINED) is how a KTX2 file says "this is
    // Basis Universal" — the real format then lives in the supercompression
    // global data below, not in this field.
    if (vkFormat == VkFormat.undefined) {
      if (supercompressionScheme != Ktx2SupercompressionScheme.basisLZ) {
        // Naming UASTC because that is what this almost always is: `toktx
        // --uastc` writes an undefined vkFormat with no supercompression,
        // and the only Basis half transcoded here is ETC1S.
        throw Ktx2FormatException(
          'vkFormat is undefined, so the pixels are Basis Universal, but the '
          'supercompression scheme is $supercompressionScheme '
          '(${_supercompressionName(supercompressionScheme)}), not Basis-LZ. '
          'That is what a UASTC file looks like, and only the ETC1S half of '
          'Basis Universal is transcoded here — re-encode with ETC1S '
          '(`toktx --encode etc1s`) or to an explicit vkFormat.',
        );
      }
      if (levelCount == 0) {
        throw const Ktx2FormatException(
          'levelCount is 0, which asks the loader to generate mip levels at '
          'load time — not implemented yet.',
        );
      }
      return _parseBasisEtc1s(bytes, view, pixelWidth, pixelHeight, levelCount);
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
/// reads the supercompression global data — the codebooks and one
/// `ImageDesc` per mip level — then each level's bytes through the ordinary
/// KTX2 level index, and transcodes every level straight to RGBA8.
///
/// **Alpha is a second slice, not a fifth channel.** ETC1S has no alpha, so
/// Basis stores an image with alpha as two ETC1S images in one level — the
/// colour, then the alpha as a grey image — and the `ImageDesc` says where
/// each is. The alpha slice transcodes through the same call as the colour
/// one and its green channel is the alpha, which is what the reference
/// transcoder's `cA32` branch does with it.
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
  int levelCount,
) {
  final levelIndexEnd =
      kKtx2LevelIndexOffset + levelCount * kKtx2LevelIndexEntryBytes;
  if (levelIndexEnd > bytes.lengthInBytes) {
    throw Ktx2FormatException(
      'Level index claims $levelCount entries, which runs past the end of '
      'a ${bytes.lengthInBytes}-byte file.',
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
  // One ImageDesc per image, and with no layers and one face an image is a
  // level: `levelCount` of them, level 0 first, whatever order the levels'
  // bytes sit in the file.
  if (sgdByteLength <
      Ktx2GlobalDataField.headerBytes + levelCount * Ktx2ImageDescField.bytes) {
    throw Ktx2FormatException(
      'Supercompression global data is $sgdByteLength bytes, too short for '
      'its header and $levelCount ImageDescs.',
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

  final imageDescsOffset = sgdByteOffset + Ktx2GlobalDataField.headerBytes;
  final codebooksOffset =
      imageDescsOffset + levelCount * Ktx2ImageDescField.bytes;
  if (codebooksOffset +
          endpointsByteLength +
          selectorsByteLength +
          tablesByteLength >
      sgdByteOffset + sgdByteLength) {
    throw const Ktx2FormatException(
      'The ETC1S codebooks run past the end of the supercompression global '
      'data.',
    );
  }
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

  final levels = <ByteData>[];
  for (var level = 0; level < levelCount; level++) {
    final width = pixelWidth >> level;
    final height = pixelHeight >> level;
    final levelWidth = width < 1 ? 1 : width;
    final levelHeight = height < 1 ? 1 : height;

    final levelEntry =
        kKtx2LevelIndexOffset + level * kKtx2LevelIndexEntryBytes;
    final levelByteOffset = _readOffsetOrLength(
      view,
      levelEntry,
      'level $level offset',
    );
    final levelByteLength = _readOffsetOrLength(
      view,
      levelEntry + 8,
      'level $level length',
    );
    if (levelByteOffset + levelByteLength > bytes.lengthInBytes) {
      throw Ktx2FormatException(
        'Level $level runs from $levelByteOffset for $levelByteLength bytes, '
        'past the end of a ${bytes.lengthInBytes}-byte file.',
      );
    }

    final imageDescOffset = imageDescsOffset + level * Ktx2ImageDescField.bytes;
    int imageDesc(int field) =>
        view.getUint32(imageDescOffset + field, Endian.little);
    final rgbSliceByteOffset = imageDesc(Ktx2ImageDescField.rgbSliceByteOffset);
    final rgbSliceByteLength = imageDesc(Ktx2ImageDescField.rgbSliceByteLength);
    final alphaSliceByteOffset = imageDesc(
      Ktx2ImageDescField.alphaSliceByteOffset,
    );
    final alphaSliceByteLength = imageDesc(
      Ktx2ImageDescField.alphaSliceByteLength,
    );
    if (rgbSliceByteOffset + rgbSliceByteLength > levelByteLength ||
        alphaSliceByteOffset + alphaSliceByteLength > levelByteLength) {
      throw Ktx2FormatException(
        'Level $level\'s ETC1S slices run past the end of its '
        '$levelByteLength-byte data.',
      );
    }

    Uint8List slice(int offset, int length) => bytes.buffer.asUint8List(
      bytes.offsetInBytes + levelByteOffset + offset,
      length,
    );
    Uint8List transcode(Uint8List sliceData) => transcodeEtc1sSliceToRgba8(
      endpointsData: endpointsData,
      numEndpoints: endpointCount,
      selectorsData: selectorsData,
      numSelectors: selectorCount,
      tableData: tablesData,
      sliceData: sliceData,
      pixelWidth: levelWidth,
      pixelHeight: levelHeight,
      numBlocksX: (levelWidth + 3) ~/ 4,
      numBlocksY: (levelHeight + 3) ~/ 4,
    );

    final rgba8 = transcode(slice(rgbSliceByteOffset, rgbSliceByteLength));
    if (alphaSliceByteLength != 0) {
      final alpha = transcode(
        slice(alphaSliceByteOffset, alphaSliceByteLength),
      );
      for (var i = 0; i < levelWidth * levelHeight; i++) {
        rgba8[i * 4 + 3] = alpha[i * 4 + 1];
      }
    }
    levels.add(ByteData.view(rgba8.buffer, 0, rgba8.lengthInBytes));
  }

  return Ktx2Texture._(
    pixelWidth,
    pixelHeight,
    TextureFormat.r8g8b8a8UNormInt,
    levels,
  );
}

/// Refuses a file whose key/value data asks for something the upload does
/// not do.
///
/// The section was skipped entirely until this, and skipping it is not free:
/// its three interesting keys each describe pixels the upload would then get
/// wrong without a word, and wrong in a way that looks like an authoring
/// mistake rather than a loader one.
///
///  * `KTXorientation` — the axes the rows run along. `rd` (left to right,
///    top to bottom) is the specification's default and what `toktx` writes,
///    and it is what the upload assumes; a file from a GL-oriented writer
///    says `ru` and would arrive upside down.
///  * `KTXswizzle` — a channel permutation to apply on sampling. Nothing
///    here applies one, so anything but `rgba` samples the wrong channels.
///  * `KTXpremultipliedAlpha` — its mere presence is the flag. Base-colour
///    textures are sampled and then multiplied by the material factor (see
///    `texture_upload.dart`), so a premultiplied texture darkens its
///    translucent texels twice.
///
/// Refused rather than warned because this stage has no warnings list to
/// hand anything to: it throws or it returns a texture, and a texture it
/// knows is wrong is the one thing it must not return. Honouring any of the
/// three later is additive — a flip, a swizzle in the sampler, an unmultiply
/// — and each turns a refusal into a load.
void _checkKeyValues(Uint8List bytes, ByteData view) {
  final kvdByteOffset = view.getUint32(
    kKtx2IndexOffset + Ktx2IndexField.kvdByteOffset,
    Endian.little,
  );
  final kvdByteLength = view.getUint32(
    kKtx2IndexOffset + Ktx2IndexField.kvdByteLength,
    Endian.little,
  );
  if (kvdByteLength == 0) return;
  if (kvdByteOffset + kvdByteLength > bytes.lengthInBytes) {
    throw Ktx2FormatException(
      'Key/value data runs from $kvdByteOffset for $kvdByteLength bytes, '
      'past the end of a ${bytes.lengthInBytes}-byte file.',
    );
  }

  final end = kvdByteOffset + kvdByteLength;
  // Entries are a u32 length, that many bytes of NUL-separated key and
  // value, then padding to the next multiple of four. Fewer than four bytes
  // left is that padding, not a truncated entry.
  for (var at = kvdByteOffset; at + 4 <= end;) {
    final length = view.getUint32(at, Endian.little);
    at += 4;
    if (length == 0 || at + length > end) {
      throw Ktx2FormatException(
        'A key/value entry claims $length bytes, and only ${end - at} of the '
        'section are left.',
      );
    }
    final entry = bytes.buffer.asUint8List(bytes.offsetInBytes + at, length);
    final nul = entry.indexOf(0);
    if (nul < 0) {
      throw const Ktx2FormatException(
        'A key/value entry has no NUL between its key and its value.',
      );
    }
    final key = String.fromCharCodes(entry.sublist(0, nul));
    // The value is a NUL-terminated string for every key read here, and the
    // terminator counts towards the entry's length rather than the text's.
    final raw = entry.sublist(nul + 1);
    final value = String.fromCharCodes(
      raw.isNotEmpty && raw.last == 0 ? raw.sublist(0, raw.length - 1) : raw,
    );
    switch (key) {
      case 'KTXorientation':
        if (value != 'rd') {
          throw Ktx2FormatException(
            'KTXorientation is "$value", and this loader uploads rows as they '
            'come, which only "rd" (left to right, top to bottom) describes.',
          );
        }
      case 'KTXswizzle':
        if (value != 'rgba') {
          throw Ktx2FormatException(
            'KTXswizzle is "$value", and nothing here permutes channels on '
            'sampling, so the texture would be sampled unswizzled.',
          );
        }
      case 'KTXpremultipliedAlpha':
        throw const Ktx2FormatException(
          'KTXpremultipliedAlpha is set, and this engine samples base-colour '
          'textures straight and multiplies by the material factor after, so '
          'the translucent texels would be darkened twice.',
        );
    }
    at += length;
    at = (at + 3) & ~3;
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
///
/// **An sRGB `vkFormat` maps to the linear-sampling engine format with the
/// same bits**, which is a deliberate reinterpretation and not an oversight.
/// The two differ only in whether the *sampler* decodes; the payload of a
/// `BC7_SRGB` block and a `BC7_UNORM` one is identical, as it is for ETC2,
/// ASTC and RGBA8. This engine's shaders decode themselves —
/// `SrgbToLinear(texel.rgb)` in `surface.glsl`, `toLinear` in
/// `cpu_shaders_surface.dart` — for the same reason `color.glsl` says the
/// render target is a plain UNorm format: the decode belongs where the code
/// can see it, and the software rasteriser has no hardware sampler to
/// delegate it to. Handing Impeller or WebGL2 a real sRGB format decoded the
/// texture twice and drew it dark, on the two backends only, from a file the
/// third read correctly.
///
/// It also puts the decision where it belongs. Whether a texture is colour is
/// a property of the *slot*, not of the file: `surface.glsl` decodes the base
/// colour and the emissive map and leaves the normal and metallic-roughness
/// maps alone. A normal map an encoder happened to write as `BC7_SRGB` was
/// decoded anyway while the sampler made the choice.
TextureFormat? _engineFormat(int vkFormat) => switch (vkFormat) {
  VkFormat.r8g8b8a8UNorm ||
  VkFormat.r8g8b8a8Srgb => TextureFormat.r8g8b8a8UNormInt,
  VkFormat.b8g8r8a8UNorm ||
  VkFormat.b8g8r8a8Srgb => TextureFormat.b8g8r8a8UNormInt,
  VkFormat.r16g16b16a16Sfloat => TextureFormat.r16g16b16a16Float,
  VkFormat.r32Sfloat => TextureFormat.r32Float,
  VkFormat.r32g32b32a32Sfloat => TextureFormat.r32g32b32a32Float,
  VkFormat.bc1RgbaUNormBlock ||
  VkFormat.bc1RgbaSrgbBlock => TextureFormat.bc1RGBAUNormInt,
  VkFormat.bc3UNormBlock ||
  VkFormat.bc3SrgbBlock => TextureFormat.bc3RGBAUNormInt,
  VkFormat.bc5UNormBlock => TextureFormat.bc5RGUNormInt,
  VkFormat.bc7UNormBlock ||
  VkFormat.bc7SrgbBlock => TextureFormat.bc7RGBAUNormInt,
  VkFormat.etc2R8g8b8UNormBlock ||
  VkFormat.etc2R8g8b8SrgbBlock => TextureFormat.etc2RGB8UNormInt,
  VkFormat.etc2R8g8b8a8UNormBlock ||
  VkFormat.etc2R8g8b8a8SrgbBlock => TextureFormat.etc2RGBA8UNormInt,
  VkFormat.astc4x4UNormBlock ||
  VkFormat.astc4x4SrgbBlock => TextureFormat.astc4x4LDR,
  VkFormat.astc8x8UNormBlock ||
  VkFormat.astc8x8SrgbBlock => TextureFormat.astc8x8LDR,
  VkFormat.astc4x4SfloatBlock => TextureFormat.astc4x4HDR,
  VkFormat.astc8x8SfloatBlock => TextureFormat.astc8x8HDR,
  _ => null,
};

/// What to call a `supercompressionScheme` in a refusal.
///
/// `none` is here because it is the value a refused file most often carries:
/// UASTC leaves `vkFormat` undefined the way ETC1S does and then does not
/// supercompress at all, so the branch that expects Basis-LZ reads a nought.
/// Calling that a vendor scheme — the fallback's old job for everything
/// unnamed — told the one person most likely to see this message that the
/// spec's own value was somebody's extension.
String _supercompressionName(int scheme) => switch (scheme) {
  Ktx2SupercompressionScheme.none => 'none',
  Ktx2SupercompressionScheme.basisLZ => 'Basis-LZ',
  Ktx2SupercompressionScheme.zstandard => 'Zstandard',
  Ktx2SupercompressionScheme.zlib => 'ZLIB',
  // Khronos keeps everything to 0xFFFF; past it is a vendor's.
  _ => scheme > 0xFFFF ? 'vendor scheme $scheme' : 'unknown scheme $scheme',
};

/// True when [bytes] is a KTX2 file whose `vkFormat` is undefined — a Basis
/// Universal file, whose pixels are a transcode rather than a copy.
///
/// Asked before [Ktx2Texture.parse] by a caller deciding where to run it: a
/// plain file's parse is a handful of reads and belongs on the calling
/// isolate, a transcode is a pass over every block and does not.
bool isBasisUniversalKtx2(Uint8List bytes) {
  if (!isKtx2File(bytes) ||
      bytes.lengthInBytes < kKtx2HeaderOffset + Ktx2HeaderField.vkFormat + 4) {
    return false;
  }
  return ByteData.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      ).getUint32(
        kKtx2HeaderOffset + Ktx2HeaderField.vkFormat,
        Endian.little,
      ) ==
      VkFormat.undefined;
}

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
