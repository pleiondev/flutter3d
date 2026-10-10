---
description: flutter3d convert brings models, materials and scenes in from glTF, OBJ, STL, PLY, USD, MaterialX, Unity, Godot, FBX and Blender. What each format becomes, what survives the trip, what does not, and the same conversion as a library for a server.
---

# Bringing assets in

`flutter3d convert` reads what other tools save and writes the engine's own
files. **Each input becomes one `.f3d`**: the model with its lights and
cameras, its materials and textures, its material language programs, and its
scene as prefab documents, with any other model the scene names carried
inside it. `--split` writes the same things as separate files instead: models
as `.f3d`, materials as `.fmat` (or `.f3dmat` when a material is a program),
and scenes and prefabs as level documents with `prefabs`. It is the
`flutter3d` command from `flutter3d_build`:

```sh
dart pub global activate flutter3d_build
flutter3d doctor                       # what is installed, and what is missing
flutter3d convert MyUnityGame/Assets/Prefabs/Crate.prefab -o assets_src/imported
flutter3d convert 'MyGodotGame/**.tscn' -o assets_src/imported --dry-run
```

Every run reads every input first and writes at the end. `--dry-run` writes
nothing and says what it would. A file that already exists with other
contents is refused unless `--overwrite` is given, and then nothing at all is
written; a file that already holds exactly what would be written is not a
conflict, so running the same conversion twice is fine. The output is the
same bytes on every machine.

Every input gets a report: what it wrote, what mapped, what was approximated,
and what was dropped and why. `--json` prints it as JSON, and `--report
file.json` saves it as well.

## What each format becomes

With `--split`, each format writes the files below. Without it, all of them
go into the one `<name>.f3d` (see [what a bundle carries](#bundle)).

| Input | Output with `--split` | Notes |
|---|---|---|
| glTF, GLB | `<name>.f3d`, `materials/*.fmat`, `<name>.level.json` | The scene is a prefab placing the model with its own node tree. PBR and the `KHR_materials_*` layers the engine draws (clear coat, sheen, transmission, volume, IOR, specular, iridescence, anisotropy, dispersion) are kept. |
| OBJ + MTL | `<name>.f3d`, `materials/*.fmat` | The MTL's Phong terms are approximated as metal-rough, as the loader does. |
| STL | `<name>.f3d` | Geometry only. |
| PLY mesh | `<name>.f3d` | ASCII and binary; positions, normals, colours, UVs and faces. A file without faces is a point cloud and is refused. |
| PLY / SPZ splat capture | `<name>.f3dsplat` | A PLY whose header names `f_dc_0`. |
| USDA, USDZ | `<name>.f3d`, `materials/*.fmat`, `<name>.level.json` | One model per layer. A reference to another file is an instance of that file's prefab. UsdPreviewSurface becomes metal-rough. `upAxis` Z is turned to Y and `metersPerUnit` to metres. |
| USDC (binary) | as USDA | Through `usdcat`, when installed. |
| MaterialX `.mtlx` | `materials/*.fmat`, or `*.f3dmat` beside an `.fmat` | See [materials](#materials). |
| Unity `.prefab`, `.unity` | `<name>.level.json`, `models/*.f3d`, `materials/*.fmat` | Needs the project's `.meta` files to find meshes, materials and textures. |
| Unity `.mat` | `materials/*.fmat` | Built-in Standard, URP Lit and HDRP Lit. |
| Godot `.tscn` | `<name>.level.json`, `models/*.f3d`, `materials/*.fmat` | Godot 4 (format 3) and Godot 3 (format 2). `res://` is the directory holding `project.godot`. |
| Godot `.tres` | `materials/*.fmat` | `StandardMaterial3D`, `ORMMaterial3D`, Godot 3's `SpatialMaterial`. |
| FBX | as glTF | Through FBX2glTF, or Blender when FBX2glTF is absent. |
| `.blend` | as glTF | Through Blender in the background. |

A converted scene is a level document, format version 2: every prefab it
needs under `prefabs`, the materials it names under `materials` (each one
deferring to its `.fmat` through the `fmat` key), and one instance of the
input's own prefab at the origin, so the document opens as the thing it was
converted from. Rows are `model` entities, which `ModelVisuals` draws from the
file named by `asset`, `prop` entities for primitive shapes, which
`PropVisuals` draws by `shape` and size, and `prefab` instances. The paths in
the document are asset paths: the output directory as typed, or
`--asset-prefix`. The document carries `generatedBy`, so the editor offers to
save a copy instead of writing over it.

## What a bundle carries {#bundle}

The default `<name>.f3d` holds, besides the model:

- **lights and cameras**, on the nodes that carry them. Intensities are lux
  for a directional light and candela for a point or spot one, as in
  [the units contract](https://github.com/pleiondev/flutter3d/blob/main/docs/CONTRACTS.md);
- **each material's lighting model**, so a material drawn by a program names
  it, and the **programs** themselves (`.f3dmat` sources), by the material
  they declare. An older reader skips both and draws the base parameters;
- **the scene as prefab documents**, the same level documents `--split`
  writes, by name. A prefab places the bundle itself by its own path;
- **files carried whole**, by the path a prefab names them by: the other
  models of a scene, its `.fmat` materials and textures. For an input that
  is one model, its materials and images are already in the model, so the
  sidecars are left out.

From Dart, `F3dDocument.lights`, `cameras`, `programs`, `prefabs` (JSON
objects for `Level.fromJson`) and `files` read them back. No section is
must-understand: a reader that predates one opens a poorer asset, never a
different one.

## Placement

A level places a row by `at` and `yaw`, and an instance turns its prefab by
its yaw alone. A converter writes the rest of a rotation as `tilt`, a
quaternion applied before the yaw, and a scale as `scale`; `ModelVisuals`
reads both. Since an instance cannot carry a tilt or a scale to its rows, an
instance placed at an angle or scaled is written out row by row instead,
which keeps the picture and loses the link to the template. The report says
which ones.

Unity is left-handed and the engine is right-handed. Every Unity transform is
mirrored through Z: a position's z and a rotation's x and y change sign. Unity
also mirrors a model through X when it imports it, and the engine's `.f3d` of
the same file is not mirrored, so a Unity model row carries a half turn about
Y on top. Godot and glTF need nothing: both are right-handed, Y up, metres.

## Materials

A material that is only parameters of a built-in lighting model is an
`.fmat`, which the loader reads with no build step. That covers glTF, MTL,
UsdPreviewSurface, Unity's and Godot's materials, and every MaterialX
material whose inputs are constants or images. An image multiplied by a
constant is folded into the factor.

A MaterialX node graph that computes an input, such as a mix of two colours
across the surface, becomes a program: `<name>.f3dmat` in the material
language, and an `.fmat` beside it that names the program as its lighting
and binds its images. The program's diffuse and highlight come from the
graph; the highlight is a normalised Blinn-Phong lobe, an approximation of
the engine's own metal-rough response. Convert into `assets_src/` and the
build hook compiles it. The converter parses the program before writing it.
A graph with a node the language has no word for (noise, for example) is
folded to the nearest metal-rough surface, with a warning naming the node.

Unity and Godot keep metal and roughness in other channels than glTF does.
Unity's metallic/smoothness map, HDRP's mask map and Godot's separate
metallic and roughness maps are repacked into one image with occlusion in
red, roughness in green and metal in blue. Godot's ORM image already is one.

## What does not survive

| Lost | Why |
|---|---|
| Lights and cameras from USD, Unity and Godot | Place level lights. glTF's stay on their nodes inside the model. |
| Scripts, colliders, rigidbodies, particles | Behaviour, not content. |
| Animation in USD | The first time sample is the rest pose. glTF and FBX keep their animation inside the model. |
| USD skeletons, instancers, curves, points, volumes | Not read. Export glTF for skinned models. |
| USD composition beyond references | `over` and `class` prims, variants and inherits are not evaluated. A reference to a sub-prim places the whole layer. |
| Units between USD layers | Each layer is converted in its own units, as its author meant. USD itself would compose the referenced numbers unscaled. The report says when layers disagree. |
| Unity overrides other than placement and materials | A level overrides a row's own keys, and `m_CastShadows` has no counterpart. Added and removed components and objects are dropped. |
| Unity detail, parallax and coat maps; HDRP's other inputs | No slot in the engine's surface. |
| The specular workflow | Read as a dielectric with its smoothness. |
| Godot rim, subsurface, refraction, detail, height | No counterpart. |
| `ArrayMesh` data inside a Godot scene, CSG | Save the mesh as glTF, bake the CSG. |
| Unity's capsule, plane and quad | Drawn as a cylinder and thin boxes. |

## External tools

| Tool | For | Install |
|---|---|---|
| FBX2glTF | `.fbx` | A release from github.com/godotengine/FBX2glTF, on `PATH` or named by `FLUTTER3D_FBX2GLTF` |
| Blender | `.blend`, and `.fbx` without FBX2glTF | blender.org, `blender` on `PATH` or named by `FLUTTER3D_BLENDER` |
| usdcat | binary `.usdc` layers | `pip install usd-core` |

Without them those inputs are refused with what to install, and the command
exits 3. `flutter3d doctor` lists them beside the SDK checks: Dart and
Flutter against the floors and the versions CI runs, impellerc, and
glslangValidator and naga for the WebGPU section of a material.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Every input converted |
| 1 | An input could not be read or written |
| 2 | Usage |
| 3 | A needed external tool is not installed |
| 4 | An output exists with other contents and `--overwrite` was not given |

## As a library

A service that takes uploads calls the same conversion with bytes on both
sides, from `package:flutter3d_build/convert.dart`:

```dart
final result = await convertFiles(
  files,                         // Map<String, Uint8List>, by path in the bundle
  to: ConversionTarget.everything,
  entry: 'Assets/Scenes/Room.unity',
);
result.files;                    // Map<String, Uint8List>: one Room.f3d bundle
                                 // (bundle: false gives .f3d, .fmat, .level.json)
result.reports;                  // what mapped, what was dropped
```

It is plain Dart and runs no external program: FBX, `.blend` and binary USD
come back as unsupported, with exit code 3 in `result.exitCode`.
