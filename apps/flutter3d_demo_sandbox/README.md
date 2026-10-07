# Voxel Sandbox

A first-person sandbox on `packages/flutter3d_voxel`: rolling hills from a
seed, a block dug out wherever you look, one put back from a hotbar of five,
and the world as you left it on the next launch.

```
flutter run -d macos
flutter run -d macos --dart-define=FLUTTER3D_PHYSICS=dart   # the Dart reference
```

W A S D walk, space jumps, shift runs, and dragging looks round. A click digs
the block under the crosshair and a right click places the hotbar's block
against the face you are looking at; Q and E do the same from the keyboard.
1 to 5 or the mouse wheel pick the block.

## What it is made of

- `lib/src/staging.dart` holds `SandboxRun`, the one place a run is put
  together. It owns the blocks, a `CollisionWorld` attached to the run's
  physics, the chunks' boxes in that world, the navigation mesh, and the body
  (`LevelWalk`). It holds no device and no scene, so the tests play it
  headless.
- `lib/src/chunk_meshes.dart` puts each chunk in the scene as one node per
  surface. After an edit it uploads again only the chunks whose faces moved.
  It takes the visible faces from `flutter3d_voxel`'s mesher unmerged and
  lays each one down again with its block's picture once across it, the
  right way up, and its corners darkened where it meets other blocks. Grass,
  sand, earth and stone also drift lighter and darker in patches a few
  blocks across, so a meadow seen from a hill is not one flat green.
- `lib/src/block_surfaces.dart` loads the pictures into materials and holds
  the one way a block face becomes a mesh, which falling blocks use too.
- `lib/src/palette.dart` names the blocks and the surfaces each face shows:
  grass is turf on top, earth with a fringe of turf on the sides, and earth
  underneath.

The block pictures in `assets/blocks/` are ambientCG's CC0 materials, a
colour map and a normal map for each, taken down to 256 pixels and graded
by `tool/make_block_pictures.py`, which also composes the grass side and
bevels the gold. Where each came from is in
[`assets/blocks/CREDITS.md`](assets/blocks/CREDITS.md).

The HUD reports whether the body could still walk back to where it started.
It asks the navigation mesh, which is baked again around every edit, so
walling yourself in or digging into a pit turns the answer to no.

The save is a `Snapshot` of the terrain's seed, the edits, where the body
stands and what is in hand. It is written a few seconds after you stop
building and again when the window goes.

## Tests

```
flutter test
flutter test --dart-define=FLUTTER3D_PHYSICS=dart test/voxel_physics_test.dart
```

`voxel_physics_test.dart` walks voxel ground on whichever backend the build
asked for: the native core by default, the Dart reference with the define.
On either one, a wall built ahead of the body stops it and a pit dug ahead of
it is a pit it falls into.
