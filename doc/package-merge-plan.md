# Fewer packages — the merge plan

Compiled 2026-09-13. Grounded in the owner's own question about whether
forty-five packages is over-abstraction, and a review of every package
against its pubspec, its dependency graph, `ARCHITECTURE.md` §3, and
pub.dev's own answers the same day, on the `modeler` branch.

Notation — as in [tooling-plan.md](tooling-plan.md): **size** — how big for
one person (S up to a day, M two to three days); **pub** — the package is
published on pub.dev, and a merge needs a version bump and a CHANGELOG entry
on both sides. Line counts are `lib/` only, no tests.

## 1. What makes a package boundary, and what doesn't

In this repository a package is justified if one of six things separates it:

1. **The Flutter SDK.** A server, an MCP server, a CLI, and a build hook
   cannot import Flutter. The boundary is checked by the `the simulation
   names no Flutter` rule against the `flatDartPackages` list in
   `tool/structure/repository.dart`.
2. **Native code or a plugin.** Platform folders, `flutter_gpu`,
   `flutter_soloud`, `flutter_webrtc`. A plugin cannot be folded into a
   non-plugin without making the receiver a plugin too.
3. **A third-party dependency a consumer should not inherit.** `dart_mcp`,
   `flutter_bloc`, `flutter_test`, `web`.
4. **Asset weight.** 4.7 MB of Khronos samples, GLSL sources, the shader
   bundle.
5. **The genre rule.** `no package names a genre` and `a genre package
   reaches no other genre` — both in `tool/structure.dart`.
6. **Independent publishing.** 27 packages on pub.dev, 18 not. Unpublished
   ones merge with no consequence for anyone else's `pubspec.yaml`.

What does **not** make a boundary: "written after the 0.6.0 set was decided"
(the `flutter3d_cloth`/`flutter3d_rig` CHANGELOGs), "convenient to import in
one line" (`flutter3d_app`), "for later" (`flutter3d_fbx`), and "nobody uses
it yet" (`flutter3d_render_job`, `flutter3d_stereo`).

## 2. What the review found

Of 45 packages, 38 hold up under one of the reasons above and stay. Seven
hold up only on history, and fold into six merges (one of the seven is
contested, §4). Result: **45 → 39**, or 38 if the contested one lands too.

A seventh reason, added by the owner on 2026-09-13 while reading the first
draft: **a narrow subject-matter domain**. `flutter3d_lab` (the pendulum,
`edu-04`) is built on `sim`, but an educational simulation is a vertical, not
part of the engine — the same way a genre package is not part of
`flutter3d_game`. It stays a separate package on the same grounds as the four
genres.

The full table across every package, with its reason for standing alone, is
in §6.

## 3. The merges

Ordered from cheap to expensive: unpublished packages first, then pairs
already on pub.dev. Each merge is its own commit, so a bad one reverts alone.

### 3.1 `flutter3d_cloth` → `flutter3d_physics` — size S, pub (physics)

Cloth depends only on `physics` and shares its own shape types. The only
reason it's a separate package, per its own CHANGELOG, is when it was
written. Moves into `packages/flutter3d_physics/lib/src/cloth/`, exported
through `flutter3d_physics.dart`. Consumers: `flutter3d_model_core`,
`apps/flutter3d_modeler`.

### 3.2 `flutter3d_rig` → `flutter3d_model_core` — size S, not pub

Its own description promises "no Flutter, no renderer," yet its pubspec
depends on `flutter3d_model_core` — meaning this is a modeler operation, not
a library. Its only consumer is `flutter3d_model_mcp`. Moves into
`packages/flutter3d_model_core/lib/src/rig/`. No cycle results: `model_core`
does not depend on `rig`.

### 3.3 `flutter3d_fbx` → `flutter3d_formats` — size S, not pub

73 lines: `handles()` recognizes the file, `decode()` refuses with a
`FormatException`. It belongs next to glTF, OBJ, STL and USDZ in `formats`.
Splitting it back out only makes sense if the `fmt-24`/`fmt-25` reader
brings in a dependency `formats` shouldn't carry. Drop the `flutter3d_fbx`
line from `flatDartPackages` — `formats` is already in that list.

### 3.4 `flutter3d_render_job` — not a merge, a consumer — size S, not pub

`RenderSnapshotJob` is imported by no package and no app, and the plan's
first draft marked it for removal. The 2026-09-13 review found it doesn't
depend on the editor at all: it takes a `ModelProject` in (which `model_core`
assembles, including from any `formats` document through
`fromModelDocument`) and produces a PNG. It owns three things that exist
nowhere else: `sceneFromProject` (a second document-to-`Scene` converter; the
first is the modeler's own `scene_sync.dart`), tiled rendering with stitching
and 2× SSAA, and a choice between `Isolate.run` and yielding frame by frame
on the web.

It only runs inside a Flutter process: `flutter3d` names Flutter, so
`dart run` and `flutter3d_model_mcp` are both out. So its home is a package
sitting above the pure `model_core`, the same shape `particles` has above
`particles_core`.

**Owner decision (2026-09-13): keep it as a package and give it a
consumer.** The cheapest option is a "Render" button in
`apps/flutter3d_modeler` and a thumbnail in the project list. While at it,
collapse the two document-to-scene converters into one: the modeler's own
`scene_sync.dart` and `sceneFromProject` build the same scene two different
ways, and the second of the two already lives in a package the modeler can
import. Do not fold this into `flutter3d_testing`: `testing` would inherit
`model_core` and `mesh` just to close over one scenario.

### 3.5 `flutter3d_sim_mcp` + `flutter3d_render_mcp` → `flutter3d_sim_mcp` — size M, not pub

Both are Flutter packages, both build on `dart_mcp`, both close over
`bridge` + `cpu` + `sim` + `flutter3d`; `sim_mcp` additionally pulls in
`game_shooter`. One process with two tool sets: an agent that plays a level
blind (`ai-00`) and an agent that asks "why is this frame wrong" (`par-02`)
are the same agent in the same session, and today it needs two stdio
servers.

The name stays `flutter3d_sim_mcp`; `render_mcp`'s tools move into their own
file, `lib/src/render_tools.dart`, and both `bin/` entries are kept as long
as any agent configuration still names them. Check `tool/skills` — server
descriptions there may reference these by name.

### 3.6 `flutter3d_backend` → `flutter3d_app` — size S, pub (both)

`app` is a five-`export` barrel; `backend` is 188 lines of conditional
"which backend to open" import logic plus `openDevice`. Together they're one
"assemble the application" package. `app` already re-exports `backend`, so
the seven apps importing `flutter3d_app` notice nothing. Only
`apps/flutter3d_demo_strategy/pubspec.yaml` imports `flutter3d_backend`
directly — drop that line.

The `the engine names no backend` rule only reads `packages/flutter3d`, so
`app`, which names all four backends, doesn't violate it.

### 3.7 `flutter3d_session` → `flutter3d_screens` — size M, pub (both)

`session` depends on `screens` (for `RenderSettings`), so no consumer's own
dependency closure changes from the merge — including `flutter3d_bridge`,
which needs `RunSession`. Should the name stay `flutter3d_screens`? No: the
merged package is "the application around a game" — surface, run lifecycle,
and screens together. The proposed name is **`flutter3d_session`** (the
wider concept); `screens` moves into `lib/src/screens/`.

`flutter3d_app/lib/flutter3d_app.dart`'s own claim of "five packages, none
of which know about each other" is already wrong: `session` knows about
`screens`. After 3.6 and 3.7 the barrel re-exports three packages —
`session`, `pad_input`, `pointer_lock` — plus its own backend-selection code.

## 4. Contested: `flutter3d_particles` → `flutter3d`

488 lines contributing a pass. Folding it into the engine would make
`flutter3d` depend on `flutter3d_particles_core` (pure Dart, harmless), and
the `flutter3d_particles` package on pub.dev would sit at its last version,
marked discontinued. `particles_core` can't be renamed to `particles` while
that name is taken. The gain is one fewer package; the cost is a
discontinued entry and moving four consumers (`bridge` and three demos).
**Deferred**; revisit when the next major version forces touching consumers
anyway.

## 5. What stays, and why it's worth writing down

- **`flutter3d_stereo`** (914 lines, an Android plugin, v0.1.0) and
  **`flutter3d_net_webrtc`** (174 lines, `flutter_webrtc`) have no
  importers. There's nowhere to merge them into: native code. The question
  isn't "where" but "are they needed"; that's the owner's call, this plan
  leaves them alone.
- **`flutter3d_shaders`** (66 lines + GLSL) — three consumers: `impeller`,
  `cpu`, `conformance`. It doesn't go into `hardware`, because "hardware
  names no graphics API," and GLSL is an API. Stays.
- **`flutter3d_build`** — `tool/init` (pure Dart) imports it for
  build-time conversion; it can't live in `flutter3d`.
- **The four MCP packages** become three after 3.5: `editor_mcp` (Dart,
  `sim`), `model_mcp` (Dart, modeler), `sim_mcp` (Flutter, game + frame).
  No further merging: their closures differ, and `editor_mcp`'s consumer
  would inherit the modeler.

## 6. What to update on every merge

Listed because half of this is caught by a scan and half isn't.

1. Root `pubspec.yaml`: drop the package from `workspace:`.
2. Consumers' `pubspec.yaml`: swap the dependency, `flutter pub get`.
3. Imports `package:<old>/` → `package:<new>/` (`rg -l` across `packages/`,
   `apps/`, `tool/`).
4. `ARCHITECTURE.md`: the §3.2 table, the **The order, used on the day**
   list (the `the publishing order names every package` rule fails if a
   package is in the tree but not the list — and vice versa), the "Thirty-
   five packages" count in §3 (the tree already holds 45 today, so the
   document is already wrong; after the plan, 39).
5. README.md: the "holds thirty-five" line (line 14).
6. `tool/structure/repository.dart`: `flatDartPackages` (3.3),
   `genrePackages` untouched.
7. The test count in README, ARCHITECTURE.md, and the site — `tool/
   structure.dart` counts "says N tests"; merging tests doesn't change the
   number, a new test for the "Render" button (3.4) does.
8. The receiving package's CHANGELOG.md: a bold thesis, "accepted `X`,
   because…"; the departing package's CHANGELOG.md: a final entry, "merged
   into `Y`."
9. For pub packages (3.1, 3.6, 3.7): the receiving package bumps to
   `0.7.0`; the departing one gets a final `flutter pub publish` of its last
   version, then marked `discontinued` via pub.dev's admin UI, with
   `replaced_by` set.
10. `doc/plan-status.json` — if a merged package is named in an item's own
    status text (`pro-rn-02`, `fmt-29d`, `ai-00`, `par-02`), update the
    reason.
11. `tool/skills` — MCP server descriptions that name packages (3.5).
12. CI `.github/workflows/ci.yml` — packages named in explicit steps:
    `flutter3d_mesh` (bench), `flutter3d_impeller` (bundle). None of the
    merging packages are named there; check after 3.5.

## 7. Order and estimate

| Step | Merge | size | pub | Blocks |
|---|---|---|---|---|
| 1 | 3.3 `fbx` → `formats` | S | no | — |
| 2 | 3.2 `rig` → `model_core` | S | no | — |
| 3 | 3.4 `render_job`: a "Render" button in the modeler | S | no | — |
| 4 | 3.5 `render_mcp` → `sim_mcp` | M | no | — |
| 5 | 3.1 `cloth` → `physics` | S | yes | bump physics |
| 6 | 3.6 `backend` → `app` | S | yes | bump app |
| 7 | 3.7 `screens` → `session` | M | yes | bump session, bridge |

Steps 1–4 are a day or two with no publishing. Steps 5–7 go out with the
0.7.0 release, since three discontinued packages are easier to explain in
one release than one at a time across three.

## 8. The full table

| Package | Lines | pub | Held up by | Verdict |
|---|---|---|---|---|
| `flutter3d` | 23,894 | yes | the core | stays |
| `flutter3d_hardware` | 4,422 | yes | the HAL, §1.5 "engine names no backend" | stays |
| `flutter3d_impeller` | 2,753 | yes | §1.2 `flutter_gpu`, a hook, a bundle | stays |
| `flutter3d_webgl` | 15,131 | yes | §1.3 `web`, conditional import | stays |
| `flutter3d_webgpu` | 20,293 | yes | a backend, WGSL | stays |
| `flutter3d_cpu` | 6,443 | yes | the software backend, 19 dependents | stays |
| `flutter3d_backend` | 188 | yes | history | → `app` (3.6) |
| `flutter3d_app` | 35 | yes | a barrel | absorbs `backend` |
| `flutter3d_session` | 1,737 | yes | history | absorbs `screens` (3.7) |
| `flutter3d_screens` | 2,664 | yes | §1.3 `flutter_bloc`, but `session` already depends on it | → `session` (3.7) |
| `flutter3d_conformance` | 4,598 | yes | §1.3 `flutter_test` | stays |
| `flutter3d_testing` | 328 | yes | §1.3 `flutter_test` | stays |
| `flutter3d_shaders` | 66 + GLSL | yes | §1.4, three consumers | stays |
| `flutter3d_samples` | 33 + 4.7 MB | yes | §1.4 | stays |
| `flutter3d_particles` | 488 | yes | the Flutter half | contested (§4), deferred |
| `flutter3d_particles_core` | 1,826 | no | §1.1, needed by `model_core` | stays |
| `flutter3d_physics` | 5,099 | yes | §1.1, 7 dependents | absorbs `cloth` (3.1) |
| `flutter3d_cloth` | 579 | no | history | → `physics` (3.1) |
| `flutter3d_rig` | 1,722 | no | history | → `model_core` (3.2) |
| `flutter3d_fbx` | 73 | no | "for later" | → `formats` (3.3) |
| `flutter3d_lab` | 249 | no | §2, the `edu-04` vertical | stays |
| `flutter3d_render_job` | 535 | no | the Flutter half above `model_core`; no consumer yet | stays, gets wired up (3.4) |
| `flutter3d_stereo` | 914 | no | §1.2 an Android plugin; no consumers | stays, question in §5 |
| `flutter3d_sim` | 15,937 | yes | §1.1 | stays |
| `flutter3d_game` | 1,893 | yes | the Flutter half of the game, 15 dependents | stays |
| `flutter3d_game_shooter` | 4,968 | yes | §1.5 | stays |
| `flutter3d_game_platformer` | 4,415 | yes | §1.5 | stays |
| `flutter3d_game_racing` | 4,805 | yes | §1.5 | stays |
| `flutter3d_game_strategy` | 4,133 | no | §1.5 | stays |
| `flutter3d_bridge` | 2,377 | yes | the only package on both sides | stays |
| `flutter3d_audio` | 1,469 | yes | §1.2 `flutter_soloud` | stays |
| `flutter3d_net` | 608 | no | §1.1 | stays |
| `flutter3d_net_webrtc` | 174 | no | §1.2 `flutter_webrtc`; no consumers | stays, question in §5 |
| `flutter3d_editor_core` | 2,796 | yes | §1.1, `tool/init` | stays |
| `flutter3d_editor_mcp` | 720 | yes | §1.3 `dart_mcp` | stays |
| `flutter3d_model_core` | 21,265 | no | §1.1 | absorbs `rig` |
| `flutter3d_model_mcp` | 4,277 | no | §1.3 `dart_mcp`; the modeler loads it in-process | stays |
| `flutter3d_mesh` | 15,875 | no | `cpu` and the bench use it without `model_core` | stays |
| `flutter3d_geometry` | 3,141 | no | `mesh` uses it without decoders | stays |
| `flutter3d_formats` | 14,046 | no | §1.1, `tool/convert_asset` | absorbs `fbx` |
| `flutter3d_build` | 1,026 | no | §1.1, `tool/init` | stays |
| `flutter3d_sim_mcp` | 927 | no | §1.3 `dart_mcp` | absorbs `render_mcp` (3.5) |
| `flutter3d_render_mcp` | 589 | no | the same closure as `sim_mcp` | → `sim_mcp` (3.5) |
| `pad_input` | 1,407 | yes | §1.2, a standalone name | stays |
| `pointer_lock` | 499 | yes | §1.2 macOS code | stays |
