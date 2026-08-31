/// Writes `.f3d`'s per-vertex data: layouts and the meshes built over them.
///
/// **A part of `f3d_writer.dart`, not a file of its own.** These writers touch
/// the layout/mesh interning tables (`_layoutIndices`, `_meshIndices`, ...) and
/// the blob/string helpers (`_blobAppend`, `_string`) declared as fields and
/// methods of `F3dWriter` in `f3d_writer.dart`, and `_writeSurfaces` (in
/// `f3d_writer_scene.dart`) calls `_meshIndex` back. A `part` keeps the phase
/// in its own file without making any of that public.
part of 'f3d_writer.dart';

extension _F3dWriteGeometry on F3dWriter {
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
}
