---
description: assets_src/, the build hook that converts it on every build, the manifest that overrides a file, texture families by target, and what a failed hook actually says.
---

# The asset pipeline

Source models and textures live in a project's own `assets_src/`; a build hook converts them into `flutter3d_generated/` on every `flutter build`/`flutter run`, and the engine loads the converted files by their source name. No step to remember, and no committed binary that drifts from the source it was built from.

```mermaid
flowchart LR
  src["assets_src/models/chair.glb"] -->|"hook, every build"| gen["flutter3d_generated/models/chair.f3d"]
  gen -->|"loadModelAsset('assets_src/models/chair.glb')"| doc["ModelDocument"]
```

## Wiring a project

```bash
dart run flutter3d_build:init
```

Writes four things, each idempotent:

| | |
|---|---|
| `hook/build.dart` | Calls `buildAssets`, the function the Flutter tool runs during a real build |
| `pubspec.yaml`'s `dev_dependencies:` | `flutter3d_build`, pinned the way the rest of the project pins its dependencies |
| `pubspec.yaml`'s `flutter: assets:` | `flutter3d_generated/`, and one line per subdirectory a source actually converts into — see the warning below for why more than one line |
| `.gitignore` | `/flutter3d_generated/` — generated, never committed |

`--check` reports what a run would change without changing it; `--force` overwrites a `hook/build.dart` a person has edited, which is otherwise left alone and reported instead. A second run of `init` on an already-wired project is a no-op.

<div class="warn">
<p><strong>Flutter's own asset bundler does not read a declared directory recursively</strong> — <code>flutter_tools</code> lists it with a plain <code>listSync()</code>, no <code>recursive: true</code>. A source at <code>assets_src/models/chair.glb</code> converts to <code>flutter3d_generated/models/chair.f3d</code>, and a <code>pubspec.yaml</code> naming only <code>flutter3d_generated/</code> bundles the hook's own bookkeeping file and silently drops every model in <code>models/</code>. <code>init</code> declares a line per subdirectory that actually holds a converted file, computed from the real sources on disk each time it runs — not a single line assumed to cover everything under it.</p>
</div>

<div class="warn">
<p><strong>A dependency added after the last build needs `flutter clean` before the hook runs.</strong> The build system's own incremental cache can remember "this project has no hooks" from before `flutter3d_build` was added, and neither a fresh `pubspec.yaml` nor a deleted `flutter3d_generated/` on their own make it look again — only a full clean does. The same cause `apps/flutter3d_demo_racing`'s own <code>pubspec.yaml</code> already names for `flutter_soloud`'s "no available native assets".</p>
</div>

## What gets converted, and where

Without a manifest, every recognised file under `assets_src/` maps to `flutter3d_generated/` with the same relative path, extension swapped to `.f3d`. An empty `assets_src/`, or none at all, plans nothing — that is a project that has not added a model yet, not an error.

With `flutter3d_assets.yaml` at the project root, a list of rules overrides the default per file:

```yaml
rules:
  - glob: "props/**.obj"
    textures: etc2
  - glob: "props/placeholder.obj"
    exclude: true
```

| Key | Meaning |
|---|---|
| `glob` | Matched against the path relative to `assets_src/`. `package:glob`'s own rule applies: `**/*.obj` does not match a root-level `a.obj` — `**.obj` (no slash) matches both |
| `textures` | `auto` \| `bc` \| `etc2` \| `none`, overriding `--target`'s own choice for files this rule matches |
| `mips` | `true`/`false` — skip the mip chain for files this rule matches |
| `objNormals` | `smooth` \| `flat` \| `none`, for an OBJ with no normals of its own |
| `exclude` | Leaves the file alone — no conversion, no entry in `flutter3d_generated/` |

The **last** matching rule wins, not the first, so a broad rule and a narrower exception below it read the way a person writes them. A bad glob or an unknown key names the line it is on, in `flutter3d_assets.yaml:N: ...` form — the manifest's own author reads that error, not a player of the finished game.

## Texture families by target

```bash
dart run flutter3d_build:convert assets_src/chair.glb --target=web
```

| `--target` | Family | Why |
|---|---|---|
| `macos` \| `windows` \| `linux` | BC | Desktop GPUs |
| `android` \| `ios` | ETC2 | Mobile GPUs |
| `web` | Both | A laptop and a phone in the same browser build load different files, chosen at runtime by what the WebGL context actually supports |

<div class="warn">
<p><strong>The build hook itself does not pass `--target` — it cannot.</strong> `buildAssets` runs through `package:hooks`, which has no way to name the platform a build is for without `package:code_assets`, rejected for this pipeline as experimental on stable. So a hook-driven build converts with `--textures auto` and no target, which behaves as `none`: textures ship uncompressed, and the mip chain <code>ap-08</code> still adds costs a byte or two without a saving to offset it. Compression by target is proven and tested — <code>dart run flutter3d_build:convert --target=...</code>, and `flutter3d_webgl`'s own `WebGlDevice.compressedTextureSupport` at load time — but only through the CLI today, not through the automatic path a real `flutter build` takes.</p>
</div>

## Loading by source path

```dart
final document = await loadModelAsset('assets_src/models/chair.glb');
```

Reads the converted `flutter3d_generated/models/chair.f3d`. Missing it means two different things on purpose:

- **In debug**, decodes `assets_src/models/chair.glb` directly instead, and prints one warning — not one per frame — the first time. A project with no build yet still draws something.
- **Outside debug**, throws a `StateError` naming `flutter3d_build:init` — a release build that shipped without its own hook ever running is a real problem, not something to keep paying the decode cost of silently.

The debug fallback reads the source straight off disk, which only exists during `flutter run`/`flutter test` from a checkout — never in a shipped build, and never on the web, which has no `dart:io`. There, a missing generated file is the release error in every build mode.

`FixtureVisuals` and `ActorVisuals` in `flutter3d_bridge` — the level-driven loaders every game shares — resolve a path the same way: `assets_src/…` goes through `loadModelAsset`, anything else loads exactly as it always did, so a game that has not moved onto the pipeline yet keeps working unchanged.

## When the hook fails

| Symptom | Cause |
|---|---|
| `flutter analyze` says an asset directory does not exist | Expected on a fresh checkout — hooks run during a real build, never during `analyze`, and the declared directory has nothing in it yet. Build once |
| `flutter analyze` says `hook/build.dart`'s own imports are not a dependency | `hook/` sits outside `test/`, where the analyzer does not look for `dev_dependencies:`. Excluded from analysis in `analysis_options.yaml`, the way generated platform folders already are |
| A model that used to load throws in release | The generated `.f3d` is missing from the shipped bundle — check every subdirectory under `flutter3d_generated/` has its own `pubspec.yaml` line, and that the build ran with `flutter3d_build` as a real dependency, not added after the last build with no `flutter clean` since |
| A build with a brand-new `flutter3d_build` dependency still skips the hook | `flutter clean`, then build again — see the warning above |

## What this does not cover

Level geometry (BSP brushes) names its own surface textures directly in the level document, read by `LevelLoader` — a completely different path from a model's own materials, and one this pipeline has no way to convert a bare texture file for: every stage here (`AssetLayout.plan`, `rolesByImageIndex`) classifies an image by the model material that references it, and a level material references nothing this pipeline reads. Those textures stay hand-placed and hand-committed.

## Next

- [Assets & animation](/core/assets/): the runtime side — decoders, `.f3d`, loading, skinning, morph targets
- [Package index](/reference/packages/#flutter3d_build): where `flutter3d_build` sits among the rest
- [Testing](/reference/testing/): what `dart run tool/structure.dart` holds every package to
