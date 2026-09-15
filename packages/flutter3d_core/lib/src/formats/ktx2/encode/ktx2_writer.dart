import 'dart:typed_data';

import '../ktx2_format.dart';

/// Assembles a KTX2 file from already-encoded mip levels — the writer half
/// of `ktx2_loader.dart`, and the reason `ap-07` in
/// `doc/asset-pipeline-plan.md` lives beside it rather than in
/// `flutter3d_build`: both read and write the same container, in the same
/// package, with no Flutter SDK behind either.
///
/// **No data format descriptor, no key/value data.** The specification asks
/// for a DFD; `ktx2_loader.dart`'s own doc comment says why this engine's
/// reader never looks at one — it takes the format from the header alone —
/// so a writer whose only reader is this one has nothing to gain from
/// spending bytes on a section nothing here parses. A file this writes and
/// a third-party tool (RenderDoc, `ktx2check`) opens would want one; nothing
/// in this repository does that yet, and adding the section later is
/// additive, the same reasoning `ktx2_format.dart` gives for refusing a
/// feature outright rather than half-writing it.
///
/// [levels] is level 0 (the base, largest image) first, matching
/// `Ktx2Texture.levels`' own order — a caller with an encoder's single-level
/// output and a caller with `ap-08`'s future mip chain call this the same
/// way.
Uint8List writeKtx2({
  required int vkFormat,
  required int pixelWidth,
  required int pixelHeight,
  required List<Uint8List> levels,
}) {
  if (levels.isEmpty) {
    throw ArgumentError('writeKtx2 needs at least one level (level 0).');
  }

  final levelCount = levels.length;
  final levelIndexEnd =
      kKtx2LevelIndexOffset + levelCount * kKtx2LevelIndexEntryBytes;
  final levelOffsets = <int>[];
  var cursor = levelIndexEnd;
  for (final level in levels) {
    levelOffsets.add(cursor);
    cursor += level.lengthInBytes;
  }

  final bytes = Uint8List(cursor);
  bytes.setRange(0, kKtx2Identifier.length, kKtx2Identifier);
  final view = ByteData.sublistView(bytes);

  void putHeader(int field, int value) =>
      view.setUint32(kKtx2HeaderOffset + field, value, Endian.little);
  putHeader(Ktx2HeaderField.vkFormat, vkFormat);
  // Block-compressed formats carry no per-texel type: the spec's own
  // wording for `typeSize` is "1 for block-compressed formats".
  putHeader(Ktx2HeaderField.typeSize, 1);
  putHeader(Ktx2HeaderField.pixelWidth, pixelWidth);
  putHeader(Ktx2HeaderField.pixelHeight, pixelHeight);
  putHeader(Ktx2HeaderField.pixelDepth, 0);
  putHeader(Ktx2HeaderField.layerCount, 0);
  putHeader(Ktx2HeaderField.faceCount, 1);
  putHeader(Ktx2HeaderField.levelCount, levelCount);
  putHeader(
    Ktx2HeaderField.supercompressionScheme,
    Ktx2SupercompressionScheme.none,
  );

  for (var i = 0; i < levelCount; i++) {
    final entry = kKtx2LevelIndexOffset + i * kKtx2LevelIndexEntryBytes;
    final length = levels[i].lengthInBytes;
    // 64-bit fields as two little-endian 32-bit halves, high half always
    // zero — the same limit `ktx2_loader.dart`'s `_readOffsetOrLength`
    // states, and nothing an encoder in this package ever produces gets
    // near it.
    view.setUint32(entry, levelOffsets[i], Endian.little);
    view.setUint32(entry + 4, 0, Endian.little);
    view.setUint32(entry + 8, length, Endian.little);
    view.setUint32(entry + 12, 0, Endian.little);
    // No supercompression, so the uncompressed length is the stored length.
    view.setUint32(entry + 16, length, Endian.little);
    view.setUint32(entry + 20, 0, Endian.little);
    bytes.setRange(levelOffsets[i], levelOffsets[i] + length, levels[i]);
  }

  return bytes;
}
