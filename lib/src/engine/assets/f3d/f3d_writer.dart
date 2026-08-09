import 'dart:convert';
import 'dart:typed_data';

import '../../geometry/geometry.dart';
import '../model_document.dart';
import 'f3d_format.dart';

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

  // ------------------------------------------------------------------ layouts

  int _layoutIndex(VertexLayout layout) {
    final existing = _layoutIndices[layout];
    if (existing != null) return existing;

    final index = _layouts.length;
    _layouts.add(layout);
    _layoutIndices[layout] = index;
    return index;
  }

  Uint8List _writeLayouts() {
    final table = Uint8List(_layouts.length * F3dRecord.layout);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < _layouts.length; i++) {
      final layout = _layouts[i];
      final first = _attributeCount;

      for (final attribute in layout.attributes) {
        final (nameOffset, nameLength) = _string(attribute.name);
        final record = ByteData(F3dRecord.attribute);
        record.setUint32(0, nameOffset, Endian.little);
        record.setUint32(4, nameLength, Endian.little);
        record.setUint32(8, attribute.componentCount, Endian.little);
        _attributes.add(record.buffer.asUint8List());
        _attributeCount++;
      }

      final o = i * F3dRecord.layout;
      view.setUint32(o, layout.attributes.length, Endian.little);
      view.setUint32(o + 4, first, Endian.little);
    }
    return table;
  }

  // ------------------------------------------------------------------- meshes

  int _meshIndex(MeshData mesh) {
    final existing = _meshIndices[mesh];
    if (existing != null) return existing;
    final index = _meshes.length;
    _meshes.add(mesh);
    _meshIndices[mesh] = index;
    return index;
  }

  Uint8List _writeMeshes() {
    // Collected first so the mesh table is written in one pass, and so surfaces
    // can reference indices that already exist.
    for (final surface in document.surfaces) {
      _meshIndex(surface.mesh);
    }

    final table = Uint8List(_meshes.length * F3dRecord.mesh);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < _meshes.length; i++) {
      final mesh = _meshes[i];
      // Written exactly as `MeshData` holds them, which is the whole point: the
      // loader views these bytes rather than rebuilding the arrays. Indices stay
      // 32-bit even where 16 would fit — narrowing would save a few kilobytes
      // and cost the very copy the format exists to avoid.
      final vertexOffset = _blobAppend(mesh.vertices);
      final indexOffset = _blobAppend(mesh.indices);

      final o = i * F3dRecord.mesh;
      view.setUint32(o, _layoutIndex(mesh.layout), Endian.little);
      view.setUint32(o + 4, vertexOffset, Endian.little);
      view.setUint32(o + 8, mesh.vertices.lengthInBytes, Endian.little);
      view.setUint32(o + 12, indexOffset, Endian.little);
      view.setUint32(o + 16, mesh.indices.lengthInBytes, Endian.little);
      view.setUint32(o + 20, mesh.vertexCount, Endian.little);
    }
    return table;
  }

  // ----------------------------------------------------------------- surfaces

  Uint8List _writeSurfaces() {
    final table = Uint8List(document.surfaces.length * F3dRecord.surface);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < document.surfaces.length; i++) {
      final surface = document.surfaces[i];
      final (nameOffset, nameLength) = _string(surface.name);

      final o = i * F3dRecord.surface;
      view.setUint32(o, _meshIndex(surface.mesh), Endian.little);
      view.setInt32(o + 4, surface.materialIndex ?? -1, Endian.little);
      view.setUint32(o + 8, nameOffset, Endian.little);
      view.setUint32(o + 12, nameLength, Endian.little);
      view.setUint32(o + 16, surface.flipWinding ? 1 : 0, Endian.little);

      // Column-major, matching vector_math's storage, so the reader can copy
      // straight into a Matrix4 without transposing.
      for (var e = 0; e < 16; e++) {
        view.setFloat32(
          o + 20 + e * 4,
          surface.transform.storage[e],
          Endian.little,
        );
      }
    }
    return table;
  }

  // ---------------------------------------------------------------- materials

  Uint8List _writeMaterials() {
    final table = Uint8List(document.materials.length * F3dRecord.material);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < document.materials.length; i++) {
      final material = document.materials[i];
      final (nameOffset, nameLength) = _string(material.name);
      var o = i * F3dRecord.material;

      view.setUint32(o, nameOffset, Endian.little);
      view.setUint32(o + 4, nameLength, Endian.little);
      o += 8;

      view.setFloat32(o, material.baseColor.x, Endian.little);
      view.setFloat32(o + 4, material.baseColor.y, Endian.little);
      view.setFloat32(o + 8, material.baseColor.z, Endian.little);
      view.setFloat32(o + 12, material.baseColor.w, Endian.little);
      o += 16;

      view.setFloat32(o, material.metallic, Endian.little);
      view.setFloat32(o + 4, material.roughness, Endian.little);
      view.setFloat32(o + 8, material.normalScale, Endian.little);
      view.setFloat32(o + 12, material.occlusionStrength, Endian.little);
      o += 16;

      view.setFloat32(o, material.emissive.x, Endian.little);
      view.setFloat32(o + 4, material.emissive.y, Endian.little);
      view.setFloat32(o + 8, material.emissive.z, Endian.little);
      view.setFloat32(o + 12, material.emissiveStrength, Endian.little);
      o += 16;

      // The alpha mode's index is written deliberately: the enum is part of the
      // format now, so its order may not be shuffled without a version bump.
      view.setUint32(o, material.alphaMode.index, Endian.little);
      view.setFloat32(o + 4, material.alphaCutoff, Endian.little);
      view.setUint32(o + 8, material.doubleSided ? 1 : 0, Endian.little);
      view.setUint32(o + 12, material.unlit ? 1 : 0, Endian.little);
      o += 16;

      for (final binding in <TextureBinding?>[
        material.baseColorTexture,
        material.metallicRoughnessTexture,
        material.normalTexture,
        material.occlusionTexture,
        material.emissiveTexture,
      ]) {
        _writeBinding(view, o, binding);
        o += F3dRecord.textureBinding;
      }
    }
    return table;
  }

  void _writeBinding(ByteData view, int offset, TextureBinding? binding) {
    if (binding == null) {
      // -1 rather than a separate "present" flag: an index is either a real
      // image or it is not, and one sentinel cannot disagree with itself.
      view.setInt32(offset, -1, Endian.little);
      view.setUint32(offset + 4, 0, Endian.little);
      view.setUint32(offset + 8, 0, Endian.little);
      return;
    }

    final s = binding.sampling;
    var flags = 0;
    if (s.magLinear) flags |= F3dSamplingFlags.magLinear;
    if (s.minLinear) flags |= F3dSamplingFlags.minLinear;
    if (s.useMipmaps) flags |= F3dSamplingFlags.useMipmaps;
    flags |= s.wrapS.index << F3dSamplingFlags.wrapSShift;
    flags |= s.wrapT.index << F3dSamplingFlags.wrapTShift;

    view.setInt32(offset, binding.imageIndex, Endian.little);
    view.setUint32(offset + 4, binding.texCoordSet, Endian.little);
    view.setUint32(offset + 8, flags, Endian.little);
  }

  // ------------------------------------------------------------------- images

  Uint8List _writeImages() {
    final table = Uint8List(document.images.length * F3dRecord.image);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < document.images.length; i++) {
      final image = document.images[i];
      // Still encoded. Decoding a PNG needs `dart:ui`, which the asset layer
      // deliberately does not have, and a converter that produced raw RGBA
      // would multiply the file size by ten to save a decode the GPU upload
      // path already has to do.
      final dataOffset = _blobAppend(image.bytes);
      final (nameOffset, nameLength) = _string(image.name);
      final (mimeOffset, mimeLength) = _string(image.mimeType);

      final o = i * F3dRecord.image;
      view.setUint32(o, dataOffset, Endian.little);
      view.setUint32(o + 4, image.bytes.length, Endian.little);
      view.setUint32(o + 8, nameOffset, Endian.little);
      view.setUint32(o + 12, nameLength, Endian.little);
      view.setUint32(o + 16, mimeOffset, Endian.little);
      view.setUint32(o + 20, mimeLength, Endian.little);
    }
    return table;
  }

  // -------------------------------------------------------------------- nodes

  Uint8List _writeNodes() {
    final nodes = document.nodes;
    final table = Uint8List(nodes.length * F3dRecord.node);
    final view = ByteData.view(table.buffer);

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final (nameOffset, nameLength) = _string(node.name);
      final childOffset = _blobAppend(Int32List.fromList(node.children));
      final surfaceOffset = _blobAppend(Int32List.fromList(node.surfaces));

      var o = i * F3dRecord.node;
      view.setUint32(o, nameOffset, Endian.little);
      view.setUint32(o + 4, nameLength, Endian.little);
      o += 8;

      view.setFloat32(o, node.translation.x, Endian.little);
      view.setFloat32(o + 4, node.translation.y, Endian.little);
      view.setFloat32(o + 8, node.translation.z, Endian.little);
      o += 12;

      view.setFloat32(o, node.rotation.x, Endian.little);
      view.setFloat32(o + 4, node.rotation.y, Endian.little);
      view.setFloat32(o + 8, node.rotation.z, Endian.little);
      view.setFloat32(o + 12, node.rotation.w, Endian.little);
      o += 16;

      view.setFloat32(o, node.scale.x, Endian.little);
      view.setFloat32(o + 4, node.scale.y, Endian.little);
      view.setFloat32(o + 8, node.scale.z, Endian.little);
      o += 12;

      view.setUint32(o, childOffset, Endian.little);
      view.setUint32(o + 4, node.children.length, Endian.little);
      view.setUint32(o + 8, surfaceOffset, Endian.little);
      view.setUint32(o + 12, node.surfaces.length, Endian.little);
    }
    return table;
  }

  Uint8List _writeRoots() {
    final roots = Int32List.fromList(document.roots);
    return Uint8List.view(
      roots.buffer,
      roots.offsetInBytes,
      roots.lengthInBytes,
    );
  }

  // --------------------------------------------------------------- animations

  (Uint8List, Uint8List, int, int) _writeAnimations() {
    final clips = document.animations;
    final animationTable = Uint8List(clips.length * F3dRecord.animation);
    final animationView = ByteData.view(animationTable.buffer);

    final trackRecords = BytesBuilder();
    var trackCount = 0;

    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final (nameOffset, nameLength) = _string(clip.name);
      final firstTrack = trackCount;

      for (final track in clip.tracks) {
        final timesOffset = _blobAppend(track.times);
        final valuesOffset = _blobAppend(track.values);

        final record = ByteData(F3dRecord.track);
        record.setUint32(0, track.nodeIndex, Endian.little);
        record.setUint32(4, track.path.index, Endian.little);
        record.setUint32(8, track.interpolation.index, Endian.little);
        record.setUint32(12, track.componentCount, Endian.little);
        record.setUint32(16, timesOffset, Endian.little);
        record.setUint32(20, track.times.length, Endian.little);
        record.setUint32(24, valuesOffset, Endian.little);
        record.setUint32(28, track.values.length, Endian.little);
        trackRecords.add(record.buffer.asUint8List());
        trackCount++;
      }

      final o = i * F3dRecord.animation;
      animationView.setUint32(o, nameOffset, Endian.little);
      animationView.setUint32(o + 4, nameLength, Endian.little);
      animationView.setUint32(o + 8, firstTrack, Endian.little);
      animationView.setUint32(o + 12, clip.tracks.length, Endian.little);
    }

    return (animationTable, trackRecords.toBytes(), clips.length, trackCount);
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
