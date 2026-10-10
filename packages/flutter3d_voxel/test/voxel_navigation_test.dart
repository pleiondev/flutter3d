/// The navigation mesh kept on the blocks as they are edited, held against
/// the edited world baked whole.
///
///     dart test test/voxel_navigation_test.dart
///
/// The claim `navmesh_rebake_test` makes for a level, made for blocks: after
/// an edit, the mesh with the tiles it reached baked again is the mesh of the
/// edited world baked whole, digest for digest — for a trench dug across, a
/// wall built, an edit on a chunk's border and on a tile's corner, and a
/// save restored over edits made after it.
library;

import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Level ground four deep, thirty-two metres square.
VoxelWorld _plot() => VoxelWorld(
  chunksX: 2,
  chunksY: 1,
  chunksZ: 2,
  terrain: const VoxelTerrain.flat(4),
);

/// [nav] after [edits], and the same world baked whole.
({VoxelNavigation followed, int whole}) _after(
  VoxelWorld world,
  VoxelNavigation nav,
  void Function(VoxelWorld world) edits,
) {
  edits(world);
  nav.follow(world.drainChanges());
  return (followed: nav, whole: VoxelNavigation(world).mesh.digest);
}

bool _routeAcross(VoxelNavigation nav, double z) =>
    nav.mesh.route(Vector3(4, 4, z), Vector3(28, 4, z))?.complete ?? false;

void main() {
  test('a wall built across the plot bakes as the walled plot does', () {
    final world = _plot();
    final nav = VoxelNavigation(world);
    expect(_routeAcross(nav, 10.5), isTrue);
    final before = nav.mesh.digest;

    final (:followed, :whole) = _after(world, nav, (w) {
      for (var z = 0; z < w.sizeZ; z++) {
        for (var y = 4; y < 7; y++) {
          w.edit(15, y, z, Voxels.firstPlaced);
        }
      }
    });
    // Mutation: following the changes with the brushes as they were — not
    // rebuilding the edited chunks' — bakes the old plot again; baking
    // again from the far corner of the changes rather than their near one
    // leaves most of the wall out of the mesh.
    expect(followed.mesh.digest, isNot(before));
    expect(followed.mesh.digest, whole);
    expect(_routeAcross(followed, 10.5), isFalse);
  });

  for (final (name, x, z) in <(String, int, int)>[
    ('mid-tile', 9, 9),
    ('on a chunk\'s border', 16, 5),
    ('on a tile\'s corner', 4, 8),
    ('at the world\'s corner', 0, 0),
  ]) {
    test('a block dug $name bakes as the dug world does', () {
      final world = _plot();
      final nav = VoxelNavigation(world);
      final (:followed, :whole) = _after(
        world,
        nav,
        (w) => w
          ..edit(x, 3, z, Voxels.empty)
          ..edit(x, 2, z, Voxels.empty),
      );
      // Mutation: following with the dug chunk's brushes as they were bakes
      // the hole as floor.
      expect(followed.mesh.digest, whole);
      expect(followed.mesh.polygonsAt(x + 2.5, z + 2.5), isNotEmpty);
    });
  }

  test('a trench dug across and a pillar put up, one after the other', () {
    final world = _plot();
    final nav = VoxelNavigation(world);
    for (var x = 0; x < world.sizeX; x++) {
      world
        ..edit(x, 3, 20, Voxels.empty)
        ..edit(x, 2, 20, Voxels.empty)
        ..edit(x, 1, 20, Voxels.empty);
      // Each block followed on its own, as a player digs.
      nav.follow(world.drainChanges());
    }
    expect(nav.mesh.digest, VoxelNavigation(world).mesh.digest);
    expect(
      nav.mesh.route(Vector3(10, 4, 10), Vector3(10, 4, 28))?.complete ?? false,
      isFalse,
    );
    world
      ..edit(6, 4, 6, 5)
      ..edit(6, 5, 6, 5);
    nav.follow(world.drainChanges());
    expect(nav.mesh.digest, nav.bakeWhole().digest);
    expect(nav.mesh.polygonsAt(6.5, 6.5), isEmpty);
  });

  test('a save restored over later edits bakes as the save does', () {
    final world = _plot()..edit(3, 3, 3, Voxels.empty);
    final saved = world.toJson();
    world.drainChanges();
    final nav = VoxelNavigation(world);
    world
      ..edit(25, 3, 25, Voxels.empty)
      ..edit(12, 4, 3, 5);
    nav.follow(world.drainChanges());
    world.restoreEdits(saved);
    nav.follow(world.drainChanges());
    expect(
      nav.mesh.digest,
      VoxelNavigation(VoxelWorld.fromJson(saved)).mesh.digest,
    );
  });

  test('nothing changed is nothing baked', () {
    final world = _plot();
    final nav = VoxelNavigation(world);
    final mesh = nav.mesh;
    nav.follow(world.drainChanges());
    expect(nav.mesh, same(mesh));
  });
}
