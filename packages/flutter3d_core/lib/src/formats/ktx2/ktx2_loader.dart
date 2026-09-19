import 'dart:typed_data';

import '../image/inflate.dart';
import 'basis_universal/etc1s_transcoder.dart';
import 'basis_universal/uastc_decoder.dart';
import 'ktx2_format.dart';
import 'universal/universal_block.dart';
import 'zstd.dart';

/// `zlibInflate` in the shape the level loop wants — `gfx-78n`.
///
/// The inflate one directory over already reads a zlib wrapper, which is what
/// KTX2's ZLIB supercompression is; it just does not take a size hint, because
/// PNG's `IDAT` never knows one in advance.
Uint8List? _inflateLevel(Uint8List bytes, {int? sizeHint}) =>
    zlibInflate(bytes);

/// A KTX2 file, read down to what a texture upload needs: dimensions, the
/// raw [vkFormat] its mip bytes are in, and each level's bytes.
///
/// **`vkFormat`, not `TextureFormat`.** `ap-01` in
/// `doc/asset-pipeline-plan.md`: this class used to carry the engine's own
/// `TextureFormat`, and carrying it here would put `flutter3d_hardware` —
/// and the Flutter SDK it needs — on this package's own dependency graph,
/// the thing `flatDartPackages` exists to keep off it. Reading a container
/// and knowing which pixel formats a specific GPU backend accepts are two
/// different questions; this answers only the first, honestly, in the
/// container's own vocabulary — the Khronos [VkFormat] numbers, not an
/// engine's. `flutter3d`'s own `Ktx2Texture` wraps this one and does the
/// second: see its own doc comment for why the exact same wrapping act,
/// with the exact same reasoning, is not new to this session.
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
    this.vkFormat,
    this.levels,
  );

  final int pixelWidth;
  final int pixelHeight;

  /// The Khronos `VkFormat` number the mip bytes are in — see [VkFormat] for
  /// the subset this container ever carries. A Basis Universal file, ETC1S or
  /// UASTC, comes out of here as plain RGBA8, so this is
  /// [VkFormat.r8g8b8a8UNorm] for those paths too: one vocabulary for "what
  /// format are these bytes in", whichever path produced them.
  final int vkFormat;

  /// Level 0 (the base, largest image) first.
  final List<ByteData> levels;

  /// Reads [bytes] as a KTX2 file.
  ///
  /// Throws [Ktx2FormatException] rather than returning null: a caller that
  /// picked this decoder has already decided the bytes are a `.ktx2`, and a
  /// silent null would surface later as a missing texture with no reason.
  ///
  /// [universalTarget] is the GPU format a universal-block file is turned
  /// into on the way past — `gfx-83n`. It is required for such a file and
  /// ignored for every other, because the choice is the device's and this
  /// package cannot see one: [universalBlockFormat] answers whether a file
  /// needs it, and the engine's own wrapper picks the target from what the
  /// device says it samples.
  factory Ktx2Texture.parse(
    Uint8List bytes, {
    UniversalTarget? universalTarget,
  }) {
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
    final keyValues = _checkKeyValues(bytes, view);

    // `vkFormat == 0` (VK_FORMAT_UNDEFINED) is how a KTX2 file says "this is
    // Basis Universal" — the real format then lives in the supercompression
    // global data below, not in this field.
    if (vkFormat == VkFormat.undefined) {
      final universal = keyValues[kUniversalBlockKey];
      if (universal != null) {
        if (levelCount == 0) {
          throw const Ktx2FormatException(
            'levelCount is 0, which asks the loader to generate mip levels at '
            'load time — not implemented yet.',
          );
        }
        if (supercompressionScheme != Ktx2SupercompressionScheme.none) {
          throw Ktx2FormatException(
            'A universal-block file is ${_supercompressionName(supercompressionScheme)}-'
            'compressed, and only an uncompressed one is read here — the '
            'transcode and the decompression would both have to run on the '
            'load, and nothing writes this combination yet.',
          );
        }
        return _parseUniversal(
          bytes,
          view,
          pixelWidth,
          pixelHeight,
          levelCount,
          universal,
          universalTarget,
        );
      }
      // **Which Basis Universal, from the data format descriptor — `gfx-78n`.**
      // An undefined `vkFormat` says "Basis" and nothing more. The
      // supercompression scheme used to stand in for the rest — Basis-LZ
      // means ETC1S, anything else must be UASTC — which was only ever a
      // guess, and the descriptor's colour model is the field that says. A
      // file with no descriptor at all still gets the old inference for
      // Basis-LZ, which cannot be anything but ETC1S: the codebooks it names
      // are ETC1S's.
      final colorModel = _colorModelOf(bytes, view);
      if (colorModel == Ktx2ColorModel.uastc) {
        return _parseUastc(
          bytes,
          view,
          pixelWidth,
          pixelHeight,
          levelCount,
          supercompressionScheme,
        );
      }
      if ((colorModel != null && colorModel != Ktx2ColorModel.etc1s) ||
          supercompressionScheme != Ktx2SupercompressionScheme.basisLZ) {
        final named = colorModel == null
            ? 'there is no descriptor'
            : 'it names colour model $colorModel '
                  '(${Ktx2ColorModel.nameOf(colorModel)})';
        throw Ktx2FormatException(
          'vkFormat is undefined, so the pixels are Basis Universal and the '
          'data format descriptor says which kind: $named, under '
          'supercompression scheme $supercompressionScheme '
          '(${_supercompressionName(supercompressionScheme)}). What is read '
          'here is ETC1S under Basis-LZ, and UASTC LDR 4x4 under none, '
          'Zstandard or ZLIB.',
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

    return Ktx2Texture._(
      pixelWidth,
      pixelHeight,
      vkFormat,
      _readLevels(bytes, view, levelCount, supercompressionScheme),
    );
  }
}

/// Every level's bytes, through the level index and out of whatever
/// supercompression wraps them.
///
/// **Zstandard and ZLIB are unpacked here — `gfx-78n`.** Both wrap the
/// ordinary level index rather than changing it: each level's bytes are a
/// compressed stream and the index's third field says what it decompresses
/// to, so the whole of the difference is one call per level. Anything else,
/// including a vendor number above the range Khronos reserves, is still
/// refused by name. Shared by the plain formats and by UASTC, whose blocks a
/// current encoder Zstandard-compresses unless told not to.
List<ByteData> _readLevels(
  Uint8List bytes,
  ByteData view,
  int levelCount,
  int supercompressionScheme,
) {
  final decompress = switch (supercompressionScheme) {
    Ktx2SupercompressionScheme.none => null,
    Ktx2SupercompressionScheme.zstandard => zstdDecode,
    Ktx2SupercompressionScheme.zlib => _inflateLevel,
    _ => throw Ktx2FormatException(
      'Unsupported supercompression scheme $supercompressionScheme '
      '(${_supercompressionName(supercompressionScheme)}) — not '
      'implemented yet.',
    ),
  };
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
    final byteLength = _readOffsetOrLength(view, entry + 8, 'level $i length');
    if (byteOffset + byteLength > bytes.lengthInBytes) {
      throw Ktx2FormatException(
        'Level $i runs from $byteOffset for $byteLength bytes, past the '
        'end of a ${bytes.lengthInBytes}-byte file.',
      );
    }
    final stored = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes + byteOffset,
      byteLength,
    );
    if (decompress == null) {
      levels.add(stored);
      continue;
    }

    final uncompressed = _readOffsetOrLength(
      view,
      entry + 16,
      'level $i uncompressed length',
    );
    final unpacked = decompress(
      Uint8List.view(stored.buffer, stored.offsetInBytes, byteLength),
      sizeHint: uncompressed,
    );
    if (unpacked == null) {
      throw Ktx2FormatException(
        'Level $i did not decompress as '
        '${_supercompressionName(supercompressionScheme)}.',
      );
    }
    // The index's own claim, held to: a level that unpacks to a different
    // size is a file whose mip dimensions and whose pixels disagree, and
    // uploading it would read past the end of one of them.
    if (unpacked.length != uncompressed) {
      throw Ktx2FormatException(
        'Level $i decompressed to ${unpacked.length} bytes where the level '
        'index says $uncompressed.',
      );
    }
    levels.add(
      ByteData.view(
        unpacked.buffer,
        unpacked.offsetInBytes,
        unpacked.lengthInBytes,
      ),
    );
  }
  return levels;
}

/// The colour model byte of the first block of the data format descriptor.
///
/// The descriptor is a `u32` total size, then blocks; a basic block opens with
/// eight bytes of vendor, type, version and size, and the colour model is the
/// byte after them. Every Basis Universal file has exactly this shape, since
/// the descriptor is the only place the file can say which Basis it is. Null
/// when the file has no descriptor to read.
int? _colorModelOf(Uint8List bytes, ByteData view) {
  final offset = view.getUint32(
    kKtx2IndexOffset + Ktx2IndexField.dfdByteOffset,
    Endian.little,
  );
  final length = view.getUint32(
    kKtx2IndexOffset + Ktx2IndexField.dfdByteLength,
    Endian.little,
  );
  const colorModelAt = 4 + 8;
  if (length == 0) return null;
  if (length <= colorModelAt || offset + length > bytes.lengthInBytes) {
    throw Ktx2FormatException(
      'The data format descriptor is $length bytes at $offset in a '
      '${bytes.lengthInBytes}-byte file, which cannot hold a colour model.',
    );
  }
  return bytes[offset + colorModelAt];
}

/// The UASTC path — `gfx-78n`: every level's blocks unpacked to RGBA8.
///
/// No global data and no slices — a UASTC level is nothing but its blocks,
/// which is why this is a fraction of [_parseBasisEtc1s]. What it shares with
/// the plain formats is the supercompression, and that is [_readLevels].
Ktx2Texture _parseUastc(
  Uint8List bytes,
  ByteData view,
  int pixelWidth,
  int pixelHeight,
  int levelCount,
  int supercompressionScheme,
) {
  final stored = _readLevels(bytes, view, levelCount, supercompressionScheme);
  int extent(int size, int level) => size >> level < 1 ? 1 : size >> level;
  return Ktx2Texture._(
    pixelWidth,
    pixelHeight,
    VkFormat.r8g8b8a8UNorm,
    <ByteData>[
      for (final (level, blocks) in stored.indexed)
        ByteData.sublistView(
          decodeUastcToRgba8(
            Uint8List.sublistView(blocks),
            width: extent(pixelWidth, level),
            height: extent(pixelHeight, level),
          ),
        ),
    ],
  );
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

  return Ktx2Texture._(pixelWidth, pixelHeight, VkFormat.r8g8b8a8UNorm, levels);
}

/// The universal-block path — `gfx-83n`: every level's blocks turned into
/// [target] on the way past.
///
/// **The target is the caller's, and it has to be**, which is the whole point
/// of the format. This package cannot ask a device what it samples without
/// taking on the dependency `ap-01` moved out of it, so the choice arrives
/// from the engine's own wrapper and the refusal for a missing one names that
/// rather than guessing a format.
Ktx2Texture _parseUniversal(
  Uint8List bytes,
  ByteData view,
  int pixelWidth,
  int pixelHeight,
  int levelCount,
  String marker,
  UniversalTarget? target,
) {
  final hasAlpha = switch (marker) {
    kUniversalBlockRgba => true,
    kUniversalBlockRgb => false,
    _ => throw Ktx2FormatException(
      '$kUniversalBlockKey is "$marker", which is not a block layout this '
      'build reads — "$kUniversalBlockRgb" and "$kUniversalBlockRgba" are.',
    ),
  };
  if (target == null) {
    throw const Ktx2FormatException(
      'This file holds universal blocks, which are not a GPU format: the '
      'caller has to name the one the device samples. Parse it again with a '
      'universalTarget.',
    );
  }
  if (hasAlpha && !target.carriesAlpha) {
    throw Ktx2FormatException(
      'This texture carries alpha and ${target.name} does not, so the '
      'transcode would drop it silently.',
    );
  }

  final levels = <ByteData>[];
  for (var i = 0; i < levelCount; i++) {
    final entry = kKtx2LevelIndexOffset + i * kKtx2LevelIndexEntryBytes;
    final byteOffset = _readOffsetOrLength(view, entry, 'level $i offset');
    final byteLength = _readOffsetOrLength(view, entry + 8, 'level $i length');
    if (byteOffset + byteLength > bytes.lengthInBytes) {
      throw Ktx2FormatException(
        'Level $i runs from $byteOffset for $byteLength bytes, past the end '
        'of a ${bytes.lengthInBytes}-byte file.',
      );
    }
    final width = pixelWidth >> i;
    final height = pixelHeight >> i;
    final blocks = Uint8List.view(
      bytes.buffer,
      bytes.offsetInBytes + byteOffset,
      byteLength,
    );
    final transcoded = transcodeUniversal(
      blocks,
      target,
      width: width < 1 ? 1 : width,
      height: height < 1 ? 1 : height,
    );
    levels.add(ByteData.sublistView(transcoded));
  }

  return Ktx2Texture._(pixelWidth, pixelHeight, target.vkFormat, levels);
}

/// Whether [bytes] is a universal-block file and whether it carries alpha, or
/// null when it is an ordinary KTX2.
///
/// Asked before [Ktx2Texture.parse] by a caller that has to pick a target: on
/// the engine's side the device knows what it samples and the isolate the
/// transcode runs on does not, so the choice is made here and carried in.
({bool hasAlpha})? universalBlockFormat(Uint8List bytes) {
  // Long enough for the header and the index that points at the key/value
  // section — this is asked *before* the parse, of bytes nothing has checked,
  // so a file too short to hold the question is a no rather than a throw. The
  // parse that follows is what reports the truncation.
  if (bytes.lengthInBytes < kKtx2LevelIndexOffset) return null;
  if (!isBasisUniversalKtx2(bytes)) return null;
  final view = ByteData.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final marker = _checkKeyValues(bytes, view)[kUniversalBlockKey];
  return switch (marker) {
    kUniversalBlockRgba => (hasAlpha: true),
    kUniversalBlockRgb => (hasAlpha: false),
    _ => null,
  };
}

/// Reads the key/value section, and refuses a file whose entries ask for
/// something the upload does not do.
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
Map<String, String> _checkKeyValues(Uint8List bytes, ByteData view) {
  final entries = <String, String>{};
  final kvdByteOffset = view.getUint32(
    kKtx2IndexOffset + Ktx2IndexField.kvdByteOffset,
    Endian.little,
  );
  final kvdByteLength = view.getUint32(
    kKtx2IndexOffset + Ktx2IndexField.kvdByteLength,
    Endian.little,
  );
  if (kvdByteLength == 0) return entries;
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
    entries[key] = value;
    at += length;
    at = (at + 3) & ~3;
  }
  return entries;
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

/// What to call a `supercompressionScheme` in a refusal.
///
/// `none` is here because it is a value a refused file can well carry: an
/// undefined `vkFormat` with a colour model this does not read — UASTC HDR,
/// say — and no supercompression at all. Calling that a vendor scheme — the
/// fallback's old job for everything unnamed — told the one person most likely
/// to see this message that the spec's own value was somebody's extension.
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
