---
description: A factual comparison with Flutter Scene, the other 3D engine on Flutter GPU — what each one actually ships, who built it, and where they differ.
---

# flutter3d and Flutter Scene

[Flutter Scene](https://fscene.dev) is the other engine built on Flutter GPU. It is maintained by the author of Flutter GPU itself — a former core Flutter engine team member who spent four years on Flutter, most of it building Impeller — which gives it a relationship with the underlying API that no third-party package can have: Scene's own render tests catch Flutter GPU regressions before they ship, because the person writing the engine and the person writing the graphics API are the same person. flutter3d reads `flutter_gpu` the way any other package does, through the public surface.

The two are not aimed at the same claim. Scene is trying to be a complete, production-grade 3D engine and toolkit for anyone building on Flutter. flutter3d exists to answer a narrower question: whether a HAL, a scene graph and a game layer of this shape can be built by someone with no inside access to Impeller, proven against three complete games of different genres that share no engine-level code changes between them. The numbers below were pulled from pub.dev and the GitHub API on 2026-09-15, not written from memory.

## Quick facts

| | flutter3d | Flutter Scene |
|---|---|---|
| First commit | 2026-08-08 | 2024-02-01 |
| GitHub stars | 24 | 779 |
| pub.dev likes | 6 | 332 |
| pub.dev downloads | 510 | 10,100 |
| Core package version | 0.6.0 | 0.23.0 |
| Maintainer | An independent developer, unaffiliated with the Flutter team | The author of Flutter GPU, formerly on the core Flutter engine team |
| Licence | MIT | MIT |
| Web backend | WebGL2, and WebGPU behind a flag | Built-in WebGL2 |
| Physics | Pure Dart, in-tree (`flutter3d_physics`) | Native: [`flutter_scene_rapier`](https://pub.dev/packages/flutter_scene_rapier) (prebuilt binaries + wasm) or [`flutter_scene_box3d`](https://pub.dev/packages/flutter_scene_box3d) |
| Audio | Pure Dart, pluggable backend, in-tree | Native: [`flutter_scene_soloud`](https://pub.dev/packages/flutter_scene_soloud) or [`flutter_scene_fmod`](https://pub.dev/packages/flutter_scene_fmod) (commercial middleware) |
| CPU / GPU-less test backend | Yes — `flutter3d_cpu`, a software rasteriser used in CI | No — CI renders through Impeller on macOS runners |
| Multiplayer | No | [`flutter_scene_net`](https://pub.dev/packages/flutter_scene_net), over `dashwire` |
| Editor with an MCP server | Yes — `flutter3d_editor_mcp`, published to pub.dev at 0.6.0 alongside the rest of the set | Yes — the Flutter Scene Editor stack, shipped as a desktop app, not on pub.dev, and explicitly "in active development" |

## What Scene has that flutter3d doesn't

Reading its README against flutter3d's own feature table:

- **Global illumination.** Scene bakes or progressively computes a world-space irradiance probe field with visibility, plus screen-space indirect light and ground-truth ambient occlusion. flutter3d has screen-space reflections, cascaded shadows and ambient occlusion, but light does not bounce.
- **Gaussian splatting.** Scene renders `.ply` and `.splat` captures as scene nodes. flutter3d has no splatting support.
- **Decals.** Scene projects boxes onto existing geometry. flutter3d's renderer mentions decals only in doc comments describing where a raycast hit could place one.
- **A deeper post-processing stack.** Physical camera exposure with automatic eye adaptation, depth of field with bokeh, film-look colour grading from `.cube` LUTs, chromatic aberration, radial distortion, and temporal anti-aliasing alongside FXAA and SMAA. flutter3d has bloom, tone mapping, fog and screen-space reflections, and no TAA.
- **Native physics and audio through mature third-party engines** — Rapier for physics, SoLoud and FMOD for audio — rather than an implementation scoped to this project alone. flutter3d's physics package covers overlap, sweeps, rays and a character controller: no continuous collision, no constraint solver, no joints.
- **A declarative widget API** (`SceneNode`, `SceneMesh`, `SceneModel`) alongside the imperative scene graph, and screen-reader accessibility through Flutter semantics. flutter3d's scene graph is imperative only.
- **Two shipped games in the wild** — [Dashsurfers](https://github.com/bdero/dashsurfers) and [Dashmap](https://github.com/bdero/dashmap) — plus 43 runnable feature examples in the example app.
- **Two and a half years of runtime** against flutter3d's five weeks, and an order of magnitude more stars, likes and downloads by every public number above.

## What flutter3d has that Scene doesn't

- **No native dependencies anywhere.** Physics, cloth, rig retargeting and audio are plain Dart — no `dart:ffi`, no prebuilt binaries, no wasm module to vendor. `flutter pub get` is the entire dependency story on every platform, including the ones `flutter_scene_rapier` ships native binaries for.
- **A CPU software backend.** `flutter3d_cpu` rasterises entirely in Dart, gives the renderer a second, independent implementation to check the GPU backends against, and runs the golden-image suite in CI with no GPU at all. Scene's CI renders through Impeller on Codemagic's macOS hardware and checks results through Argos.
- **A second web backend.** flutter3d ships both WebGL2 and an experimental WebGPU backend behind `--dart-define=FLUTTER3D_WEBGPU=true`. Scene ships WebGL2 only on the web.
- **Three complete games of different genres, one engine, no genre-specific code shared between them** — a shooter, a platformer and a racing game, each built without editing the engine packages the other two depend on, with the boundary enforced by structural scans (`tool/structure.dart`) rather than by convention. A fourth genre, strategy, exists in the workspace and is not yet published.

<div class="why">
<p><strong>These are different bets on where a young engine spends its first year, not a scoreboard.</strong> Scene put that time into rendering depth, native-grade physics and audio, and a widget-level API, with two and a half years and a maintainer who tracks Impeller from the inside. flutter3d put it into proving the architecture across three shipped games and keeping the whole dependency stack — physics, cloth, rig, audio — in pure Dart, plus a software rendering backend neither project's CI ran on before this one built it. Both are pre-1.0, both MIT, both sit on the same `flutter_gpu` foundation.</p>
</div>

## Picking one

If a project needs global illumination, Gaussian splatting, a mature physics or audio backend, a declarative widget API, or accessibility support today, Scene already has it. If a project's constraints run the other way — no native binaries anywhere in the build, rendering tests that have to run without a GPU, or an interest in how the genre-package split holds up across three real games — that is what flutter3d is actually built to show.
