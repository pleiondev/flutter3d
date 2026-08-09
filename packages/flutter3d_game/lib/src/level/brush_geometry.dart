import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'level.dart';

/// The triangles of every brush sharing one material.
///
/// Plain arrays rather than the engine's `MeshData`, because this package does
/// not depend on the engine and should not: turning brushes into triangles is
/// arithmetic, and arithmetic has no business knowing about a GPU. The
/// application interleaves these into whatever vertex layout it draws with,
/// which is about twenty lines and the only place the two packages meet.
final class BrushSurface {
  BrushSurface({
    required this.material,
    required this.positions,
    required this.normals,
    required this.texcoords,
    required this.tangents,
    required this.indices,
  });

  final String material;

  /// Three floats per vertex.
  final Float32List positions;

  /// Three floats per vertex.
  final Float32List normals;

  /// Two floats per vertex.
  final Float32List texcoords;

  /// Four floats per vertex: the tangent direction, and a handedness sign.
  ///
  /// Emitted here rather than left to the caller because the generator already
  /// knows each face's two axes, and rebuilding tangents from triangles
  /// afterwards is both slower and less accurate.
  ///
  /// The sign follows glTF: `bitangent = cross(normal, tangent.xyz) * w`, and
  /// glTF's bitangent is **minus** dP/dv, because texture V grows downwards
  /// while a normal map's green channel points up. With `cross(u, v) == normal`
  /// that makes `cross(normal, u) == v`, so the sign is -1. Getting it backwards
  /// lights normal-mapped surfaces from the wrong side, and only on mirrored
  /// UVs — which is exactly the bug this project already spent a day on once.
  final Float32List tangents;

  final Uint32List indices;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}

/// Turns a level's brushes into drawable triangles.
///
/// ## UVs come from world space
///
/// A face's texture coordinates are its world position projected onto the two
/// axes of that face, so a texture repeats every metre regardless of how large
/// the brush is. The alternative — stretching one copy of the texture across
/// each face — makes a two-metre wall and a twenty-metre wall look like
/// different materials, and is the single most recognisable sign of a level
/// nobody unwrapped. It also means two brushes meeting in a line have
/// continuous texturing across the seam, for free.
///
/// ## Hidden faces are dropped
///
/// A face whose centre lies inside another solid brush cannot be seen and is
/// not emitted. In a level built by stacking blocks that is a large fraction of
/// them. The test is deliberately conservative — strictly inside, not merely
/// touching — so a face that is merely coplanar with a neighbour survives; a
/// generator that removed those would eventually remove one that was visible,
/// and a hole in a wall is far worse than a triangle nobody sees.
final class BrushGeometry {
  const BrushGeometry({this.cullHiddenFaces = true, this.cellSize = 8.0});

  final bool cullHiddenFaces;

  /// Cell side for the index used to find neighbouring brushes.
  final double cellSize;

  /// The six faces, as an outward normal and the two axes across it.
  ///
  /// `cross(u, v) == normal`, which is what makes the corner order below wind
  /// counter-clockwise seen from outside. Get one of these wrong and the face
  /// is culled as a back face, which looks like a hole rather than like a
  /// winding error.
  static final List<(Vector3, Vector3, Vector3)> _faces =
      <(Vector3, Vector3, Vector3)>[
    (Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
    (Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0)),
    (Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0)),
    (Vector3(0.0, -1.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)),
    (Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)),
    (Vector3(0.0, 0.0, -1.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)),
  ];

  /// One surface per material actually used.
  List<BrushSurface> build(Level level) {
    final builders = <String, _SurfaceBuilder>{};
    final index = _BrushIndex(level, cellSize);

    for (final brush in level.brushes) {
      final material = level.materialFor(brush);
      final builder = builders.putIfAbsent(
        brush.material,
        () => _SurfaceBuilder(brush.material),
      );
      _emitBrush(brush, material, index, builder);
    }

    return <BrushSurface>[
      for (final builder in builders.values)
        if (builder.isNotEmpty) builder.finish(),
    ];
  }

  void _emitBrush(
    Brush brush,
    LevelMaterial material,
    _BrushIndex index,
    _SurfaceBuilder out,
  ) {
    final half = brush.halfExtents;
    final scale = material.texelsPerMetre;

    for (final (normal, u, v) in _faces) {
      // Distance from the centre to this face, along its own normal.
      final offset = normal.x.abs() * half.x +
          normal.y.abs() * half.y +
          normal.z.abs() * half.z;

      final centreX = brush.centre.x + normal.x * offset;
      final centreY = brush.centre.y + normal.y * offset;
      final centreZ = brush.centre.z + normal.z * offset;

      if (cullHiddenFaces &&
          index.containsPoint(centreX, centreY, centreZ, brush)) {
        continue;
      }

      // Half the face, measured along its own two axes.
      final halfU =
          u.x.abs() * half.x + u.y.abs() * half.y + u.z.abs() * half.z;
      final halfV =
          v.x.abs() * half.x + v.y.abs() * half.y + v.z.abs() * half.z;

      final first = out.vertexCount;
      for (final (su, sv) in const <(double, double)>[
        (-1.0, -1.0),
        (1.0, -1.0),
        (1.0, 1.0),
        (-1.0, 1.0),
      ]) {
        final x = centreX + u.x * halfU * su + v.x * halfV * sv;
        final y = centreY + u.y * halfU * su + v.y * halfV * sv;
        final z = centreZ + u.z * halfU * su + v.z * halfV * sv;

        out.addVertex(
          x,
          y,
          z,
          normal.x,
          normal.y,
          normal.z,
          u.x,
          u.y,
          u.z,
          // World position projected onto the face's axes: continuous across
          // the seam between two brushes, and independent of face size.
          (x * u.x + y * u.y + z * u.z) * scale,
          (x * v.x + y * v.y + z * v.z) * scale,
        );
      }

      out.addQuad(first);
    }
  }
}

/// Which brushes sit near a point, without walking all of them.
final class _BrushIndex {
  _BrushIndex(this.level, this.cellSize) {
    for (var i = 0; i < level.brushes.length; i++) {
      final brush = level.brushes[i];
      if (!brush.solid) continue;
      final min = brush.min;
      final max = brush.max;
      for (var x = (min.x / cellSize).floor();
          x <= (max.x / cellSize).floor();
          x++) {
        for (var z = (min.z / cellSize).floor();
            z <= (max.z / cellSize).floor();
            z++) {
          (_cells[(x << 32) ^ (z & 0xFFFFFFFF)] ??= <int>[]).add(i);
        }
      }
    }
  }

  final Level level;
  final double cellSize;
  final Map<int, List<int>> _cells = <int, List<int>>{};

  /// Whether any solid brush other than [except] strictly contains the point.
  ///
  /// Strictly: a point exactly on another brush's surface does not count, so
  /// two brushes that merely share a face both keep their faces.
  bool containsPoint(double x, double y, double z, Brush except) {
    const epsilon = 1e-4;
    final bucket = _cells[((x / cellSize).floor() << 32) ^
        ((z / cellSize).floor() & 0xFFFFFFFF)];
    if (bucket == null) return false;

    for (final i in bucket) {
      final other = level.brushes[i];
      if (identical(other, except)) continue;
      final min = other.min;
      final max = other.max;
      if (x > min.x + epsilon &&
          x < max.x - epsilon &&
          y > min.y + epsilon &&
          y < max.y - epsilon &&
          z > min.z + epsilon &&
          z < max.z - epsilon) {
        return true;
      }
    }
    return false;
  }
}

/// Accumulates one material's triangles.
final class _SurfaceBuilder {
  _SurfaceBuilder(this.material);

  final String material;
  final List<double> _positions = <double>[];
  final List<double> _normals = <double>[];
  final List<double> _texcoords = <double>[];
  final List<double> _tangents = <double>[];
  final List<int> _indices = <int>[];

  int get vertexCount => _positions.length ~/ 3;
  bool get isNotEmpty => _indices.isNotEmpty;

  void addVertex(
    double x,
    double y,
    double z,
    double nx,
    double ny,
    double nz,
    double tx,
    double ty,
    double tz,
    double u,
    double v,
  ) {
    _positions.addAll(<double>[x, y, z]);
    _normals.addAll(<double>[nx, ny, nz]);
    _texcoords.addAll(<double>[u, v]);
    _tangents.addAll(<double>[tx, ty, tz, -1.0]);
  }

  /// Two triangles over four corners added in order.
  void addQuad(int first) {
    _indices.addAll(<int>[
      first,
      first + 1,
      first + 2,
      first,
      first + 2,
      first + 3,
    ]);
  }

  BrushSurface finish() => BrushSurface(
        material: material,
        positions: Float32List.fromList(_positions),
        normals: Float32List.fromList(_normals),
        texcoords: Float32List.fromList(_texcoords),
        tangents: Float32List.fromList(_tangents),
        indices: Uint32List.fromList(_indices),
      );
}
