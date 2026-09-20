---
description: A factual comparison with Flutter Scene, the other 3D engine on Flutter GPU — what each one actually ships, who built it, and where they differ.
---

# flutter3d and Flutter Scene

[Flutter Scene](https://fscene.dev) is the other engine built on Flutter GPU. It is maintained by the author of Flutter GPU itself — a former core Flutter engine team member who spent four years on Flutter, most of it building Impeller — which gives it a relationship with the underlying API that no third-party package can have: Scene's own render tests catch Flutter GPU regressions before they ship, because the person writing the engine and the person writing the graphics API are the same person. flutter3d reads `flutter_gpu` the way any other package does, through the public surface.

The two are not aimed at the same claim. Scene is trying to be a complete, production-grade 3D engine and toolkit for anyone building on Flutter. flutter3d exists to answer a narrower question: whether a HAL, a scene graph and a game layer of this shape can be built by someone with no inside access to Impeller, proven against three complete games of different genres that share no engine-level code changes between them. The quick-facts numbers below were pulled from pub.dev and the GitHub API on 2026-09-20, not written from memory. The flutter3d half of the feature lists was read against the source tree again on 2026-09-20; the Scene half still describes its README as of 2026-09-15, except where noted.

## Quick facts

| | flutter3d | Flutter Scene |
|---|---|---|
| First commit | 2026-08-08 | 2024-02-01 |
| GitHub stars | 27 | 784 |
| pub.dev likes | 8 | 338 |
| pub.dev downloads | 520 | 11.8k |
| Core package version | 0.6.0 | 0.23.0 |
| Maintainer | An independent developer, unaffiliated with the Flutter team | The author of Flutter GPU, formerly on the core Flutter engine team |
| Licence | MIT | MIT |
| Web backend | WebGL2, and WebGPU behind a flag | Built-in WebGL2 |
| Physics | Pure Dart, in-tree (`flutter3d_physics`) | Native: [`flutter_scene_rapier`](https://pub.dev/packages/flutter_scene_rapier) (prebuilt binaries + wasm) or [`flutter_scene_box3d`](https://pub.dev/packages/flutter_scene_box3d) |
| Audio | [`flutter_soloud`](https://pub.dev/packages/flutter_soloud) — FFI binding to the SoLoud engine — behind a pluggable backend interface | [`flutter_scene_soloud`](https://pub.dev/packages/flutter_scene_soloud), the same SoLoud engine, or [`flutter_scene_fmod`](https://pub.dev/packages/flutter_scene_fmod) (commercial middleware) |
| CPU / GPU-less test backend | Yes — `flutter3d_cpu`, a software rasteriser used in CI | No — CI renders through Impeller on macOS runners |
| Multiplayer | Rollback netcode for two peers (`flutter3d_net`, WebSocket or WebRTC transport), in the tree and not on pub.dev yet | [`flutter_scene_net`](https://pub.dev/packages/flutter_scene_net), over `dashwire` |
| Editor with an MCP server | Yes — `flutter3d_editor_mcp`, published to pub.dev at 0.6.0 alongside the rest of the set | Yes — the Flutter Scene Editor stack, shipped as a desktop app, not on pub.dev, and explicitly "in active development" |

## What Scene has that flutter3d doesn't

Reading its README against flutter3d's own feature table:

- **More global illumination.** Scene bakes or progressively computes a world-space irradiance probe field with visibility, plus screen-space indirect light and ground-truth ambient occlusion. flutter3d has a probe field of its own, traced with the CPU raycaster and good for one bounce, and baked lightmaps for brush levels only. It has no screen-space indirect light, and its ambient occlusion is plain SSAO.
- **Decals.** Scene projects boxes onto existing geometry. flutter3d's renderer mentions decals only in doc comments describing where a raycast hit could place one.
- **Temporal anti-aliasing and radial lens distortion.** Scene has TAA and SMAA alongside FXAA, plus a radial distortion pass. flutter3d has neither — its anti-aliasing is FXAA with contrast-adaptive sharpening built into that same pass, and it has no distortion pass. Its own post pipeline otherwise runs bloom, screen-space ambient occlusion, contact shadows, screen-space reflections, depth of field, light shafts, chromatic aberration, film grain, a vignette, automatic exposure, colour grading from a strip LUT, and a choice of three tone-mapping curves (Khronos PBR Neutral, ACES, AgX) — more of this list than the previous version of this page credited it with. Turning on any effect that reads the surface buffer still switches MSAA off for the frame.
- **Native physics through a mature third-party engine.** Rapier or box3d, pluggable, rather than an implementation scoped to this project alone. flutter3d's physics package covers overlap, sweeps, rays and a character controller: no continuous collision, no constraint solver, no joints. Audio is not really a difference between the two — both wrap the same SoLoud engine; Scene additionally offers FMOD, commercial middleware, as a second backend.
- **A declarative widget API** (`SceneNode`, `SceneMesh`, `SceneModel`) alongside the imperative scene graph. flutter3d's scene graph is imperative only. Both describe the scene to a screen reader through Flutter semantics.
- **Two shipped games in the wild** — [Dashsurfers](https://github.com/bdero/dashsurfers) and [Dashmap](https://github.com/bdero/dashmap) — plus 43 runnable feature examples in the example app.
- **Two and a half years of runtime** against flutter3d's five weeks, and an order of magnitude more stars, likes and downloads by every public number above.

## What flutter3d has that Scene doesn't

- **No native dependencies outside audio.** Physics, cloth and rig retargeting are plain Dart — no `dart:ffi`, no prebuilt binaries, no wasm module to vendor. Audio is the one exception: `flutter3d_audio` wraps `flutter_soloud`, an FFI binding to the same SoLoud engine Scene's own `flutter_scene_soloud` wraps. Physics is where the gap is real: `flutter pub get` is the entire dependency story for it on every platform, where `flutter_scene_rapier` ships prebuilt native binaries.
- **A CPU software backend.** `flutter3d_cpu` rasterises entirely in Dart, gives the renderer a second, independent implementation to check the GPU backends against, and runs the golden-image suite in CI with no GPU at all. Scene's CI renders through Impeller on Codemagic's macOS hardware and checks results through Argos.
- **A second web backend.** flutter3d ships both WebGL2 and an experimental WebGPU backend behind `--dart-define=FLUTTER3D_WEBGPU=true`. Scene ships WebGL2 only on the web.
- **Three complete games of different genres, one engine, no genre-specific code shared between them** — a shooter, a platformer and a racing game, each built without editing the engine packages the other two depend on, with the boundary enforced by structural scans (`tool/structure.dart`) rather than by convention. A fourth genre, strategy, exists in the workspace and is not yet published.
- **A bidirectional bridge to Flame, the established Flutter 2D game engine.** `flutter3d_flame` composites a Flame layer and a flutter3d layer in one widget, each drawing itself, with transform, ECS (through `flutter3d_sim`'s own actor system), physics, input and camera reconciled between the two rather than one engine driving the other's renderer — proven end to end in a fifth demo, Meteor Yard, that uses all five. Scene's README (checked 2026-09-20) does not describe an equivalent.

<div class="why">
<p><strong>These are different bets on where a young engine spends its first year, not a scoreboard.</strong> Scene put that time into rendering depth, native-grade physics and audio, and a widget-level API, with two and a half years and a maintainer who tracks Impeller from the inside. flutter3d put it into proving the architecture across three shipped games and keeping physics, cloth and rig retargeting in pure Dart, plus a software rendering backend neither project's CI ran on before this one built it. Both are pre-1.0, both MIT, both sit on the same `flutter_gpu` foundation.</p>
</div>

## Picking one

If a project needs decals, temporal anti-aliasing, a mature physics backend with joints, or a declarative widget API today, Scene already has it. If a project's constraints run the other way — no native physics binaries in the build, rendering tests that have to run without a GPU, or an interest in how the genre-package split holds up across three real games — that is what flutter3d is actually built to show.
