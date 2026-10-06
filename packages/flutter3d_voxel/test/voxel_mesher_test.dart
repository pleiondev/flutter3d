/// A chunk's faces as meshes: which faces, how few quads, and which way they
/// look.
///
///     dart test test/voxel_mesher_test.dart
library;

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// An empty world [chunks] chunks along x, one chunk high and deep.
VoxelWorld _air({int chunks = 1}) => VoxelWorld(
  chunksX: chunks,
  chunksY: 1,
  chunksZ: 1,
  terrain: const VoxelTerrain.flat(0),
);

const ChunkKey _first = (x: 0, y: 0, z: 0);

int _quads(Map<int, MeshData> meshes) => meshes.values.fold(
  0,
  (int sum, MeshData mesh) => sum + mesh.triangleCount ~/ 2,
);

Vector3 _at(MeshData mesh, int vertex, int offset) {
  final i = vertex * mesh.layout.floatsPerVertex + offset;
  return Vector3(
    mesh.vertices[i].toDouble(),
    mesh.vertices[i + 1].toDouble(),
    mesh.vertices[i + 2].toDouble(),
  );
}

/// Every face's area, in voxel faces: what the quads cover, merged or not.
double _area(Map<int, MeshData> meshes) {
  var area = 0.0;
  for (final mesh in meshes.values) {
    for (var t = 0; t < mesh.triangleCount; t++) {
      final a = _at(mesh, mesh.indices[t * 3], 0);
      final b = _at(mesh, mesh.indices[t * 3 + 1], 0);
      final c = _at(mesh, mesh.indices[t * 3 + 2], 0);
      area += (b - a).cross(c - a).length / 2.0;
    }
  }
  return area;
}

void main() {
  test('one block is six quads, one a side', () {
    final world = _air()..edit(3, 4, 5, 9);
    final meshes = meshChunk(world, _first);
    expect(meshes.keys, <int>[9]);
    expect(_quads(meshes), 6);
    expect(meshes[9]!.vertexCount, 24);
    expect(meshes[9]!.layout, VertexLayout.standard);
  });

  test('a cube of blocks merges into six quads where faces alone are 24', () {
    final world = _air();
    for (var y = 0; y < 2; y++) {
      for (var z = 0; z < 2; z++) {
        for (var x = 0; x < 2; x++) {
          world.edit(x + 4, y + 4, z + 4, 9);
        }
      }
    }
    // Mutation: dropping the second, row-by-row half of the merge leaves
    // each side two strips — twelve quads.
    expect(_quads(meshChunk(world, _first)), 6);
    expect(_quads(meshChunk(world, _first, merge: false)), 24);
    expect(_area(meshChunk(world, _first)), 24.0);
  });

  test('no face between two blocks, whatever they are made of', () {
    final world = _air()
      ..edit(4, 4, 4, 5)
      ..edit(5, 4, 4, 6);
    final meshes = meshChunk(world, _first, merge: false);
    // Mutation: drawing a face wherever the two sides differ, rather than
    // where one is air, adds the two faces between them.
    expect(_quads(meshes), 10);
    expect(meshes.keys, <int>[5, 6]);
    expect(_quads(<int, MeshData>{5: meshes[5]!}), 5);
  });

  test('different materials never merge into one quad', () {
    final world = _air();
    for (var x = 0; x < 4; x++) {
      world.edit(x, 0, 0, x < 2 ? 5 : 6);
    }
    final meshes = meshChunk(world, _first);
    // Each material's half is its own five quads, the face between them
    // hidden; were materials merged, top, bottom and the two long sides
    // would be one quad each and the strip six.
    expect(_quads(meshes), 10);
    expect(_area(meshes), 18.0);
  });

  test('a field of terrain is a quad on top and its sides', () {
    final world = VoxelWorld(
      chunksX: 1,
      chunksY: 1,
      chunksZ: 1,
      terrain: const VoxelTerrain.flat(4),
    );
    final meshes = meshChunk(world, _first);
    // Grass on top and its own band on the four sides; dirt and stone
    // under it, as bands, plus the stone floor.
    expect(meshes[Voxels.grass]!.triangleCount ~/ 2, 5);
    expect(_quads(meshes), 5 + 4 + 4 + 1);
    expect(_area(meshes), _area(meshChunk(world, _first, merge: false)));
  });

  test('every quad faces air, and winds counter-clockwise seen from it', () {
    final world = VoxelWorld(
      chunksX: 2,
      chunksY: 1,
      chunksZ: 2,
      terrain: const VoxelTerrain(seed: 3),
    );
    for (final chunk in world.chunks) {
      for (final mesh in meshChunk(world, chunk).values) {
        for (var t = 0; t < mesh.triangleCount; t++) {
          final a = _at(mesh, mesh.indices[t * 3], 0);
          final b = _at(mesh, mesh.indices[t * 3 + 1], 0);
          final c = _at(mesh, mesh.indices[t * 3 + 2], 0);
          final normal = _at(mesh, mesh.indices[t * 3], 3);
          // Mutation: one winding for both directions of an axis turns every
          // face looking along -x, -y or -z inside out.
          expect((b - a).cross(c - a).dot(normal), greaterThan(0.0));
          final centre = (a + b + c) / 3.0;
          bool solid(Vector3 p) =>
              world.isSolid(p.x.floor(), p.y.floor(), p.z.floor());
          expect(solid(centre + normal * 0.5), isFalse, reason: 'air ahead');
          expect(
            solid(centre - normal * 0.5),
            isTrue,
            reason: 'a block behind',
          );
        }
      }
    }
  });

  test('a chunk border hides the faces the neighbour covers', () {
    // A slab two chunks long: the face at x = 16 is between two blocks.
    final world = _air(chunks: 2);
    for (var x = 14; x < 18; x++) {
      world.edit(x, 0, 0, 9);
    }
    final left = meshChunk(world, _first, merge: false);
    final right = meshChunk(world, (x: 1, y: 0, z: 0), merge: false);
    // Mutation: treating everything past the chunk as air draws a face on
    // each side of the border.
    expect(_quads(left) + _quads(right), 4 * 4 + 2);
    expect(_quads(left), 9);

    // And with nothing past it, the border face is drawn.
    world.edit(16, 0, 0, Voxels.empty);
    expect(_quads(meshChunk(world, _first, merge: false)), 10);
  });

  test('the world\'s outer skin is drawn', () {
    final world = _air()..edit(0, 0, 0, 9);
    expect(_quads(meshChunk(world, _first)), 6);
  });
}
