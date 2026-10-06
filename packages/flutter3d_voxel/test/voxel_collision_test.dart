/// The blocks as boxes to collide with: that the boxes are the blocks, that
/// an edit replaces its chunk's and no other's, and that a body stands on
/// them and falls through a hole dug under it.
///
///     dart test test/voxel_collision_test.dart
///
/// On the Dart reference: the same world attached to the native core is
/// walked in `apps/flutter3d_demo_sandbox/test/voxel_physics_test.dart`,
/// which has the core to attach to.
library;

import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

VoxelWorld _hills() => VoxelWorld(
  chunksX: 2,
  chunksY: 2,
  chunksZ: 2,
  terrain: const VoxelTerrain(seed: 11),
);

/// How many boxes cover each voxel of [world], indexed as the world is.
Uint8List _cover(VoxelWorld world, Iterable<VoxelBox> boxes) {
  final cover = Uint8List(world.sizeX * world.sizeY * world.sizeZ);
  for (final b in boxes) {
    for (var y = b.minY; y < b.maxY; y++) {
      for (var z = b.minZ; z < b.maxZ; z++) {
        for (var x = b.minX; x < b.maxX; x++) {
          cover[(y * world.sizeZ + z) * world.sizeX + x]++;
        }
      }
    }
  }
  return cover;
}

void main() {
  test('the boxes cover every solid voxel once and nothing else', () {
    final world = _hills()
      ..edit(5, 2, 5, Voxels.empty)
      ..edit(20, 25, 20, 9)
      ..edit(15, 3, 15, Voxels.empty);
    final boxes = <VoxelBox>[
      for (final chunk in world.chunks) ...boxesOf(world, chunk),
    ];
    final cover = _cover(world, boxes);
    for (var y = 0; y < world.sizeY; y++) {
      for (var z = 0; z < world.sizeZ; z++) {
        for (var x = 0; x < world.sizeX; x++) {
          // Mutation: growing a box along y without checking the slab is
          // free covers air above a lower column; not marking a box's
          // voxels taken covers them twice.
          expect(
            cover[(y * world.sizeZ + z) * world.sizeX + x],
            world.isSolid(x, y, z) ? 1 : 0,
            reason: '($x, $y, $z)',
          );
        }
      }
    }
    // And far fewer of them than voxels: the point of merging.
    expect(boxes.length * 20, lessThan(world.solidCount));
  });

  test('a full chunk is one box, an empty one none', () {
    final world = VoxelWorld(
      chunksX: 1,
      chunksY: 2,
      chunksZ: 1,
      terrain: const VoxelTerrain.flat(16),
    );
    expect(boxesOf(world, (x: 0, y: 0, z: 0)), <VoxelBox>[
      (minX: 0, minY: 0, minZ: 0, maxX: 16, maxY: 16, maxZ: 16),
    ]);
    expect(boxesOf(world, (x: 0, y: 1, z: 0)), isEmpty);
  });

  test('an edit replaces its chunk\'s boxes and leaves the others', () {
    final world = _hills();
    final physics = CollisionWorld();
    final collision = VoxelCollision(world, physics);
    expect(physics.staticCount, collision.boxCount);
    final untouched = collision.collidersOf((x: 1, y: 0, z: 1));
    final revision = physics.revision;
    var top = world.sizeY - 1;
    while (!world.isSolid(3, top, 3)) {
      top--;
    }

    world.edit(3, top, 3, Voxels.empty);
    collision.refresh(world.takeChanges().chunks);

    // Mutation: refreshing without removing the old boxes leaves the dug
    // voxel solid, and the count grows.
    expect(physics.staticCount, collision.boxCount);
    expect(physics.revision, greaterThan(revision));
    expect(collision.collidersOf((x: 1, y: 0, z: 1)), untouched);
    final hit = RayHit();
    expect(
      physics.raycast(Vector3(3.5, 40, 3.5), Vector3(0, -1, 0), 80, hit),
      isTrue,
    );
    expect(hit.point.y, closeTo(top.toDouble(), 1e-9), reason: 'one lower');
    // And with the whole column gone, nothing to stop it.
    for (var y = 0; y < top; y++) {
      world.edit(3, y, 3, Voxels.empty);
    }
    collision.refresh(world.takeChanges().chunks);
    expect(
      physics.raycast(Vector3(3.5, 40, 3.5), Vector3(0, -1, 0), 80, hit),
      isFalse,
    );

    collision.dispose();
    expect(physics.staticCount, 0);
  });

  test('a body stands on the blocks and falls down a hole dug under it', () {
    final world = VoxelWorld(
      chunksX: 2,
      chunksY: 1,
      chunksZ: 2,
      terrain: const VoxelTerrain.flat(4),
    );
    final physics = CollisionWorld();
    final collision = VoxelCollision(world, physics);
    final body = CharacterController(
      world: physics,
      position: Vector3(8.5, 6.0, 8.5),
    );
    void settle(int steps) {
      for (var i = 0; i < steps; i++) {
        body.step(1 / 60, wishDirection: Vector3.zero());
        physics.update();
      }
    }

    settle(90);
    expect(body.isGrounded, isTrue);
    expect(body.position.y, closeTo(4.9, 0.01));

    // A shaft two wide, down to the floor's last layer.
    for (var y = 1; y < 4; y++) {
      for (final (x, z) in const <(int, int)>[(8, 8), (8, 9), (9, 8), (9, 9)]) {
        world.edit(x, y, z, Voxels.empty);
      }
    }
    collision.refresh(world.takeChanges().chunks);
    settle(90);
    // Mutation: refreshing nothing after the edit leaves it standing.
    expect(body.isGrounded, isTrue);
    expect(body.position.y, closeTo(1.9, 0.01));
  });
}
