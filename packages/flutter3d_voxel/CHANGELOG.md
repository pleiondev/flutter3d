## 1.0.0-rc.1

- **A voxel world is a format of its own.** `VoxelWorld.toJson` writes the
  envelope (`f3d.voxelWorld`, `VoxelWorld.format`), keeps the keys a later
  build added, and refuses a newer world; a world saved before the envelope
  reads as version 1, against the `v1/sandbox.voxels.json` fixture.
- **Seeded terrain says which drawing made it.** `VoxelTerrain` writes
  `generatorVersion` beside the seed, and a world drawn by a newer one is
  refused rather than having its edits land on other blocks.
- **Breaking: a world that will not read throws `VoxelFormatException`**,
  a `Flutter3dFormatException`, where it threw the SDK's
  `FormatException`.

- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `NavMeshConfig` is `NavMeshSettings`. Every settings class is
  `final` with a `const` constructor and a `copyWith` over every field; a
  nullable field is reset with `copyWith(clearX: true)`. `dart fix` carries
  the renames.
- **Breaking: `VoxelWorld.takeChanges` is `drainChanges`**, the one verb for
  a read that empties what it reads. `dart fix` carries it.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **The first publication, and the number skips from 0.1.0.** That number
  was carried inside the workspace and never reached pub.dev, so nobody
  outside saw the ones passed over. The shelf goes out on one number so
  that one number names one tree, and `^1.0.0` on any `flutter3d_*`
  package resolves against every other.

- **A world of blocks, kept as a seed and the edits since.** `VoxelWorld`
  holds a byte a voxel in chunks of sixteen cubed, drawn from a
  `VoxelTerrain`: rolling ground from a `GameRandom` stream and nothing but
  `+`, `-` and `*`, so two machines draw it bit for bit. `toJson` writes the
  terrain's few numbers and every voxel that differs from it, and a voxel
  edited back to what the terrain had is no edit at all. `restoreEdits`
  puts a save back over a world touching only what differs.

- **A chunk's faces as greedy meshes.** `meshChunk` draws a face only
  where a block meets air, reads across chunk borders so a wall has no seam
  in it, and merges the faces of one slice, direction and material into the
  fewest rectangles it finds: `MeshData` per material, wound for the
  engine's back-face culling, with texture coordinates in metres.

- **Collision as boxes, on whichever physics the run chose.** `boxesOf`
  covers a chunk's solid voxels exactly once with greedy boxes, and
  `VoxelCollision` keeps a `CollisionWorld`'s statics on them, chunk by
  chunk, replacing only an edited chunk's. A world attached to the native
  core mirrors those statics by revision, so the core collides with the
  blocks as they are with nothing voxel-shaped in it.

- **The navigation mesh follows the digging.** `VoxelNavigation` bakes the
  boxes as brushes on a lattice fixed to the world's footprint, and
  `follow` bakes again only the tiles an edit reaches — the same mesh as
  baking the edited world whole, digest for digest.

- **`raycast` picks a block.** Through the grid rather than the merged
  boxes, which say where a ray stopped and not which voxel it was; the face
  it entered by is where a placed block goes.

Its `flutter3d_*` dependencies ask for `^1.0.0`.
