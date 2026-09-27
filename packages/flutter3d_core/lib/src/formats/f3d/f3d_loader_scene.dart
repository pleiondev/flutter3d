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
    final table = _table(F3dSection.surfaces, F3dRecord.surface);
    final attributeTable = _table(
      F3dSection.surfaceAttributes,
      F3dRecord.surfaceAttributes,
    );
    final meshNameTable = _table(F3dSection.meshNames, F3dRecord.meshName);
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
            morphWeights: _morphWeights[i],
            // Absent (a file written before `fmt-03`) means null here, which
            // `ModelSurface` itself reads as "every attribute the layout
            // has" — see its own doc comment.
            authoredAttributes: attributeTable.count == 0
                ? null
                : _authoredAttributesAt(i),
            meshName: i < meshNameTable.count ? _meshNameAt(i) : null,
            variantMaterials: _variants.$2[i],
          );
        }(),
    ];
  }

  /// Section 23: every variant's name, and its `(surface, material)` pairs
  /// turned into the per-surface map a [ModelSurface] carries.
  (List<String>, Map<int, Map<int, int>>) _readVariants() {
    final table = _table(F3dSection.variants, F3dRecord.variant);
    final bySurface = <int, Map<int, int>>{};
    final names = <String>[
      for (var v = 0; v < table.count; v++)
        () {
          final o = table.offset + v * F3dRecord.variant;
          int word(int at) => _view.getUint32(o + at, Endian.little);
          final pairs = _int32s(word(8), word(12) * 2);
          for (var p = 0; p < pairs.length; p += 2) {
            (bySurface[pairs[p]] ??= <int, int>{})[v] = pairs[p + 1];
          }
          return _string(word(0), word(4)) ?? 'variant $v';
        }(),
    ];
    return (names, bySurface);
  }

  /// The string surface `i`'s `meshNames` record holds, or null.
  String? _meshNameAt(int i) {
    final o = _recordOffset(F3dSection.meshNames, i, F3dRecord.meshName);
    return _string(
      _view.getUint32(o, Endian.little),
      _view.getUint32(o + 4, Endian.little),
    );
  }

  /// The attribute names bit `i`'s `surfaceAttributes` record marks, read
  /// against [F3dAttributeFlags].
  Set<String> _authoredAttributesAt(int i) {
    final o = _recordOffset(
      F3dSection.surfaceAttributes,
      i,
      F3dRecord.surfaceAttributes,
    );
    final flags = _view.getUint32(o, Endian.little);
    const named = <(String, int)>[
      ('position', F3dAttributeFlags.position),
      ('normal', F3dAttributeFlags.normal),
      ('texcoord', F3dAttributeFlags.texcoord),
      ('tangent', F3dAttributeFlags.tangent),
      ('color', F3dAttributeFlags.color),
      ('joints', F3dAttributeFlags.joints),
      ('weights', F3dAttributeFlags.weights),
    ];
    return <String>{
      for (final (name, bit) in named)
        if (flags & bit != 0) name,
    };
  }

  // -------------------------------------------------------------------- nodes

  /// [ModelNode.lods], grouped by their own node index — sparse, the same
  /// shape [_readMorphTargets] already reads for surfaces. Absent (a file
  /// written before this section existed) reads as an empty map, and
  /// [_readNodes] below turns a missing entry into `const <ModelLod>[]`.
  Map<int, List<ModelLod>> _readLods() {
    final table = _table(F3dSection.lods, F3dRecord.lod);
    final grouped = <int, List<ModelLod>>{};
    // One per lod record when present; absent, or shorter than the table,
    // reads as a level nobody measured, and a negative value says so too.
    final errors = _table(F3dSection.lodErrors, F3dRecord.lodError);
    double? errorOf(int record) {
      if (record >= errors.count) return null;
      final error = _view.getFloat32(
        errors.offset + record * F3dRecord.lodError,
        Endian.little,
      );
      return error < 0.0 ? null : error;
    }

    for (var i = 0; i < table.count; i++) {
      final o = table.offset + i * F3dRecord.lod;
      final nodeIndex = _view.getUint32(o, Endian.little);
      final maxScreenFraction = _view.getFloat32(o + 4, Endian.little);
      final surfaceIndices = _int32s(
        _view.getUint32(o + 8, Endian.little),
        _view.getUint32(o + 12, Endian.little),
      ).toList();

      (grouped[nodeIndex] ??= <ModelLod>[]).add(
        ModelLod(
          surfaceIndices: surfaceIndices,
          maxScreenFraction: maxScreenFraction,
          error: errorOf(i),
        ),
      );
    }

    // `C4`: an impostor is always the coarsest level, so it goes after the
    // surface levels whatever order the sections sit in.
    final impostors = _table(F3dSection.impostors, F3dRecord.impostor);
    for (var i = 0; i < impostors.count; i++) {
      final o = impostors.offset + i * F3dRecord.impostor;
      double f32(int at) => _view.getFloat32(o + at, Endian.little);
      int u32(int at) => _view.getUint32(o + at, Endian.little);
      (grouped[u32(0)] ??= <ModelLod>[]).add(
        ModelLod.impostor(
          maxScreenFraction: f32(4),
          impostor: ModelImpostor(
            albedoImage: u32(8),
            normalDepthImage: u32(12),
            grid: u32(16),
            centre: Vector3(f32(20), f32(24), f32(28)),
            radius: f32(32),
          ),
        ),
      );
    }
    return grouped;
  }

  List<ModelNode> _readNodes() {
    final table = _table(F3dSection.nodes, F3dRecord.node);
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
            lods: _lods[i],
          );
        }(),
    ];
  }

  List<int> _readRoots() {
    // Four bytes a root: the table is a bare `Int32List`, not a record type.
    final table = _table(F3dSection.roots, 4);
    return <int>[
      for (var i = 0; i < table.count; i++)
        _view.getInt32(table.offset + i * 4, Endian.little),
    ];
  }
}
