# flutter3d against flutter_scene

Written 2026-08-10, against `flutter_scene` 0.20.0 (`bdero/flutter_scene`, master)
and `flutter3d` at branch `point-shadows`.

Everything below was checked by reading the other engine's source and its
published API, not by reading its marketing. Where a claim is about their code,
the file it came from is named. Where a claim is about ours, the golden or test
that pins it is named.

## The headline, stated plainly

**flutter_scene is the broader engine today.** It ships roughly 250 Dart files
against our 62 (~15.7k lines here), and it has whole subsystems we do not have
at all: physics, audio, a web backend, compressed textures, mipmaps, IBL, and a
post-processing stack several effects deep. A comparison that put us ahead on
breadth would be a comparison of the wrong thing.

**What we have instead is depth in one direction they have not gone**, and it
is not a small one: we shadow every light type, they shadow two of three. For a
dungeon — a torch-lit interior where the point light *is* the lighting — that
single gap is the difference between a lit room and a lit room that looks
correct. This document is organised around defending that lead and closing the
rest.

## 1. Where we are genuinely ahead

| Capability | flutter3d | flutter_scene | How this was checked |
|---|---|---|---|
| **Point-light shadows** | **Yes.** Cube atlas, six 90° faces per light, four lights per frame, one pass | **No — not at any quality.** `PointLight` takes `intensity`, `range`, `falloffExponent` and nothing else; there is no `castsShadow` on it. Only `DirectionalLight` and `SpotLight` have shadow parameters | `src/light.dart:387` (theirs); `cube-shadow`, `cube-shadow-many` goldens (ours) |
| **Radial-distance cube faces** | Faces store distance/range, not clip depth, so no seam at a face boundary | n/a — no cube shadows to seam | `shaders/lighting/shadow_distance.frag` |
| **Static/dynamic shadow split for point lights** | Two atlases, walls baked once at load, movers redrawn per frame, shader takes `min` | They have the same idea, but only for **directional cascades** (`shadowStatic` + `DirectionalShadowCache`). Spot and point get nothing | `src/render/shadow_cache.dart` (theirs) |
| **Model formats** | glTF/GLB, OBJ, and our own `.f3d` binary with a writer | glTF/GLB and their own `.fscene`. No OBJ | `lib/src/engine/assets/` vs `src/importer/` |
| **Fixed menu of lighting models** | Six switchable at runtime per material: unlit, lambert, blinn-phong, PBR, toon, normals — each pinned by its own golden | PBR and unlit, plus a material DSL. Toon or lambert is something you write | `lighting-*` goldens |

Two honest caveats on that table. Their material DSL (`fmat`, a parser, AST and
emitter with hot reload) is strictly more powerful than our fixed menu once you
are willing to write a shader — our advantage is that six useful models exist
without writing one. And their spot shadows are more carefully filtered than
anything we have: rotated Poisson disk, a choice of caster faces, separate depth
and normal bias. We do 3×3 PCF.

## 2. Where we are roughly level

Bloom, fog, tonemapping, MSAA, skeletal animation, glTF import, LOD, BVH
culling, raycasting, particles, debug drawing, multiple views. Both engines
have all of it. Ours is smaller and theirs is more configurable; neither is a
reason to choose one.

One genuine difference in kind: we expose a **render-plugin seam**
(`RenderPlugin`, `RenderStage`) that lets an application inject a pass — the
view-model overlay is built on it. They solve the same problem with a formal
**render graph** (`src/render/render_graph.dart`) with a blackboard. Theirs is
the more serious architecture and we should expect to end up there.

## 3. What they have and we do not

Grouped by what it would cost us, not by their file layout.

### Blocking for a shipped game

| Missing | Theirs | Why it bites |
|---|---|---|
| **Physics** | `src/physics/` — rigid bodies, colliders, joints, character controller, queries, events | We have a ground probe that lets a passenger sink into a moving platform. That is a symptom of not having this |
| **Audio** | `src/audio/` — engine, buses, 3D sources, attenuation, listener, velocity (Doppler) | A dungeon with no sound is a demo |
| **Compressed textures + mipmaps** | `src/texture/` — KTX2, ASTC/BC1/BC3/ETC2 transcode, `mipmap.dart` | RESEARCH.md §7 records that this channel has no mips at all. They built the chain themselves. Ours minification-aliases and we have no prefiltered specular |
| **Web** | `src/gpu/web/` — a complete second backend | We are macOS/Impeller-only in practice |

### Visible quality gap

| Missing | Theirs |
|---|---|
| Image-based lighting, environment/skybox, sky bake, spherical harmonics | `src/material/environment.dart`, `src/render/env_prefilter.dart`, `sh_composite.dart`, `sky_bake.dart` |
| SSAO | `src/render/ssao_pass.dart` |
| Screen-space reflections that work | `src/render/ssr_pass.dart` — ours is written, wrong (front-most depth only), and off |
| Depth of field, god rays, FXAA, auto-exposure | `dof_pass.dart`, `god_rays.dart`, `fxaa_pass.dart`, `auto_exposure_pass.dart` |
| Depth prepass, light culling | `depth_prepass.dart`, `light_culling.dart` |
| Instancing | `src/instanced_mesh.dart`, `render/instance_batching.dart` — we redraw |

### Scale and tooling

Gaussian splats, a scene file format with lazy subtrees and streaming, hot
reload of materials, texture atlasing, accessibility semantics, Flutter widgets
rendered into 3D, selection outlines, trails, sprites, memory reports, render
profiling.

## 4. Strategy: the race not to run

### The premise to reject

`flutter_scene` is written by the author of `flutter_gpu` itself. They are
closer to the platform than we will ever be — engine capabilities land there
first — and they are four times our size. **Competing on breadth means being
permanently second while spending the whole budget on our weakest ground.**

Getting ahead requires changing the axis, not running faster on theirs.

### The axis: dynamic local light

This is the one place they are *structurally absent* rather than merely behind:

- point-light shadows: none (`PointLight` has no `castsShadow` at all);
- particles as a light source: none (no mention of light in any particle file);
- volumetric light: **directional only** — `god_rays.dart` marches the cascaded
  shadow map and documents itself as requiring a shadow-casting
  `DirectionalLight`, "skipped otherwise".

And it is where we already lead. The point that matters: these are not three
features but **one foundation and three things built on it**. The cube atlas is
the foundation, and they do not have it. Until they build it, none of the steps
below are available to them at any price.

### The steps

Each reuses the atlas, so each one raises the cost of catching up rather than
just adding to a list.

| # | Step | Rough effort | What it buys |
|---|---|---|---|
| 1 | **Many shadowed lights.** Slot allocator replacing the hard four: lights sorted by screen size, slots by size, a light keeps its slot across frames, bakes amortised at one per frame. PlayCanvas's model, already read | **1–2 weeks** — atlas, slot table and static/dynamic split all exist; the new work is selection and slot persistence | Dozens of shadowed torches instead of four. Their clustered `light_culling.dart` cannot substitute: clustering without point shadows still leaves the point lights shadowless |
| 2 | **Shadow quality.** Take their spot filtering — rotated Poisson, `ShadowCasterFaces`, split depth/normal bias — then PCSS so a torch's shadow softens with distance | **1–2 weeks** — mostly shader and parameters; PCSS adds a blocker-search tap | Converts "we have point shadows and they do not" into "our point shadows are good", which is the far harder claim to catch |
| 3 | **Volumetric light from a torch.** Ray march sampling the same cube atlas: dusty shafts, correctly occluded | **2–4 weeks** — new pass, dithered march, half-res plus upsample for cost | The visual signature. Uncopyable without steps 0–1 first; their god rays are structurally sun-only |
| 4 | **Baked interior light.** Lightmaps rather than probes — see §6: PlayCanvas bakes them at **runtime**, so there is no asset pipeline or editor to build first | **3–6 weeks**, revised down from 4–8: the design is readable rather than inventable, and runtime baking removes the tooling half of the job | Their IBL is environment lighting, which is to say outdoors. An interior needs this or a PBR render never looks finished |
| 5 | **Area lights (LTC).** A torch is a small glowing volume, not a point | **1–2 weeks** — LTC is table-driven; PlayCanvas ships the tables | Soft falloff and a correctly stretched highlight. With light-emitting particles already here, it is the natural end of the same thread. They have punctual lights only |

Estimates are rough — call them ±50% — and assume one engineer who already
knows this code. They are sized against what is already here, not against a
green field.

### Deliberately not doing

- **Web.** Large, they have it, and a dungeon does not need it.
- **Our own physics and audio.** These are disqualifiers — no game ships without
  them — but writing them spends the differentiation budget on ground where
  there is none to gain. Integrate instead: **physics 2–4 weeks, audio 1–3
  weeks** to bind and wire, against months to author.
- **Material DSL, Gaussian splats, a scene format.** Catch-up moves by
  definition.

### The one breadth item we still have to take

**Mipmaps and a compressed texture format** — 3–6 weeks, with an unknown to
resolve first. Everything minification-aliases without them, and prefiltered
specular (hence step 4) is gated on them. RESEARCH.md §7 records that this
channel has no mip chain at all, yet they ship `mipmap.dart`, `mipmap_async.dart`
and transcoders for ASTC/BC1/BC3/ETC2. **Read how they did it before planning
the work** — it could be much cheaper or much dearer than it looks, and that
answer changes the order of everything after it.

### Positioning

Not "a 3D engine for Flutter" — that fight is lost — but **an engine for games
with dynamic light in enclosed spaces**. We are first there and the gap widens
on its own.

One asset worth naming: we have **a real game driving the engine**.
`flutter_scene` is an engine in search of games. Every feature here is checked
against a product, which is how three defects surfaced in a single sitting.

## 5. State of the shadow work

Done on this branch, in order: the atlas fills all four rows (one pass, one
clear); the golden that claimed to cover point shadows was recording the
directional map and now covers the atlas; a second golden gives four lights a
row each; the sample is held half a texel inside its tile so a bilinear tap
cannot cross into the next face; the `PointShadow` block is no longer bound to
Unlit, which kept none of it and failed the bind.

A note on how all four hid: the goldens were run only for the scenes judged
affected. Every one of these was found by running the whole suite once.

## 6. What PlayCanvas has that neither of us does

A third engine is worth reading precisely where the two of us agree by
omission — a gap both have is more likely to be an unsolved problem than a
solved one nobody needed. Checked against `playcanvas/engine` `main` and the
`flutter_scene` tree; every key below returns **nothing at all** on their side.

| From PlayCanvas | Size there | flutter_scene | Worth to us |
|---|---|---|---|
| **Runtime lightmapper** — `src/framework/lightmapper/`: direct and ambient bake, seam dilation, filters | 20 files | none | **Highest.** This is step 4, with a working design to read instead of invent. Baking at runtime is the part that matters: no asset pipeline and no editor have to exist first |
| **Anim state graph** — `src/framework/anim/`: 1D / 2D-cartesian / 2D-directional / direct blend trees, transitions, layers, masks | 29 files | see below | The practical gap for any game with a character |
| **Area lights (LTC)** — `src/scene/area-light-luts.js` | tables shipped | punctual only | Step 5. A torch is a small glowing volume, and it reads as one |
| **Morph targets** — `morph-target.js`, `morph-instance.js`, shader chunks | 7 files | none | Cheap, and it stops a silent loss: glTF carries morph targets, so without support a model imports with its expressions quietly gone |
| **Gizmos** — `src/extras/gizmo/`: translate, rotate, scale, with shapes and shaders | 18 files | none | Only if in-app authoring is ever decided on — but then it is weeks of work already done |
| **Static batching** — `src/scene/batching/`: merges the geometry of *different* meshes | 8 files | instancing only | When draw calls become the limit. Their `instance_batching.dart` groups draws sharing one geometry and material; a room of a hundred distinct props does not instance, but it does merge |

**On animation, a correction worth keeping.** `flutter_scene` *does* blend:
clips carry weights, the player normalises them and blends into the bound
nodes. What it has no layer for is the controller above that — states,
parameter-driven transitions, blend trees, per-bone masks. The difference is
between crossfading two clips by hand and "locomotion blends on movement speed
while the upper body plays its own clip through a mask".

### Ordering

- **On our axis, take now:** the lightmapper and area lights. Both strengthen
  exactly where we already lead, and both are absent from the competitor.
- **Take when the game needs it:** the anim state graph, once a character
  exists; morph targets, which are cheap and stop data disappearing on import.
- **Later or never:** gizmos, tied to the editor decision; static batching, once
  draw calls are measured to be the limit and not before.
