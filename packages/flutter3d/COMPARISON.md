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
at all: physics, a web backend, compressed textures, mipmaps, IBL, and a
post-processing stack several effects deep. A comparison that put us ahead on
breadth would be a comparison of the wrong thing.

**But none of it runs on the stable channel.** Their README states the
requirement plainly, and it reframes every row below: breadth you cannot pin a
toolchain to is not the same kind of asset as breadth you can. See §4.

**What we have instead is depth in one direction they have not gone**, and it
is not a small one: we shadow every light type, they shadow two of three. For a
dungeon — a torch-lit interior where the point light *is* the lighting — that
single gap is the difference between a lit room and a lit room that looks
correct. This document is organised around defending that lead and closing the
rest.

## 1. Where we are genuinely ahead

| Capability | flutter3d | flutter_scene | How this was checked |
|---|---|---|---|
| **Runs on the stable channel** | **Yes.** Flutter 3.44.6 stable, no channel switch and no experimental flags. `flutter_gpu` ships inside the stable SDK at `bin/cache/pkg/flutter_gpu` (RESEARCH.md §4), and `tool/build_shaders.sh` calls `impellerc` directly rather than going through Native Assets | **No.** Their README: Flutter GPU "hasn't shipped to the stable channel yet, so Flutter Scene requires the Flutter master channel", specifically a build from 2026-06-09 or later. Their `pubspec.yaml` lower bound says stable only so pub.dev can score the package, and they say so — it is "looser than the real requirement". Plus a one-time `flutter config --enable-dart-data-assets` | their README §Requirements, lines 81 and 83 |
| **Point-light shadows** | **Yes.** Cube atlas, six 90° faces per light, four lights per frame, one pass | **No — not at any quality.** `PointLight` takes `intensity`, `range`, `falloffExponent` and nothing else; there is no `castsShadow` on it | Said outright in their own README: "Directional, point, and spot lights. **Directional and spot lights cast shadows**" (line 90), and confirmed in `src/light.dart:387` and `render/punctual_lights.dart`, which carries `spotShadow*` fields and no point equivalent. Ours: `cube-shadow`, `cube-shadow-lit`, `cube-shadow-many` goldens |
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
| **Physics** | `src/physics/` is the engine-side API; the backends are **separate published packages**, `flutter_scene_rapier` (prebuilt native binaries and a wasm module) and `flutter_scene_box3d` | We have a ground probe that lets a passenger sink into a moving platform. That is a symptom of not having this. Note the shape of their answer — an integration, not an implementation. It is the right shape and we should copy it |
| **Audio** | `src/audio/` exists in the engine, but **no backend is published**: `flutter_scene_soloud` and `flutter_scene_fmod` are both marked "Not yet published" in their README | Smaller gap than it looks — their users cannot have this today either. A dungeon still needs sound |
| **Compressed textures + mipmaps** | `src/texture/` — KTX2, ASTC/BC1/BC3/ETC2 transcode, `mipmap.dart` | The catch is in §4: their mip chain is what **forces them onto master**, since render-to-mip-level landed there on 2026-06-09. Copying their route costs us the stable channel, which is the more valuable of the two |
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
  weeks** to bind and wire, against months to author. They reached the same
  conclusion: their physics is `flutter_scene_rapier` / `flutter_scene_box3d`
  as separate packages, and their audio backends (SoLoud, FMOD) are the same
  shape — still unpublished, so on audio nobody has shipped anything yet.
- **Material DSL, Gaussian splats, a scene format.** Catch-up moves by
  definition.

### Mipmaps: the question that turned out to be a trap

This was written up as "the one breadth item we have to take — read how they did
it first". Reading it changed the answer.

How they did it is **leave the stable channel**. Their README names the date:
0.19.0 needs a master build from 2026-06-09 or later, "which is when
render-to-mip-level Flutter GPU support landed". The mip chain is not a thing
they built around the platform; it is the thing that put them on master.

So the item is not "3–6 weeks of texture work". It is a choice:

1. **Mips their way** — move to master, gain the texture pipeline, lose stable.
2. **Mips the hard way** — a chain as separate textures with explicit LOD
   selection in the shader. Unknown cost, no reference implementation, and
   worth a spike before it is worth an estimate.
3. **No mips** — accept minification aliasing, mitigate with texture authoring
   and anisotropy where the sampler allows, and give up prefiltered specular.
   Note that step 4's lightmaps do **not** need it, which is a point in their
   favour over probes.

**Recommend 3 now and a spike on 2**, and do not take 1. Everything below says
why.

### Positioning

Not "a 3D engine for Flutter" — that fight is lost — but **an engine for games
with dynamic light in enclosed spaces, on stable Flutter**.

That last clause may be the most valuable thing in this document, and it was
found in their README rather than their source. They cannot ship on stable:
Flutter GPU is not there yet, and their own text calls the stable lower bound in
their `pubspec.yaml` "looser than the real requirement" — present so pub.dev can
score the package. Anyone shipping a product reads "requires the master channel"
as "cannot pin a toolchain", and for a studio that is close to disqualifying.

We are on 3.44.6 stable with no channel switch and no experimental flags, and
that is not luck: `tool/build_shaders.sh` calls `impellerc` directly precisely
because the packaged path wanted Native Assets, and we use no mips at all. The
same two decisions that make us smaller are what make us shippable today.

It follows that **staying on stable is a feature to defend, not an accident to
outgrow**. Anything that would force a channel move — mips their way, most of
all — has to pay for the loss, and the price is high.

Two more assets worth naming. We have **a real game driving the engine**;
`flutter_scene` is an engine in search of games, and every feature here is
checked against a product, which is how four defects surfaced in a single
sitting. And they are **pre-1.0 with breaking changes in minor releases**, by
their own statement — stability is ours to claim if we choose to.

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

## 7. glint_engine, the third entrant

`glint_engine` 0.2.0 (`kiddo4/glint`), published 2026-07-23. This is what the
handoff had recorded from memory as "glide-engine" — a name that returns nothing
anywhere, which is why the first check reported the project did not exist.

**A measurement correction, since it nearly became a false accusation.** A first
pass counted 16 files and 95 KB and made the feature list below look impossible
for one week's work. The path filter had missed the repository's root `lib/`.
The real figures: **71 `.dart` files, 640 KB, of which `lib/` is 27 files and
429 KB** — roughly 11k lines, the same order as ours. It is a real engine.
Structured monolithically, though: `glb.dart` at 55 KB, `game_view.dart` at 53
KB, and the whole renderer in `first_light.dart` at 36 KB.

### On our axis it is the weakest of the three

| | flutter3d | flutter_scene | glint_engine |
|---|---|---|---|
| Directional shadows | yes | yes, cascaded | yes |
| Spot shadows | no | yes | **no** |
| Point shadows | **yes** | no | no |

Their game view offers "translucent blob shadows" besides — a decal under the
model, which is what an engine reaches for when its shadow system does not cover
things that move.

### Where it is behind on fundamentals

- **No normal or ORM maps.** Their own FAQ, under "Model renders but looks
  wrong": Glint reads base-colour textures and factors, "but normal/ORM maps and
  Draco compression are not supported yet". For a PBR renderer that is more
  basic than anything on our gap list; our normal mapping is pinned by a golden.
- Embedded textures decoded at 1024 px maximum, to protect mobile memory.
- No morph targets, no web, no Windows, no Linux. On Android **emulators the app
  aborts natively** — Impeller falls back to OpenGLES, which Flutter GPU does
  not support, and they note there is no Dart-level way to detect it.
- Depends on `flutter_gpu_shaders` and build hooks, so it wants the experimental
  Native Assets feature — the one `tool/build_shaders.sh` exists to avoid. On
  "runs on stable with no experimental flags" we are ahead of both engines.

### Where it is ahead, and worth reading

- **Animation state machines** — additive and override layers, bone masks,
  events, root motion, crossfades. This is exactly the gap §6 attributed to
  PlayCanvas alone, and it is closed here in Dart, inside a 30 KB file. Useful
  evidence that the feature is a fortnight, not a quarter.
- **Deterministic physics** — rollback snapshots, repeatable replay, state
  digests, a mixed stress harness.
- **Shader graphs** — typed JSON with cycle and type validation, compiled
  offline through Impeller.
- **A diagnostics overlay** — FPS, frame time, draw calls, triangles. Cheap, and
  we have nothing like it.

### What to conclude

Not a threat today: weaker than `flutter_scene` on our axis, missing normal
maps, narrower on platforms, and dormant — created 2026-07-17, last pushed
2026-07-24, 45 commits. Read it for the animation controller and the
diagnostics overlay, and note that between the three engines **nobody else
shadows a point light**.

## 8. The consolidated plan: best of three, and what "better" has to mean

### First, a definition, because the goal is unfalsifiable without one

"Better than all of them" cannot mean better on every axis. `flutter_scene` is
four times our size and written by the author of the platform layer;
`glint_engine` shipped a physics stack with ragdolls and vehicles that we have
no answer to at all. Matching every row of three feature tables is how a small
engine spends five years arriving second.

It can mean this, which is checkable:

> For a game with dynamic light in enclosed spaces, on stable Flutter,
> flutter3d is the best choice available — and on the lighting itself, no other
> Flutter engine is close.

Four claims fall out of that, each either true today or reachable below:

1. **More shadowed point lights than anyone.** Trivially first: the other two
   have none. The bar to hold is *many*, not *four*.
2. **The only Flutter engine with volumetric light from a local source.** Their
   god rays are sun-only by construction.
3. **The only one that runs on a pinned stable toolchain.**
4. **Not embarrassing anywhere else** — animation, physics, audio and
   diagnostics good enough that nobody rejects the engine over them.

Claims 1–3 are the moat and get built. Claim 4 is a floor, and the cheapest way
to reach a floor is to take what three engines have already proven.

### What to take, from whom, in order

**Phase A — the moat.** Nothing here exists elsewhere; every item reuses the
cube atlas.

| | Take | From | Effort |
|---|---|---|---|
| A1 | Shadow-atlas allocator: slots by size class, lights by screen size, a light keeps its slot across frames, `NONE`/`THISFRAME`/`REALTIME` update modes | PlayCanvas | 1–2 w |
| A2 | Shadow filtering: rotated Poisson, `ShadowCasterFaces`, split depth/normal bias — then PCSS | flutter_scene | 1–2 w |
| A3 | Volumetric light marched against the cube atlas | nobody — ours | 2–4 w |
| A4 | Runtime lightmapper: direct + ambient bake, seam dilation, filters | PlayCanvas | 3–6 w |
| A5 | Area lights (LTC), because a torch is a volume | PlayCanvas | 1–2 w |

Also from `flutter_scene`'s `DirectionalShadowCache`, applied to A1 rather than
copied wholesale: **amortise re-bakes at a bounded count per frame, and key the
cache on a content signature.** That is the part that stops a hitch when several
lights enter a room at once, and it is the failure mode A1 walks into otherwise.

**Phase B — the floor, by integration and never by implementation.**

| | Take | From | Effort |
|---|---|---|---|
| B1 | Physics as a separate backend package, Rapier first | flutter_scene's *shape* (`flutter_scene_rapier`); `glint_engine` proves Box3D works too | 2–4 w |
| B2 | Audio backend, SoLoud or miniaudio | `glint_engine` — theirs is published and working, while `flutter_scene`'s is not | 1–3 w |

Note the asymmetry worth exploiting: on audio, `flutter_scene` has engine code
and **no published backend**. Shipping audio is a place we can arrive first.

**Phase C — cheap, and disproportionate.**

| | Take | From | Effort |
|---|---|---|---|
| C1 | Diagnostics overlay: FPS, frame time, draw calls, triangles | `glint_engine` | days |
| C2 | Morph targets | PlayCanvas | ~1 w — stops glTF expressions vanishing silently on import |
| C3 | Animation state machine: layers, bone masks, events, root motion | `glint_engine` (30 KB of Dart); PlayCanvas for the blend-tree shapes | ~2 w |
| C4 | Instancing | flutter_scene | when draw calls are *measured* to be the limit |

**Phase D — architecture, when it hurts and not before.** The render graph with
a blackboard (flutter_scene) to replace the plugin seam; static batching
(PlayCanvas `batch-manager`) for rooms of distinct props that will never
instance; depth prepass and light culling (flutter_scene).

### What we refuse, and why refusing is the plan

- **Web** — a second backend, and a dungeon does not need one.
- **Mips their way** — costs the stable channel, which is claim 3. Go without,
  and spike a manual chain. Lightmaps do not need them.
- **Material DSL, Gaussian splats, a scene format, gizmos without an editor
  decision** — catch-up moves, each one a quarter spent arriving second.

Every refusal above is a quarter bought for Phase A. That is the whole trade,
and the reason the plan can be finished by a small team: **A+B+C is roughly two
to four months, and it is what makes all four claims true at once.**
