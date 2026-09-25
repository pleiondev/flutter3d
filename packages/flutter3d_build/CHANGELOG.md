## 0.8.0

**Every cached model converts again once.** `kAssetPipelineVersion` is 2,
because a manifest rule can now ask for levels of detail and an impostor, and
an output cached by 0.7 may be missing what its rule asks for. The first build
after the upgrade converts every source; after that a source is skipped when
it did not change, as before.

**`convert --lods=0.5,0.25,0.1` gives a model its own levels of detail.** A
manifest rule's `lods: [0.5, 0.25]` does the same from the build hook. Each
ratio, strictly between 0 and 1, cuts one level from every node's full mesh
with `flutter3d_mesh`'s `simplifyMeshWithAttributesMeasured`, and the node
switches to it at a screen fraction of half the square root of the ratio. A
surface with morph targets stays whole in every level, and a node whose
surfaces all morph gets no levels. `generateLods` is the same from Dart and
hands back a `LodLevelReport` per ratio. Nothing is cut unless a ratio is
named, and each level adds its triangles to the file. `C5`

**`--impostor` ends the chain in a card that turns to the eye.** With the flag,
or `impostor: true` in a rule, each node that draws something is drawn by the
software rasteriser from 8x8 directions laid out on an octahedral map, into an
albedo atlas and a normal-depth atlas that come out as the same bytes on every
machine. The bake runs after the mesh levels and before texture encoding, so
it can still decode the source images; a texture it cannot decode is baked as
its material's base colour, and the report says which. At run time the node's
`LodGroup` ends in the card, one draw that casts no shadow. `bakeImpostors`
is the entry from Dart, and a `device` handed to it is left open for its
owner; everything the bake uploads it releases again. On five trees at the
switch distance, 11% of the silhouette differs from the mesh and the mean
colour error is under 13 steps a channel. Off by default. At the default
`cell` of 64 it costs two 512 by 512 atlases per node. `C4`

**`--chunks` splits a scan into runs the renderer culls one at a time.**
`--chunks`, `--chunks=N`, or `chunks: true` or a triangle count in a rule runs
`flutter3d_mesh`'s `clusterMesh` on every static mesh above the threshold,
`kDefaultChunkThreshold` (65536 triangles). Each run of up to 4096 triangles
carries a box and a cone of normals, which the scene pass tests against the
view, the facing and the occlusion test. No vertex moves, and a skinned or
morphing mesh stays whole. The table goes in a `.f3d` section of its own,
written only when a mesh has one, so a reader from before 0.8.0 loads the same
mesh and draws all of it. `splitLargeMeshes` is the entry from Dart. Off by
default. `C9`

**One file per device class.** A manifest can name `classes: [phone, web,
desktop]`, or map a class to its own `lods`, `impostor`, `impostorCell`,
`maxTextureSide` and `lightDifference`. The build then writes
`model.phone.f3d`, `model.web.f3d` and `model.desktop.f3d` in place of
`model.f3d`, each with its own level-of-detail chain, impostor and largest
texture side. The presets are `DeviceClassBudget.phone` (levels at 0.5, 0.25
and 0.1, an impostor cell of 32, `TextureBudget.mobile`),
`DeviceClassBudget.web` (0.5 and 0.25, an impostor, `TextureBudget.web`) and
`DeviceClassBudget.desktop` (the rule's own chain, `TextureBudget.desktop`).
`convert --classes phone,desktop` does the same from the command line. The
hook carries the phone and desktop files on a native target and the web files
on a build with no code configuration, which is how a web build calls it; a
`deviceClasses` hook user define overrides the choice. It deletes class files
an earlier build left, and still writes the single `.f3d` whenever a carried
class has no file of its own, so the loader's fallback always finds one. At
run time `flutter3d_core` picks the class, and `loadModelAsset` reads its file
first. A manifest without `classes:` builds what it built before, to the same
cache key. `N7`

**`dart run flutter3d_build:lights --optimize <level.json>` gives a level fewer
lights.** It runs `flutter3d_editor_core`'s `LightOptimizer`, the same one the
editor's button and its agent server call. The views come from `--poses`, the
list a game's `Recorder` writes while it plays a run back, or else four
headings from every player spawn. `--state` names a lighting state the level
must still look right under, such as the noon sun or a night with no light,
and may be repeated. The command prints the moves and the numbers, writes
before and after previews with `--preview`, writes over the input or to
`--out`, writes nothing with `--dry-run`, and refuses to overwrite a generated
level. A plan whose drawn result misses the optimizer's bounds is reported and
not written. `--classes phone,web,desktop` writes `level.phone.json` and the
others beside the output, each optimised to its class's `lightDifference`
from the nearest `flutter3d_assets.yaml` (or the preset's), and leaves the
level itself alone. The command lives under `bin/` only, so the build hook
does not compile the optimizer. `N1`

**A Gaussian splat capture converts to a paged `.f3dsplat`.** `convert` turns
a `.ply` or `.spz` capture into an octree of merged levels of detail, written
coarse levels first so a viewer reads only the pages its cut needs.
`convertSplat` is the entry from Dart. Walking a directory, a `.ply` counts as
a capture only when its header names `f_dc_0`, so a folder that also holds a
mesh saved as PLY converts. A `.ply` named on its own is still tried, and
refused with the reason.

**Smoke without an asset.** `bakeSixWay` bakes a density field into a
`SixWaySheet` for `flutter3d_particles`' six-way stage, with single scattering
along the six axes, and `smokePuff(seed:)` is a procedural puff to bake. The
defaults are 16 frames in 4 columns of 64-pixel cells at an `extinction` of
6.0; a sheet that size is a few million multiplications on the CPU. `N6`

`init` writes `^0.8.0` for this package (`kFlutter3dBuildVersionConstraint`).
The package now depends on `flutter3d_mesh`, `flutter3d_cpu`,
`flutter3d_model_core`, `flutter3d_editor_core` and `flutter3d_sim`, all plain
Dart, and on `vector_math` ^2.4.3.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**The manifest's doc says what `glob` 2.2.0 does:** `**/*.obj` matches a
root-level `a.obj` as well as `props/a.obj`.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `code_assets` ^2.1.0, `glob` ^2.2.0, `yaml` ^3.1.4, `image` ^4.10.1, `vector_math` ^2.4.3.

## 0.7.0

* **The first publication.** The 0.6.0 below was a number carried inside the
  workspace and never reached pub.dev, and it describes a scaffold with no
  exports. 0.7.0 is the number the whole shelf goes out on, so one number names
  one tree and `^0.7.0` on any `flutter3d_*` package resolves against every
  other; `doc/boundary-0.7.0.md` lists the thirteen packages that begin here.
  What follows is what the scaffold was filled in with. The package is plain
  Dart: it depends on `flutter3d_core` for the decoders and encoders, on
  `hooks` and `code_assets` for the build-hook contract, and on `glob`, `yaml`,
  `crypto` and `image`.
* **`dart run flutter3d_build:convert <model-or-directory>`.** Converts a glTF,
  GLB, OBJ or STL model into the engine's `.f3d` container, and a directory
  converts every recognised model under it. `-o` names the output file or
  directory, and `--textures` takes `auto`, `bc`, `etc2`, `universal` or
  `none`. `bc` writes BC1 for an opaque image and BC3 for one with alpha.
  `etc2` writes ETC2 RGB8 and leaves an image with alpha as it arrived, saying
  so, because the EAC alpha block is not encoded. An image whose sides are not
  multiples of four is left as it arrived too. `runConvert`, `convertOne`,
  `ConvertOptions`, `TextureFamily` and `encodeDocumentTextures` are the same
  from Dart. `TextureFamily` is a final class with static constants and not an
  enum, so a `switch` over one needs a default.
* **`buildAssets(input, output)` is the build hook.** A project's
  `hook/build.dart` calls it. With no configuration everything under
  `assets_src/` is converted into `flutter3d_generated/` at the same relative
  path with the extension `.f3d`, which is `AssetLayout.plan`. A
  `flutter3d_assets.yaml` overrides that per glob through `AssetManifest`: the
  texture family, `mips`, how an OBJ without normals gets them, or `exclude`,
  with the last matching rule winning, and a `ManifestFormatException` names
  the line. The glob `**/*.obj` does not match a file directly under
  `assets_src/`; `**.obj` matches both.
* **A source is converted again when its content changed, and not when its
  date did.** `runAssetBuild` keeps a cache of a content hash per source with
  the texture family that wrote the output and two version stamps,
  `kAssetPipelineVersion` and the `.f3d` format's own, and any of the four
  moving converts the file again. A cache that cannot be read converts
  everything. `AssetBuildReport` lists what was `converted`, what was `skipped`
  and the `dependencies` the hook declares, so the next build is asked for when
  one of them changes.
* **The hook picks the texture family from the platform it builds for.**
  `familyForTargetOS` answers `bc` for macOS, Windows and Linux, `etc2` for
  Android and iOS, and `auto`, which converts no texture, for anything else,
  the web included. A `textures:` value under this package's key in the
  project's `hook_user_defines` comes first. The target is read only when the
  build input carries a code configuration.
* **A compressed texture carries a mip chain.** Each level is a box filter of
  the one above in the channel's stored values, down to the last level that is
  whole 4x4 blocks: a 64-pixel image gets five levels and a 12-pixel one gets
  one.
* **`--textures universal` cooks one texture for every device.** It writes a
  4x4 block intermediate of `kUniversalBlockBytes`, twenty, bytes a block that
  is not a GPU format, and `flutter3d_core`'s upload turns it into BC1, BC3,
  ASTC 4x4, ETC2 or RGBA8 against what the device says it samples. A project
  that ships to desktop and phone from one build sets it in
  `hook_user_defines`.
* **`--no-mips` skips something.** It was accepted and answered with a note,
  because nothing generated a chain to skip; every compressed family has since
  learned to write one. `convertOne` and `encodeDocumentTextures` take
  `mips:`, and with it false a texture keeps its base level alone — `bc`,
  `etc2` and `universal` alike. The note `--textures auto` prints, and the
  usage text, stop promising a per-target choice the converter was never going
  to make: a build hook is told its target and resolves `auto`, a command line
  names a family, and `universal` is the one that needs no target at all.
* **A project stops needing a person to wire up its own build hook.**
  `dart run flutter3d_build:init` (`ap-10`) writes the four things the hook
  needs — `hook/build.dart`, a `dev_dependencies:` line on this package, the
  `flutter: assets:` entries for the generated directory, and a `.gitignore`
  line for it — each idempotent on its own, so a second run is an empty diff.
  `--check` reports what a run would change and changes nothing; a
  `hook/build.dart` somebody edited is reported and left alone without
  `--force`. **One `assets:` entry per generated subdirectory, not one for the
  root:** Flutter bundles a declared directory without recursing, so a single
  `flutter3d_generated/` line ships the hook's own cache file and silently
  drops every model converted under `models/`.

## 0.6.0

* **The scaffold, and nothing else.** `ap-02` in `doc/asset-pipeline-plan.md`:
  a plain Dart package, `flutter3d_formats` and `flutter3d_geometry` for the
  decoders a hook will convert through, `package:hooks` for the contract
  `ap-00`'s spike proved works on macOS, web, Android and iOS without
  `package:data_assets`, which stays experimental on stable. No exports yet —
  those arrive with `ap-03` through `ap-05`.
