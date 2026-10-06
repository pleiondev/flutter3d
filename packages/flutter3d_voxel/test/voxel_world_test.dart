/// The blocks themselves: the seeded terrain, edits, and edits saved as
/// deltas against the seed.
///
///     dart test test/voxel_world_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart' show Snapshot;
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:test/test.dart';

VoxelWorld _hills({int seed = 7}) => VoxelWorld(
  chunksX: 3,
  chunksY: 2,
  chunksZ: 3,
  terrain: VoxelTerrain(seed: seed),
);

void main() {
  group('the terrain', () {
    test('one seed draws the same ground every time', () {
      // Mutation: seeding the lattice from anything but the seed — a
      // second `GameRandom` on a clock, or the broad and fine octaves from
      // one stream in a different order — and two worlds differ.
      expect(_hills().digest, _hills().digest);
      expect(_hills().solidCount, _hills().solidCount);
    });

    test('another seed draws other ground', () {
      expect(_hills(seed: 8).digest, isNot(_hills().digest));
    });

    test('the ground rolls, inside the world, rock under soil under grass', () {
      final world = _hills();
      final tops = <int>{};
      for (var z = 0; z < world.sizeZ; z++) {
        for (var x = 0; x < world.sizeX; x++) {
          var top = world.sizeY - 1;
          while (top > 0 && !world.isSolid(x, top, z)) {
            top--;
          }
          tops.add(top);
          expect(world.isSolid(x, 0, z), isTrue, reason: 'no hole to fall in');
          expect(
            world.at(x, top, z),
            anyOf(Voxels.grass, Voxels.sand),
            reason: 'the top of ($x, $z)',
          );
          if (top >= 4) expect(world.at(x, top - 4, z), Voxels.stone);
        }
      }
      expect(tops.length, greaterThan(4), reason: 'not flat');
    });

    test('flat terrain is level at its height', () {
      final world = VoxelWorld(
        chunksX: 1,
        chunksY: 1,
        chunksZ: 1,
        terrain: const VoxelTerrain.flat(3),
      );
      expect(world.solidCount, 16 * 16 * 3);
      expect(world.at(5, 2, 5), Voxels.grass);
      expect(world.at(5, 3, 5), Voxels.empty);
    });
  });

  group('edits', () {
    test('an edit changes one voxel and says so; outside the world, none', () {
      final world = _hills();
      expect(world.edit(4, 30, 4, 9), isTrue);
      expect(world.at(4, 30, 4), 9);
      expect(world.edit(4, 30, 4, 9), isFalse, reason: 'already that');
      expect(world.edit(-1, 3, 3, 9), isFalse);
      expect(world.edit(3, world.sizeY, 3, 9), isFalse);
      expect(world.at(-1, 3, 3), Voxels.empty);
    });

    test('an edit back to the terrain is no edit at all', () {
      final world = _hills();
      final base = world.at(10, 1, 10);
      world.edit(10, 1, 10, Voxels.empty);
      expect(world.editCount, 1);
      world.edit(10, 1, 10, base);
      // Mutation: keeping every edit, even one that restores the base.
      expect(world.editCount, 0);
      expect((world.toJson()['edits']! as List).isEmpty, isTrue);
    });

    test('the changes name the chunk, its neighbour across a border, and '
        'the region', () {
      final world = _hills()..takeChanges();
      world
        ..edit(16, 0, 3, Voxels.empty)
        ..edit(20, 7, 9, 9);
      final changes = world.takeChanges();
      expect(changes.chunks, <ChunkKey>{(x: 1, y: 0, z: 0)});
      // x = 16 is the first column of chunk 1, so chunk 0 draws the face
      // the dug voxel opened.
      expect(changes.surfaces, <ChunkKey>{
        (x: 1, y: 0, z: 0),
        (x: 0, y: 0, z: 0),
      });
      expect(changes.bounds, (
        minX: 16,
        minY: 0,
        minZ: 3,
        maxX: 21,
        maxY: 8,
        maxZ: 10,
      ));
      expect(world.takeChanges().isEmpty, isTrue, reason: 'taken once');
    });
  });

  group('saved as deltas', () {
    VoxelWorld edited() => _hills()
      ..edit(3, 2, 3, Voxels.empty)
      ..edit(3, 1, 3, Voxels.empty)
      ..edit(40, 20, 7, 6)
      ..edit(0, 0, 0, Voxels.empty)
      ..edit(47, 31, 47, 5);

    test('a save is the seed and the edits, not the blocks', () {
      final json = edited().toJson();
      expect(json['terrain'], const VoxelTerrain(seed: 7).toJson());
      expect(json['edits'], <List<int>>[
        <int>[0, 0, 0, 0],
        <int>[3, 1, 3, 0],
        <int>[3, 2, 3, 0],
        <int>[40, 20, 7, 6],
        <int>[47, 31, 47, 5],
      ]);
    });

    test('a save read back through JSON and a snapshot is the same world', () {
      final world = edited();
      final text = jsonEncode(Snapshot(world.toJson()).toJson());
      final back = VoxelWorld.fromJson(
        Snapshot.fromJson(jsonDecode(text) as Map<String, Object?>).data,
      );
      // Mutation: reading the edits back in another order of x, y and z.
      expect(back.digest, world.digest);
      expect(back.toJson(), world.toJson());
      expect(back.takeChanges().isEmpty, isTrue);
    });

    test('restoring over a world puts back exactly the edits saved', () {
      final saved = edited().toJson();
      final world = edited()
        ..edit(3, 2, 3, Voxels.dirt)
        ..edit(10, 20, 10, 7)
        ..takeChanges();
      world.restoreEdits(saved);
      // Mutation: leaving an edit made after the save in place.
      expect(world.digest, edited().digest);
      expect(world.editCount, 5);
      expect(world.takeChanges().chunks, <ChunkKey>{
        (x: 0, y: 0, z: 0),
        (x: 0, y: 1, z: 0),
      });
    });

    test('edits saved over other ground are refused', () {
      final saved = edited().toJson();
      expect(() => _hills(seed: 8).restoreEdits(saved), throwsFormatException);
      expect(
        () => VoxelWorld(
          chunksX: 2,
          chunksY: 2,
          chunksZ: 3,
          terrain: const VoxelTerrain(seed: 7),
        ).restoreEdits(saved),
        throwsFormatException,
      );
    });
  });
}
