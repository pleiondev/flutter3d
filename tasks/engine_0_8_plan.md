# flutter3d 0.8 — implementation plan

Date: 2026-09-23. Branch `hal-contract-0.8` at `6170558f`. Companion to
[`0.8-engine-roadmap.md`](0.8-engine-roadmap.md), which says *what* and *why*;
this says *where*, *in which order* and *how it is proved*. Item ids (H1, R2…)
are the roadmap's and the synapse project's.

## Overview

Fifty-three buildable items in phases 0–7 and 10, six more waiting on an
upstream trigger (Phase 8) and four lab experiments (Phase 9), grouped by
dependency. Phase 0 builds
the four pieces of infrastructure that more than one item stands on
(multi-frame goldens, data tables, a previous-frame store, a sampler budget),
so no item invents its own. Every rendering item follows one of three recipes
in §Recipes rather than restating them. Every new effect is off by default,
has a golden scene in all four reference sets, and a Dart mirror in
`flutter3d_cpu`.

## Current state — what the plan rests on

Facts the research passes read in the tree (paths under `packages/`):

- **Uniforms are name maps end to end.** `PassEncoder.bindUniformBlock(shader,
  block, Map<String, Float32List>)` (`flutter3d_hardware/lib/src/command_encoder.dart:310`);
  27 call sites in `flutter3d_core/lib` build the maps inline; 28 block types
  across 56 shader files. Impeller resolves member offsets through
  `UniformSlot.getMemberOffsetInBytes`, WebGL through `UNIFORM_OFFSET`, WebGPU
  through a generated table with std140 offsets already cross-checked against
  glslang (`flutter3d_webgpu/lib/src/wgsl_section.dart:174`), the CPU backend
  keeps the map and its stages read by name.
- **`tool/stage_bindings.dart`** already runs impellerc with
  `--reflection-json` per stage and keeps only block and sampler names; the
  JSON carries member offsets it ignores.
- **Timing exists per graph node on the CPU** (`renderer.dart:3305–3347` →
  `FrameResult.passes`), with `Timeline` spans in the scene, shadow and pick
  passes. No pass label, no GPU time.
- **`Recorded`** (`flutter3d_hardware/lib/src/testing_recorded.dart`) has 20
  command variants but carries no vertex bytes, no device-level calls and no
  pass boundaries.
- **No previous-frame state anywhere.** `_frameIndex` (`renderer.dart:515`) is
  private and only indexes the release ring; skinning is on the GPU from
  `Skeleton.matrices` (64 joints); morphs through `MorphState`; instances
  through `InstancedMeshNode.instanceBytes`. Change keys exist:
  `worldVersion`, `poseVersion`, `MorphState.version`, `dataVersion`.
- **`renderScale` shrinks every target; the presenter stretches.** No engine
  upscale (`render_settings.dart:895–911`).
- **Composite already has AgX** (codes 3 and 5) and the FXAA pass already has a
  CAS-style sharpen (`AntiAliasSettings.sharpen`). The grading LUT is 8-bit,
  sampled after the tone map, and supplied by the application.
- **The sun already has a crude PCSS** (`shadow.glsl:138–160`, five taps).
  Every shadow atlas is `hdrColorFormat` (rgba16f); nothing renders to
  rgba32f.
- **No LUT or noise texture ships.** Data textures reach all four backends as
  `createTextureFromPixels` from Dart bytes (the light list does this).
- **`SurfaceMaterial` is listed field by field in six constructors**; `.f3d`
  materials are a fixed 132-byte record, extended by new sections that old
  readers skip.
- **`RenderList.consider` is the only culling hook**; `SceneBvh._visit` is
  private; `VisibilityCuller` works by toggling `visible` from outside.
- **`LevelLoader`** (`flutter3d_app/lib/src/level/level_loader.dart`) imports
  Flutter only for `rootBundle`, but lives in a Flutter package, and brushes
  are batched per material, so a pixel cannot name a brush.
- **The dungeon generators are Python** (`apps/flutter3d_demo_dungeon/tool/cryptkit.py`)
  and use no seed.

Two corrections to the roadmap that this plan adopts: `gltf_test.dart` has
**two** required-extension refusals, not four; and `flutter3d_build convert`
writes `.f3d`, whose LOD section is its own (§C5) — the glTF writer already
emits `MSFT_lod`.

## Recipes

Each item below names its recipe instead of repeating it.

### Recipe P — a new fragment pass

1. GLSL in `flutter3d_shaders/shaders/post/<name>.frag` against
   `fullscreen.vert`; block named by struct type.
2. Manifest entry in `flutter3d.shaderbundle.json`; name in `kRequiredShaders`
   (`flutter3d_shaders/lib/flutter3d_shaders.dart:26–76`); pair with
   `FullscreenVertex` in `flutter3d_conformance/lib/src/shader_link_checks.dart:101–117`.
3. Regenerate `stage_bindings.dart` (and, after H1, `uniform_blocks.dart`),
   `flutter3d_webgl/lib/engine_shaders.dart`,
   `flutter3d_webgpu/lib/engine_shaders.dart`; rebuild the Impeller bundle.
4. Dart stage in `flutter3d_cpu/lib/src/cpu_shaders_<area>.dart`, registered
   in `cpu_shaders_builtin.dart`.
5. Settings class in `render_settings.dart` (off by default) plus a field and
   `copyWith` on `RenderSettings`.
6. Shader handle on `Renderer` (`renderer.dart:133–156`, resolved in
   `Renderer.create`), encode function in `renderer_post_pass.dart` through
   `drawFullscreen`, node in `renderer_frame_nodes.dart`, registered in
   `_compileFrameGraph` (`renderer.dart:1891–2045`) at its place in the chain,
   resource id in `frame_plan.dart`, descriptor in `render()`.

### Recipe M — a new material input

The ten-hop path the research traced for a PBR parameter: glTF
`extensionsMap` (`gltf_loader_materials.dart:120`) → `SurfaceMaterial` field
plus the six field-by-field constructors → glTF writer `extensions`
(`gltf_writer_materials.dart:106`) → `.fmat` keys (`fmat.dart`) → a new `.f3d`
section 22 `materialExtensions` (per-material extra records) →
`bindSurfaceMaterial`/`bindMaterial` → `Material` field and `copy()` →
`FragInfo` append (never reorder; `surface.glsl:121`) packed in
`renderer_mesh_encode.dart:545` → GLSL → `PbrShader` in
`flutter3d_cpu/lib/src/cpu_shaders_lit.dart`. A round-trip test through glTF,
`.fmat` and `.f3d` holds the field.

### Recipe G — a golden scene

Scene in `flutter3d/example/lib/src/spike/golden_scenes.dart` (geometry in
`golden_extras.dart` if new), recorded with `flutter3d/tool/golden.sh --update`
(Impeller and `--cpu`) and `flutter3d_webgl/tool/golden_web.sh --update` (WebGL
and `--backend=webgpu`); a budget in each of the three `cross_backend_test.dart`
maps; the test counts `tool/structure.dart` holds (README, ARCHITECTURE.md,
`site/content/reference/testing.md`) updated in the same commit.

## Design and steps

### Phase 0 — shared infrastructure

**G0. Multi-frame golden scenes.** `GoldenScene` gains `frames` (default 1)
and an optional `cameraAt(int frame)`; the harness renders frames `0..n-1`
through one `Renderer` and captures the last. Jitter, noise and history are
functions of `Renderer.frameIndex` only, so a sequence is as deterministic as a
still. Files: `golden_scene.dart`, `golden.sh`, `golden_web.py`,
`flutter3d/example/lib/main.dart` (the golden runner). Test: an existing scene
at `frames: 3` equals its one-frame golden byte for byte.

**G1. Engine data tables.** `flutter3d_core/lib/src/engine/render/engine_tables.dart`:
`EngineTables.of(device)` lazily uploads Dart-const tables with
`createTextureFromPixels` and caches them per device. First users: blue noise
(R3), LTC (L7), sheen albedo scaling (M2). Tables live as generated Dart files
under `engine/render/tables/` written by `flutter3d_core/tool/make_tables.dart`,
so the CPU backend samples the same bytes. Test: each table's hash is pinned.

**G2. `FrameHistory`.** `engine/render/frame_history.dart`: a
renderer-owned store keyed by `MeshNode` (an `Expando`) holding last frame's
world matrix, a copy of the joint palette, the morph weights and the instance
bytes, refreshed after each frame only for nodes whose change key moved, plus
last frame's per-view unjittered `viewProjection`. `Renderer.frameIndex`
becomes public. Test: a node moved between two frames reports the old matrix;
an unmoved one allocates nothing (`FrameHistory.allocations`).

**G3. Sampler budget.** WebGL2 guarantees 16 samplers per stage; PBR binds 11
today. A test over `stageBindings` fails any stage above 16, and every item
that adds a sampler to lit stages packs rather than appends: the irradiance
atlas is one texture (L3), clusters one (L6), LTC one (L7), material
extensions two packed maps (M1–M3).

### Phase 1 — the contract (H1–H6)

**H1. Typed uniform blocks.**
- `flutter3d_impeller/tool/stage_bindings.dart` also reads each member's
  `name`, `offset`, `byte_length`, `array_elements` and type, and writes a
  second file, `flutter3d_shaders/lib/uniform_blocks.dart`: per block a
  `final class FragInfoBlock` with one preallocated `Float32List` per member,
  typed setters (`set cameraPosition(Vector3)`, `lightColor(int i, …)`), and a
  `members` getter returning the `Map<String, Float32List>` the contract
  already takes. The HAL signature does not change; no backend changes.
- The renderer's 27 call sites move to the generated classes one pass at a
  time (mesh encode, shadow, post, pick, probe, overlays, contributors); the
  scratch `Float32List` fields on `Renderer` (`renderer.dart:556–587`,
  `781–1094`) go with them.
- `FullscreenEffect.uniforms` and `PassContribution.uniforms` keep their map
  type for applications; a `UniformBlock` interface lets them pass a
  generated block too.
- Tests: `uniform_blocks_test.dart` compares every generated offset with the
  WebGPU table in `flutter3d_webgpu/lib/engine_shaders.dart`; a
  `FakeBackend` test renders the golden scenes and fails any bind that omits
  a member the reflection keeps (`RecordedUniformBlock` already records the
  names); the existing freshness test in `stage_bindings_test.dart` covers the
  new file.
- Commits: generator; mesh-encode blocks; shadow and probe blocks; post
  blocks; the rest and removal of the scratch fields.

**H2. Profiler by pass.**
- `RenderPassDescriptor` gains `String? label`; the 11 `beginRenderPass`
  calls pass the node name. WebGPU forwards it to `beginRenderPass({label})`
  and `pushDebugGroup`; the others ignore it.
- `GraphicsDevice.supportsGpuTimestamps` (false on Impeller, CPU, WebGL
  unless `EXT_disjoint_timer_query_webgl2`; true on WebGPU with
  `timestamp-query` granted). WebGPU writes `timestampWrites` per labelled
  pass, resolves in `onFrameComplete`, and reports through a new
  `FrameTimings` callback a frame or two late.
- `FramePass` gains `int? gpuMicros`; the CPU span already exists.
- A `Timeline` span per node, named by the node, replaces the scattered
  spans.
- Tests: `FakeBackend` sees every pass labelled; WebGPU browser test gets a
  non-null `gpuMicros` or declines.
- Commits: label; spans; WebGPU timestamps.

**H3. `.f3dtrace`.**
- `flutter3d_hardware/lib/src/trace/`: `RecordingDevice(GraphicsDevice inner)`
  decorates any device and records device calls (uploads with their bytes,
  textures with their pixels, pipelines by stage name, pass descriptors,
  submits) plus the `Recorded` stream per pass, with member arrays copied.
  `Recorded` gains `RecordedPassBegin`, `RecordedSubmit`,
  `RecordedVertexData(bytes)`.
- `TraceWriter`/`TraceReader`: a JSON header plus a blob section.
- `replayTrace(Trace, GraphicsDevice)` re-issues it against any backend.
- Tests: record a golden scene on the CPU device, replay on a fresh CPU
  device, compare frames byte for byte; replay in the WebGL browser suite.
- Commits: recording decorator; file format; replay.

**H4. Fuzzing the backends.**
- `flutter3d_conformance/lib/src/fuzz/`: `TraceGenerator(seed)` builds valid
  traces over the probe stages the conformance suite already ships
  (clears, viewports, scissors, blend, stencil, instanced draws,
  render-to-mip). Metamorphic transforms: split a draw, reorder draws that
  do not overlap, fold an identity into a matrix, insert a copy hop.
- Oracle: CPU against itself under a transform; CPU against each hardware
  backend within the conformance tolerance.
- Shrinking: delta debugging over the trace's commands.
- Runners: `dart test` for CPU (fixed seed set, 200 traces); the WebGL and
  WebGPU browser suites (50 traces); Impeller through
  `conformance_main.dart` behind a flag.
- A second arm feeds generated GLSL expressions through impellerc and naga
  and compares their evaluated output on a probe stage.
- Commits: generator; transforms and oracle; shrinker; per-backend runners;
  GLSL arm.

**H5. `FieldPass`.**
- `engine/render/field_pass.dart`: two targets of a spec, `step(kernel,
  bind)` draws a full-screen pass from `current` into the other and swaps;
  kernels are ordinary fragment stages; vertex stages read `current` by
  vertex texture fetch.
- Conformance, added to `shaderChecks`: render to `r16g16b16a16Float` and
  `r32g32b32a32Float` and read the value back through a vertex stage (the
  existing `checkFloatTextureUpload` covers upload only); NaN and denormal
  stay what they were written.
- Test consumer in the tree: a ping-pong decay kernel in the conformance
  suite; L4 is the engine's first.

**H6. Optional compute.**
- `flutter3d_hardware`: `supportsCompute`, `StorageBuffer`
  (`createStorageBuffer(bytes, {hostReadable})`), `ComputePipelineHandle`
  (`createComputePipeline(ShaderHandle)`), `ComputeEncoder`
  (`bindStorageBuffer`, `bindUniformBlock`, `dispatch(x, [y, z])`, `submit`)
  from `beginComputePass({label})`, `Future<ByteData> readBuffer(...)`.
  Impeller and WebGL answer false and throw `UnsupportedError` from the
  creators.
- WebGPU implements it over `createComputePipeline` and `mapAsync`; the
  toolchain accepts `"type": "compute"` in the manifest (`.comp` → glslang →
  naga → WGSL), reflecting storage bindings and workgroup size.
- CPU: `CpuStage.compute(CpuComputeShader)` run per invocation over a
  workgroup grid.
- Conformance: a `computeChecks` tier that declines when unsupported: a
  prefix sum over 1024 ints, read back.
- The shape follows flutter/flutter#188474 so Impeller becomes a mapping when
  #188480 lands.

### Phase 2 — the frame (R1–R3)

**R1. Jitter and motion vectors.**
- `AntiAliasSettings.temporal` (a `TemporalSettings`: enabled, sequence
  length 16, history weight, sharpen). Enabling it forces the surface buffer
  (TAA replaces the MSAA it turns off; `FrameResult.antiAliasing` says so).
- `JitteredProjection` beside `TiledProjection` (`projection.dart:360`) adds
  a Halton(2,3) sub-pixel offset from `frameIndex % 16`. The scene and sky
  draws use it; post passes, picking and debug lines keep the unjittered
  matrix, which the call sites listed in the research (`renderer_scene_pass.dart:165`,
  `renderer_pick_pass.dart:154`, `renderer_post_pass.dart:268/358/442/685`,
  `view_model_node.dart:124`) choose explicitly.
- Velocity target: `hdrColorFormat` (no `rg16f` in `TextureFormat`, and the
  enum mirrors flutter_gpu), resource `FrameResourceIds.velocity`.
- `CameraVelocity` pass (Recipe P): reconstructs from the surface buffer's
  view depth and `prevViewProjection · inverse(viewProjection)` from G2.
- `ObjectVelocity` pass for nodes G2 says moved: stages `VelocityVertex`,
  `VelocitySkinnedVertex`, `VelocityInstancedVertex` with a `PrevFrameInfo`
  block (previous mvp, previous joint palette as `PrevSkinInfo`, previous
  morph weights in `MorphInfo`'s shape) and a `Velocity` fragment stage;
  depth test `lessEqual`, no depth write, loading the camera velocity.
  Particles and the sky write zero.
- Tests: golden `velocity-shapes` (a rigid, a skinned and a morphed mesh
  moving over two frames, velocity encoded to colour); a VM test that a
  static camera and scene give zero velocity everywhere.
- Commits: frame index and jitter; camera velocity; object velocity.

**R2. TAAU and RCAS.**
- Two sizes: scene targets at `renderScale`, post chain from TAA on at
  output size. `_ensureTargets` (`renderer.dart:1188–1280`) splits into scene
  and output sets; bloom, composite, FXAA and the frame are output-sized when
  temporal is on, and exactly as today when it is off.
- `TemporalResolve` pass (Recipe P) after the scene and the screen-space
  effects, before bloom: nearest-depth 3×3 velocity, Catmull-Rom history,
  YCoCg variance clipping, luminance weighting, disocclusion by depth and
  velocity, reset on a camera cut (`RenderView` gains `cut`), history stored
  divided by exposure. History: two output-sized rgba16f textures the
  renderer owns, exposed through `keeps` like the cube atlases.
- Texture LOD bias `log2(renderScale) − 0.5` through `SamplerOptions` for
  material textures while temporal is on.
- RCAS: the FXAA pass's CAS sharpen becomes RCAS when temporal is on.
- Tests: goldens `taa-converge` (16 static frames against a CPU 16× jittered
  average within budget), `taa-railing` (thin geometry moving, frame 12) at
  scale 1.0 and 0.6; a VM test that temporal off leaves every golden's bytes
  unchanged.
- Commits: target split; resolve; history and exposure; LOD bias; RCAS.

**R3. Blue noise and temporal denoising.**
- Blue noise from G1: a 64×64×32 R8 table generated by void-and-cluster in
  `make_tables.dart` (our own, so no licence question), indexed by
  `frameIndex % 32`.
- SSAO, SSR and contact shadows take their rotation from it and add a
  reprojection step into a per-effect history (half-size for AO) using the
  R1 velocity; sample counts drop when temporal is on.
- Light shafts replace the fixed Bayer offset with the noise.
- Tests: golden `ao-temporal` (8 frames); the existing
  `ambient-occlusion-corner` and `screen-space-reflections` goldens unchanged
  with temporal off.

### Phase 3 — light (L1–L7)

**L1. Multiscatter GGX.** `RenderSettings.energyCompensation` (off). In
`pbr.frag` and `PbrShader`: `Ess = ab.x + ab.y` from `EnvBrdfApprox`,
`Favg = f0 + (1 − f0)/21`, ambient specular scaled by the Fdez-Agüera term,
direct specular by `1 + f0·(1/Ess − 1)`. Fix the CPU's `max(nDotV, 0)` in the
IBL path to the GLSL's clamped `n_dot_v` first, in its own commit, since it is
a divergence the new term would amplify. Golden `rough-metals` (a roughness
row of gold spheres).

**L2. ACES 2.0.** AgX already exists. What is missing is a scene-referred LUT
slot: `LookSettings.displayTransform` takes a float 3D LUT (rgba16f, 33³ as a
strip) sampled **instead of** the tone map, after exposure, through a log2
shaper (−10…+6 stops). `make_tables.dart` bakes ACES 2.0 SDR output (Rec.709,
100 nits) from a Dart port of the reference transform; `TonemapCurve.aces2`
selects it. Golden `tonemap-aces2` over the HDR test card scene.

**L3. The irradiance field per pixel.**
- Upload: `IrradianceField.toAtlas()` packs irradiance (10×10 tiles, rgb)
  and moments (18×18 tiles, rg) into **one** rgba16f texture, irradiance
  tiles above, moment tiles below, re-uploaded on `IrradianceField.version`.
- `lib/irradiance.glsl`: `SampleIrradiance(world, normal, view)` with
  bilinear taps inside a tile's gutter, trilinear × backface × Chebyshev
  weights and a normal and view bias. `IrradianceInfo` block (origin,
  spacing, counts, tile sizes, enabled). Lit models replace the hemisphere
  ambient with it when enabled; the sampler is bound to a black fallback
  otherwise.
- CPU: the same function over the uploaded atlas texture, not over
  `IrradianceField.sample` (which is nearest-texel and unbiased); that
  function stays as the bake-side reference.
- `_applyIrradiance` (`renderer_mesh_encode.dart:679–700`) is removed.
- Tests: `irradiance_bounce_test.dart` keeps its three assertions; golden
  `irradiance-room` (a red wall bleeding onto a floor across its width, which
  the per-object version cannot show).

**L4. Probes updated on the GPU.**
- `IrradianceField.gpuUpdates` (probes per frame, default 2, hysteresis
  0.9). A node `_IrradianceUpdateNode` after the shadow nodes: per scheduled
  probe, six 16² cube faces through `_captureProbeFace`
  (`renderer_probe_pass.dart:200`) into radiance, and six through the
  `ShadowDistance` stage into distance; then two `FieldPass` kernels,
  `IrradianceConvolve` and `MomentsConvolve`, write the probe's tiles blended
  with the previous atlas.
- Round-robin scheduling in the manner of `ShadowFaceScheduler`.
- Requires `supportsCubeTextures`; otherwise the field stays whatever was
  baked.
- Tests: after enough frames to visit every probe `k` times, the atlas agrees
  with a CPU `gather` of the same scene within a tolerance on the test room;
  a static scene converges (successive atlases stop changing).

**L5. GTAO, then SSIL.** Replace `ssao.frag`'s kernel with horizon search
over the surface buffer (two directions per pixel rotated by R3's noise,
cosine-weighted integral, multi-bounce fit) behind
`AmbientOcclusionSettings.method` (`ssao` stays the default). Then the
visibility-bitmask variant: 32 sectors, constant thickness, and the same
loop reading last frame's lit colour (an output-sized history the renderer
already keeps after R2) for indirect diffuse, added in composite before the
tone map. CPU mirrors in `cpu_shaders_ssao.dart`. Goldens `gtao-corner`,
`ssil-room`.

**L6. Clusters on the CPU.**
- `engine/render/light_clusters.dart`: a 16×9×24 grid, logarithmic depth
  slices, built per view from the frame's candidate table by sphere and cone
  against froxel bounds; reused buffers.
- One r32Float texture holds both halves: a header region (offset, count per
  cluster) and the index list after it.
- `ClusterInfo` block: grid size, depth slice parameters, screen size.
- In `surface.glsl`, `LightCount`/`SampleLight` take the cluster's list in
  place of the 24-row per-draw list when `RenderSettings.clusteredLights` is
  on; the eight shadowed slots stay in `FragInfo`.
- CPU mirror in `cpu_shaders_lighting.dart`.
- Tests: a builder unit test (a light lands in exactly the froxels it
  touches); golden `many-lights` (a floor under 64 lights, which saturates
  at 32 today); the existing light goldens unchanged with the setting off.

**L7. LTC.** Two 64×64 rgba32f tables (inverse matrix and magnitude/Fresnel)
generated into G1 from the published fits, packed into one 64×128 texture.
The area branch in `SampleLight` (`surface.glsl:486–532`) keeps its exact
form-factor diffuse and replaces the representative-point specular with the
LTC polygon integral; `ShadeLight` receives a flag telling it the specular
term is already integrated. CPU mirror in `cpu_shaders_lighting.dart`.
Golden `area-light-gloss` (a rectangle light over a glossy floor at three
roughnesses).

### Phase 4 — shadows and air (S1–S4)

**S1. Cached and scrolling cascades.** The directional atlas splits like the
cube atlases: a static atlas holding static casters and a per-frame atlas.
Each frame the per-frame atlas copies the static one (one full-screen blit per
tile) and draws only dynamic casters on top. The static atlas redraws a
cascade when its `_directionalBakeKey` changes — the key becomes per cascade —
and, when a texel-snapped centre moved by whole texels, **scrolls**: a blit of
the old tile at the offset plus a scissored draw of the strip that appeared.
Tests: `cascade_test.dart` extended to count static redraws while a camera
walks; golden `cascade-walk` (8 frames) equal to the same frames drawn
uncached.

**S2. EVSM.** `ShadowSettings.filter` (`pcf`, `pcss`, `evsm`). The depth
atlas stays as it is; a conversion pass writes `exp(±c·d)` moments into an
rgba32f atlas, then a separable blur and mips. That keeps S1's static and
dynamic combination on depth, where min works, and moves the non-combinable
step after it. New capability `supportsFloat32Filtering` (a device without
it refuses `evsm` in `FrameResult.shadowsDenied`), with a conformance check.
Golden `evsm-soft`.

**S3. PCSS for the sun, refined.** The existing five-tap search
(`shadow.glsl:138–160`) becomes 16 blocker and 16 filter taps on a Vogel
disk rotated by R3's noise, with blocker distance converted per cascade from
depth units to world units. Golden `sun-contact-hardening`.

**S4. Volumetric fog.** `VolumetricFogSettings` (density, height falloff,
anisotropy, steps). A half-resolution raymarch grown from `light_shafts.frag`
through the cascade atlas and, when L6 is on, the clusters' point lights;
start offset from R3's noise; a depth-aware upsample pass; the result
composited before the tone map. Golden `fog-torches` (8 frames).

### Phase 5 — content (M1–M4, C1–C5)

**M1–M3. Material extensions.**
- A new lighting model `pbrLayered` (`PbrLayered` stage, a second
  permutation of `pbr.frag` under `#define F3D_LAYERED`) so plain PBR keeps
  its cost and its samplers. A material with any extension takes it.
- Textures are packed at load into two maps (G3): *coat map* (R clearcoat, G
  clearcoat roughness, B transmission, A thickness) and *sheen map* (RGB sheen
  colour, A sheen roughness); the specular colour texture and the clearcoat
  normal are read in 0.8 only as factors, and the loader says so in
  `warnings`.
- M1: `ior`, `specular` (F0 and its tint), `clearcoat` (a second GGX lobe
  with its own roughness on the geometric normal).
- M2: `sheen` (Charlie distribution, albedo-scaling table from G1),
  `anisotropy` (tangent-space direction and strength; tangents exist).
- M3: `transmission`, `volume`, then `dispersion`, `iridescence`. The scene
  pass splits into an opaque pass and a transparent pass with a
  `SceneColourCopy` node between them that writes a mip chain
  (`supportsRenderToMip`, else a single level). Transmissive draws sample it
  at a roughness-chosen level through the thickness and attenuation.
- Each extension follows Recipe M and flips its refusal in
  `gltf_test.dart:758` to a load. Goldens per extension against the Khronos
  sample models' single-material spheres: `clearcoat-car-paint`,
  `sheen-fabric`, `anisotropy-disc`, `transmission-glass`.

**M4. Variants and animation pointer.**
- Variants: `ModelDocument.variants` (names) and per-primitive
  `variantMaterials`; `ModelInstance.selectVariant(name)`; written back by
  the glTF writer; `.f3d` section 23.
- Animation pointer: a `pointer` track kind resolved at load from its JSON
  pointer to a setter on `Material` (base colour, emissive strength,
  roughness, metallic, texture transform offset) or a light (colour,
  intensity); `.f3d` track section extension.
- Tests: glTF round trips; an animation golden sampled at three times.

**C1. Splats.**
- glTF: a primitive carrying `KHR_gaussian_splatting` decodes into a
  `SplatCloud` attached to its node (`ModelDocument.splats`), opacity linear,
  SH degree 0 used and higher degrees kept for later. The first commit checks
  the extension's ratification status and names the version it follows.
- Sorting: `splat_sort.dart`, a two-pass 8-bit counting sort over 16-bit
  quantised view depths in `Uint32List`s, identical on native and web (the
  shared `PackedKeys` is comparator-based on web). Re-sort only when the eye
  moved more than a threshold or turned more than an angle.
- `SplatQuads.build` stops re-sorting every frame.
- Tests: the sort matches a reference comparator sort's order on random
  clouds; golden `splat-glTF` from a small checked-in `.glb`.

**C2. Occlusion on the engine's own rasteriser.**
- `engine/scene/occlusion/occlusion_buffer.dart`: a depth-only 256×128
  rasteriser (edge functions, top-left rule, near clip lifted from
  `flutter3d_cpu/lib/src/cpu_encoder.dart:670–972`; `flutter3d_core` cannot
  depend on `flutter3d_cpu`), max-depth per 8×8 tile for fast rejects.
- Occluders: `MeshNode.occluder` (bool) and an optional `occluderMesh`;
  capped at 2 000 triangles a frame by screen size.
- Hook: an `OcclusionTest` interface; `RenderList.build` takes one;
  `SceneBvh` gains a public `queryFrustumWhere(frustum, accepts, visit)` so
  whole subtrees are rejected.
- `RenderSettings.occlusion` (`none`, `software`, `hiZ`).
- Tests: rasteriser unit tests (coverage, top-left rule, clipping); a
  metamorphic golden test — every golden scene renders identically with
  occlusion on — plus `FrameResult.culled` rising on a new `occlusion-city`
  scene.

**C3. Hi-Z by readback.** A `DepthPyramid` pass (Recipe P) reduces the
surface buffer's view depth to 256×128 max depth packed into rgba8 (24-bit
depth, 8-bit validity); `readback`; the CPU side reprojects last frame's
depths through G2's matrices and answers the same `OcclusionTest`. Returns
"visible" for anything on a cut or before the first answer. Test: the same
metamorphic golden with a static camera.

**C4. Octahedral impostors.** Baked in `flutter3d_build` on the CPU device
(`flutter3d_build` gains a dependency on `flutter3d_cpu`, so the bake is the
same bytes everywhere): 8×8 views of albedo-alpha and normal-depth into two
atlases stored with the model. Runtime: `ImpostorNode` (an instanced
billboard) with `ImpostorVertex` and `Impostor` stages blending the three
nearest views; a new `ModelLod` kind so a `LodGroup` ends in one. Golden
`impostor-forest` against the full meshes within a budget at the switch
distance.

**C5. Automatic LOD.** `flutter3d_mesh`: `simplifyMeshWithAttributes` gains
`targetError` and returns the error reached. `flutter3d_build` (new
dependency on `flutter3d_mesh`): `convert --lods=0.5,0.25,0.1` and a manifest
key `lods:` on `AssetRule`, filling `ModelNode.lods` between texture encoding
and `F3dWriter`; bump `kAssetPipelineVersion`. The glTF writer already emits
`MSFT_lod`. Test: a converted model carries three levels whose triangle
counts fall within 10% of target and whose error is monotonic.

### Phase 6 — agents (A1–A4)

**A1. Screenshot and on-screen report.**
- Move the Flutter-free part of `LevelLoader.build` (brush meshes,
  materials, lights, probes) into `flutter3d_editor_core/lib/src/level_scene.dart`,
  which imports no Flutter, with an option `batching: perBrush`;
  `flutter3d_app` keeps `rootBundle` and delegates.
- `Renderer.captureObjectIds()` → `ObjectIdFrame(width, height, Uint32List
  ids, List<MeshNode> nodes)`: the pick pass drawn for the whole frame and
  read back whole.
- `flutter3d_editor_mcp` depends on `flutter3d_core` and `flutter3d_cpu`,
  switches to `PictureAnswer`, and `screenshot` renders the level through
  `CpuDevice` with `perBrush` batching. `report` answers per brush, light and
  entity: visible pixels, screen box, depth range, and what hides it — the
  ids found inside its projected bounds, weighted by the pixels they own.
- Tests: `three_torches_test.dart` and `tools_test.dart` flip from the
  refusal to a picture and a report on the three-torch level; ARCHITECTURE.md
  §15's paragraph is rewritten.

**A2. Claims backed by replays.** `flutter3d_sim_mcp`: `expect` runs a tape
until a predicate over `HeadlessRun.reading` holds (`near`, `alive`,
`health`, `inside box`) or a step limit passes, and answers with the step,
the digest at it and a written `.f3drun`; `verify` replays a `.f3drun` and
reports `DigestTrace.divergenceFrom` or agreement. Contacts are out of reach
(`GameEvent`s are not saved) and the tool description says so. Tests over the
shooter's staging level.

**A3. Checking generated assets.** `flutter3d_model_core/lib/src/asset_audit.dart`:
units (overall size outside 1 cm…100 m), pivot (distance from the bounds'
base centre), triangle and texture budgets through `ExportReadiness`,
duplicate materials by `_materialKey`, degenerate and non-manifold counts
from the mesh `ImportReport`. `model_mcp` gains `audit` (text plus the
seven-view `renderSheet`) and `import` stops dropping `report.issues`. A
`repair` option applies `setOrigin`, `applyTransform` and `makeGameReady`.
Tests on a deliberately broken fixture GLB.

**A4. Seeded generators.** `flutter3d_editor_core/lib/src/generators/`:
the whole of `cryptkit.py`, `levelkit.py` and every `make_*.py` ported to
Dart and driven by `GameRandom(seed)`; each shipped level regenerated from
Dart matches its current JSON byte for byte before its Python is deleted,
and `tool/regenerate_levels.py` becomes a Dart tool. New kits (`room`,
`corridor`, `scatter`) take a seed. The level format gains optional `recipes: [{kind, seed,
params}]`, expanded deterministically by `expandRecipes(level)` in
`flutter3d_sim` wherever a level is read (loader, validator, visibility bake;
the visibility hash covers the expansion). `editor_mcp` gains `generate`.
Tests: the same seed produces the same brushes; a recipe level validates.

### Phase 7 — the rest of the research that fits the constraints

Items the research ranked but the roadmap had parked under "not decided",
now in 0.8 with the same rules (off by default, four-way goldens, a CPU
mirror).

**R4. Reactive mask for TAAU.** Particles, splats and alpha-blended draws
write a per-pixel "reactive" value into the velocity target's spare channel
(blue); `TemporalResolve` lowers the history weight by it, as Arm ASR does.
Stops embers and glass from smearing. Golden `taa-embers` (12 frames).
Depends on R2.

**R5. Spatial upscale for the non-temporal path.** An `Easu` pass (Recipe P,
FSR1's edge-adaptive 12-tap filter) runs when `renderScale < 1` and temporal
is off, followed by the existing sharpen. Runs after the tone map, before
grain, because EASU rings on HDR highlights. Golden `easu-half` at scale 0.5
against the same scene at 1.0 within a budget.

**R6. Motion blur.** McGuire's reconstruction: `VelocityTileMax` (two
separable passes to 20-pixel tiles), `VelocityNeighborMax` (3×3), `MotionBlur`
gather of 15 samples offset by R3's noise, placed before `TemporalResolve`.
`MotionBlurSettings` (off; shutter fraction, max radius). Golden
`motion-blur-spin` (a spinning wheel at a fixed frame). Depends on R1.

**R7. Local exposure.** Exposure fusion after Wronski: three synthetic
exposures of the bloom chain's quarter-size level, weighted by
well-exposedness, blended through a Laplacian pyramid built with the bloom
down/upsample stages, and applied at full size by a guided upsample in
composite before the tone map. `LocalExposureSettings` (off; strength,
highlight and shadow stops). Golden `window-interior` (a dark room with a
bright window), the case global auto exposure cannot handle.

**R8. Weighted blended OIT.** `RenderSettings.transparency` (`sorted` stays
default, `weightedBlended`). The transparent half draws into an
accumulation target (rgba16f, additive) and a revealage target (multiply),
then a `WboitResolve` pass composites. Per-attachment blend on Impeller
through `setBlend`'s attachment index and on WebGL2 through
`OES_draw_buffers_indexed` (a new capability `supportsIndependentBlend`);
where it is missing, the transparent list is drawn twice, once per target,
each its own pass. The test is order independence itself: the scene rendered
with its transparent draws shuffled is byte-identical. Golden
`glass-stack-oit`.

**R9. HDR display output.** The composite gains an output transform stage:
SDR as today, or scene-referred extended-sRGB for an HDR surface.
`GraphicsDevice.hdrOutputFormats` answers empty on Impeller (flutter/flutter#187069
removed the Apple-only formats), WebGL2 and CPU; WebGPU answers
`rgba16float` when `matchMedia('(dynamic-range: high)')` holds and configures
the canvas with `toneMapping: {mode: 'extended'}`. Goldens stay SDR; a VM
test holds the transform's SDR branch to today's composite byte for byte.

**L8. Energy-preserving diffuse.** The EON diffuse lobe (2024) as an option
on `pbr` and `pbrLayered` beside Lambert (`RenderSettings.diffuseModel`).
Arithmetic only; CPU mirror in `PbrShader`. Golden `rough-dielectrics`.

**H7. Transient aliasing and memoryless attachments.** `RenderTargetPool`
learns first and last use per frame from the compiled graph and colours the
intervals, so two targets with disjoint lifetimes and one spec share a
texture. `StorageMode.deviceTransient` maps to WebGPU's
`TRANSIENT_ATTACHMENT` (behind a feature check) and to
`invalidateFramebuffer` at pass end on WebGL2; a no-op on CPU. Test on the
CPU backend: a texture poisoned at the end of its lifetime changes no
golden; `RenderTargetPool.createdCount` falls on the ten-pass scene.

**H8. Retire the hand-kept binding flags.** On the first Flutter stable that
carries flutter/flutter#190040 and #189820: re-test the phantom-block crash
of ARCHITECTURE.md §2 on Metal; if gone, the renderer takes "bind or not"
from `stageBindings` and the `usesFragInfo`-style flags on `LightingModel`
become derived rather than declared. Until that release the item is a
failing-by-design test that says which SDK version to look for.

**C6. SPZ.** A pure-Dart `.spz` reader (gzip, quantised fields) into
`SplatCloud`; the glTF wrapper `KHR_gaussian_splatting_compression_spz_2`
once its pull request (KhronosGroup/glTF#2531) merges. Test: the reader
against a checked-in `.spz` and its `.ply` twin.

**C7. Splat LOD and streaming.** An octree built offline by merging
Gaussians (`flutter3d_build convert` for splat inputs), a budgeted cut chosen
on the CPU from a priority queue each time C1 re-sorts, and range-request
loading of octree pages. Depends on C1. Test: the cut never exceeds its
budget and converges to the full cloud as the budget grows.

**C8. Per-texture transforms.** Accept `KHR_texture_transform` when
*required*: the transform travels to the shader as a 2×3 matrix per texture
slot (packed into the layered model's `FragInfo` append) instead of being
baked into one UV set, which is what refuses textures that disagree today.
The third refusal in `gltf_test.dart:792` becomes a load.

**C9. Chunked clusters for huge static meshes.** For scans and CAD only:
meshes above a triangle threshold are split at import into 1–4k-triangle
chunks with a bounding cone, culled on the CPU by frustum, backface cone and
C2's occlusion test, and repacked into one index buffer only when the visible
set changes. `flutter3d_build` does the split with `flutter3d_mesh`. Golden
`scan-chunks` equal to the unsplit mesh.

### Phase 8 — waiting on upstream, with a trigger each

These are designed now and built when the trigger fires. The trigger is a
check in `tool/structure.dart` that reads the pinned Flutter SDK version and
the WebGPU feature list, and fails with the item's id when the item becomes
buildable, so the plan cannot silently go stale.

| Id | Item | Trigger |
|---|---|---|
| H9 | Immediates / push constants: `setImmediates(UniformBlock)`, no other API change after H1 | flutter/flutter#190406 in stable; WebGPU immediates in Chrome stable |
| H10 | Indirect draw and GPU culling: WebGPU compute culls, writes an indirect buffer, the scene draws from it; Impeller follows | `supportsCompute` (H6) plus flutter/flutter#190402 in stable; WebGPU part can start with H6 |
| H11 | GPU splat sort on WebGPU with compute, falling back to C1's CPU sort — H6's first engine consumer | H6 merged |
| H12 | Subgroups, texture tier 2 read-write storage, bindless resource tables | WebGPU features shipping in Chrome and Safari stable; bindless when the gpuweb proposal has a spec |
| H13 | Slang as the shader source | flutter_gpu accepting SPIR-V or MSL input |
| C10 | Neural texture compression, inference on load, transcoding to the BC/ASTC encoders already in `ktx2/encode/` | tooling usable without an NVIDIA-only SDK |

### Phase 9 — `flutter3d_lab`, research that has to earn its way in

**X1. Screen-space radiance cascades.** Cascades as render targets
raymarched against the surface buffer's depth and merged by 5–6 fragment
passes; compared against L5's SSIL on the same scenes for cost and noise.
Promoted only if it beats SSIL on the A55.

**X2. Differentiable shading on the CPU rasteriser.** Promoted out of the
lab as the core of N1 (Phase 10). What stays here is its other uses: fit
materials to a reference image, fit a backend's constants to the CPU golden,
an MCP `matchLook` tool.

**X3. A neural lighting model.** One AOT permutation with a fixed 2×16 MLP,
weights in a texture, and the same MLP in Dart so the CPU reference agrees.
Measured on the A55 and in WebGL2 before anything else is said about it.

### Phase 10 — ideas from the 2026 research

From a pass over SIGGRAPH 2026 (papers and the Advances course), HPG, I3D
and EGSR 2026 and arXiv through September 2026, filtered by the same
constraints. Every finding is taken; the answers below are the owner's
(2026-09-24).

**N1. Light optimizer** (after LightOpt, SIGGRAPH 2026: 18–52% cheaper
lighting than artist reductions). X2's differentiable shading leaves the lab
as this tool's core: with visibility frozen, the CPU rasteriser renders views
before and after, and the optimizer removes, merges, inserts and retunes
lights against an image loss plus LightOpt's two regularisers (redundant
overlap, under-illumination).
- Views: camera paths from the level's `.f3drun` replays, which is where
  players actually are.
- Result: one editor command with a before/after preview and the numbers
  (lights, cost from N2's table, FLIP difference), undone like any edit.
- Entry points: `flutter3d_build lights --optimize`, an editor button, and
  an `editor_mcp` tool, over one core in `flutter3d_editor_core/lib/src/light_opt/`.
- Time of day: a second commit optimises one light set against several
  lighting states.
- Tests: a synthetic room with three coincident lights collapses to one
  within a FLIP bound; the command round-trips through undo.

**N2. Adaptive quality from a measured table** (after LUT-Opt 2026 and
Mantiuk et al., SIGGRAPH 2026).
- `QualityTable`: per device class (A55, Mac, web), settings →
  (frame time, FLIP difference against full settings), built offline by
  rendering the golden scenes at every setting combination on that device
  with H2 timing. Stored as a Dart const per class.
- Levers: `renderScale` and effect tiers (SSAO/SSR samples, fog steps,
  shadow resolution, probe and irradiance update budgets, the k-DOP axes of
  N4).
- Runtime: `AdaptiveQuality` replaces `AdaptiveScale`'s single timer. It
  queries the table each frame for the best quality inside the budget and
  refines the table's times with measurements on the device (exponential
  average per row), so heat and background load are seen.
- Motion: camera speed from R1 lowers the input resolution in motion, where
  the eye cannot resolve it; TAAU keeps the output full size.
- FLIP is implemented in Dart (`flutter3d_testing/lib/src/flip.dart`) and is
  also offered to the golden budgets.
- Tests: FLIP against the reference implementation's published values;
  the controller never exceeds the budget on a recorded timing trace and
  climbs back when timings fall.

**N3. Even frame pacing** (after the I3D 2026 study: frame-time spikes, not
graphics settings, cost players score and accuracy).
- `tool/pacing.sh`: plays a `.f3drun` through the renderer on macOS/Impeller
  in CI and fails on any frame longer than 50 ms (three 60 Hz budgets); p50,
  p99 and spike counts go into a report kept in the repository. The same
  command runs on the A55 by hand before a release and its numbers are
  committed.
- A per-frame budget for amortised work: probe faces, irradiance updates
  (L4), static shadow scrolls (S1), texture uploads and impostor bakes share
  one `FrameWorkBudget` in microseconds rather than each counting items.
- Pipeline warm-up: every pipeline a level can need is created on the
  loading screen from its materials and the frame graph's nodes.
- Tests: `FrameWorkBudget` never exceeds its allowance on a scripted
  burst; a warm-up test asserts no pipeline is created during the first 300
  frames of a replay.

**N4. k-DOP clipping in TAAU** (Ikkala et al., SIGGRAPH Asia 2024, 0.2 ms).
`TemporalSettings.clip`: `aabb`, `kdop8`, `kdop16`, with the axes from the
published optimiser baked into G1; N2 chooses per device class. Golden
`taa-railing` held at each setting.

**N5. Splats without sorting.** When temporal is on, splats draw as opaque
fragments kept or discarded by a hash of pixel, splat and `frameIndex`
against their opacity (the engine's `hashed` alpha mode), writing depth, and
TAAU integrates the noise; with temporal off they sort with C1's radix. The
default follows the temporal setting. Golden `splat-stochastic` (16 frames)
against the sorted render within a FLIP bound.

**N6. Six-way lit particles.** `flutter3d_particles` gains a six-way
material: a flipbook of six directional light responses plus emission and
alpha, lit per particle by the frame's lights (and clusters when L6 is on)
in `particle_textured.frag`. Import of the EmberGen/Houdini six-way layout,
plus a CPU baker in `flutter3d_build` that raymarches a procedural density
volume into a flipbook, so the engine ships effects of its own. Golden
`smoke-six-way` lit from two sides.

**N7. Assets per device class** (after Roblox SLIM, Advances 2026).
`flutter3d_build` writes one file per class — `model.phone.f3d`,
`model.web.f3d`, `model.desktop.f3d` — each with its own LOD chain (C5),
impostors (C4), texture budget (`makeGameReady`) and, for levels, the N1
light set. The runtime picks a class once, from capability flags plus a
short measurement on the loading screen, remembers it, and lets the player
override it. Web builds bundle only the web files. Tests: the three files
differ as their budgets say; the selector is deterministic for a given
capability set and measurement.

**X4. [lab] Frame extrapolation** (after Amulet, 2026, no neural network).
Shade at half the display rate and present the other frames by reprojecting
the last shaded frame with R1's velocity and a layered depth cache for
disocclusions; measured at phone 30 → 60 Hz and desktop 60 → 120 Hz, input
latency included, before any promotion.

### Out of scope, with the reason

Nanite-style cluster DAGs and visibility buffers (compute, indirect draw and
64-bit atomics; C9 is the part that transfers); ReSTIR, MegaLights and path
tracing (ray tracing; their caching and light-scoring lessons are in L4 and
L6); FSR 2–4, DLSS, XeSS (compute and ML; R2 is the fragment-only
equivalent); linked-list and moment OIT (storage atomics); cooperative
vectors (DX12 and Vulkan extensions); interactive world models (not an
engine). Triangle-splatting meshes need no work — they load as ordinary glTF
today, and C1's fixture set includes one to keep it so.

## Order of commits

```
Phase 0  G3 → G1 → G0 → G2
Phase 1  H1 (5 commits) → H2 (3) → H3 (3) → H4 (5) ; H5 → H6
Phase 2  R1 (3) → R2 (5) → R3
Phase 3  L1 ; L2 ; L3 → L4 ; L6 ; L7 ; L5 (after R3)
Phase 4  S1 → S2 ; S3 (after R3) ; S4 (after L6, R3)
Phase 5  M1 → M2 → M3 ; M4 ; C5 → C4 ; C1 ; C2 → C3
Phase 6  A1 ; A2 ; A3 ; A4
Phase 7  R4 (after R2) ; R5 ; R6 (after R1) ; R7 ; R8 ; R9 ; L8 (after M1)
         H7 ; H8 (on the SDK trigger) ; C6 → C7 (after C1) ; C8 (after M1) ; C9 (after C2)
Phase 8  each on its trigger; H11 first, as soon as H6 lands
Phase 9  X1 (after L5) ; X2 ; X3 ; X4 (after R1) — lab only, never on the release path
Phase 10 N3 (after H2, early: it measures everything after it) ; N1 (after A1's builder)
         N2 (after H2, R1, R2) → N4 ; N5 (after C1, R2) ; N6 (after L6) ; N7 (after C4, C5, N1)
```

Each phase ends with a `0.8.0-dev.N` pre-release of the touched packages on
pub.dev; 0.8.0 goes out when every phase but 8 and 9 is in.

`;` separates items that do not depend on each other and can go in any
order. Each commit leaves `flutter test` green in the packages it touches, the
structure scan green, and every existing golden unchanged unless the commit's
own item is the reason. Titles follow the repository's narrative style.

## Files to modify (by area)

- Contract: `flutter3d_hardware/lib/src/{command_encoder,graphics_device,render_pass_descriptor,testing_recorded}.dart`,
  new `trace/`, all four `*_device.dart`/`*_encoder.dart`.
- Shaders: `flutter3d_shaders/shaders/{lib/surface.glsl,lib/shadow.glsl,lib/color.glsl,lighting/pbr.frag,post/*}`,
  new stages as listed, `flutter3d.shaderbundle.json`,
  `lib/flutter3d_shaders.dart`, generated `stage_bindings.dart`,
  `uniform_blocks.dart`, both `engine_shaders.dart`.
- Renderer: `flutter3d_core/lib/src/engine/render/{renderer,renderer_frame_nodes,renderer_post_pass,renderer_mesh_encode,renderer_scene_pass,renderer_shadow_pass,renderer_probe_pass,renderer_pick_pass,render_settings,frame_plan,render_list,splat_contributor}.dart`,
  `scene/{projection,irradiance_field,bvh,lod_group}.dart`, new files as
  listed.
- CPU mirror: `flutter3d_cpu/lib/src/cpu_shaders_*.dart`,
  `cpu_shaders_builtin.dart`, `cpu_encoder.dart` (compute).
- Formats: `formats/{surface_material,gltf/*,fmat/fmat,f3d/*,splat/*}.dart`.
- Tools and packages: `flutter3d_build`, `flutter3d_mesh`,
  `flutter3d_model_core`, `flutter3d_model_mcp`, `flutter3d_editor_core`,
  `flutter3d_editor_mcp`, `flutter3d_sim`, `flutter3d_sim_mcp`,
  `flutter3d_app/lib/src/level/level_loader.dart`.
- Conformance: `flutter3d_conformance/lib/{flutter3d_conformance.dart,src/*}`.

## Trade-offs

- **Typed blocks generate a map, not bytes.** Changing the HAL to take bytes
  would touch four backends and the CPU stages' 65 reads for no gain the
  compiler does not already give; the map stays the wire format.
- **Velocity in rgba16f** rather than a new `rg16f`: `TextureFormat` mirrors
  flutter_gpu value for value and a new value trips the structure rule; two
  wasted channels cost less.
- **TAA forces the surface buffer** rather than supporting TAA over MSAA:
  velocity needs depth, and the surface buffer is where depth already is.
- **`pbrLayered` as a second permutation** rather than growing `pbr`: keeps
  the common path's cost and stays under 16 samplers.
- **EVSM converts from depth after combining** rather than rendering
  moments: keeps S1's static half, at one extra full-atlas pass.
- **Our own blue noise** rather than NVIDIA's STBN files: no licence
  question, same bytes on every backend, at the cost of an offline
  void-and-cluster run.
- **Occlusion rasteriser copied into `flutter3d_core`** rather than shared
  with `flutter3d_cpu`: the core must not depend on a backend; the shared part
  is small.

## Decisions

- Everything in 0.8; picture quality first; phones on Impeller are the
  measure; WebGL2 the floor; CPU mirrors every effect (owner, 2026-09-23).
- Every new effect is off by default until its golden scene exists in all
  four sets.
- The roadmap's "four refusals" and "MSFT_lod from convert" are corrected
  here, not there.
- Every aspect of the research is placed: Phase 7 builds what fits, Phase 8
  waits on a named upstream trigger, Phase 9 stays in the lab, and the rest
  is out of scope with its reason (owner, 2026-09-23).
- The layered model's parameter names follow OpenPBR 1.1 where glTF leaves
  a choice; no OpenPBR or MaterialX runtime.
- H6's first engine consumer is the WebGPU splat sort (H11).
- The 2026 findings are all taken (Phase 10); X2 leaves the lab as N1's
  core; the frame-extrapolation experiment targets both phone and desktop
  (owner, 2026-09-24).
- The Flutter-free level-to-scene builder lives in `flutter3d_editor_core`;
  `flutter3d_app`'s `LevelLoader` delegates to it and keeps `rootBundle`.
- Every Python level generator (`cryptkit.py`, `levelkit.py`, the
  `make_*.py` scripts) is ported to Dart generators in
  `flutter3d_editor_core` with seeds; regenerated levels must match today's
  JSON byte for byte, and the Python goes when they do.
- The A55 target is 60 Hz (16.6 ms); a frame over 50 ms is a spike.
- ~~One 0.8 release, with a `0.8.0-dev.N` pre-release after each phase.~~
  Replaced 2026-09-24 (owner): **0.8.0 fixes the contract, 0.8.x fills it
  in.** See §0.8.0 below.

## 0.8.0 — the contract release

Decided 2026-09-24. `GraphicsDevice`, `PassEncoder` and `CommandEncoder` are
`abstract interface class`es and `Recorded` is `sealed`, and every backend is
its own package pinned `^0.8.0` to `flutter3d_hardware`. A member added to
any of them in 0.8.1 breaks `flutter3d_webgl 0.8.0` resolved against it, and
a new `Recorded` variant breaks every exhaustive switch. So every member and
variant the cycle needs goes in now, answered conservatively (`false`, empty,
`UnsupportedError`) where the implementation is large, and each later item
ships as a 0.8.x patch that only turns an answer on.

The contract, in 0.8.0:

- Bind contract: `bindTexture` returns `bool`, `bindPipeline` forgets
  (done, `2fe2213c`).
- H1 typed uniform blocks and the `UniformBlock` interface, all call sites
  moved.
- H2 surface: `RenderPassDescriptor.label`, `supportsGpuTimestamps`,
  `FramePass.gpuMicros`, the `FrameTimings` callback, `Timeline` spans per
  node. WebGPU timestamps may follow in a patch.
- H3: `RecordingDevice`, `Trace` with its `.f3dtrace` writer and reader,
  and `replayTrace`, in `package:flutter3d_hardware/trace.dart`. **Its own
  sealed `TraceEvent` rather than new `Recorded` variants**, decided while
  building it: `Recorded` is what tests assert against and is lossy on
  purpose (a vertex binding records a count, not the buffer), so it cannot
  be replayed. `TraceEvent` has one variant per call of the whole contract,
  compute included, so it too is complete in 0.8.0.
- H6 surface: `supportsCompute`, `StorageBuffer`, `ComputePipelineHandle`,
  `ComputeEncoder`, `beginComputePass`, `readBuffer`; every backend answers
  false in 0.8.0, WebGPU and CPU implement it in a patch.
- Capabilities reserved for later phases, all false or empty in 0.8.0:
  `supportsFloat32Filtering` (S2), `supportsIndependentBlend` (R8),
  `hdrOutputFormats` (R9), `StorageMode.deviceTransient` (H7, treated as
  `devicePrivate`).
- gfx-92n: built-in `LightingModel`s bind what their stages declare, read
  from `stageBindings`; the hand-kept `usesX` flags go.

Fixes and small items, in 0.8.0:

- PCF taps clamped to their own atlas tile; near cascades' depth range
  pulled toward the light to catch casters behind the near plane.
- WebGL frame orientation for the Bayer dither; the raised WebGL budgets
  go back down.
- glTF `baseColorFactor` converted once; rect lights normalised.
- gfx-90n: the CPU sRGB conversion without `pow`, the render lane back on.
- G3 sampler budget test; the CPU IBL `n·v` clamped as the GLSL does (L1's
  first commit); H4 fuzzing on the CPU (browser suites in a patch); spot
  lights wider than the atlas tile allows shadowed through the cube atlas.

Everything else in this plan is 0.8.x, one item or phase per patch, each
additive: new settings off by default, new goldens, no contract change.

## Documentation

- ARCHITECTURE.md: §4.3 (temporal, velocity, clusters, probes, occlusion),
  §6 (layered model, LTC, irradiance), §7.1–7.2 (labels, timestamps,
  compute, `supportsFloat32Filtering`), §8 (`.f3d` sections 22–23, splats),
  §13 (fuzzing, traces), §15 (compute, TAA, occlusion, screenshot paragraphs
  rewritten), §14 (phone timings from H2).
- README and `site/content/`: test counts per Recipe G; a page per new
  setting group.
- CHANGELOG.md of each touched package at release.

## Testing strategy

Unit tests wherever a function takes constructed input: generators (H1,
H4), builders (L6 clusters, C2 rasteriser, C1 sort, G2 history), format round
trips (Recipe M, M4, C1), scheduler and convergence logic (L4), audit rules
(A3), recipe expansion (A4), MCP tools against fixture levels (A1, A2).

Rendering is held by golden scenes in all four reference sets through the
recipes, plus three metamorphic properties that catch what a single golden
cannot: temporal off leaves every existing golden unchanged; occlusion on
leaves every golden unchanged; a trace replayed on a fresh device gives the
same bytes. The browser suites (WebGL2, WebGPU) run the conformance, fuzz and
cross-backend tests in Chrome, since a VM test against a fake cannot see a
driver's behaviour; Impeller runs `conformance.sh` on macOS for the same
reason.

## Manual verification

1. `flutter run -d <Galaxy A55>` on the dungeon demo with temporal on at
   `renderScale 0.67`, then off at 1.0; compare `FrameResult.passes` timings
   printed by H2's overlay. Why manual: the point is a phone's cost, and CI
   has no phone.
2. The same with clusters and volumetric fog on the crypt level. Expected:
   frame time within the budget the H2 numbers set for the level; the
   numbers go into ARCHITECTURE.md §14.

## Open questions

1. **`KHR_gaussian_splatting` status** — checked in C1's first commit.

The other four (where the level builder lives, one release or several, the
Python generators, the A55 budget) were answered on 2026-09-24 and moved to
Decisions.
