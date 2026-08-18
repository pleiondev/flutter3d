---
description: A 3D engine on Flutter GPU, a game layer on top of it, and two shipped games of different genres built from both.
---

<p class="hero-kicker">A 3D engine on Flutter GPU</p>

# Three games, one engine, no edits in between

flutter3d is a renderer, a game layer, and three finished games of different genres. The second and third were built without changing a line in the first one's engine packages.

<div class="frameband">
  <p class="frameband-label"><span>One frame, as this engine encodes it</span><span>one command buffer per pass</span></p>
  <div class="frameband-track">
    <div class="pass hdr"><b>shadow</b><span>4 cascades<br>linear depth</span></div>
    <div class="pass hdr"><b>opaque</b><span>sorted by<br>pipeline</span></div>
    <div class="pass hdr"><b>transparent</b><span>back to front<br>no depth write</span></div>
    <div class="pass hdr"><b>bloom</b><span>half-size chain<br>blur between</span></div>
    <div class="pass ldr"><b>composite</b><span>tonemap<br>exposure, sRGB</span></div>
    <div class="pass ldr"><b>overlay</b><span>debug lines<br>view model</span></div>
  </div>
  <p class="frameband-foot">The first four render into <code>r16g16b16a16Float</code>. Metal allows one open encoder per command buffer and flutter_gpu cannot end a render pass, so each pass gets its own command buffer, submitted in order.</p>
</div>

<dl class="stats">
  <div><dt>Tests</dt><dd>1805<small>across 16 packages</small></dd></div>
  <div><dt>Need a GPU</dt><dd>~30<small>the Impeller goldens only</small></dd></div>
  <div><dt>Lighting models</dt><dd>6<small>one shader each</small></dd></div>
  <div><dt>Model load</dt><dd>1.1 µs<small>.f3d vs 4.54 ms as OBJ</small></dd></div>
</dl>

## Status

| | |
|---|---|
| Channel | Flutter 3.47.0 stable, Dart 3.12.2 |
| Platforms | macOS, Windows and Linux desktop through Impeller; the browser through WebGL2 |
| Published | No. Packages resolve by path inside one pub workspace |
| Stability | Pre-1.0. The graphics HAL carries a written compatibility promise; nothing else does |

## Where to start

<ul class="cards">
  <li><a href="/quickstart/">
    <span class="card-kind">15 minutes</span>
    <h3>Quickstart</h3>
    <p>Resolve the workspace, build the shader bundle, and put a lit mesh on screen.</p>
  </a></li>
  <li><a href="/core/">
    <span class="card-kind">Engine</span>
    <h3>Core</h3>
    <p>The renderer, the scene graph, geometry, assets, the fixed step and collision.</p>
  </a></li>
  <li><a href="/shooter/demo/">
    <span class="card-kind">Genre · playable</span>
    <h3>Shooter</h3>
    <p>Weapons, hitscan and projectiles, monsters that path around corners, an inventory, locked doors.</p>
  </a></li>
  <li><a href="/platformer/demo/">
    <span class="card-kind">Genre · playable</span>
    <h3>Platformer</h3>
    <p>A double jump with coyote time, wall slides, ice and conveyors, springs, checkpoints.</p>
  </a></li>
  <li><a href="/racing/">
    <span class="card-kind">Genre</span>
    <h3>Racing</h3>
    <p>A track as a measured curve, a tire that falls away past its peak, laps that cannot be cheated, AI drivers and ghosts.</p>
  </a></li>
</ul>

The shooter and the platformer run in a browser on the WebGL2 backend and are embedded on their demo pages. The racing game renders there and is not fast enough to drive; [its demo page says what was measured](/racing/demo/).

## The package split

Sixteen packages. Each boundary is a rule that a test enforces.

```mermaid
flowchart TB
  subgraph app["applications"]
    dungeon["apps/dungeon<br>the shooter"]
    platformer["apps/platformer<br>the platformer"]
    racing["apps/racing<br>the racing game"]
  end

  subgraph genre["genres — vocabulary"]
    shooter["flutter3d_shooter<br>weapons, monsters, inventory"]
    plat["flutter3d_platformer<br>runner, springs, surfaces"]
    race["flutter3d_racing<br>track, car, tire, lap"]
  end

  bridge["flutter3d_bridge<br>the only package that may see both sides"]

  subgraph draw["drawing"]
    f3d["flutter3d<br>renderer, scene, assets"]
    gfx["flutter3d_graphics<br><b>the HAL</b>"]
    impeller["flutter3d_impeller<br>flutter_gpu"]
    webgl["flutter3d_webgl<br>WebGL2"]
    cpu["flutter3d_cpu<br>software"]
  end

  subgraph sim["simulating, no Flutter, no GPU"]
    game["flutter3d_game<br>step, input, levels, actors, ECS"]
    physics["flutter3d_physics<br>shapes, sweeps, controller"]
  end

  dungeon --> shooter & bridge
  platformer --> plat & bridge
  racing --> race & bridge
  shooter --> game
  plat --> game
  race --> game
  bridge --> f3d & game
  f3d --> gfx
  impeller --> gfx
  webgl --> gfx
  cpu --> gfx
  game --> physics
```

Three rules hold the picture up, and a test checks each one.

- **`flutter3d_game` does not depend on `flutter3d`.** Simulation, input and collision say nothing about how a frame is drawn. That is what lets the failures which never show up in a screenshot be reached from a plain unit test: a collision that passes through a wall once in a thousand steps, a jump that is a different height on a faster monitor, a press swallowed at a low frame rate.
- **A genre is a package.** `flutter3d_shooter` holds what only a shooter wants, so a platformer inherits none of its vocabulary. `test/no_genre_test.dart` and its twin in the bridge check it.
- **The engine names no graphics API.** `flutter3d` is written against a hardware abstraction layer, `flutter3d_graphics`, and three backends implement it. Checked by `test/backend_is_contained_test.dart`.

The bridge exists because neither of the first two rules leaves anywhere for the mapping to live. Level geometry has to become mesh nodes and an actor has to get a visual, while the game layer must not learn what a mesh is and the renderer must not learn what a monster is. One package is allowed to know both.

## One HAL, three backends

The renderer talks to a hardware abstraction layer and never to a graphics API. Three packages implement that layer.

| Backend | Runs on | Status |
|---|---|---|
| `flutter3d_impeller` | `flutter_gpu`: Metal on Apple platforms, Vulkan elsewhere | Complete. Both games ship on it |
| `flutter3d_webgl` | WebGL2, in the browser | Runs the shooter and the platformer, slower and at a fixed resolution. The racing game renders and is too slow to play |
| `flutter3d_cpu` | Nothing. It rasterises in Dart | Complete for the golden set. A dev dependency of every game |

An application names one of them in its pubspec and hands the device to `Renderer.create`. Moving between them is that line and one constructor call.

Each backend exists for a different reason. Impeller is the production one. WebGL2 answers whether the HAL is a seam or a description of Impeller, because a fake backend can only show that an interface is callable, never that it is implementable. The CPU rasteriser shares no driver, shading language or command buffer with either of the others, so agreement with it means more than agreement between two GPU backends would.

[How the HAL is put together](/core/architecture/#the-hal) · [Writing a fourth backend](/core/backends/)

## What is in the box

| | |
|---|---|
| Rendering | Six lighting models as pre-built shaders. HDR pipeline with tone mapping and exposure, bloom from a half-size chain, cascaded directional shadows with PCF, point-light shadows, screen-space reflections, fog, 4× MSAA, wireframe |
| Geometry | Surfaces of revolution as the base generator, `MeshData` and `MeshBuilder`, custom vertex layouts, tangent generation with Lengyel's method |
| Assets | glTF 2.0 / GLB, Wavefront OBJ, and `.f3d`, the engine's own container. Decoding on a background isolate, a reference-counted cache |
| Animation | All three glTF interpolations, skinning with 64 joint matrices, an `AnimationPlayer` with crossfades, transport and once/loop/ping-pong |
| Scene | Version-stamped nodes, a BVH shared by culling and picking, LOD groups by screen coverage, orbit and follow cameras, CPU raycasting |
| Simulation | A fixed step with interpolation, device-agnostic input with latched edges, a level format with a validator, mechanisms, actors and brains, a navigation grid with flow fields, an ECS, snapshots |
| Physics | Overlap, sweeps and rays over a uniform-grid broadphase, a character controller that walks, jumps, climbs a step and rides a lift, and rigid bodies without rotation |
| Driving | A track as a spline with width, camber and surface bands, a sphere-and-frame vehicle, a tire curve with a friction circle, lap counting through checkpoints, AI drivers and ghost tapes |
| Extras | A pooled particle system that draws in one call, positional audio with attenuation, panning, occlusion and voice limiting |

## What it does not do

- **No runtime shader compilation.** Shaders are compiled ahead of time into a bundle, so a material graph in the style of Babylon's `NodeMaterial` or three.js TSL is not possible. Every lighting model is a separate pre-built shader and every shader is a separate pipeline.
- **No compressed textures, no compute passes, no rendering into a mip level.** These are what `flutter_gpu` still lacks.
- **No navmesh, no flanking, no squads.** Navigation gets an agent there, not around you.
- **No gamepad and no touch backend.** `InputState` is device-agnostic and `setStickAxis` is the seam; nobody has written the other side of it.
- **No morph targets, no Draco, no KTX2.** A decoder reports these in `warnings` rather than failing the file.
