/// Picking a block: the ray walk through the grid, and the face it enters
/// by, which is where a placed block goes.
///
///     dart test test/voxel_ray_test.dart
library;

import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

VoxelWorld _plot() => VoxelWorld(
  chunksX: 2,
  chunksY: 1,
  chunksZ: 1,
  terrain: const VoxelTerrain.flat(4),
);

void main() {
  test('looking down finds the top block, through its top face', () {
    final hit = _plot().raycast(Vector3(5.5, 7.2, 5.5), Vector3(0, -1, 0), 10)!;
    expect((hit.x, hit.y, hit.z), (5, 3, 5));
    expect((hit.normalX, hit.normalY, hit.normalZ), (0, 1, 0));
    // A `Vector3` holds single precision.
    expect(hit.distance, closeTo(3.2, 1e-6));
    expect(hit.before, (x: 5, y: 4, z: 5));
  });

  test('a shallow ray meets the first block on its way, not one past it', () {
    final world = _plot()..edit(9, 4, 5, 6);
    // Nearly level, rising along -x then meeting the block's side.
    final hit = world.raycast(
      Vector3(20.5, 4.6, 5.5),
      Vector3(-1, -0.01, 0.003),
      30,
    )!;
    // Mutation: stepping the axis whose next face is furthest, rather than
    // nearest, skips through the block into the ground behind it.
    expect((hit.x, hit.y, hit.z), (9, 4, 5));
    expect((hit.normalX, hit.normalY, hit.normalZ), (1, 0, 0));
    expect(hit.before, (x: 10, y: 4, z: 5));
  });

  test('nothing within reach, or nowhere to look, is no hit', () {
    final world = _plot();
    expect(world.raycast(Vector3(5.5, 9, 5.5), Vector3(0, -1, 0), 4.9), isNull);
    expect(world.raycast(Vector3(5.5, 9, 5.5), Vector3(0, 1, 0), 40), isNull);
    expect(world.raycast(Vector3(5.5, 9, 5.5), Vector3.zero(), 40), isNull);
  });

  test('a ray that starts inside a block hits it with no face', () {
    final hit = _plot().raycast(Vector3(2.5, 1.5, 2.5), Vector3(1, 0, 0), 3)!;
    expect((hit.x, hit.y, hit.z), (2, 1, 2));
    expect((hit.normalX, hit.normalY, hit.normalZ), (0, 0, 0));
  });
}
