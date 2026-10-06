## 0.9.0

- **The first publication, and the number skips from 0.1.0.** That number
  was carried inside the workspace and never reached pub.dev, so nobody
  outside saw the ones passed over. The shelf goes out on one number so
  that one number names one tree, and `^0.9.0` on any `flutter3d_*`
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

Its `flutter3d_*` dependencies ask for `^0.9.0`.
