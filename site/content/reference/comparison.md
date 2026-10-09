---
description: A factual comparison with Flutter Scene, the other 3D engine on Flutter GPU, covering what each one ships, who built it, and where they differ.
---

# flutter3d and Flutter Scene

[Flutter Scene](https://fscene.dev) is the other engine built on Flutter GPU. It is maintained by the author of Flutter GPU itself, a former core Flutter engine team member who spent four years on Flutter, most of it building Impeller. That gives it a relationship with the underlying API that no third-party package can have: Scene's render tests are where Flutter GPU regressions get caught, because the author of Flutter GPU also writes the engine. flutter3d uses `flutter_gpu` the way any other package does, through the public surface.

The two projects are not after the same thing. Scene is a complete 3D game engine and toolkit for anyone building on Flutter, pre-1.0 and moving quickly. flutter3d started from a narrower question: whether a HAL, a scene graph and a game layer of this shape can be built by someone with no inside access to Impeller, tested against three complete games of different genres that needed no engine-level code changes between them. For 1.0.0 I took Scene's 0.24 as the bar to reach, and most of this page's old "Scene has, flutter3d doesn't" list moved as a result. This version of the page is as of 2026-10-09. The flutter3d half was read against the source tree of the 1.0.0-rc.1 release candidate. The Scene half was read against `flutter_scene` 0.24.1, published on pub.dev on 2026-10-07: its README (last changed on 2026-10-05), its CHANGELOG, and the published package's source, which was searched for every capability the README does not name. Commits on Scene's main branch after 0.24.1 are not counted until they are released.

## Quick facts

| | flutter3d | Flutter Scene |
|---|---|---|
| First commit | 2026-08-08 | 2024-02-01 |
| Core package version | 1.0.0-rc.1 | 0.24.1 (2026-10-07) |
| Maintainer | An independent developer, unaffiliated with the Flutter team | The author of Flutter GPU, formerly on the core Flutter engine team |
| Licence | MIT | MIT |
| Web backend | WebGPU by default, WebGL2 where WebGPU does not start | Built-in WebGL2 |
| Windows and Linux | Windows: games and editor built in CI, nobody has played them there yet. Linux: every test suite runs there, but Impeller does not draw yet, so a game draws through the CPU backend | Both listed as platforms; shipping a release build needs Flutter 3.47.1 |
| Physics | Its own core in C (`flutter3d_physics_native`, through `dart:ffi` natively and WebAssembly in the browser), compiled from source by a build hook, with the pure-Dart `flutter3d_physics` as its reference and fallback | Native: [`flutter_scene_rapier`](https://pub.dev/packages/flutter_scene_rapier) (prebuilt binaries + wasm) or [`flutter_scene_box3d`](https://pub.dev/packages/flutter_scene_box3d) |
| Audio | [`flutter_soloud`](https://pub.dev/packages/flutter_soloud), an FFI binding to the SoLoud engine, behind a pluggable backend interface | [`flutter_scene_soloud`](https://pub.dev/packages/flutter_scene_soloud), the same SoLoud engine, or [`flutter_scene_fmod`](https://pub.dev/packages/flutter_scene_fmod) (commercial middleware) |
| Input | [`pad_input`](https://pub.dev/packages/pad_input) for gamepads, [`pointer_lock`](https://pub.dev/packages/pointer_lock) for mouse look, and rebindable controls with a settings screen in `flutter3d_game` | [`flutter_scene_input`](https://pub.dev/packages/flutter_scene_input) 0.1.0, new with 0.24: rebindable actions for keyboard, mouse, gamepads and pointer lock, with contexts and saved profiles |
| CPU / GPU-less test backend | Yes: `flutter3d_cpu`, a software rasteriser used in CI | No backend of its own; CI renders its smoke scenes through Impeller on Mesa's software rasterisers (Linux), SwiftShader (Android emulator), headless Chrome and Windows, and Metal on Codemagic, compared in Argos |
| Multiplayer | Rollback for two to thirty-two peers, spectators fed from the settled tape, an authoritative server with predicting clients, and a relay that holds parties (`flutter3d_net`, [`flame_multiplayer`](https://pub.dev/packages/flame_multiplayer); WebSocket, WebRTC or `dashwire` underneath) | [`flutter_scene_net`](https://pub.dev/packages/flutter_scene_net), over `dashwire`: replicated state, client-side prediction, and physics rollback for the entity a client owns |
| Editor with an MCP server | Yes: `flutter3d_mcp` on pub.dev (`flutter3d_editor_mcp` before 1.0); the editor app builds for the desktop and, new in 1.0, for the browser, but is not offered as a download yet | Yes: the Flutter Scene Editor, a desktop app with macOS, Windows and Linux downloads on its GitHub releases, not on pub.dev, and still "in active development" |

## Feature by feature

A green dot is a capability the engine has; a red one is a capability it does not. For flutter3d that is read from its source. For Flutter Scene it is read from its README and its CHANGELOG up to 0.24.1, and then checked against its source: a red dot there means none of the three names it in the engine's packages. Where Scene has something close in another form, the row is worded to the difference, and here is the form: god rays rather than volumetric fog, splats sorted on the CPU rather than on the GPU, a pure-Dart physics backend for queries and triggers with no dynamics, physics rollback for the one entity a client owns rather than every player's input, occlusion culling through planes an application supplies rather than a depth pyramid, and a selection outline rather than a high-contrast look. Each row is one capability, so where both engines have something in different depths (physics, global illumination, the editor) the sections below say how they differ.

<table class="compare">
<thead><tr><th>Capability</th><th>flutter3d</th><th>Flutter Scene</th></tr></thead>
<tbody>
<tr class="group"><th colspan="3">Rendering</th></tr>
<tr><td>Physically based materials with clearcoat, sheen, anisotropy and transmission</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>User materials compiled for every backend, with lighting hooks</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Rectangle area lights</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Clustered lights, so a scene can hold many</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Cascaded sun shadows with soft penumbrae and contact shadows</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Exponential variance shadow maps (EVSM) for the sun</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Caustics under glass and water</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Irradiance probe field with a visibility test per probe</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Horizon-based ambient occlusion and screen-space bounced light</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Screen-space reflections, depth of field, bloom, automatic exposure</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Planar reflections, and a camera that renders into a texture</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>A physical sky, and fog that thins with height</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Volumetric fog</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Order-independent transparency</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Motion blur</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Local exposure, and HDR output (WebGPU only)</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Temporal anti-aliasing, FXAA and SMAA</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Lens flares, radial lens distortion and <code>.cube</code> LUTs</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Projected decals</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Orthographic cameras through every effect</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Gaussian splats</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Splats sorted on the GPU (WebGPU compute)</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Octahedral impostors for distant models</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Automatic occlusion culling (Hi-Z)</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Reversed depth, a near plane fitted to what is drawn, and depth layers for coplanar surfaces</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>A probe that names the nodes fighting over depth in a running scene</td><td class="dot"><span class="no">no</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Quality that adapts to measured frame times</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Debug views of material channels, and render stats per pass</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr class="group"><th colspan="3">Assets and animation</th></tr>
<tr><td>Skinning, morph targets and blended animation</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>An animation graph: state machines, blend spaces, layers, IK after the pose</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>glTF material variants</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>glTF animation pointers (a clip moves a material or a light)</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Retargeting a clip onto another skeleton</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Models converted at build time by a build hook</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Hot reload for shaders, models, textures, environments and levels</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr class="group"><th colspan="3">Backends</th></tr>
<tr><td>Impeller through Flutter GPU</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>WebGL2 in the browser</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>WebGPU in the browser</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>A software rasteriser in Dart, so rendering tests run without a GPU</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr class="group"><th colspan="3">Games</th></tr>
<tr><td>Native rigid bodies that rotate, with joints and continuous collision</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Physics through an established third-party engine (Rapier, box3d)</td><td class="dot"><span class="no">no</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>The same games on pure-Dart dynamics when the native core is not there</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Ragdolls</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Cloth in the engine's packages</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Liquids, floating bodies, heat and fire in the physics</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Particles</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Audio through SoLoud</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Rebindable input with gamepads and pointer lock</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Multiplayer with a server and client-side prediction</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Rollback of every player's input, for parties of more than two</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Navigation meshes and behaviour trees</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>A run recorded and replayed to the bit, with a time-travel debugger</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Levels generated from a seed (wave function collapse, erosion)</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Voxel worlds</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>Genre packages: shooter, platformer, racing, strategy</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr><td>A bridge to the Flame 2D engine</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
<tr class="group"><th colspan="3">Tools and app integration</th></tr>
<tr><td>A scene editor with an MCP server for coding agents</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Editor downloads for macOS, Windows and Linux</td><td class="dot"><span class="no">no</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Render stats and the frame's draws, read by an agent over MCP</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>Agent skills shipped with the packages</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>A declarative widget API for the scene</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>The scene described to a screen reader</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="yes">yes</span></td></tr>
<tr><td>A high-contrast look with outlines, and colour-vision correction</td><td class="dot"><span class="yes">yes</span></td><td class="dot"><span class="no">no</span></td></tr>
</tbody>
</table>

## What Scene has that flutter3d doesn't

Reading its README and CHANGELOG against flutter3d's own feature table:

- **Physics on an engine other people have already shipped games with.** Rapier and box3d, pluggable behind one contract, with Rapier's binaries built in CI and downloaded prebuilt. flutter3d's physics core in C covers a lot of the same ground now (turning bodies, convex hulls and triangle meshes, joints with motors and limits, continuous collision, a character controller, ragdolls, threads, the browser through WebAssembly), but it was started on 2026-10-04, and nobody outside this repository has run it yet. The games pass their suites on it and on the Dart reference both. That tells me it works for these games; it tells you much less about yours. It is compiled from source by a build hook, with the compiler the target already uses, so there is nothing prebuilt to download, but the build machine needs that compiler.
- **FMOD.** Both engines wrap the same SoLoud engine for audio, so that is not a difference; Scene also offers FMOD, commercial middleware, as a second backend.
- **An editor you can download today.** The Flutter Scene Editor 0.24.0 is on GitHub releases for macOS, Windows and Linux. flutter3d's editor builds for the desktop and, since 1.0, for the browser (documents kept in the page, Play attached to a game already running), and `flutter3d_editor_mcp` is on pub.dev, but the editor app itself is not handed out anywhere yet.
- **Windows and Linux through Impeller.** Scene lists both as platforms, and its editor ships for them. On Windows, flutter3d's CI builds the games and the editor and runs the native physics core's tests under MSVC, and nobody has played a game there yet. On Linux every flutter3d test suite runs and the CPU backend draws the golden scenes, but Impeller does not draw: Flutter GPU is off unless the runner turns it on, and with it on, Impeller's OpenGL ES backend refuses shaders that read `gl_VertexID`. A flutter3d game on Linux draws through the software backend until that is fixed.
- **Tools that find z-fighting.** Both engines now store reversed float depth where the device allows it, move the near plane out to what is drawn each frame, and let a material put one coplanar surface over another with a depth layer; Scene shipped it in 0.24.0, flutter3d in 1.0.0-rc.1. Scene also has tools that look for it. `Scene.probeDepthConflicts` names each pair of nodes that trade pixels as the camera moves, `Scene.findCoplanarOverlaps` lists faces that overlap in one plane, and a debug view shows the gap two surfaces need at each pixel. flutter3d's nearest thing is the level validator, which warns when two solid brushes of a level share volume, since their coincident faces are where z-fighting shows. It knows nothing about models or a running scene.
- **Two projects built on it**, the [Dashsurfers](https://github.com/bdero/dashsurfers) endless runner and the [Dashmap](https://github.com/bdero/dashmap) live world map, plus 43 runnable feature examples in the example app.
- **More than two and a half years in its own repository**, and an earlier life inside the Flutter engine, against flutter3d's two months.

Most of what this list held in 0.8 is now on both sides of the table. Reversed depth and depth layers, SMAA, lens flares, radial distortion and `.cube` LUTs; hot reload of models, textures, environments and levels as well as shaders; a declarative widget API (`Scene3D` with `Node3D`, `Mesh3D`, `Model3D` and the rest, which mounts nodes of an ordinary scene); rotating bodies with joints. Global illumination and temporal anti-aliasing had already moved off in 0.8. In each case Scene had it first, and in some it still goes further: its SMAA tunes its search at runtime where flutter3d has the 1x mode only, and its hot reload patches a changed scene document into the live graph in place.

## What flutter3d has that Scene doesn't

- **Physics that still runs with no native code at all.** The C core is the default, and `flutter3d_physics`, in plain Dart, is its reference and its fallback: when the core will not start, the run says why and goes on in Dart, and the games' suites pass under both. A recording says which one it ran on, and a replay refuses the other. Scene's pure-Dart backend answers queries and triggers but has no dynamics. Beyond rigid bodies, the physics also carries cloth, liquids in vessels and pipes, floating bodies, and heat and fire with wind; Scene's README names none of those.
- **A CPU software backend.** `flutter3d_cpu` rasterises entirely in Dart, gives the renderer a second, independent implementation to check the GPU backends against, and runs the golden-image suite in CI with no GPU at all. Scene has no software backend of its own; its CI renders through Impeller on Mesa and SwiftShader software rasterisers, in headless Chrome, and on Codemagic's Apple hardware, and checks the frames in Argos.
- **WebGPU in the browser, by default.** flutter3d tries WebGPU first and falls back to WebGL2, and on WebGPU it sorts splats on compute. Scene ships WebGL2 only on the web.
- **Three complete games of different genres on one engine, with no genre-specific code shared between them.** A shooter, a platformer and a racing game, each built without editing the engine packages the other two depend on, with the boundary held by structural scans in `tool/structure.dart`. A fourth genre, strategy, is in the workspace too, and its genre package is on pub.dev. A voxel sandbox joined them in 1.0: `flutter3d_voxel` and a demo that digs, builds and saves.
- **Simulation tooling a game is built from.** An animation graph with state machines, blend spaces, layers, markers and IK; navigation meshes rebaked where a wall breaks; behaviour trees written in the editor or by an agent over MCP; cutscenes played in the fixed step; saves with migrations; a time-travel debugger; and replay tests that hold a recorded run to its digests in `flutter test`. Every one of these runs in the deterministic step, which is why a run replays to the bit. And levels generated from a seed and a set of rules, by wave function collapse over a kit's tiles and erosion of a heightfield, refused when no route reaches the exit.
- **Parties with rollback.** `flame_multiplayer` rolls back every player's input for two to thirty-two machines (the tests and the racing game run four), feeds spectators from the settled tape, and also has an authoritative server with predicting clients. Scene's networking is the authoritative kind, with rollback for the entity a client owns.
- **A bridge to Flame, the established Flutter 2D game engine.** `flame_flutter3d` composites a Flame layer and a flutter3d layer in one widget, each drawing itself, with transform, ECS (through `flutter3d_sim`'s own actor system), physics, input and camera reconciled between the two, so neither engine drives the other's renderer. Since 0.8.5 a plain Flame game can also hold one 3D model as a `Model3dComponent`, ordered by Flame's priority like a sprite. A demo, [Meteor Yard](/arcade/demo/), uses the bridge end to end and plays in a browser. Scene's README does not describe an equivalent.
- **Colour accessibility.** A high-contrast look that flattens texture detail and rings what the game marks as important in its role colour, colour-vision simulation and correction, and a lint for cues told apart by hue alone. Both engines describe the scene to a screen reader.
- **Rendering features Scene does not list.** Order-independent transparency, motion blur, volumetric fog, caustics under see-through casters, local exposure, and HDR output on the WebGPU backend; octahedral impostors and occlusion culling. Scene has god rays, which are a near relative of the volumetric fog, and it may have more than its README and CHANGELOG say.

<div class="why">
<p><strong>I read these as different bets on where a young engine spends its first months.</strong> Scene put more than two and a half years into rendering depth, physics and audio on established engines, an editor people can download, and the platforms it runs on, with a maintainer who wrote Flutter GPU. flutter3d spent the months before its 1.0 catching up on the renderer and the API, and put the rest into the simulation: deterministic runs, tools for building games on top of them, and a software rendering backend in Dart, so rendering tests need no GPU and no graphics driver. Scene is pre-1.0 and flutter3d is at its first 1.0 release candidate; both are MIT, both sit on the same `flutter_gpu` foundation.</p>
</div>

## Picking one

If a project needs physics that other people have already shipped, FMOD, an editor to download today, Windows and Linux through Impeller, or tools that find z-fighting for you, Scene already has it, and I would pick Scene. If a project's constraints run the other way (physics that has to work with no native code when it must, rendering tests that run with no GPU or graphics driver inside `flutter test`, WebGPU, replays and rollback that hold to the bit, or an interest in how the genre-package split holds up across three real games), flutter3d is built to show exactly that.
