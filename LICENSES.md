# Third-party material

flutter3d's own code is MIT, in [LICENSE](LICENSE). This file lists what in the
repository is somebody else's: who made it, under which licence, where its
full record lives, and what an application that ships it owes. It was put
together on 2026-10-12 by reading every `LICENSES.md`, `CREDITS.md`,
`ATTRIBUTION.md` and `third_party/` directory in the tree, and every source
file that carries a copyright line.

flutter3d is not affiliated with or endorsed by Google or the Flutter project.
"Flutter" is a trademark of Google LLC.

## What an application owes

Most of what is listed below is CC0 or a test fixture that no application
ships. Three things reach a built application and carry a notice that has to
go with it:

| Material | Reaches an app through | Licence | What the app does |
|---|---|---|---|
| The LTC tables of Heitz, Dupuy, Hill and Neubelt | `flutter3d_core` (any app that draws) | BSD-style, notice required in binary form | Include the notice from `packages/flutter3d_core/tool/third_party/ltc/LICENSE` in the app's licences or credits screen |
| wgpu-native | `flutter3d_wgpu` and `flutter3d_physics_native`, linked by their build hooks | MIT or Apache-2.0, the user's choice | Include one of the two notices from [gfx-rs/wgpu-native](https://github.com/gfx-rs/wgpu-native) |
| SMAA | `flutter3d_shaders` | MIT, with no notice required in binary form | Nothing; the notice is in the shader sources |

Flutter's `LicenseRegistry` and `showLicensePage` pick up the licences of
pub dependencies, but not these, because they are data and native code
inside a package. I would rather an app add the two notices by hand than
learn about them from a store review.

## Code and data in the packages

**LTC: linearly transformed cosines.** `packages/flutter3d_core/lib/src/engine/render/tables/ltc.dart`
holds the published fit from Heitz, Dupuy, Hill and Neubelt, "Real-Time
Polygonal-Light Shading with Linearly Transformed Cosines", ACM TOG 35(4),
2016. Copyright (c) 2017, Eric Heitz, Jonathan Dupuy, Stephen Hill and David
Neubelt. The licence is at the path the file names,
[`packages/flutter3d_core/tool/third_party/ltc/LICENSE`](packages/flutter3d_core/tool/third_party/ltc/LICENSE),
beside the two `.dds` tables it was converted from, and it ships in the
published package. `flutter3d_shaders/shaders/lib/ltc.glsl` and
`flutter3d_cpu`'s `cpu_shaders_ltc.dart` read the table and point back to it.

**SMAA.** The three passes in `packages/flutter3d_shaders/shaders/post/smaa_*.frag`,
their CPU twins in `flutter3d_cpu` and the `smaaArea` table in `flutter3d_core`
implement Jimenez, Echevarria, Sousa and Gutierrez, "SMAA: Enhanced Subpixel
Morphological Antialiasing", Eurographics 2012. They were written for this
engine from the paper and follow the conventions of the reference
implementation, [iryoku/smaa](https://github.com/iryoku/smaa), MIT, Copyright
(C) 2013 Jorge Jimenez, Jose I. Echevarria, Belen Masia, Fernando Navarro and
Diego Gutierrez. Its notice is in full at the top of `smaa_edges.frag`.

**FLIP.** `packages/flutter3d_testing/lib/src/flip.dart` is NVIDIA's FLIP
image metric, ported line for line from the reference C++. BSD 3-Clause, Copyright (c) 2020-2025 NVIDIA CORPORATION &
AFFILIATES, in
[`packages/flutter3d_testing/third_party/flip/LICENSE`](packages/flutter3d_testing/third_party/flip/LICENSE).
Used by tests that compare pictures. An application does not normally ship
it, and one that does includes that notice.

**wgpu-native.** Not in the repository. The build hooks of `flutter3d_wgpu`
and, when an application asks for its GPU passes, `flutter3d_physics_native`
fetch the pinned release (`v29.0.1.1`, in each package's
`tool/hook/wgpu_native.dart`), check its sha256 and link it statically. MIT or
Apache-2.0.

## Assets in published packages

**`flutter3d_samples`**, test models for the loaders. The full record is
[`packages/flutter3d_samples/assets/ATTRIBUTION.md`](packages/flutter3d_samples/assets/ATTRIBUTION.md).
The licences below were read from each model's `metadata.json` in
[KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets)
on 2026-10-12. The `f3d/` files are conversions of the same models and carry
the same licences.

| File | Author or owner | Licence |
|---|---|---|
| `Box.glb`, `BoxAnimated.glb`, `BoxTextured.glb`, `RiggedSimple.glb`, `RiggedFigure.glb` | Cesium, 2017 | CC BY 4.0 (the Cesium logo in `BoxTextured` is a trademark, not licensed) |
| `NormalTangentMirrorTest.glb` | Ed Mackey, Analytical Graphics, Inc., 2018 | CC BY 4.0 |
| `NormalTangentTest.glb` | Ed Mackey, Analytical Graphics, Inc., 2018 | CC0 1.0 |
| `BoxVertexColors.glb`, `Triangle.gltf`, `simple_skin/SimpleSkin.gltf` | Marco Hutter | CC0 1.0 |
| `cube/Cube.gltf`, `animated_cube/AnimatedCube.gltf` | Norbert Nopper, UX3D | CC0 1.0 |
| `InterpolationTest.glb` | Khronos | CC0 1.0 |
| `AnimatedMorphCube.glb` | Microsoft | CC0 1.0 |
| `RobotExpressive.glb` | Tomás Laulhé (Quaternius), morph targets by Don McCurdy | CC0 1.0 |
| `teapot.obj`, `teapot.stl` | the Utah teapot (Martin Newell, 1975), tessellated by the package's `tool/make_teapot.py` from the Bezier patches in three.js' `TeapotGeometry.js` | the patch table MIT (three.js authors, notice in the script); the tessellation this repository's, MIT |
| `radiance/*`, `ktx2/*` | written for the fixtures by ImageMagick and `basisu` | this repository's, MIT |

The CC BY 4.0 models owe credit to the owner named above and a link to the
licence, <https://creativecommons.org/licenses/by/4.0/>; this table is that
credit.

**`flutter3d_effects`**: `falls_loop.wav`, `fire_loop.wav` and `splash.wav`
are synthesised by the package's `tool/make_sounds.py`. This repository's,
MIT.

## Test fixtures no application ships

- `packages/flutter3d/test/fixtures/hero.glb`: *Animated Platformer
  Character* by Quaternius, CC0 1.0 (record in the directory's `README.md`).
- `packages/flutter3d_core/test/formats/fixtures/draco/`: the editor's
  shooter template monster (generated by `tool/make_models.py`, this
  repository's) and the racing game's `building-k.glb` (Kenney, CC0 1.0),
  recompressed with `@gltf-transform/cli`.
- The other fixtures under `test/` are generated by the tests' own tools or
  written by hand in this repository.

## The applications

Each application keeps its record beside its assets, with author, source,
licence and what was changed. The five games with a credits screen (arcade,
dungeon, platformer, racing, strategy) each test it in `credits_test.dart`.

| Application | Record | Licences |
|---|---|---|
| `flutter3d_demo_arcade` | `assets/models/LICENSES.md` | CC0 (Kenney) |
| `flutter3d_demo_dungeon` | `assets/textures/LICENSES.md`, `assets_src/models/LICENSES.md` | CC0 (ambientCG, Quaternius), generated |
| `flutter3d_demo_hollow` | `assets/CREDITS.md` | CC0 (Quaternius, ambientCG, Poly Haven) |
| `flutter3d_demo_platformer` | `assets_src/models/LICENSES.md` | CC BY 4.0 (`penguin.glb`, "Weathered penguin-bot" by epilogueronin, modified), CC0 |
| `flutter3d_demo_racing` | `assets_src/models/LICENSES.md` | CC0 (Kenney) |
| `flutter3d_demo_reef` | `assets/CREDITS.md` | CC0 (Poly Haven, ambientCG, Quaternius) |
| `flutter3d_demo_river` | `assets/models/LICENSES.md` | CC BY 3.0 (two jets by Poly by Google), CC0 |
| `flutter3d_demo_sandbox` | `assets/blocks/CREDITS.md` | CC0 (ambientCG) |
| `flutter3d_demo_strategy` | `assets/CREDITS.md`, `assets/models/LICENSES.md` | CC0 (Kenney, ambientCG) |
| `flutter3d_showcase` | `assets/fonts/RobotoMono-OFL.txt` | SIL Open Font License 1.1 (Roboto Mono) |

## The engine's example

`packages/flutter3d/example/assets/models/LICENSES.md` is the record:
`avocado.glb` is Khronos' Avocado (Microsoft, CC0 1.0) with its tangents
removed and its maps at 512 px, and `splat_grid.glb` is generated here. The
avocado replaced `fantasy_chest.glb` on 2026-10-12, a model whose terms were
never recorded, and the teapot in `flutter3d_samples` was regenerated from
a source with a known licence the same day.

## Adding something

Anything from outside comes with the three rows (author, source, licence)
and what was changed, in a record beside it, and a line here. An asset with
no provenance does not get one later, so it does not go in.
