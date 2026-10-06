# flutter3d_voxel

A world of blocks for a [flutter3d](https://flutter3d.pleion.dev) game:
chunks over a seeded terrain, edits saved as deltas, greedy meshes to draw,
greedy boxes to collide with, and a navigation mesh that follows the digging.

Plain Dart. Nothing here draws or opens a window; a chunk becomes `MeshData`
and the game uploads it. A server holding a sandbox's state runs the same
code the player did.

```dart
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';

final blocks = VoxelWorld(
  chunksX: 4,
  chunksY: 2,
  chunksZ: 4,
  terrain: const VoxelTerrain(seed: 7),
);
final physics = CollisionWorld();
final collision = VoxelCollision(blocks, physics);
final navigation = VoxelNavigation(blocks);

// Dig one out, then hand every consumer what changed.
blocks.edit(10, 6, 10, Voxels.empty);
final changes = blocks.takeChanges();
collision.refresh(changes.chunks);
navigation.follow(changes);
for (final chunk in changes.surfaces) {
  final meshes = meshChunk(blocks, chunk); // one MeshData per material
}

// A save is the seed and the edits, never the blocks.
final saved = Snapshot(blocks.toJson());
final again = VoxelWorld.fromJson(saved.data);
```

## How it is put together

**A voxel is a metre, and the world's corner is the origin.** Voxel
`(x, y, z)` fills `[x, x + 1)` along each axis. The meshes, the boxes, the
navigation and the rays all agree on that, so none of them carries a scale.

**Bounded, not endless.** A tiled navigation mesh may only be baked again on
the lattice it was baked on, so the world has a footprint and keeps it.
`VoxelNavigation` fixes its lattice to that footprint rather than taking it
from the blocks, which would move the day somebody dug out the lowest corner.

**The terrain is a function of its seed.** Heights are value noise read from
one `GameRandom` stream in a fixed order and blended by a smoothstep. No
transcendental is involved: the VM answers those from the host's libm and a
browser from its own engine, and the two disagree in the last bit. That is
what lets a save hold a seed and the edits instead of the blocks.

**Meshes are greedy and per material.** `meshChunk` draws a face only where a
block meets air, reads the neighbouring chunk at a border, and merges faces
that share a slice, a direction and a material into rectangles. A flat field
sixteen voxels square is two triangles. `merge: false` keeps a quad per face,
which is the reference the tests count the merge against.

**Collision is boxes in an ordinary `CollisionWorld`.** `boxesOf` covers a
chunk's solid voxels with greedy boxes, each voxel exactly once.
`VoxelCollision` adds them as statics and replaces only the edited chunk's
boxes on `refresh`. Nothing voxel-shaped is needed anywhere: a character
controller, a ray and a rigid body all collide with boxes already. A world
attached to the native core (`usePhysics().attach(world)`) mirrors its statics
when the world's revision moves, so the core collides with the blocks as they
are now.

**The navigation mesh is baked from those boxes as `Brush`es**, with the same
bake every level uses. `follow` bakes again the tiles an edit reaches, and the
tests hold the result to the edited world baked whole, digest for digest.

**Picking walks the grid.** `raycast` steps voxel by voxel (Amanatides and
Woo). A merged collision box can say where a ray stopped but not which of its
voxels that was, and picking needs the voxel. The face the ray entered by is
where a placed block goes.

## Tests

```bash
dart test        # plain Dart, no Flutter needed
```

The native core is exercised from `apps/flutter3d_demo_sandbox`, which has it
to attach to: a body walks voxel ground there on the core and on the Dart
reference.
