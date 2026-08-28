/// Reads `.f3d`'s node hierarchy and the surfaces hung off it.
///
/// **A part of `f3d_loader.dart`, not a file of its own.** `_readSurfaces`
/// calls `_mesh` (in `f3d_loader_geometry.dart`), and every reader here calls
/// the private byte-view helpers (`_section`, `_recordOffset`, `_string`, ...)
/// declared on `F3dDocument` in `f3d_loader.dart`. A `part` keeps the phases
/// in their own files without making any of that public.
part of 'f3d_loader.dart';

extension _F3dScene on F3dDocument {
  // ----------------------------------------------------------------- surfaces

  List<ModelSurface> _readSurfaces() {
    final table = _section(F3dSection.surfaces);
    return <ModelSurface>[
      for (var i = 0; i < table.count; i++)
        () {
          final o = _recordOffset(F3dSection.surfaces, i, F3dRecord.surface);
          final materialIndex = _view.getInt32(o + 4, Endian.little);

          final storage = Float32List(16);
          for (var e = 0; e < 16; e++) {
            storage[e] = _view.getFloat32(o + 20 + e * 4, Endian.little);
          }

          return ModelSurface(
            mesh: _mesh(_view.getUint32(o, Endian.little)),
            materialIndex: materialIndex < 0 ? null : materialIndex,
            name: _string(
              _view.getUint32(o + 8, Endian.little),
              _view.getUint32(o + 12, Endian.little),
            ),
            flipWinding: _view.getUint32(o + 16, Endian.little) & 1 != 0,
            skinIndex: () {
              final packed = _view.getUint32(o + 16, Endian.little) >> 1;
              return packed == 0 ? null : packed - 1;
            }(),
            transform: Matrix4.fromFloat32List(storage),
          );
        }(),
    ];
  }

  // -------------------------------------------------------------------- nodes

  List<ModelNode> _readNodes() {
    final table = _section(F3dSection.nodes);
    return <ModelNode>[
      for (var i = 0; i < table.count; i++)
        () {
          var o = _recordOffset(F3dSection.nodes, i, F3dRecord.node);

          final name = _string(
            _view.getUint32(o, Endian.little),
            _view.getUint32(o + 4, Endian.little),
          );
          o += 8;

          final translation = Vector3(
            _view.getFloat32(o, Endian.little),
            _view.getFloat32(o + 4, Endian.little),
            _view.getFloat32(o + 8, Endian.little),
          );
          o += 12;

          final rotation = Quaternion(
            _view.getFloat32(o, Endian.little),
            _view.getFloat32(o + 4, Endian.little),
            _view.getFloat32(o + 8, Endian.little),
            _view.getFloat32(o + 12, Endian.little),
          );
          o += 16;

          final scale = Vector3(
            _view.getFloat32(o, Endian.little),
            _view.getFloat32(o + 4, Endian.little),
            _view.getFloat32(o + 8, Endian.little),
          );
          o += 12;

          return ModelNode(
            name: name,
            translation: translation,
            rotation: rotation,
            scale: scale,
            children: _int32s(
              _view.getUint32(o, Endian.little),
              _view.getUint32(o + 4, Endian.little),
            ).toList(),
            surfaces: _int32s(
              _view.getUint32(o + 8, Endian.little),
              _view.getUint32(o + 12, Endian.little),
            ).toList(),
          );
        }(),
    ];
  }

  List<int> _readRoots() {
    final table = _section(F3dSection.roots);
    return <int>[
      for (var i = 0; i < table.count; i++)
        _view.getInt32(table.offset + i * 4, Endian.little),
    ];
  }
}
