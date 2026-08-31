/// Reads `.f3d`'s per-vertex data: layouts and the meshes built over them.
///
/// **A part of `f3d_loader.dart`, not a file of its own.** These readers call
/// the private byte-view helpers (`_section`, `_recordOffset`, `_floats`, ...)
/// declared on `F3dDocument` in `f3d_loader.dart`, and `_mesh` is called from
/// `_readSurfaces` in `f3d_document_scene.dart`. Making any of that public just
/// so the phases could see each other across an ordinary import would widen
/// this class's surface for no reader's benefit; a `part` avoids that.
part of 'f3d_loader.dart';

extension _F3dGeometry on F3dDocument {
  // ------------------------------------------------------------------ layouts

  List<VertexLayout> _readLayouts() {
    final table = _section(F3dSection.layouts);
    return <VertexLayout>[
      for (var i = 0; i < table.count; i++) _readLayout(i),
    ];
  }

  VertexLayout _readLayout(int index) {
    final o = _recordOffset(F3dSection.layouts, index, F3dRecord.layout);
    final attributeCount = _view.getUint32(o, Endian.little);
    final first = _view.getUint32(o + 4, Endian.little);

    return VertexLayout(<VertexAttribute>[
      for (var a = 0; a < attributeCount; a++)
        () {
          final ao = _recordOffset(
            F3dSection.attributes,
            first + a,
            F3dRecord.attribute,
          );
          final name = _string(
                _view.getUint32(ao, Endian.little),
                _view.getUint32(ao + 4, Endian.little),
              ) ??
              '';
          return VertexAttribute(
            name,
            _view.getUint32(ao + 8, Endian.little),
          );
        }(),
    ]);
  }

  // ------------------------------------------------------------------- meshes

  /// Meshes are cached by index so a mesh shared between surfaces stays one
  /// object, exactly as the decoders produce it — the GPU upload path
  /// deduplicates on identity, and rebuilding a `MeshData` per surface would
  /// quietly defeat it.
  MeshData _mesh(int index) => _meshCache.putIfAbsent(index, () {
        final o = _recordOffset(F3dSection.meshes, index, F3dRecord.mesh);
        final layoutIndex = _view.getUint32(o, Endian.little);
        final vertexOffset = _view.getUint32(o + 4, Endian.little);
        final vertexBytes = _view.getUint32(o + 8, Endian.little);
        final indexOffset = _view.getUint32(o + 12, Endian.little);
        final indexBytes = _view.getUint32(o + 16, Endian.little);

        if (layoutIndex >= _layouts.length) {
          throw F3dFormatException(
            'meshes[$index] names layout $layoutIndex, but the file has '
            '${_layouts.length}.',
          );
        }

        return MeshData(
          layout: _layouts[layoutIndex],
          vertices: _floats(vertexOffset, vertexBytes ~/ 4),
          indices: _uint32s(indexOffset, indexBytes ~/ 4),
        );
      });
}
