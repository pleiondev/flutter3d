/// Turns `f` records into triangles: corner parsing and the accumulator that
/// builds a [MeshData] from them.
///
/// **A part of `obj_loader.dart`, not a file of its own.** `_SurfaceBuilder`
/// and `_Corner` are constructed and driven from `ObjLoader.load`'s per-line
/// dispatch, and neither is meant to be visible outside the OBJ pipeline —
/// making them public just so this file could import `obj_loader.dart` (or
/// vice versa) would turn an implementation detail into API. A `part` keeps
/// them private to the library instead.
part of 'obj_loader.dart';

extension _ObjFaces on ObjLoader {
  _SurfaceBuilder _startSurface(
    List<_SurfaceBuilder> builders,
    _SurfaceBuilder current, {
    String? name,
    String? materialName,
  }) {
    // Reuse the current builder while it is still empty, so a file that declares
    // `g` and `usemtl` back to back does not produce an empty surface between
    // them.
    if (current.isEmpty) {
      return current
        ..name = name
        ..materialName = materialName;
    }
    final next = _SurfaceBuilder(name: name, materialName: materialName);
    builders.add(next);
    return next;
  }

  /// Parses one `f` record, fanning polygons into triangles.
  void _addFace(
    List<String> args,
    _SurfaceBuilder surface,
    List<double> positions,
    List<double> texcoords,
    List<double> normalData,
    List<String> warnings,
  ) {
    if (args.length < 3) {
      warnings.add('Face with ${args.length} vertices skipped.');
      return;
    }

    final corners = <_Corner>[];
    for (final token in args) {
      final corner = _parseCorner(
        token,
        positionCount: positions.length ~/ 3,
        texcoordCount: texcoords.length ~/ 2,
        normalCount: normalData.length ~/ 3,
      );
      if (corner == null) {
        warnings.add('Malformed face vertex "$token" skipped.');
        return;
      }
      corners.add(corner);
    }

    // Fan from the first corner. OBJ polygons are expected to be planar and
    // convex, which is what makes a fan sufficient.
    for (var i = 1; i + 1 < corners.length; i++) {
      surface.addTriangle(corners[0], corners[i], corners[i + 1]);
    }
  }

  /// Parses `v`, `v/vt`, `v//vn` or `v/vt/vn`, resolving 1-based and negative
  /// indices to 0-based ones.
  _Corner? _parseCorner(
    String token, {
    required int positionCount,
    required int texcoordCount,
    required int normalCount,
  }) {
    final parts = token.split('/');
    final position = _resolveIndex(parts[0], positionCount);
    if (position == null) return null;

    int? texcoord;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      texcoord = _resolveIndex(parts[1], texcoordCount);
    }
    int? normal;
    if (parts.length > 2 && parts[2].isNotEmpty) {
      normal = _resolveIndex(parts[2], normalCount);
    }

    return _Corner(position, texcoord, normal);
  }

  /// OBJ indices are 1-based; a negative index counts back from the most recent
  /// element, which is how streamed files reference vertices they just declared.
  int? _resolveIndex(String text, int count) {
    final value = int.tryParse(text);
    if (value == null || value == 0) return null;
    final index = value > 0 ? value - 1 : count + value;
    if (index < 0 || index >= count) return null;
    return index;
  }
}

/// One face corner: indices into the position, texcoord and normal streams.
///
/// OBJ indexes each attribute independently, so a renderable vertex is a unique
/// combination of the three. That is why decoding needs a dedup map rather than a
/// straight copy.
final class _Corner {
  const _Corner(this.position, this.texcoord, this.normal);

  final int position;
  final int? texcoord;
  final int? normal;
}

/// Accumulates the triangles of one surface and turns them into a [MeshData].
final class _SurfaceBuilder {
  _SurfaceBuilder({this.name, this.materialName});

  String? name;
  String? materialName;

  final List<_Corner> _corners = <_Corner>[];

  bool get isEmpty => _corners.isEmpty;

  void addTriangle(_Corner a, _Corner b, _Corner c) {
    _corners
      ..add(a)
      ..add(b)
      ..add(c);
  }

  /// Builds the mesh, and says which of [layout]'s attributes the file
  /// actually gave a value for — see [ModelSurface.authoredAttributes].
  ({MeshData mesh, Set<String> authoredAttributes}) build({
    required VertexLayout layout,
    required List<double> positions,
    required List<double> texcoords,
    required List<double> normalData,
    required ObjNormals normalMode,
  }) {
    final hasFileNormals =
        normalData.isNotEmpty &&
        _corners.any((corner) => corner.normal != null);
    final hasFileTexcoords =
        texcoords.isNotEmpty &&
        _corners.any((corner) => corner.texcoord != null);
    // Flat shading needs one normal per face, so vertices cannot be shared.
    final split = !hasFileNormals && normalMode == ObjNormals.flat;

    final builder = MeshBuilder(
      layout,
      reserveVertices: split ? _corners.length : _corners.length ~/ 2,
      reserveIndices: _corners.length,
    );

    final position = Vector3.zero();
    final normal = Vector3.zero();
    final texcoord = Vector2.zero();

    // **Smoothed per position, not per output vertex.** The dedup below splits
    // a position wherever its texture coordinates differ — every UV seam — and
    // smoothing the split copies separately gave each one only the faces on its
    // own side of the seam, which draws the seam as a hard crease on a model
    // that has no crease there.
    final smoothNormals = !hasFileNormals && normalMode == ObjNormals.smooth
        ? _smoothNormalsByPosition(positions)
        : null;

    void writeVertex(_Corner corner) {
      final p = corner.position * 3;
      position.setValues(positions[p], positions[p + 1], positions[p + 2]);

      final t = corner.texcoord;
      if (t != null && t * 2 + 1 < texcoords.length) {
        texcoord.setValues(texcoords[t * 2], texcoords[t * 2 + 1]);
      } else {
        texcoord.setZero();
      }

      final n = corner.normal;
      final smoothed = smoothNormals?[corner.position];
      if (smoothed != null) {
        normal.setFrom(smoothed);
      } else if (n != null && n * 3 + 2 < normalData.length) {
        normal.setValues(
          normalData[n * 3],
          normalData[n * 3 + 1],
          normalData[n * 3 + 2],
        );
      } else {
        normal.setZero();
      }
    }

    // Position is the one attribute OBJ cannot omit; tangent is the one it
    // never has — `withGeneratedTangents` below always fills it when the
    // layout wants one, so it is never in this set.
    final authored = <String>{
      VertexLayout.position.name,
      if (hasFileNormals) VertexLayout.normal.name,
      if (hasFileTexcoords) VertexLayout.texcoord.name,
    };

    if (split) {
      final a = Vector3.zero();
      final b = Vector3.zero();
      final c = Vector3.zero();
      final faceNormal = Vector3.zero();

      for (var i = 0; i + 2 < _corners.length; i += 3) {
        _readPosition(positions, _corners[i].position, a);
        _readPosition(positions, _corners[i + 1].position, b);
        _readPosition(positions, _corners[i + 2].position, c);
        (b - a).crossInto(c - a, faceNormal);
        if (faceNormal.length2 > 0.0) faceNormal.normalize();

        final base = builder.vertexCount;
        for (var k = 0; k < 3; k++) {
          writeVertex(_corners[i + k]);
          normal.setFrom(faceNormal);
          builder.addVertex(
            position: position,
            normal: normal,
            texcoord: texcoord,
          );
        }
        builder.addTriangle(base, base + 1, base + 2);
      }

      return (mesh: builder.build(), authoredAttributes: authored);
    }

    // Deduplicate by the (position, texcoord, normal) triple, which is the unit
    // OBJ actually addresses. A record rather than the three packed into one
    // int: packing needs 63 bits, which the web does not have — its shifts are
    // 32-bit, so the texcoord and normal fields collapsed and two corners that
    // differed only there shared one vertex and one set of UVs.
    final lookup = <(int, int, int), int>{};
    final indices = <int>[];

    for (final corner in _corners) {
      final key = (corner.position, corner.texcoord ?? -1, corner.normal ?? -1);
      var index = lookup[key];
      if (index == null) {
        writeVertex(corner);
        index = builder.addVertex(
          position: position,
          normal: normal,
          texcoord: texcoord,
        );
        lookup[key] = index;
      }
      indices.add(index);
    }

    for (var i = 0; i + 2 < indices.length; i += 3) {
      builder.addTriangle(indices[i], indices[i + 1], indices[i + 2]);
    }

    final mesh = builder.build();
    // OBJ has no tangent record at all, so a layout that wants one always has
    // to derive it. After the smoothing pass, because the frame is built
    // relative to the final normals.
    if (layout.has(VertexLayout.tangent)) {
      return (
        mesh: mesh.withGeneratedTangents(target: layout),
        authoredAttributes: authored,
      );
    }
    return (mesh: mesh, authoredAttributes: authored);
  }

  static void _readPosition(List<double> positions, int index, Vector3 out) {
    final o = index * 3;
    out.setValues(positions[o], positions[o + 1], positions[o + 2]);
  }

  /// Area-weighted normals for every position this surface's triangles touch,
  /// keyed by position index.
  ///
  /// Unnormalized cross products are accumulated, so each face contributes in
  /// proportion to its area — the standard approach, and the reason a large
  /// smooth face is not outvoted by a cluster of slivers next to it. A map
  /// rather than an array the size of the file's position list, because a file
  /// of many groups builds one of these per group.
  Map<int, Vector3> _smoothNormalsByPosition(List<double> positions) {
    final sums = <int, Vector3>{};
    final a = Vector3.zero();
    final b = Vector3.zero();
    final c = Vector3.zero();
    final faceNormal = Vector3.zero();

    for (var i = 0; i + 2 < _corners.length; i += 3) {
      _readPosition(positions, _corners[i].position, a);
      _readPosition(positions, _corners[i + 1].position, b);
      _readPosition(positions, _corners[i + 2].position, c);
      (b - a).crossInto(c - a, faceNormal);
      for (var k = 0; k < 3; k++) {
        (sums[_corners[i + k].position] ??= Vector3.zero()).add(faceNormal);
      }
    }

    for (final sum in sums.values) {
      if (sum.length2 > 0.0) sum.normalize();
    }
    return sums;
  }
}
