---
description: The engine under all three games: the HAL and its three backends, the renderer, scene graph, geometry, assets, the fixed step and collision.
---

# What core is

Core is everything all three games use and none of them owns. Six packages that never learn what a monster, a coin or a lap is, plus three backends that never learn what a scene is.

Nothing in this section is genre knowledge. That is not a stylistic preference. It is the property that made the second game possible to write, and every page here says which test enforces it.

## The six packages

| Package | What it owns | Depends on |
|---|---|---|
| [`flutter3d`](/core/rendering/) | The renderer, the scene graph, geometry, decoders, animation | `flutter3d_hardware` and nothing below it |
| [`flutter3d_hardware`](/core/architecture/#the-hal) | **The HAL** — devices, encoders, buffers, textures, pipelines, passes. No implementation at all | nothing |
| [`flutter3d_sim`](/core/simulation/) | Fixed step, input, levels and holes in them, mechanisms, actors, navigation and the automap, ECS, snapshots, demos, rewind | `flutter3d_physics`, `vector_math`. Plain Dart, no Flutter |
| `flutter3d_game` | The devices: touch stick and buttons, keyboard and mouse, the gamepad route. Re-exports `flutter3d_sim` | `flutter3d_sim` and Flutter |
| [`flutter3d_physics`](/core/physics/) | Shapes, broadphase, sweeps, rays, character controller, rigid bodies | nothing. Plain Dart |
| [`flutter3d_bridge`](/core/architecture/#the-bridge) | Level geometry to mesh nodes, actor to visual, fixture to light | both sides, and it is the only package allowed to |

**Three backends implement the HAL**, and an application names exactly one of them in its pubspec:

| Backend | Runs on |
|---|---|
| `flutter3d_impeller` | `flutter_gpu` — Metal and Vulkan. The production one |
| `flutter3d_webgl` | WebGL2 in the browser. Runs the shooter and the platformer at a fixed resolution and a lower frame rate |
| `flutter3d_cpu` | Nothing — it rasterises in Dart, so thirty-four golden scenes stay checkable with no GPU in the room |

`flutter3d_conformance` is the suite any fourth one would have to pass, and [Writing a HAL backend](/core/backends/) is the guide for writing that fourth one.

## The two halves, and the line between them

```mermaid
flowchart LR
  subgraph drawn["drawn — needs a device"]
    direction TB
    renderer["Renderer"]
    passes["passes: shadow, opaque,<br>transparent, bloom, composite"]
    device["GraphicsDevice"]
    renderer --> passes --> device
  end

  subgraph headless["headless — plain Dart"]
    direction TB
    step["FixedStep · GameLoop"]
    input["InputState"]
    world["CollisionWorld · CharacterController"]
    level["Level · Mechanism · ActorSystem"]
    step --> world
    input --> world
    level --> world
  end

  subgraph shared["shared, device-free"]
    direction TB
    scene["Scene graph · bounds · culling"]
    geom["MeshData · Shape · MeshBuilder"]
    assets["glTF · OBJ · .f3d decoders"]
  end

  headless -. "one package may see both" .-> bridge["flutter3d_bridge"]
  bridge -.-> drawn
  shared --> drawn
```

The left half runs under `dart test` on the VM. Its characteristic failures happen once in a thousand steps, so finding them means running thousands of steps in a loop, which is possible because none of it needs a device.

The middle band is the part people expect to need a GPU and does not. Bounds, culling, framing, picking, decoding and draw-call sorting are all arithmetic. The scene layer holds a `MeshGeometry`, not a `GpuMesh`, and requiring a device would have meant none of them could be unit tested.

## What to read, in what order

Each page below stands alone, but this is the order in which each one stops being surprising.

<ul class="cards">
  <li><a href="/core/architecture/">
    <span class="card-kind">01</span>
    <h3>Architecture</h3>
    <p>The dependency rules, the HAL and its three backends, and the one consequence that shapes everything: shaders are compiled ahead of time.</p>
  </a></li>
  <li><a href="/core/backends/">
    <span class="card-kind">02 · guide</span>
    <h3>Writing a HAL backend</h3>
    <p>The full contract, the ten semantics no signature can express, the conformance suite, and the shader bundle you cannot avoid writing.</p>
  </a></li>
  <li><a href="/core/rendering/">
    <span class="card-kind">03</span>
    <h3>The frame</h3>
    <p>Render views, the pass order, instanced batches, precomputed visibility, HDR, bloom, cascaded shadows, fog, reflections, and the frame graph that schedules them.</p>
  </a></li>
  <li><a href="/core/scene/">
    <span class="card-kind">04</span>
    <h3>Scene graph</h3>
    <p>Nodes with version stamps, cameras and projections, eight lights of any type, the BVH, LOD groups and picking.</p>
  </a></li>
  <li><a href="/core/geometry/">
    <span class="card-kind">05</span>
    <h3>Geometry &amp; materials</h3>
    <p>Shapes as values, surfaces of revolution, vertex layouts, and why a material is a pipeline.</p>
  </a></li>
  <li><a href="/core/assets/">
    <span class="card-kind">06</span>
    <h3>Assets &amp; animation</h3>
    <p>glTF, OBJ, the <code>.f3d</code> container, isolate decoding, the resource cache, clips, skinning and crossfades.</p>
  </a></li>
  <li><a href="/core/simulation/">
    <span class="card-kind">07</span>
    <h3>Simulation layer</h3>
    <p>The fixed step, device-agnostic input, the level format and holes in its walls, mechanisms, actors, navigation and the automap, the ECS, saves, demos and rewind.</p>
  </a></li>
  <li><a href="/core/physics/">
    <span class="card-kind">08</span>
    <h3>Collision &amp; physics</h3>
    <p>Shapes, the uniform-grid broadphase, sweeps that do not tunnel, the character controller, and rigid bodies without rotation.</p>
  </a></li>
  <li><a href="/core/extras/">
    <span class="card-kind">09</span>
    <h3>Particles &amp; audio</h3>
    <p>One pool and one draw call, lights measured from the particles that cast them, and positional audio computed in Dart.</p>
  </a></li>
  <li><a href="/core/tutorial/">
    <span class="card-kind">10 · tutorial</span>
    <h3>Your first scene</h3>
    <p>Thirteen steps from an empty Flutter app to a lit, shadowed, animated scene you can click on.</p>
  </a></li>
</ul>
