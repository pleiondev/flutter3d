import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';

import '../fmat/lighting_json.dart';
import '../model_document.dart';
import 'f3d_format.dart';
import 'f3d_loader.dart';
import 'f3d_wire.dart';

// `write()` below is the top of the encode pipeline. Writing each section's
// records is split into its own file by theme (geometry, scene, materials,
// animation), mirroring how `f3d_loader.dart` reads them back. Every one of
// them calls the interning/blob helpers declared below, so they are `part`s
// of this library rather than files that import it — see each part's doc
// comment for why.
part 'f3d_writer_animation.dart';
part 'f3d_writer_bundle.dart';
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
  F3dWriter(
    this.document, {
    List<F3dExtraSection> extraSections = const <F3dExtraSection>[],
    Map<String, String> programs = const <String, String>{},
    Map<String, Map<String, Object?>> prefabs =
        const <String, Map<String, Object?>>{},
    Map<String, Uint8List> files = const <String, Uint8List>{},
  }) : extraSections = List<F3dExtraSection>.unmodifiable(extraSections),
       programs = Map<String, String>.unmodifiable(programs),
       prefabs = Map<String, Map<String, Object?>>.unmodifiable(prefabs),
       files = Map<String, Uint8List>.unmodifiable(files) {
    for (final extra in extraSections) {
      if (F3dSection.known.contains(extra.kind)) {
        throw ArgumentError.value(
          extra.kind,
          'extraSections',
          'is one of the engine\'s kinds',
        );
      }
    }
  }

  /// A writer for [document] that carries everything a `.f3d` it was read
  /// from carried: its programs, prefabs, files and every section of a kind
  /// the engine does not write itself, flags included. A document from any
  /// other reader carries nothing beyond the model.
  ///
  /// This is what re-exporting a bundle goes through (`F3dModelWriter`), so
  /// a `.f3d` opened and saved keeps its bundle and a tool's sections.
  factory F3dWriter.carrying(ModelDocument document) => switch (document) {
    final F3dDocument bundle => F3dWriter(
      bundle,
      programs: bundle.programs,
      prefabs: bundle.prefabs,
      files: bundle.files,
      extraSections: bundle.extraSections,
    ),
    _ => F3dWriter(document),
  };

  final ModelDocument document;

  /// Material language (`.f3dmat`) sources to carry, by the name a material's
  /// lighting model names them by — [F3dSection.programs].
  final Map<String, String> programs;

  /// Level and prefab documents to carry, by name, each a JSON object in the
  /// format envelope (`"format": "f3d.level"`) — [F3dSection.prefabs].
  final Map<String, Map<String, Object?>> prefabs;

  /// Files to carry whole, by the path a prefab names them by —
  /// [F3dSection.files].
  final Map<String, Uint8List> files;

  /// Sections written after the engine's own, as they are: a tool's data under
  /// a [f3dVendorKindStart] kind, or a section a newer engine reads.
  ///
  /// **Only a section with [F3dExtraSection.flags] set makes the file version
  /// 2**, because version 2 is the one whose directory carries the flags.
  /// Everything else, the bundle's sections and unflagged extra sections
  /// included, is written at version 1. The 0.8 readers accept only version 1
  /// and skip kinds they do not know, so they still open such a file and draw
  /// its geometry.
  final List<F3dExtraSection> extraSections;

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
  /// the container has no record for: a texture's `KHR_texture_transform`,
  /// splat clouds and an additive clip's reference time. `extras`, lights,
  /// cameras and a material's lighting model it carries (in
  /// [F3dSection.extras] and the bundle's sections). Each one it cannot is
  /// named here when the document has one, so a converted asset that draws
  /// differently from its source says why.
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
    final additive = document.animations
        .where((a) => a.referenceTime != null)
        .length;

    String dropped(int count, String what) =>
        '$count $what not written; .f3d has no record for it';

    return <String>[
      if (withTransform > 0)
        dropped(withTransform, 'material(s) with a KHR_texture_transform'),
      if (document.splats.isNotEmpty)
        dropped(document.splats.length, 'splat cloud(s)'),
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
    final (clusterTable, clusterCount) = _writeClusters();
    final surfaceTable = _writeSurfaces();
    final surfaceAttributeTable = _writeSurfaceAttributes();
    final meshNameTable = _writeMeshNames();
    final (assetTable, assetCount) = _writeAsset();
    final imageUriTable = _writeImageUris();
    final materialTable = _writeMaterials();
    final (extensionTable, extensionCount) = _writeMaterialExtensions();
    final imageTable = _writeImages();
    final nodeTable = _writeNodes();
    final (lodTable, lodCount) = _writeLods();
    final lodErrorTable = _writeLodErrors();
    final (impostorTable, impostorCount) = _writeImpostors();
    final rootTable = _writeRoots();
    final (animationTable, trackTable, animationCount, trackCount) =
        _writeAnimations();
    final (pointerTrackTable, pointerTrackCount) = _writePointerTracks();
    final variantTable = _writeVariants();
    final warningTable = _writeWarnings();
    final skinTable = _writeSkins();
    final layoutTable = _writeLayouts();
    final (extrasTable, extrasCount) = _writeExtras();
    final (lightTable, lightCount) = _writeLights();
    final (cameraTable, cameraCount) = _writeCameras();
    final (attachmentTable, attachmentCount) = _writeNodeAttachments();
    final (lightingTable, lightingCount) = _writeMaterialLighting();
    final (programTable, programCount) = _writePrograms();
    final (prefabTable, prefabCount) = _writePrefabs();
    final (fileTable, fileCount) = _writeFiles();

    final sections = <(int kind, Uint8List data, int count)>[
      (F3dSection.layouts, layoutTable, _layouts.length),
      (F3dSection.attributes, _attributes.toBytes(), _attributeCount),
      (F3dSection.meshes, meshTable, _meshes.length),
      (F3dSection.morphTargets, morphTable, morphCount),
      (F3dSection.morphWeights, weightTable, weightCount),
      // Only when a mesh was split, so every other file is the bytes it was.
      if (clusterCount > 0) (F3dSection.clusters, clusterTable, clusterCount),
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
      (F3dSection.materialExtensions, extensionTable, extensionCount),
      (F3dSection.images, imageTable, document.images.length),
      (F3dSection.nodes, nodeTable, document.nodes.length),
      (F3dSection.lods, lodTable, lodCount),
      if (lodErrorTable != null)
        (F3dSection.lodErrors, lodErrorTable, lodCount),
      // Only when there is one, so a file with no impostor is byte for byte
      // the file this writer produced before the section existed.
      if (impostorCount > 0)
        (F3dSection.impostors, impostorTable, impostorCount),
      (F3dSection.roots, rootTable, document.roots.length),
      (F3dSection.animations, animationTable, animationCount),
      (F3dSection.tracks, trackTable, trackCount),
      // Only when there is something to say, so a document with neither
      // writes the same bytes it did before these sections existed — a
      // converted asset should not change on disk for a feature it lacks.
      if (pointerTrackCount > 0)
        (F3dSection.pointerTracks, pointerTrackTable, pointerTrackCount),
      if (document.variants.isNotEmpty)
        (F3dSection.variants, variantTable, document.variants.length),
      (F3dSection.warnings, warningTable, document.warnings.length),
      (F3dSection.skins, skinTable, document.skins.length),
      // Only when there is one, so a document with none writes the bytes it
      // did before the section existed.
      if (extrasCount > 0) (F3dSection.extras, extrasTable, extrasCount),
      // The bundle's sections, each only when there is something in it, for
      // the same reason: a model without them is the bytes it always was.
      if (lightCount > 0) (F3dSection.lights, lightTable, lightCount),
      if (cameraCount > 0) (F3dSection.cameras, cameraTable, cameraCount),
      if (attachmentCount > 0)
        (F3dSection.nodeAttachments, attachmentTable, attachmentCount),
      if (lightingCount > 0)
        (F3dSection.materialLighting, lightingTable, lightingCount),
      if (programCount > 0) (F3dSection.programs, programTable, programCount),
      if (prefabCount > 0) (F3dSection.prefabs, prefabTable, prefabCount),
      if (fileCount > 0) (F3dSection.files, fileTable, fileCount),
      (F3dSection.strings, _strings.toBytes(), 0),
      (F3dSection.blob, _blob.toBytes(), 0),
      for (final extra in extraSections) (extra.kind, extra.bytes, extra.count),
    ];
    final version = extraSections.any((extra) => extra.flags != 0) ? 2 : 1;
    final entryBytes = version == 1
        ? f3dSectionEntryBytes
        : f3dSectionEntryBytesV2;

    final directoryBytes = sections.length * entryBytes;
    var cursor = _align(f3dHeaderBytes + directoryBytes);

    final offsets = <int>[];
    for (final (_, data, _) in sections) {
      offsets.add(cursor);
      cursor = _align(cursor + data.length);
    }

    final out = Uint8List(cursor);
    final view = ByteData.view(out.buffer);

    view.setUint32(0, f3dMagic, Endian.little);
    view.setUint32(4, version, Endian.little);
    view.setUint32(8, sections.length, Endian.little);
    view.setUint32(12, version == 1 ? 0 : entryBytes, Endian.little);

    for (var i = 0; i < sections.length; i++) {
      final (kind, data, count) = sections[i];
      final entry = f3dHeaderBytes + i * entryBytes;
      view.setUint32(entry, kind, Endian.little);
      view.setUint32(entry + 4, offsets[i], Endian.little);
      view.setUint32(entry + 8, data.length, Endian.little);
      view.setUint32(entry + 12, count, Endian.little);
      if (version > 1) {
        final extraIndex = i - (sections.length - extraSections.length);
        view.setUint32(
          entry + 16,
          extraIndex >= 0 ? extraSections[extraIndex].flags : 0,
          Endian.little,
        );
      }
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

/// A section of a `.f3d` as its directory describes it: what
/// [F3dDocument.section] reads back, and what [F3dWriter] writes beside the
/// engine's own.
///
/// A section handed to [F3dWriter.extraSections] must not be one of the
/// engine's kinds ([F3dSection.known]), which the writer checks; a tool's own
/// data takes a kind from [f3dVendorKindStart] up.
final class F3dExtraSection {
  F3dExtraSection({
    required this.kind,
    required this.bytes,
    this.count = 0,
    this.flags = 0,
  });

  final int kind;
  final Uint8List bytes;

  /// Records in [bytes], for a table; 0 for raw bytes.
  final int count;

  /// [F3dSectionFlags] bits; [F3dSectionFlags.mustUnderstand] makes a reader
  /// that does not know [kind] refuse the file.
  final int flags;
}
