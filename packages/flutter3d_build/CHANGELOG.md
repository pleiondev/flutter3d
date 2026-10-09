## 1.0.0-rc.1

- **Breaking: `DeviceClass` and `deviceClassPath` are not re-exported, nor is
  `flutter3d_build_hooks`.** The device classes are `flutter3d_core`'s, and
  `compileMaterial`, `MaterialCompilers` and `MaterialBuildException` are the
  build hooks' package's; a file that names them imports it.

- **The plugin author server's suite version is its own**: it no longer
  exports a `conformanceSuiteVersion` beside `flutter3d_conformance`'s.
- **`create project` lights its sphere.** The template's point light was
  16, which since 1.0 is 16 candela and a black screen; it is 92 650 cd,
  the light it was.
- **`migrate` renames the plugin key**: a top-level `flutter3d:` in the
  pubspec becomes `flutter3d_plugins:` (decision D), with what is under it
  unchanged. A pubspec with both keys keeps both, and the report says to
  merge them.
- **Breaking: `--json` starts with the format envelope.** `"format":
  "f3d.cli"`, `"version"`, `"requires"` and `"generator"` replace
  `"schema"` and `"schemaVersion"`; `cliJsonSchemaVersion` is
  `cliJsonVersion`. Each subcommand's keys are in `cliJsonBodies` and in
  `flutter3d help --surface`, so `api/flutter3d_build.cli` snapshots them.
- **Breaking: `convert --report` writes the envelope** (`f3d.convertReport`)
  with the reports under `reports`, where it wrote a bare list.
  `convertReportsFrom` reads both.
- **Breaking: the argument parsers throw a `ConvertUsageException` saying
  what was wrong** instead of answering null: `ConvertSettings.parse`,
  `TextureFamily.parse` and `parseLodRatios`. `TextureFamily.tryParse`
  answers null for a caller with a fallback.
- **`flutter3d --version` reads the version from the package's pubspec**,
  where it printed a number written into the command.
- **The asset and material caches carry the envelope**; a cache from before
  reads as empty, and everything builds again once.
- **The plugin marker is `flutter3d_plugins:`** (decision D); `flutter3d:`
  is still read, with a warning, until 2.0. New: `pluginMarkerKey`, the
  deprecated `legacyPluginMarkerKey`, `markerOf`, `PluginDiscovery.warnings`,
  and a `warnings` key in `plugins --json`.
- **An application picks which plugins it installs.** Its own pubspec may
  narrow its dependencies' plugins under `flutter3d_plugins:`, with
  `include:` and `exclude:` lists of a package (`flutter3d_post`), a library
  (`flutter3d_post/motion.dart`) or one class
  (`flutter3d_post/style.dart#ToonLightingAddon`), so depending on
  `flutter3d_post` no longer has to mean all twenty-three effects. An entry
  that matches nothing is a warning rather than silence. New:
  `PluginSelector`, `selectPlugins`, `PluginDiscovery.excluded`, and an
  `excluded` key in `plugins --json`.
- **The plugin author's server announces schema version 1.0.0**, and
  `plugin_mcp` exits 2 on a wrong argument (`CliExit.usage`), not 64.

- **A plugin marker per library.** `flutter3d: plugin:` may be a map from
  one of the package's libraries to the class or the list of classes it
  declares, beside the single entry and the list it already took; all three
  read into the same `plugins.g.dart`. `markerEntries` is the reading, for
  a tool that wants the same answer. `flutter3d_post` marks its six
  families this way.
- **`migrate` follows packages that merged.** Twenty-seven packages went
  into seven (`flutter3d_game_kit`, `flutter3d_game_physics`,
  `flutter3d_game_ui`, `flutter3d_camera`, `flutter3d_post`,
  `flutter3d_mcp`, `flutter3d_education`). A pubspec that named several of them is left
  naming their new package once, an `import` entry may move a whole
  directory (`package:flutter3d_addon_hud/src/` to
  `package:flutter3d_game_ui/src/hud/`), and the generated `fix_data.yaml`
  goes to the package a name lives in now, matching it by both its old and
  its new library.
- **The material compiler is `flutter3d_build_hooks`'.** `compileMaterial`,
  `MaterialCompilers`, `MaterialBuildException` and
  `generateMaterialAccessors` moved to that light package, so a package's
  own build hook (`flutter3d_effects`') compiles its materials without
  resolving this one's converters and servers into every game. This
  package depends on it and exports the four under the same names.
- **The MCP kit is `flutter3d_mcp`'s.** The plugin author's server is built
  on `package:flutter3d_mcp/kit.dart`, so this package depends on
  `flutter3d_mcp` where it depended on `flutter3d_mcp_kit`.
- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `ConvertCommandOptions` is `ConvertCommandSettings`,
  `ModelOptions` is `ModelSettings`. Every settings class is `final` with a
  `const` constructor and a `copyWith` over every field; a nullable field
  is reset with `copyWith(clearX: true)`. `dart fix` carries the renames.
- **Breaking: public constants are lowerCamelCase, without the k prefix,
  as Effective Dart asks.** `kAssetPipelineVersion` is
  `assetPipelineVersion`, `kDartFloor` is `dartFloor`, `kDartTested` is
  `dartTested`, `kDefaultChunkThreshold` is `defaultChunkThreshold`,
  `kFlutter3dBuildVersionConstraint` is `flutter3dBuildVersionConstraint`,
  `kFlutterFloor` is `flutterFloor`, `kFlutterTested` is `flutterTested`,
  `kGitignoreEntry` is `gitignoreEntry`, `kHookBuildContent` is
  `hookBuildContent`. The values are the same; `dart fix` carries the
  renames.
- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `ConversionResult.ok` is `isOk`. `dart fix` carries the renames.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `recognisedExtensions` is `recognizedExtensions`. Only the Dart
  names changed: a file keeps the keys it was written with, and `dart fix`
  carries the renames.
- **Breaking: `flutter3d convert` writes one `.f3d` per input.** The model
  with its lights and cameras, its materials and textures, its `.f3dmat`
  programs and its scene as prefab documents travel in one bundle (the
  sections are `flutter3d_core`'s), and a scene's other models ride inside
  it, so a converted asset can no longer be shipped with a file left behind.
  The new `--split` flag writes the separate files as before (`.fmat`,
  `.f3dmat`, `textures/`, `models/`, `.level.json`). `convertFiles` takes
  `bundle:` (true by default; `false` is the split layout) with its signature
  otherwise unchanged; `ConversionTarget.materials` and `scenes` pick from
  the split layout, since a bundle is a model (`build-convert-bundle`).
- **The plugin author's server says what its tools do.** It announces
  itself as `flutter3d.plugins` (schema 1.1.0), marks `plugin.conformance`
  and `plugin.report` read-only, and answers `flutter3d.schema`. A tool
  plugin made by `flutter3d create plugin --kind tool` asks for the `tools`
  permission, declares its schema version, and is written against
  `ToolSpec`/`ToolResult` with no dependency on the MCP library.
- **The `flutter3d` command is a contract, held like the API.** Its
  subcommands, flags, exit codes and `--json` output are frozen for 1.x and
  listed in the README; `api/flutter3d_build.cli` is the whole surface as
  `flutter3d help --surface` prints it, and the repository's structure check
  fails when the two differ or a command or flag disappears without a
  **Breaking:** entry. `CliExit`, `cliJsonSchemaVersion`, `cliJson` and every
  subcommand's usage text are in `package:flutter3d_build/cli.dart`.

- **Breaking: one set of exit codes.** 0 ok, 1 failed, 2 usage, 3 refused or
  out of date, 4 would overwrite. `flutter3d` and `create` used to answer a
  usage error with 64 and a non-empty target with 73; they answer 2 and 3.
  `init --check` with changes pending exits 3, not 1, so a CI job can tell
  "out of date" from "broke".

- **Breaking: `--json` output carries its schema.** Every document starts
  with `"schema": "f3d.cli"`, `"schemaVersion": 1` and `"command"`. `doctor
  --json` prints `{"checks": [...]}` inside it instead of a bare list;
  `convert --json` keeps its keys after the three new ones.

- **`flutter3d_assets.yaml` takes `format: 1`.** The manifest's version, the
  YAML spelling of the format envelope; a manifest without it is version 1,
  and a newer one is refused with the version that reads it.

- **The plugin author server names the badge with its suite:**
  `conformant@1.0`, and `ConformanceRun.badge` answers it.

- **`flutter3d plugins --check`** writes nothing and exits 3 when
  `lib/plugins.g.dart` is missing or is not what the dependencies declare.
  `plugins --json` prints what it found.

- **Assets from other tools come in with `flutter3d convert`.** A new
  `flutter3d` executable (`dart pub global activate flutter3d_build`) runs
  every tool of this package as a subcommand, and its `convert` reads glTF,
  GLB, OBJ with MTL, STL, PLY meshes and splat captures, USDA and USDZ,
  MaterialX, Unity `.prefab`, `.unity` and `.mat`, Godot `.tscn` and
  `.tres`, and FBX and `.blend` through FBX2glTF or Blender when they are
  installed. Models become `.f3d`. A material that is parameters of a
  built-in lighting model becomes `.fmat`; a MaterialX graph that computes
  an input becomes a `.f3dmat` program beside an `.fmat` that names it.
  Scenes and prefabs become level documents with `prefabs`, a nested
  instance an instance row with its overrides, and Unity's left-handed
  transforms are mirrored into the engine's frame. Every input gets a
  report of what mapped and what was dropped and why; `--dry-run` writes
  nothing, nothing is written over a file with other contents without
  `--overwrite`, and the output is the same bytes on every run.
  `convertFiles` in `package:flutter3d_build/convert.dart` is the same
  conversion with bytes in and bytes out, for a server: plain Dart, no
  external program.

- **`flutter3d doctor` checks the toolchain.** Dart and Flutter against the
  floors and the versions CI runs, and the optional programs: impellerc,
  glslangValidator, naga, FBX2glTF, Blender and usdcat.

- **`flutter3d create project <dir>` starts a game.** One lit sphere, the
  build hook wired and `assets_src/` ready.

- **`convertDocument` runs the model steps on a document in memory.** Levels
  of detail, chunks, impostors and texture encoding, then the `.f3d` bytes,
  read back and compared; `convertOne` is it with a file on either side.
  `decodeModelFile` decodes a model as `convertOne` does.

- **Breaking:** `ManifestFormatException` extends `Flutter3dFormatException`
  instead of implementing `Exception` directly. The name and members are
  unchanged and every `on` clause that caught it still does; every exception
  the engine throws now hangs from `Flutter3dException` in
  `flutter3d_plugin_api`, in one of four families: format, capability, plugin
  and resource. The migration table marks it as nothing to do.
- **The build's other refusals joined the same root.**
  `MaterialBuildException` and `F3dRoundTripException` are
  `Flutter3dFormatException`s; `BuildStepException`, `MissingToolException`
  and `ToolFailedException` are `ResourceException`s, the first with the
  step's own error as its `cause`; `PluginDiscoveryException` is a
  `PluginException`, so its `message` is inherited.
- **Breaking: the build's own readers throw their own exceptions.** A
  source file the converter cannot read (PLY, USD, Godot and Unity text,
  XML, a ZIP, a file `decodeModelFile` has no reader for) throws
  `SourceFormatException`, a command line `ConvertCommandSettings.parse`
  cannot read throws `ConvertUsageException`, and a damaged migration table
  `MigrationTableException`, all `Flutter3dFormatException`s, where each
  threw `dart:core`'s bare `FormatException`. `flutter3d convert` still
  answers a bad command line with the usage and exit code 2, and still
  reports an unreadable input in its row. An `on FormatException` around
  one of them no longer catches; the migration table flags it
  (`build-format-exceptions`, `build-decodeModelFile-exception`).
- **Material language version 2, built for every GPU backend.** A `vertex`
  block becomes `<Name>Vertex` and `<Name>VertexSkinned` beside the fragment
  stage, in every section. A `fullscreen` source builds like a material. A
  `compute` source fails the build with the reason: no GPU backend loads a
  compute stage from a bundle.
- **Typed material accessors.** `generateMaterialAccessors` writes an
  extension type per material that has uniforms (`SeabedParams(material
  .parameters).time = t`), and the materials step writes them to
  `lib/materials.g.dart` in a package whose pubspec names `vector_math`. The
  string map stays as it was.
- **`dart run flutter3d_build:migrate` moves a 0.8 project to 1.0.** It
  moves the pubspec constraints, rewrites imports of libraries that moved
  between packages, runs `dart fix` and `flutter3d_lints:migrate`, adds the
  dependencies the new imports need, and prints what changed and what is left
  to do by hand. Each item left by hand also gets a
  `// TODO(flutter3d-1.0):` in the code, with a link to its line in the
  guide. Run it globally activated, with `--dry-run` first. Everything it
  and the other two tools do comes from one table,
  `lib/migrations/0.8_to_1.0.yaml`. That table also generates each
  package's `fix_data.yaml` and the guide on the site.

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

- **The build is a list of steps, and a project adds its own.** The hook
  was a fixed sequence: models, then materials, then the plugin list. Each
  is now a named `BuildStep` (`models`, `materials`, `plugins`), and
  `buildAssetsWith([...])` puts a project's importers and bakers among them
  by `after` and `before`, ordered as the loop orders its systems — a cycle
  names its members. A step says what it read and wrote, its inputs are
  declared to the hook so an edit to one reruns the build, and a step that
  throws fails the build with its name. `buildAssets` is `buildAssetsWith`
  with no steps of the project's and does exactly what it did;
  `runBuildSteps` runs them on a plain directory. Steps run in the hook, not
  in an engine, so a plugin package exports its steps and the application's
  `hook/build.dart` names them.

- **A flutter3d update rebuilds every material bundle that needs it.** The
  material cache's stamp now includes the F3SB container version, the
  WebGPU and material section versions and the material language version.
  An update that moves any of them recompiles every `.f3dmat` on the next
  build, so the runtime never meets a bundle it would refuse as stale.

- **The build hook finds the plugins.** Dependencies whose pubspec says
  `flutter3d: plugin: <import>#<Class>` are written into the application's
  `lib/plugins.g.dart` as `installedPlugins`. The walk starts from the
  application's own dependencies and not from everything the workspace
  resolved. The hook declares the package graph and the pubspecs it read,
  so a new plugin dependency reruns it. `dart run flutter3d_build:plugins`
  does the same by hand. An application with no plugin dependency gets no
  file.

- **`flutter3d create plugin`: a new plugin from a template.** `dart run
  flutter3d_build:create plugin --kind <kind> --name <name>` writes a
  package for one of five kinds — `render-step`, `effect`, `genre`,
  `element`, `tool` — with the plugin, the discovery marker, a test that
  installs it and `test/conformance_test.dart`. Each template's manifest
  says what it touches and declares a budget, and the two kinds that run in
  the step enable the `flutter3d_lints` analyzer plugin. `pluginTemplate`
  and `PluginKind` are the same files as a library.

- **An MCP server for a plugin's author.** `dart run
  flutter3d_build:plugin_mcp` offers `plugin.create`, `plugin.conformance`
  and `plugin.report`: create a plugin, run its conformance suite and read
  it test by test, and say whether it earns the badge — every check run and
  passed, none declined. Its tools are held to `api/flutter3d_build.mcp`,
  schema 1.0.0. The skill `flutter3d-build-authoring-a-plugin` ships beside
  it.

- **The six-way smoke baker moved to `flutter3d_particles`,** beside the
  `SixWayMaterial` it bakes for: `bakeSixWay` and `smokePuff` are no longer
  exported here.

- **A material's bundle carries its source** in the material section, and
  `assetPipelineVersion` is 3, so bundles built before it are built again.

**A material written in the material language compiles at build time into
a shader bundle every GPU backend loads.** The hook finds
`assets_src/**/*.f3dmat` and writes `flutter3d_generated/**/*.f3dshaders` at
the same relative path. It parses each source, emits GLSL through
`flutter3d_core`'s emitter, resolves the engine's headers from
`flutter3d_shaders`, and packs one `ShaderBundle` with three sections:
`impellerc` output for Impeller, GLSL ES 3.00 for WebGL2, and WGSL with its
reflection for WebGPU. `GraphicsDevice.loadShaders` takes the file on any
backend; the software backend evaluates the same source on the CPU and needs
no section. Before this, the language emitted GLSL that nothing built, so a
material could be evaluated on the CPU and could not be drawn by a GPU.

A mistake in a material fails the build with the file, line and column
(`fx/rim.f3dmat:3:13: ...`). A compiler refusing the GLSL generated from a
valid source names the source and keeps the generated `.frag` under
`.dart_tool/flutter3d_build/materials/`, so the line in the compiler's
message can be opened. Nothing compiles at run time.

The WebGPU section needs glslangValidator and naga. On a machine without
them the bundle gets the other two sections and the log says so, and the
WebGPU backend refuses that bundle by name. Failing the whole build over one
backend's tooling would make it a requirement for everyone. A missing
`impellerc` is an error, because it ships in the Flutter SDK that runs the
hook.

Every material source and every engine shader header is declared as a hook
dependency, so editing `surface.glsl` rebuilds the bundles that include it.
A bundle whose inputs did not change is not compiled again, and a bundle
whose source is gone is deleted. A project without materials does not look
for a compiler or for the engine's sources at all.

A manifest rule's `glob` and `exclude` apply to materials as they do to
models.

`init` writes `^1.0.0` for this package (`flutter3dBuildVersionConstraint`).

Its `flutter3d_*` dependencies ask for `^1.0.0`.

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
