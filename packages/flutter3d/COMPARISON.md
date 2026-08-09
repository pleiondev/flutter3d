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

## 4. The plan

Ordered so that each stage is defensible on its own, and so the thing we lead
on stays led.

**Stage 0 — finish and defend the shadow lead.** The atlas now fills all four
rows (`cube-shadow-many`). Next: per-frame caster selection by relevance so
four is a limit on simultaneity rather than on the level, with the bake keyed
on the light rather than the atlas row. Then take their spot-shadow filtering —
rotated Poisson, `ShadowCasterFaces`, split depth/normal bias — and apply it to
our cube faces. That converts "we have point shadows and they do not" into "our
point shadows are good", which is the harder claim to catch up to.

**Stage 1 — the two absences that stop a game shipping.** Physics first, since
a bug is already open against its absence; audio second. Neither needs to be
written from scratch — both are areas where taking the shape of their API and
implementing against it is the fast path.

**Stage 2 — texture pipeline.** Mipmaps and a compressed format. This is the
single largest quality-per-effort item on the list: it fixes minification
aliasing everywhere at once and unlocks prefiltered specular, which is the
prerequisite for IBL.

**Stage 3 — IBL and environment.** Depends on stage 2. This is the biggest
purely visual gap; a PBR renderer without it never looks finished.

**Stage 4 — the post stack, cheapest first.** FXAA, then auto-exposure, then
SSAO. Fix SSR with a view-space test rather than the depth-space one that puts
highlights through walls.

**Stage 5 — architecture.** Instancing and a depth prepass, and by then the
plugin seam will want to become a render graph.

Web and Gaussian splats are deliberately not on this list. Both are large, and
neither serves a dungeon.

## 5. One thing to copy immediately

Their atlas insets each tile's scissor by `4 / atlasResolution` so a bilinear
tap at a tile edge cannot reach into its neighbour (this is PlayCanvas's trick
too). Our cube atlas has no such inset and samples with a plain `texture()`
fetch, so every face boundary in the atlas can read a neighbouring face's
distance. It is a small, contained shader change and it is a real defect today.
