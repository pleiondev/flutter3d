---
description: A factual comparison with Flutter Scene, the other 3D engine on Flutter GPU, covering what each one ships, who built it, and where they differ.
---

# flutter3d and Flutter Scene

[Flutter Scene](https://fscene.dev) is the other engine built on Flutter GPU. It is maintained by the author of Flutter GPU itself, a former core Flutter engine team member who spent four years on Flutter, most of it building Impeller. That gives it a relationship with the underlying API that no third-party package can have: Scene's render tests catch Flutter GPU regressions before they ship, because the person writing the engine and the person writing the graphics API are the same person. flutter3d uses `flutter_gpu` the way any other package does, through the public surface.

The two projects are not after the same thing. Scene is trying to be a complete, production-grade 3D engine and toolkit for anyone building on Flutter. flutter3d answers a narrower question: whether a HAL, a scene graph and a game layer of this shape can be built by someone with no inside access to Impeller, tested against three complete games of different genres that needed no engine-level code changes between them. The stars, likes and downloads below were pulled from pub.dev and the GitHub API on 2026-09-27, after flutter3d 0.8.1 went out. The flutter3d half of the feature lists was read against the source tree of 0.8.1 the same day. The Scene half describes its README, which was last changed on 2026-09-03 and was read again on 2026-09-27.

## Quick facts

| | flutter3d | Flutter Scene |
|---|---|---|
| First commit | 2026-08-08 | 2024-02-01 |
| GitHub stars | 27 | 796 |
| pub.dev likes | 8 | 340 |
| pub.dev downloads, last 30 days | 830 | 13.8k |
| Core package version | 0.8.1 | 0.23.0 |
| Maintainer | An independent developer, unaffiliated with the Flutter team | The author of Flutter GPU, formerly on the core Flutter engine team |
| Licence | MIT | MIT |
| Web backend | WebGL2, and WebGPU behind a flag | Built-in WebGL2 |
| Physics | Pure Dart, in-tree (`flutter3d_physics`) | Native: [`flutter_scene_rapier`](https://pub.dev/packages/flutter_scene_rapier) (prebuilt binaries + wasm) or [`flutter_scene_box3d`](https://pub.dev/packages/flutter_scene_box3d) |
| Audio | [`flutter_soloud`](https://pub.dev/packages/flutter_soloud), an FFI binding to the SoLoud engine, behind a pluggable backend interface | [`flutter_scene_soloud`](https://pub.dev/packages/flutter_scene_soloud), the same SoLoud engine, or [`flutter_scene_fmod`](https://pub.dev/packages/flutter_scene_fmod) (commercial middleware) |
| CPU / GPU-less test backend | Yes: `flutter3d_cpu`, a software rasteriser used in CI | No: CI renders through Impeller on macOS runners |
| Multiplayer | Rollback netcode for two peers (`flutter3d_net`, WebSocket or WebRTC transport), on pub.dev | [`flutter_scene_net`](https://pub.dev/packages/flutter_scene_net), over `dashwire` |
| Editor with an MCP server | Yes: `flutter3d_editor_mcp`, published to pub.dev with the rest of the set | Yes: the Flutter Scene Editor stack, shipped as a desktop app, not on pub.dev, and explicitly "in active development" |

## What Scene has that flutter3d doesn't

Reading its README against flutter3d's own feature table:

- **Decals.** Scene projects boxes onto existing geometry. flutter3d has no decal pass; its renderer mentions decals only in doc comments describing where a raycast hit could place one.
- **SMAA, lens flares and radial lens distortion.** Scene has SMAA beside FXAA and TAA, flares on its bloom and a radial distortion pass, and it grades from `.cube` LUTs. flutter3d has FXAA with contrast-adaptive sharpening and, since 0.8, temporal anti-aliasing; it has no SMAA, no flares and no distortion pass, and it grades from a strip LUT.
- **Native physics through a mature third-party engine.** Rapier or box3d, pluggable, where flutter3d has an implementation scoped to this project alone. flutter3d's physics package covers overlap, sweeps, rays, a character controller, an XPBD cloth solver and rigid bodies that settle their contacts with sequential impulses; its bodies do not rotate, and it has no joints and no continuous collision. Audio is not really a difference between the two, since both wrap the same SoLoud engine; Scene additionally offers FMOD, commercial middleware, as a second backend.
- **A declarative widget API** (`SceneNode`, `SceneMesh`, `SceneModel`) alongside the imperative scene graph. flutter3d's scene graph is imperative only. Both describe the scene to a screen reader through Flutter semantics.
- **Hot reload for assets.** Scene reloads models, shaders, textures, environments and scene documents while the app runs. Both convert models at build time through a build hook (`flutter3d_build` here), but flutter3d picks up a changed asset only on the next build.
- **Two shipped games in the wild**, [Dashsurfers](https://github.com/bdero/dashsurfers) and [Dashmap](https://github.com/bdero/dashmap), plus 43 runnable feature examples in the example app.
- **Two and a half years of runtime** against flutter3d's seven weeks, and an order of magnitude more stars, likes and downloads by every public number above.

Global illumination was on this list until 0.8. Both engines now read a world-space irradiance probe field with a visibility test per probe and add horizon-based ambient occlusion and screen-space indirect light. Scene bakes its field offline or progressively; flutter3d traces it with the CPU raycaster and can update it on the GPU. Temporal anti-aliasing moved off the list the same way.

## What flutter3d has that Scene doesn't

- **No native dependencies outside audio.** Physics, cloth and rig retargeting are plain Dart, with no `dart:ffi`, prebuilt binaries or wasm module to vendor. Audio is the one exception: `flutter3d_audio` wraps `flutter_soloud`, an FFI binding to the same SoLoud engine Scene's `flutter_scene_soloud` wraps. Physics is where the gap is real: `flutter pub get` is the entire dependency story for it on every platform, where `flutter_scene_rapier` ships prebuilt native binaries.
- **A CPU software backend.** `flutter3d_cpu` rasterises entirely in Dart, gives the renderer a second, independent implementation to check the GPU backends against, and runs the golden-image suite in CI with no GPU at all. Scene's CI renders through Impeller on Codemagic's macOS hardware and checks results through Argos.
- **A second web backend.** flutter3d ships both WebGL2 and an experimental WebGPU backend behind `--dart-define=FLUTTER3D_WEBGPU=true`. Scene ships WebGL2 only on the web.
- **Three complete games of different genres on one engine, with no genre-specific code shared between them.** A shooter, a platformer and a racing game, each built without editing the engine packages the other two depend on, with the boundary enforced by structural scans (`tool/structure.dart`) and not only by convention. A fourth genre, strategy, is in the workspace too, and its genre package is on pub.dev.
- **A bidirectional bridge to Flame, the established Flutter 2D game engine.** `flame_flutter3d` composites a Flame layer and a flutter3d layer in one widget, each drawing itself, with transform, ECS (through `flutter3d_sim`'s own actor system), physics, input and camera reconciled between the two, so neither engine drives the other's renderer. A fifth demo, [Meteor Yard](/arcade/demo/), uses all five end to end and plays in a browser. Scene's README does not describe an equivalent.
- **Rendering features Scene's README does not list.** Order-independent transparency, motion blur, volumetric fog, local exposure and HDR output; octahedral impostors and occlusion culling; and adaptive quality, which picks each frame the best-looking row of a quality table that fits a frame budget (off by default, and its costs are measured on the software rasteriser until each device class is measured on its own GPU). Scene has fog, god rays and resolution scaling, which are near relatives of some of these, and it may have more than its README says.

<div class="why">
<p><strong>These are different bets on where a young engine spends its first year, not a scoreboard.</strong> Scene put that time into rendering depth, native-grade physics and audio, and a widget-level API, with two and a half years behind it and a maintainer who tracks Impeller from the inside. flutter3d put it into proving the architecture across three shipped games and keeping physics, cloth and rig retargeting in pure Dart, plus a software rendering backend, which neither project's CI ran on before this one built it. Both are pre-1.0, both MIT, both sit on the same `flutter_gpu` foundation.</p>
</div>

## Picking one

If a project needs decals, a mature physics backend with joints and rotating bodies, asset hot reload, or a declarative widget API today, Scene already has it. If a project's constraints run the other way (no native physics binaries in the build, rendering tests that have to run without a GPU, or an interest in how the genre-package split holds up across three real games), flutter3d is built to show exactly that.
