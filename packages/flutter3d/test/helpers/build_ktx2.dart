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
/// The data format descriptor and key/value data are left absent
/// (`dfdByteLength`/`kvdByteLength` stay zero) — the loader never reads them,
/// only `vkFormat` directly, so a file that omitted them is exactly as valid
/// to it as one that carried them.
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
  List<List<int>> levels = const [
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
  ],
}) {
  final levelCount = levels.length;
  var cursor = kKtx2LevelIndexOffset + levelCount * kKtx2LevelIndexEntryBytes;
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
