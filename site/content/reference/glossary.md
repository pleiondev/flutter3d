---
description: The words this engine uses for things, in the order somebody meets them, with the type each one names.
---

# Glossary

Every word below is a type or a file in this repository, not a general graphics term. Where a word is used differently elsewhere, the entry says so.

## Drawing

<dl class="keys">
  <div><dt>Backend</dt><dd>One implementation of <code>flutter3d_hardware</code>. There are three: <code>flutter3d_impeller</code> on the GPU, <code>flutter3d_webgl</code> in a browser, <code>flutter3d_cpu</code> in plain Dart. An application depends on exactly one by name</dd></div>
  <div><dt>HAL</dt><dd>The hardware abstraction layer, <code>flutter3d_hardware</code>: <code>GraphicsDevice</code>, <code>CommandEncoder</code>, formats, handles. It names no graphics API, which is what lets the renderer be written once</dd></div>
  <div><dt>Pass</dt><dd>One <code>beginRenderPass</code> and everything drawn before it is submitted. A frame here is shadows, sky, scene, then post, each in its own command buffer</dd></div>
  <div><dt>Draw item</dt><dd>One mesh, one material, one transform, sorted into the render list by a packed key. Culling decides which nodes become one</dd></div>
  <div><dt>Contributor</dt><dd>A <code>PassContributor</code>: something that draws inside somebody else's pass without editing the renderer. Particles are the first user</dd></div>
</dl>

## Lighting and shadows

<dl class="keys">
  <div><dt>Lighting model</dt><dd>A <code>LightingModel</code>: one compiled fragment shader. Six ship (unlit, Lambert, Blinn-Phong, PBR, toon, normals), and switching one switches pipeline, which is why the draw sort puts pipeline first</dd></div>
  <div><dt>Cascade</dt><dd>One tile of the directional light's shadow map. Three tiles covering near, middle and far beat one large tile covering everything</dd></div>
  <div><dt>Cube atlas</dt><dd>Where point and spot shadows live: six faces across, one row per shadowed light, six lights at once. Sized by <code>ShadowSettings.cubeResolution</code>, which is <em>not</em> the cascade's <code>resolution</code></dd></div>
  <div><dt>Static / dynamic atlas</dt><dd>Two cube atlases. The static one holds what never moves and is drawn once at load; the dynamic one is redrawn as things move. The shader samples both and keeps the nearer occluder</dd></div>
  <div><dt>Normal offset</dt><dd>How far a shadow lookup moves along the surface normal before it measures, in <strong>texels</strong> of the face it lands on. It clears the width of one texel, which grows with distance — a fixed offset in metres is why a floor once shadowed itself</dd></div>
  <div><dt>Penumbra</dt><dd>The soft edge. Estimated from how far the blocker is, which is why the filter searches before it filters</dd></div>
</dl>

## Assets

<dl class="keys">
  <div><dt><code>.f3d</code></dt><dd>This engine's binary mesh container. About 360× faster to load than the same geometry as OBJ text, which is the whole reason it exists</dd></div>
  <div><dt><code>.fmat</code></dt><dd>A material as a file, so a look can be authored once and shared. <code>MaterialDecoder</code> is the seam for formats the engine does not ship</dd></div>
  <div><dt>Environment map</dt><dd>A prefiltered cube built by <code>EnvironmentMap.prefilter</code>: the specular chain plus a diffuse level. What image-based lighting samples</dd></div>
  <div><dt>LOD group</dt><dd>A <code>LodGroup</code>: several versions of one object, chosen by how much of the viewport it covers rather than by distance, because the same object at the same distance is worth different detail through different lenses</dd></div>
</dl>

## The level document

A level is JSON. These are its parts, and a game reads all of them through `LevelLoader`.

<dl class="keys">
  <div><dt>Brush</dt><dd>A <code>Brush</code>: a box with a material. Walls, floors, ledges, ramps. The geometry of a level is a list of these</dd></div>
  <div><dt>Entity</dt><dd>An <code>EntityDef</code>: a type name and some properties. <code>torch</code>, <code>monster</code>, <code>key</code>. The engine does not know what any of them mean</dd></div>
  <div><dt>Entity kind</dt><dd>An <code>EntityKind</code> in a game's registry: what that type name is worth. This is where a game says <code>monster</code> spawns an actor with this brain and that health</dd></div>
  <div><dt>Fixture</dt><dd>A <code>Fixture</code>: an entity that has been placed and given a mechanism. What the bridge turns into something you can see</dd></div>
  <div><dt>Mechanism</dt><dd>A <code>Mechanism</code>: the behaviour behind a fixture. A door that opens, a light that flickers, a platform that moves</dd></div>
  <div><dt>Level light</dt><dd>A <code>LevelLight</code>: type, colour, range, intensity, and whether it casts. A fixture can dim the one it owns by name</dd></div>
</dl>

## Simulation

<dl class="keys">
  <div><dt>Fixed step</dt><dd>The simulation advances in equal slices, whatever the frame rate. Two machines fed the same intents reach the same place; the frame interpolates between the last two steps</dd></div>
  <div><dt>Intent</dt><dd>What a player asked for, in a game's own words: <code>jump</code>, <code>fire</code>, <code>dash</code>. A <code>GameAction</code>, which is a value class rather than an enum, so a genre adds one without editing the engine</dd></div>
  <div><dt>Actor</dt><dd>An <code>Actor</code>: something alive that a brain drives. Monsters are actors; the player is not, because a player has no brain to run</dd></div>
  <div><dt>Brain</dt><dd>A <code>Brain</code>: what an actor decides each step. States, targets, a path to walk</dd></div>
  <div><dt>Snapshot</dt><dd>Everything a save needs, taken from the simulation and restored into it. Not the tuning: a save that carried the balance patch would restore a car built by an older one</dd></div>
  <div><dt>Replay / tape</dt><dd>A recording of <em>intents</em>, not of positions. Replayed through the same fixed step it reproduces the run exactly, which is what makes a bug in a race reproducible</dd></div>
</dl>

## Physics

<dl class="keys">
  <div><dt>Broadphase</dt><dd>The cheap pass that decides which pairs are worth testing properly. A uniform grid here</dd></div>
  <div><dt>Sweep</dt><dd>Moving a shape along a path and stopping at the first thing in the way, instead of teleporting it and asking what it overlaps. What keeps a fast body from passing through a wall</dd></div>
  <div><dt>Character controller</dt><dd>A <code>CharacterController</code>: kinematic, sweeps and slides, and nothing ever pushes it. That is what a first-person game feels as solidity</dd></div>
  <div><dt>Layer mask</dt><dd>Which things collide with which. A bullet passes through a pickup and stops at a wall because their masks say so</dd></div>
</dl>

## Racing, since it has its own vocabulary

<dl class="keys">
  <div><dt>Track spline</dt><dd>A <code>TrackSpline</code>: the road as a curve with widths and banks, not as geometry. A car is placed by where it is along the curve, which is what lets a circuit run to a kilometre</dd></div>
  <div><dt>Slip angle</dt><dd>The gap between where the car points and where it is going. What makes a tyre generate a cornering force, and what makes it stop when the gap gets too wide</dd></div>
  <div><dt>Slip ratio</dt><dd>The gap between how fast the wheels are turning and how fast the road is passing. Traction and wheelspin are the same number with different signs</dd></div>
  <div><dt>Grip circle</dt><dd>One budget shared between cornering and braking. Spend it all on stopping and there is none left to turn, which is why trail braking works</dd></div>
  <div><dt>Ghost</dt><dd>A recorded lap played back as <em>places</em>, not inputs, so it survives the car being retuned</dd></div>
</dl>

## Testing

<dl class="keys">
  <div><dt>Golden</dt><dd>A reference image a scene is compared against. Three independent sets, Impeller, software and WebGL2, each held to zero differing pixels against its own</dd></div>
  <div><dt>Parity fixture</dt><dd>One scene drawn by two backends and compared as a grid of average brightness. Answers "do these two draw the same picture", which a golden cannot</dd></div>
  <div><dt>Conformance</dt><dd>The suite a backend has to pass before it counts as one. Split in two: what needs no shaders, and the rest</dd></div>
  <div><dt>Structure rule</dt><dd>One of nineteen scans in <code>tool/structure.dart</code>. They read source text and hold the architecture: that a genre package stays out of another genre, that the documents' numbers are true</dd></div>
</dl>

## Next

- [Quickstart](/quickstart/): from a fresh checkout to a lit mesh
- [Your first project](/first-project/): a game of your own, from a template
- [The knobs](/reference/tuning/): every number a designer changes, and where it lives
- [Pitfalls](/reference/pitfalls/): symptoms, and what each one actually is
