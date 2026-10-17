# Models

## `avocado.glb`

| | |
|---|---|
| Title | Avocado |
| Author | Microsoft |
| Source | KhronosGroup/glTF-Sample-Assets, `Models/Avocado/glTF-Binary/Avocado.glb`, https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/Avocado |
| Licence | **CC0 1.0**, https://creativecommons.org/publicdomain/zero/1.0/ (read from the model's `metadata.json` on 2026-10-12) |

**Changed**, so the model browser exercises a normal map with no tangents
of its own, and so the example stays small:

* the `TANGENT` attribute was removed from the GLB's JSON, and the accessor
  it left behind pruned (`gltf-transform prune`);
* the three maps were resized from 2048 to 512 px
  (`gltf-transform resize --width 512 --height 512`) and stored as JPEG at
  quality 85 (`gltf-transform jpeg --formats png`), with
  `@gltf-transform/cli` 4.1.1.

8.1 MB became 73 KB. The mesh is unchanged.

It replaced `fantasy_chest.glb` on 2026-10-12, a model generated with a
third-party service whose terms were never recorded.

## `splat_grid.glb`

A copy of `flutter3d_core/test/formats/fixtures/splat/splat_grid.glb`,
which `flutter3d_core/tool/make_splat_fixture.dart` writes. Generated in
this repository; MIT, as the rest of it.
