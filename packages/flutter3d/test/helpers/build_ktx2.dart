/// Assembles a minimal, otherwise-valid KTX2 file so one field at a time can
/// be pushed out of the range the loader accepts.
///
/// The byte layout is copied from the official KTX2 specification and from
/// `VkFormat`'s numbers in `KhronosGroup/KTX-Software` (see
/// `ktx2_format.dart`), assembled here by hand field by field. A test that
/// built a file with the loader's own writer and then read it back would only
/// prove internal consistency; this proves the reader agrees with the
/// format's actual authors.
///
/// The data format descriptor is left absent (`dfdByteLength` stays zero) —
/// the loader never reads it, only `vkFormat` directly, so a file that
/// omitted it is exactly as valid to it as one that carried it. The key/value
/// data is absent by default for the same reason a real file may omit it,
/// and [keyValues] writes a section when a test needs one: the loader does
/// read that, to refuse an orientation, a swizzle or a premultiplication it
/// cannot honour.
///
/// Shared by `ktx2_test.dart`, which pushes fields out of range, and
/// `texture_upload_test.dart`, which hands the results to a device.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/ktx2/ktx2.dart';

Uint8List buildKtx2({
  int vkFormat = VkFormat.bc7UNormBlock,
  int pixelWidth = 4,
  int pixelHeight = 4,
  int pixelDepth = 0,
  int layerCount = 0,
  int faceCount = 1,
  int supercompressionScheme = Ktx2SupercompressionScheme.none,
  Map<String, String> keyValues = const <String, String>{},
  List<List<int>> levels = const [
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
  ],
}) {
  final levelCount = levels.length;
  var cursor = kKtx2LevelIndexOffset + levelCount * kKtx2LevelIndexEntryBytes;

  // Key/value data, if any, sits between the level index and the pixels:
  // per entry, a u32 length, then `key\0value\0`, then padding to four.
  final kvdByteOffset = cursor;
  final kvd = <int>[];
  for (final entry in keyValues.entries) {
    final pair = <int>[
      ...entry.key.codeUnits,
      0,
      ...entry.value.codeUnits,
      // `KTXpremultipliedAlpha` carries no value at all, only its key.
      if (entry.value.isNotEmpty) 0,
    ];
    kvd
      ..addAll(<int>[
        pair.length & 0xFF,
        (pair.length >> 8) & 0xFF,
        (pair.length >> 16) & 0xFF,
        (pair.length >> 24) & 0xFF,
      ])
      ..addAll(pair)
      ..addAll(List<int>.filled((4 - pair.length % 4) % 4, 0));
  }
  cursor += kvd.length;

  final payloadOffsets = <int>[];
  for (final level in levels) {
    payloadOffsets.add(cursor);
    cursor += level.length;
  }

  final bytes = Uint8List(cursor);
  bytes.setRange(0, kKtx2Identifier.length, kKtx2Identifier);
  final view = ByteData.view(bytes.buffer);

  void putHeader(int field, int value) =>
      view.setUint32(kKtx2HeaderOffset + field, value, Endian.little);
  putHeader(Ktx2HeaderField.vkFormat, vkFormat);
  putHeader(Ktx2HeaderField.typeSize, 1);
  putHeader(Ktx2HeaderField.pixelWidth, pixelWidth);
  putHeader(Ktx2HeaderField.pixelHeight, pixelHeight);
  putHeader(Ktx2HeaderField.pixelDepth, pixelDepth);
  putHeader(Ktx2HeaderField.layerCount, layerCount);
  putHeader(Ktx2HeaderField.faceCount, faceCount);
  putHeader(Ktx2HeaderField.levelCount, levelCount);
  putHeader(Ktx2HeaderField.supercompressionScheme, supercompressionScheme);

  if (kvd.isNotEmpty) {
    view.setUint32(
      kKtx2IndexOffset + Ktx2IndexField.kvdByteOffset,
      kvdByteOffset,
      Endian.little,
    );
    view.setUint32(
      kKtx2IndexOffset + Ktx2IndexField.kvdByteLength,
      kvd.length,
      Endian.little,
    );
    bytes.setRange(kvdByteOffset, kvdByteOffset + kvd.length, kvd);
  }

  for (var i = 0; i < levelCount; i++) {
    final entry = kKtx2LevelIndexOffset + i * kKtx2LevelIndexEntryBytes;
    // Each 64-bit field as two little-endian 32-bit halves; the high half is
    // always zero here, well within what every test file needs.
    view.setUint32(entry, payloadOffsets[i], Endian.little);
    view.setUint32(entry + 4, 0, Endian.little);
    view.setUint32(entry + 8, levels[i].length, Endian.little);
    view.setUint32(entry + 12, 0, Endian.little);
    view.setUint32(entry + 16, levels[i].length, Endian.little);
    view.setUint32(entry + 20, 0, Endian.little);
    bytes.setRange(
      payloadOffsets[i],
      payloadOffsets[i] + levels[i].length,
      levels[i],
    );
  }
  return bytes;
}
