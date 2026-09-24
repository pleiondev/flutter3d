import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
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
/// Runs offline, in `dart run flutter3d_build:convert` (`flutter3d_build`).
/// Nothing here is on a frame path, so it favours being obviously correct
/// over being quick.
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

  /// What [write] could not carry — `fmt-12`'s own row.
  ///
  /// **Not empty by assumption.** `.f3d` holds geometry, materials, the
  /// hierarchy, skins and clips, and a document has grown fields since that
  /// the container has no record for: a texture's `KHR_texture_transform`, a
  /// material's own lighting model, lights, cameras, `extras` and an additive
  /// clip's reference time. Each is named here when the document has one, so a
  /// converted asset that draws differently from its source says why.
  late final List<String> warnings = _buildWarnings();

  List<String> _buildWarnings() {
    final materials = document.materials;
    int count(bool Function(SurfaceMaterial) test) =>
        materials.where(test).length;
    bool transformed(TextureBinding? binding) =>
        !(binding?.transform?.isIdentity ?? true);

    final withTransform = count(
      (m) =>
          transformed(m.baseColorTexture) ||
          transformed(m.metallicRoughnessTexture) ||
          transformed(m.normalTexture) ||
          transformed(m.occlusionTexture) ||
          transformed(m.emissiveTexture),
    );
    final withLighting = count((m) => m.lightingModel != null);
    final withExtras =
        count((m) => m.extras != null) +
        document.nodes.where((n) => n.extras != null).length +
        document.skins.where((s) => s.extras != null).length +
        document.animations.where((a) => a.extras != null).length +
        (document.asset?.extras != null ? 1 : 0);
    final additive = document.animations
        .where((a) => a.referenceTime != null)
        .length;

    String dropped(int count, String what) =>
        '$count $what not written; .f3d has no record for it';

    return <String>[
      if (withTransform > 0)
        dropped(withTransform, 'material(s) with a KHR_texture_transform'),
      if (withLighting > 0) dropped(withLighting, 'material lighting model(s)'),
      if (document.lights.isNotEmpty)
        dropped(document.lights.length, 'light(s)'),
      if (document.cameras.isNotEmpty)
        dropped(document.cameras.length, 'camera(s)'),
      if (withExtras > 0) dropped(withExtras, 'extras block(s)'),
      if (additive > 0) dropped(additive, 'additive clip reference time(s)'),
    ];
  }

  /// Encodes the document. The result is a complete file.
  Uint8List write() {
    // Order matters only in that the blob and the string table must be built
    // before the tables that reference them; the sections themselves are
    // located by the directory, so their file order is free.
    final meshTable = _writeMeshes();
    final (morphTable, morphCount) = _writeMorphTargets();
    final (weightTable, weightCount) = _writeMorphWeights();
    final surfaceTable = _writeSurfaces();
    final surfaceAttributeTable = _writeSurfaceAttributes();
    final meshNameTable = _writeMeshNames();
    final (assetTable, assetCount) = _writeAsset();
    final imageUriTable = _writeImageUris();
    final materialTable = _writeMaterials();
    final imageTable = _writeImages();
    final nodeTable = _writeNodes();
    final (lodTable, lodCount) = _writeLods();
    final (impostorTable, impostorCount) = _writeImpostors();
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
      (F3dSection.morphTargets, morphTable, morphCount),
      (F3dSection.morphWeights, weightTable, weightCount),
      (F3dSection.surfaces, surfaceTable, document.surfaces.length),
      (
        F3dSection.surfaceAttributes,
        surfaceAttributeTable,
        document.surfaces.length,
      ),
      (F3dSection.meshNames, meshNameTable, document.surfaces.length),
      (F3dSection.asset, assetTable, assetCount),
      (F3dSection.imageUris, imageUriTable, document.images.length),
      (F3dSection.materials, materialTable, document.materials.length),
      (F3dSection.images, imageTable, document.images.length),
      (F3dSection.nodes, nodeTable, document.nodes.length),
      (F3dSection.lods, lodTable, lodCount),
      // Only when there is one, so a file with no impostor is byte for byte
      // the file this writer produced before the section existed.
      if (impostorCount > 0)
        (F3dSection.impostors, impostorTable, impostorCount),
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
