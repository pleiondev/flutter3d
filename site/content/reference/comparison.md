---
description: A factual comparison with Flutter Scene, the other 3D engine on Flutter GPU, covering what each one ships, who built it, and where they differ.
---

# flutter3d and Flutter Scene

[Flutter Scene](https://fscene.dev) is the other engine built on Flutter GPU. It is maintained by the author of Flutter GPU itself, a former core Flutter engine team member who spent four years on Flutter, most of it building Impeller. That gives it a relationship with the underlying API that no third-party package can have: Scene's render tests are where Flutter GPU regressions get caught, because the author of Flutter GPU also writes the engine. flutter3d uses `flutter_gpu` the way any other package does, through the public surface.

The two projects are not after the same thing. Scene is a complete 3D game engine and toolkit for anyone building on Flutter, pre-1.0 and moving quickly. flutter3d answers a narrower question: whether a HAL, a scene graph and a game layer of this shape can be built by someone with no inside access to Impeller, tested against three complete games of different genres that needed no engine-level code changes between them. The flutter3d half of this page was read against the source tree of 0.8.1 on 2026-09-27. The Scene half describes its README, which was last changed on 2026-09-03, and its repository at the same date was searched for every capability the README does not name.

## Quick facts

| | flutter3d | Flutter Scene |
|---|---|---|
| First commit | 2026-08-08 | 2024-02-01 |
| Core package version | 0.8.2 | 0.23.0 |
| Maintainer | An independent developer, unaffiliated with the Flutter team | The author of Flutter GPU, formerly on the core Flutter engine team |
| Licence | MIT | MIT |
| Web backend | WebGL2, and WebGPU behind a flag | Built-in WebGL2 |
| Physics | Pure Dart, in-tree (`flutter3d_physics`) | Native: [`flutter_scene_rapier`](https://pub.dev/packages/flutter_scene_rapier) (prebuilt binaries + wasm) or [`flutter_scene_box3d`](https://pub.dev/packages/flutter_scene_box3d) |
| Audio | [`flutter_soloud`](https://pub.dev/packages/flutter_soloud), an FFI binding to the SoLoud engine, behind a pluggable backend interface | [`flutter_scene_soloud`](https://pub.dev/packages/flutter_scene_soloud), the same SoLoud engine, or [`flutter_scene_fmod`](https://pub.dev/packages/flutter_scene_fmod) (commercial middleware) |
| CPU / GPU-less test backend | Yes: `flutter3d_cpu`, a software rasteriser used in CI | No backend of its own; CI renders its smoke scenes through Impeller on Mesa's software rasterisers (Linux), SwiftShader (Android emulator), headless Chrome and Windows, and Metal on Codemagic, compared in Argos |
| Multiplayer | Rollback netcode for two peers (`flutter3d_net`, WebSocket or WebRTC transport), on pub.dev | [`flutter_scene_net`](https://pub.dev/packages/flutter_scene_net), over `dashwire`: replicated state, client-side prediction, and physics rollback for the entity a client owns |
| Editor with an MCP server | Yes: `flutter3d_editor_mcp`, published to pub.dev with the rest of the set | Yes: the Flutter Scene Editor stack, shipped as a desktop app, not on pub.dev, and explicitly "in active development" |

## Feature by feature

A green dot is a capability the engine has; a red one is a capability it does not. For flutter3d that is read from its source. For Flutter Scene it is read from its README and then checked against its repository: a red dot there means neither names it in the engine's packages. Where Scene has something close in another form, the row is worded to the difference, and here is the form: an XPBD cloth solver in its example app rather than in the engine, physics rollback for the one entity a client owns against a server rather than every player's input between peers, a pure-Dart physics backend for queries and triggers with no dynamics, and occlusion culling through planes an application supplies rather than a depth pyramid. Each row is one capability, so where both engines have something in different depths (physics, global illumination, the editor) the sections below say how they differ.

<table class="compare">
<thead><tr><th>Capability</th><th>flutter3d</th><th>Flutter Scene</th></tr></thead>
<tbody>
<tr class="group"><th colspan="3">Rendering</th></tr>
<tr><td>Physically based materials with clearcoat, sheen, anisotropy and transmission</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Rectangle area lights</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Clustered lights, so a scene can hold many</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Cascaded sun shadows with soft penumbrae and contact shadows</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Exponential variance shadow maps (EVSM) for the sun</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Irradiance probe field with a visibility test per probe</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Horizon-based ambient occlusion and screen-space bounced light</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Screen-space reflections, depth of field, bloom, automatic exposure</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Volumetric fog</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Order-independent transparency</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Motion blur</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Local exposure, and HDR output (WebGPU only)</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Temporal anti-aliasing and FXAA</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>SMAA</td><td class="dot"><span class="no">no</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Lens flares and radial lens distortion</td><td class="dot"><span class="no">no</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Projected decals</td><td class="dot"><span class="no">no</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Gaussian splats</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Octahedral impostors for distant models</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Automatic occlusion culling (Hi-Z)</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr class="group"><th colspan="3">Assets and animation</th></tr>
<tr><td>Skinning, morph targets and blended animation</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>glTF material variants</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>glTF animation pointers (a clip moves a material or a light)</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Retargeting a clip onto another skeleton</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Models converted at build time by a build hook</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Hot reload for models and textures</td><td class="dot"><span class="no">no</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr class="group"><th colspan="3">Backends</th></tr>
<tr><td>Impeller through Flutter GPU</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>WebGL2 in the browser</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>WebGPU in the browser</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>A software rasteriser in Dart, so rendering tests run without a GPU</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr class="group"><th colspan="3">Games</th></tr>
<tr><td>Rigid-body dynamics in pure Dart, with no native binaries</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Native physics through Rapier or box3d</td><td class="dot"><span class="no">no</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Rigid bodies that rotate</td><td class="dot"><span class="no">no</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Cloth in the engine's packages</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Particles</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Audio through SoLoud</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Multiplayer</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Peer-to-peer rollback of every player's input</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Genre packages: shooter, platformer, racing, strategy</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>A bridge to the Flame 2D engine</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr class="group"><th colspan="3">Tools and app integration</th></tr>
<tr><td>A scene editor with an MCP server for coding agents</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>A declarative widget API for the scene</td><td class="dot"><span class="no">no</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>The scene described to a screen reader</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
</tbody>
</table>

## What Scene has that flutter3d doesn't

Reading its README against flutter3d's own feature table:

- **Decals.** Scene projects boxes onto existing geometry. flutter3d has no decal pass; its renderer mentions decals only in doc comments describing where a raycast hit could place one.
- **SMAA, lens flares and radial lens distortion.** Scene has SMAA beside FXAA and TAA, flares on its bloom and a radial distortion pass, and it grades from `.cube` LUTs. flutter3d has FXAA with contrast-adaptive sharpening and, since 0.8, temporal anti-aliasing; it has no SMAA, no flares and no distortion pass, and it grades from a strip LUT.
- **Native physics through a mature third-party engine.** Rapier or box3d, pluggable, where flutter3d has an implementation scoped to this project alone. flutter3d's physics package covers overlap, sweeps, rays, a character controller, an XPBD cloth solver and rigid bodies that settle their contacts with sequential impulses; its bodies do not rotate, and it has no joints and no continuous collision. Audio is not really a difference between the two, since both wrap the same SoLoud engine; Scene additionally offers FMOD, commercial middleware, as a second backend.
- **A declarative widget API** (`SceneNode`, `SceneMesh`, `SceneModel`) alongside the imperative scene graph. flutter3d's scene graph is imperative only. Both describe the scene to a screen reader through Flutter semantics.
- **Hot reload for assets.** Scene reloads models, shaders, textures, environments and scene documents while the app runs. flutter3d reloads a shader bundle in place (`LoadedShaderLibrary.refresh`, which the editor uses to watch one), but picks up a changed model or texture only on the next build. Both convert models at build time through a build hook (`flutter3d_build` here).
- **Two projects built on it**, the [Dashsurfers](https://github.com/bdero/dashsurfers) endless runner and the [Dashmap](https://github.com/bdero/dashmap) live world map, plus 43 runnable feature examples in the example app.
- **More than two and a half years in its own repository**, and an earlier life inside the Flutter engine, against flutter3d's seven weeks.

Global illumination was on this list until 0.8. Both engines now read a world-space irradiance probe field with a visibility test per probe and add horizon-based ambient occlusion and screen-space indirect light. Scene bakes its field offline or progressively; flutter3d traces it with the CPU raycaster and can update it on the GPU. Temporal anti-aliasing moved off the list the same way.

## What flutter3d has that Scene doesn't

- **No native dependencies outside audio.** Physics, cloth and rig retargeting are plain Dart, with no `dart:ffi`, prebuilt binaries or wasm module to vendor. Audio is the one exception: `flutter3d_audio` wraps `flutter_soloud`, an FFI binding to the same SoLoud engine Scene's `flutter_scene_soloud` wraps. Physics is where the gap is real: `flutter pub get` is the entire dependency story for it on every platform, where `flutter_scene_rapier` ships prebuilt native binaries.
- **A CPU software backend.** `flutter3d_cpu` rasterises entirely in Dart, gives the renderer a second, independent implementation to check the GPU backends against, and runs the golden-image suite in CI with no GPU at all. Scene has no software backend of its own; its CI renders through Impeller on Mesa and SwiftShader software rasterisers, in headless Chrome, and on Codemagic's Apple hardware, and checks the frames in Argos.
- **A second web backend.** flutter3d ships both WebGL2 and an experimental WebGPU backend behind `--dart-define=FLUTTER3D_WEBGPU=true`. Scene ships WebGL2 only on the web.
- **Three complete games of different genres on one engine, with no genre-specific code shared between them.** A shooter, a platformer and a racing game, each built without editing the engine packages the other two depend on, with the boundary enforced by structural scans (`tool/structure.dart`) and not only by convention. A fourth genre, strategy, is in the workspace too, and its genre package is on pub.dev.
- **A bidirectional bridge to Flame, the established Flutter 2D game engine.** `flame_flutter3d` composites a Flame layer and a flutter3d layer in one widget, each drawing itself, with transform, ECS (through `flutter3d_sim`'s own actor system), physics, input and camera reconciled between the two, so neither engine drives the other's renderer. A fifth demo, [Meteor Yard](/arcade/demo/), uses all five end to end and plays in a browser. Scene's README does not describe an equivalent.
- **Rendering features Scene's README does not list.** Order-independent transparency, motion blur, volumetric fog, local exposure, and HDR output on the WebGPU backend; octahedral impostors and occlusion culling; and adaptive quality, which picks each frame the best-looking row of a quality table that fits a frame budget (off by default, and its costs are measured on the software rasteriser until each device class is measured on its own GPU). Scene has fog, god rays and resolution scaling, which are near relatives of some of these, and it may have more than its README says.

<div class="why">
<p><strong>These are different bets on where a young engine spends its first year, not a scoreboard.</strong> Scene put that time into rendering depth, native-grade physics and audio, and a widget-level API, with more than two and a half years behind it and a maintainer who wrote Flutter GPU. flutter3d put it into proving the architecture across three shipped games and keeping physics, cloth and rig retargeting in pure Dart, plus a software rendering backend of its own, written in Dart, so rendering tests need no GPU and no graphics driver at all. Both are pre-1.0, both MIT, both sit on the same `flutter_gpu` foundation.</p>
</div>

## Picking one

If a project needs decals, a mature physics backend with joints and rotating bodies, asset hot reload, or a declarative widget API today, Scene already has it. If a project's constraints run the other way (no native physics binaries in the build, rendering tests that have to run with no GPU or graphics driver, inside `flutter test`, or an interest in how the genre-package split holds up across three real games), flutter3d is built to show exactly that.
