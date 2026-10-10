# flutter3d_build

The build hook behind a [flutter3d](https://flutter3d.pleion.dev) project's
assets. It converts model and texture sources into what the engine loads, and
it does so on every build, so nobody has to remember to run a separate step.

```sh
dart pub add dev:flutter3d_build
dart run flutter3d_build:init          # hook/build.dart, pubspec, .gitignore
dart run flutter3d_build:init --check  # say what a run would change, change nothing
```

After that, anything under `assets_src/` is converted into
`flutter3d_generated/` at the same relative path whenever the project builds,
and a second build with nothing changed converts nothing. A
`flutter3d_assets.yaml` beside the pubspec excludes files by glob.

The hook compresses textures for the platform it is building for: BC for a
desktop target, ETC2 for Android and iOS. A block format is a property of the
platform, so the hook does not have to guess about the device. A web build
names no target and is left alone. Setting `textures:` under the project's own
name in its `hooks: user_defines:` overrides either choice. The value
`universal` there is the one family every device can load; it is turned into
BC, ASTC, ETC2 or RGBA8 when the texture is uploaded.

## The `flutter3d` command

```sh
dart pub global activate flutter3d_build
flutter3d help
```

One command for every tool here: `convert`, `create` (`create project <dir>`
or `create plugin`), `init`, `plugins`, `migrate`, `lights` and `doctor`.
Each also runs as `dart run flutter3d_build:<name>`, the same code.
`flutter3d doctor` checks Dart and Flutter against the versions in
SUPPORT.md and looks for the optional programs: impellerc, glslangValidator
and naga for building materials, and FBX2glTF, Blender and usdcat for
conversion.

### The command is a contract

From 1.0 the command is held to semver like the Dart API, because CI scripts
and services call it and none of them compiles against this package. Within
a major nothing below is removed or renamed, and the `--json` output only
gains keys. `api/flutter3d_build.cli` is the whole surface as
`flutter3d help --surface` prints it, and the repository's structure check
fails when the two differ.

**Subcommands:** `convert`, `create`, `init`, `plugins`, `migrate`, `lights`,
`doctor`, `help`. Each also runs as `dart run flutter3d_build:<name>`.

**Flags**, per subcommand:

| Subcommand | Flags |
|---|---|
| `convert <input...>` | `-o`/`--output <dir>`, `--dry-run`, `--overwrite`, `--asset-prefix <path>`, `--split`, `--no-materials`, `--report <file>`, `--json`, `--textures <family>`, `--no-mips`, `--lods <ratios>`, `--impostor`, `--chunks[=<triangles>]`, `-h`/`--help` |
| `create` | `project <dir> [--name <package>]`; `plugin --kind <kind> --name <name> [--target <dir>]`; `--list` |
| `init [dir]` | `--check`, `--force`, `-h`/`--help` |
| `plugins` | `--check`, `--json` |
| `migrate <project>` | `--dry-run`, `--from <version>`, `--no-pub-get`, `--lints-from <dir>` |
| `lights` | `--optimize <level.json>`, `--poses <file>`, `--state <file>`, `-o`/`--out <path>`, `--preview <dir>`, `--dry-run`, `--classes <names>` |
| `doctor` | `--json` |
| `help [<command>]` | `--surface` |

**Exit codes**, the same for every subcommand (`CliExit` in
`package:flutter3d_build/cli.dart`):

| Code | Meaning |
|---|---|
| 0 | It did what it was asked, or there was nothing to do. |
| 1 | It tried and failed: a file it could not read or write, an input that did not convert, a step that broke. |
| 2 | Usage: an unknown subcommand or option, a missing argument. |
| 3 | Refused or out of date: `--check` with changes pending (`init`, `plugins`), a target directory that is not empty, an external tool `convert` needs that is not installed. Nothing was changed. |
| 4 | Would overwrite: `convert` found an output with other contents and was not given `--overwrite`. Nothing was written. |

**`--json` output** is one JSON document on stdout that starts with the
format envelope every flutter3d document starts with — `"format":
"f3d.cli"`, `"version": 1`, `"requires"` and `"generator"` — and
`"command"`, followed by the subcommand's own keys: `convert` gives
`output`, `dryRun` and `reports`; `doctor` gives `checks`; `plugins` gives
`check`, `path`, `current` or `written`, and `plugins`. `flutter3d help
--surface` lists them, and `api/flutter3d_build.cli` commits that list.
`version` is the output's own number, not the package's. A key added is a
minor bump of it, and nothing is removed or retyped within a major.
`convert --report <file>` writes the same reports in the envelope
`f3d.convertReport`.

`flutter3d plugins --check` writes nothing. It exits 3 when
`lib/plugins.g.dart` is missing or differs from what the dependencies
declare, which is the check a CI job wants after a dependency changes.

## Bringing assets in

```sh
flutter3d convert Assets/Prefabs/Crate.prefab -o assets_src/imported
flutter3d convert 'scenes/**.tscn' model.usdz looks.mtlx -o assets_src/imported --dry-run
```

`flutter3d convert` reads glTF, GLB, OBJ with its MTL, STL, PLY, USDA and
USDZ, MaterialX, Unity prefabs, scenes and materials, Godot scenes and
materials, and FBX and `.blend` through FBX2glTF or Blender. Models become
`.f3d`; materials become `.fmat`, or a `.f3dmat` program when a MaterialX
graph computes an input; scenes and prefabs become level documents with
`prefabs`, nested instances and their overrides included. Each input gets a
report of what mapped and what was dropped and why (`--json`, `--report`).
**Each input becomes one `.f3d`**: the model with its lights and cameras,
its materials and textures, its programs and its scene as prefab documents,
with the other models a scene names carried inside. `--split` writes them
as separate files instead. Nothing is written over a file with other contents without `--overwrite`,
and `--dry-run` writes nothing. Exit codes: 0 converted, 1 failed, 2 usage,
3 a needed tool is missing, 4 would overwrite.

The same conversion takes bytes and returns bytes for a server, with no
external program and no Flutter:

```dart
import 'package:flutter3d_build/convert.dart';

final result = await convertFiles(uploadedFiles, to: ConversionTarget.everything);
// One bundle per input by default; bundle: false gives the split layout.
```

The format table and everything that does not survive the trip are on
[Bringing assets in](https://flutter3d.pleion.dev/reference/bringing-assets-in/).

`dart run flutter3d_build:convert` is the model converter the build hook
uses, unchanged: one model or a directory of them, written next to the
source or to `-o`.

## Materials

A material written in the material language goes under `assets_src/` with the
extension `.f3dmat`, next to the models that wear it. The hook compiles
`assets_src/fx/rim.f3dmat` into `flutter3d_generated/fx/rim.f3dshaders`: one
shader bundle with a fragment stage named after the material, carrying an
Impeller section, a WebGL2 section and, when `glslangValidator` and `naga` are
on `PATH`, a WebGPU section. Load it with `GraphicsDevice.loadShaders`.
Compiling happens only here, at build time. A mistake fails the build with the
material's file, line and column. A manifest rule's `glob` and `exclude` apply
to materials as well.

A material may open with a line naming the language version it is written
in, `f3dmat 1`, ahead of `material`. A file without that line is version 1,
which covers every material written before the line existed. A build reads
every version up to its own `materialLanguageVersion`. A newer file fails
the build with the version that reads it.

Version 2 (`f3dmat 2`, 1.0) adds the `state`, `vertex`, `ambient` and
`composite` blocks, the scene behind a translucent surface (`sceneDepth`,
`viewDepth`, `scenePosition`), and two more kinds of source, `fullscreen`
and `compute`. A material with a `vertex` block gets two more stages in its
bundle, `<Name>Vertex` and `<Name>VertexSkinned`. A `fullscreen` source is
built like a material. A `compute` source fails the build with the reason:
no GPU backend loads a compute stage from a bundle. The whole language,
with what each backend does with each construct, is on the site's
[material language](https://flutter3d.pleion.dev/reference/material-language/)
page.

The build also writes `lib/materials.g.dart`, with a typed accessor for each
material that declares a `uniform`: `SeabedParams(material.parameters).time
= t` instead of `material.parameters['time']![0] = t`. That happens only in a
package whose pubspec names `vector_math`, and the file is written only when
its text changes. The string map stays as it was. It is what the renderer
binds, and what a data plugin writes, since it has no Dart to generate.

The same converter can be run by hand:

```sh
dart run flutter3d_build:convert assets_src/chair.glb --textures universal
```

## Steps of your own

The hook runs three built-in steps in order: `models`, `materials` and
`plugins`. A `BuildStep` of your own (an importer, a baker) names the files it
reads and writes, so the hook reruns when one changes, and places itself with
`after`/`before`:

```dart
void main(List<String> arguments) async {
  await build(arguments, buildAssetsWith(<BuildStep>[WindBaker()]));
}
```

A plugin package exports its steps and the application names them here.
`buildAssets` is `buildAssetsWith(const [])`. A step that throws fails the build
with its name.

## Writing a plugin

```bash
dart run flutter3d_build:create plugin --kind render-step --name my_glow
dart run flutter3d_build:create --list
```

is `flutter3d create plugin`: a new package with the plugin, its
`flutter3d_plugins:` marker for discovery, a test that installs it, and
`test/conformance_test.dart`, which runs `flutter3d_conformance`'s plugin
suite. The five kinds are `render-step`, `effect`, `genre`, `element` and
`tool`. The directory must be empty or not exist.

`dart run flutter3d_build:plugin_mcp` is the same for an agent: an MCP
server with `plugin.create`, `plugin.conformance` (runs the suite and reads
it test by test) and `plugin.report` (each check, and whether the plugin
earns the conformance badge). Its tools are snapshotted in
`api/flutter3d_build.mcp`.

`skills/` holds one skill, `flutter3d-build-authoring-a-plugin`: which kind to
choose, what each check means and what the badge needs. A project depending on
this package installs it with `dart run skills@ get`.

## Plain Dart

The Flutter tool starts `hook/build.dart` as a separate process, with no window
and no Flutter SDK to resolve inside it. None of this package's dependencies
(`flutter3d_core`, `package:hooks`, `package:code_assets` and a few plain-Dart
libraries) names Flutter, because a hook that needed the SDK would not start on
a machine that does not have it.
