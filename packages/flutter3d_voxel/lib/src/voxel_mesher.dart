import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';

import 'voxel_world.dart';

/// [chunk]'s visible faces, one mesh per material, in world space.
///
/// **Greedy**: the faces of one slice that look the same way and are made of
/// the same material are merged into the fewest rectangles that cover them,
/// so a flat field sixteen voxels square is two triangles rather than five
/// hundred and twelve. [merge] false keeps one quad per face — the reference
/// a test counts the merge against.
///
/// A face is drawn where a block meets air and nowhere else: two blocks side
/// by side hide each other's faces whatever they are made of. At the chunk's
/// border the far side is read from the neighbouring chunk, so a wall
/// running across a border has no seam of hidden faces in it, and air
/// outside the world counts as air — the world's outer skin is drawn.
///
/// Wound counter-clockwise seen from outside, which is what the engine
/// culls back faces by. The texture coordinates are metres along the face,
/// so a texture repeats once a voxel however large the merged quad, and the
/// vertex colour is white.
Map<int, MeshData> meshChunk(
  VoxelWorld world,
  ChunkKey chunk, {
  bool merge = true,
}) {
  const n = VoxelWorld.chunkSize;
  final origin = <int>[chunk.x * n, chunk.y * n, chunk.z * n];
  final builders = <int, _MeshBuilder>{};
  final mask = Int32List(n * n);
  final at = List<int>.filled(3, 0);

  int voxel(int d, int layer, int u, int j, int v, int k) {
    at[d] = origin[d] + layer;
    at[u] = origin[u] + j;
    at[v] = origin[v] + k;
    return world.at(at[0], at[1], at[2]);
  }

  for (var d = 0; d < 3; d++) {
    final u = (d + 1) % 3;
    final v = (d + 2) % 3;
    for (var layer = 0; layer <= n; layer++) {
      // The plane between voxel layer - 1 and voxel layer along d. A face
      // on it is this chunk's when the solid voxel behind it is: a positive
      // entry faces +d and belongs to layer - 1, a negative one faces -d and
      // belongs to layer.
      for (var k = 0; k < n; k++) {
        for (var j = 0; j < n; j++) {
          final behind = voxel(d, layer - 1, u, j, v, k);
          final ahead = voxel(d, layer, u, j, v, k);
          mask[k * n + j] = switch ((behind, ahead)) {
            (final a, 0) when a != 0 && layer > 0 => a,
            (0, final b) when b != 0 && layer < n => -b,
            _ => 0,
          };
        }
      }
      for (var k = 0; k < n; k++) {
        for (var j = 0; j < n;) {
          final face = mask[k * n + j];
          if (face == 0) {
            j++;
            continue;
          }
          var width = 1;
          while (merge && j + width < n && mask[k * n + j + width] == face) {
            width++;
          }
          var height = 1;
          while (merge &&
              k + height < n &&
              _rowIs(mask, (k + height) * n + j, width, face)) {
            height++;
          }
          for (var h = 0; h < height; h++) {
            mask.fillRange((k + h) * n + j, (k + h) * n + j + width, 0);
          }
          final corner = List<double>.filled(3, 0.0);
          corner[d] = (origin[d] + layer).toDouble();
          corner[u] = (origin[u] + j).toDouble();
          corner[v] = (origin[v] + k).toDouble();
          builders
              .putIfAbsent(face.abs(), _MeshBuilder.new)
              .quad(corner, d, u, v, width, height, facesUp: face > 0);
          j += width;
        }
      }
    }
  }

  return <int, MeshData>{
    for (final material in builders.keys.toList()..sort())
      material: builders[material]!.build(),
  };
}

bool _rowIs(Int32List mask, int from, int width, int face) {
  for (var i = from; i < from + width; i++) {
    if (mask[i] != face) return false;
  }
  return true;
}

/// Interleaved vertices in `VertexLayout.standard`, sixteen floats each.
final class _MeshBuilder {
  final List<double> _vertices = <double>[];
  final List<int> _indices = <int>[];

  /// A rectangle [width] along [u] by [height] along [v] from [corner], on
  /// the plane across [d], facing +[d] when [facesUp].
  ///
  /// `u × v` is `d` for the axes taken in turn, so the corners in the order
  /// below run counter-clockwise seen from +d; a face looking along -d takes
  /// them the other way round.
  void quad(
    List<double> corner,
    int d,
    int u,
    int v,
    int width,
    int height, {
    required bool facesUp,
  }) {
    final base = _vertices.length ~/ VertexLayout.standard.floatsPerVertex;
    final normal = List<double>.filled(3, 0.0)..[d] = facesUp ? 1.0 : -1.0;
    final tangent = List<double>.filled(3, 0.0)..[u] = 1.0;
    for (final (du, dv) in const <(int, int)>[(0, 0), (1, 0), (1, 1), (0, 1)]) {
      final p = List<double>.of(corner);
      p[u] += du * width;
      p[v] += dv * height;
      _vertices.addAll(<double>[
        ...p,
        ...normal,
        p[u],
        p[v],
        ...tangent,
        // The bitangent, normal × tangent, runs along +v facing up and -v
        // facing down; the sign makes it +v either way.
        if (facesUp) 1.0 else -1.0,
        1.0, 1.0, 1.0, 1.0,
      ]);
    }
    _indices.addAll(
      facesUp
          ? <int>[base, base + 1, base + 2, base, base + 2, base + 3]
          : <int>[base, base + 2, base + 1, base, base + 3, base + 2],
    );
  }

  MeshData build() => MeshData(
    layout: VertexLayout.standard,
    vertices: Float32List.fromList(_vertices),
    indices: Uint32List.fromList(_indices),
  );
}
