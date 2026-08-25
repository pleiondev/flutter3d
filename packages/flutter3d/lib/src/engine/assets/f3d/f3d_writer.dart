import 'dart:convert';
import 'dart:typed_data';

import '../../geometry/geometry.dart';
import '../model_document.dart';
import 'f3d_format.dart';

// `write()` below is the top of the encode pipeline. Writing each section's
// records is split into its own file by theme (geometry, scene, materials,
// animation), mirroring how `f3d_loader.dart` reads them back. Every one of
// them calls the interning/blob helpers declared below, so they are `part`s
// of this library rather than files that import it — see each part's doc
// comment for why.
part 'f3d_writer_animation.dart';
part 'f3d_writer_geometry.dart';
part 'f3d_writer_materials.dart';
part 'f3d_writer_scene.dart';

/// Serializes any [ModelDocument] into the `.f3d` container.
///
/// Takes a [ModelDocument] rather than a glTF or an OBJ, which is the whole
/// reason that abstraction exists: one converter serves every decoder the engine
/// has, and a third format needs a decoder rather than a second writer.
///
/// Runs offline, in `tool/convert_asset.dart`. Nothing here is on a frame path,
/// so it favours being obviously correct over being quick.
final class F3dWriter {
  F3dWriter(this.document);

  final ModelDocument document;

  final BytesBuilder _strings = BytesBuilder();
  final Map<String, int> _internedStrings = <String, int>{};

  final BytesBuilder _blob = BytesBuilder();

  /// Meshes are deduplicated by identity, matching what the decoders already do:
  /// a glTF node graph reuses one mesh across many nodes, and writing it once is
  /// the difference between a file that matches the source and one that
  /// multiplies it.
  final Map<MeshData, int> _meshIndices = <MeshData, int>{};
  final List<MeshData> _meshes = <MeshData>[];

  final Map<VertexLayout, int> _layoutIndices = <VertexLayout, int>{};
  final List<VertexLayout> _layouts = <VertexLayout>[];
  final BytesBuilder _attributes = BytesBuilder();
  int _attributeCount = 0;

  /// Encodes the document. The result is a complete file.
  Uint8List write() {
    // Order matters only in that the blob and the string table must be built
    // before the tables that reference them; the sections themselves are
    // located by the directory, so their file order is free.
    final meshTable = _writeMeshes();
    final surfaceTable = _writeSurfaces();
    final materialTable = _writeMaterials();
    final imageTable = _writeImages();
    final nodeTable = _writeNodes();
    final rootTable = _writeRoots();
    final (animationTable, trackTable, animationCount, trackCount) =
        _writeAnimations();
    final warningTable = _writeWarnings();
    final skinTable = _writeSkins();
    final layoutTable = _writeLayouts();

    final sections = <(int kind, Uint8List data, int count)>[
      (F3dSection.layouts, layoutTable, _layouts.length),
      (F3dSection.attributes, _attributes.toBytes(), _attributeCount),
      (F3dSection.meshes, meshTable, _meshes.length),
      (F3dSection.surfaces, surfaceTable, document.surfaces.length),
      (F3dSection.materials, materialTable, document.materials.length),
      (F3dSection.images, imageTable, document.images.length),
      (F3dSection.nodes, nodeTable, document.nodes.length),
      (F3dSection.roots, rootTable, document.roots.length),
      (F3dSection.animations, animationTable, animationCount),
      (F3dSection.tracks, trackTable, trackCount),
      (F3dSection.warnings, warningTable, document.warnings.length),
      (F3dSection.skins, skinTable, document.skins.length),
      (F3dSection.strings, _strings.toBytes(), 0),
      (F3dSection.blob, _blob.toBytes(), 0),
    ];

    final directoryBytes = sections.length * kF3dSectionEntryBytes;
    var cursor = _align(kF3dHeaderBytes + directoryBytes);

    final offsets = <int>[];
    for (final (_, data, _) in sections) {
      offsets.add(cursor);
      cursor = _align(cursor + data.length);
    }

    final out = Uint8List(cursor);
    final view = ByteData.view(out.buffer);

    view.setUint32(0, kF3dMagic, Endian.little);
    view.setUint32(4, kF3dVersion, Endian.little);
    view.setUint32(8, sections.length, Endian.little);
    view.setUint32(12, 0, Endian.little);

    for (var i = 0; i < sections.length; i++) {
      final (kind, data, count) = sections[i];
      final entry = kF3dHeaderBytes + i * kF3dSectionEntryBytes;
      view.setUint32(entry, kind, Endian.little);
      view.setUint32(entry + 4, offsets[i], Endian.little);
      view.setUint32(entry + 8, data.length, Endian.little);
      view.setUint32(entry + 12, count, Endian.little);
      out.setRange(offsets[i], offsets[i] + data.length, data);
    }

    return out;
  }

  static int _align(int value) => (value + 3) & ~3;

  // ------------------------------------------------------------------ strings

  /// Interns a string and returns `(offset, length)` into the strings section.
  ///
  /// Interned because names repeat heavily — a glTF scene names dozens of nodes
  /// after the same mesh — and because it makes the table deterministic, which
  /// is what lets two conversions of one source be compared byte for byte.
  (int, int) _string(String? value) {
    if (value == null || value.isEmpty) return (0, 0);

    final existing = _internedStrings[value];
    final encoded = utf8.encode(value);
    if (existing != null) return (existing, encoded.length);

    final offset = _strings.length;
    _strings.add(encoded);
    _internedStrings[value] = offset;
    return (offset, encoded.length);
  }

  /// Appends to the blob at a 4-byte boundary and returns the offset.
  int _blobAppend(TypedData data) {
    while (_blob.length % 4 != 0) {
      _blob.addByte(0);
    }
    final offset = _blob.length;
    _blob.add(
      Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
    );
    return offset;
  }

  // ----------------------------------------------------------------- warnings

  Uint8List _writeWarnings() {
    // Carried into the file rather than dropped at conversion. They describe the
    // *model* — an ignored extension, a skipped primitive — not the parse, so
    // losing them means the converted asset looks clean while still being the
    // asset that had the problem.
    final table = Uint8List(document.warnings.length * F3dRecord.warning);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < document.warnings.length; i++) {
      final (offset, length) = _string(document.warnings[i]);
      view.setUint32(i * F3dRecord.warning, offset, Endian.little);
      view.setUint32(i * F3dRecord.warning + 4, length, Endian.little);
    }
    return table;
  }
}
