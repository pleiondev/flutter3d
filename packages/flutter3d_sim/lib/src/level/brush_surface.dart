import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// The triangles of every brush sharing one material *and* one answer about
/// shadows.
///
/// Plain arrays rather than the engine's `MeshData`, because this package does
/// not depend on the engine and should not: turning brushes into triangles is
/// arithmetic, and arithmetic has no business knowing about a GPU. The
/// application interleaves these into whatever vertex layout it draws with,
/// which is about twenty lines and the only place the two packages meet.
final class BrushSurface {
  BrushSurface({
    required this.material,
    required this.castsShadow,
    required this.positions,
    required this.normals,
    required this.texcoords,
    required this.tangents,
    required this.indices,
    this.lightmapUvs,
  });

  final String material;

  /// Two floats per vertex: where the vertex is in the level's lightmap.
  ///
  /// Null when the level has no lightmap, which keeps a batch built without
  /// one byte-identical to what it always was. With one, every vertex has a
  /// place — a ramp's triangles point at the atlas's reserved texel — so the
  /// application can put these where its vertex layout keeps them without a
  /// second decision per vertex.
  final Float32List? lightmapUvs;

  /// Whether the mesh built from this takes part in the shadow pass.
  ///
  /// **The reason surfaces are keyed by this as well as by material.** Brushes
  /// are batched so that a level of two hundred and fifty of them is a handful
  /// of draws, and a batch is the smallest thing that can answer — so a fence
  /// and a wall of the same stone had to stop sharing one.
  final bool castsShadow;

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

  /// The box around every vertex, for deciding whether a batch can be seen.
  ///
  /// Computed on first use from the positions, so a surface built by hand
  /// and one built by `BrushGeometry` answer the same way.
  late final Aabb3 bounds = _computeBounds();

  Aabb3 _computeBounds() {
    if (positions.isEmpty) return Aabb3();
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    for (var i = 0; i + 2 < positions.length; i += 3) {
      final x = positions[i], y = positions[i + 1], z = positions[i + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    return Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
  }

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}
