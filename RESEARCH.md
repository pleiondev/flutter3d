# A 3D engine on Flutter GPU: research and the list of required features

Date: 2026-08-08, item status updated 2026-08-09. Items marked `[x]` are implemented;
unmarked ones are open. The scene architecture analysis lives in
`docs/ARCHITECTURE-scene-camera.md`, the measurements and the FFI verdict in
`docs/FFI-analysis.md`.

---

## 0. The main finding, which reframes the whole task

**A full-blown 3D engine on `flutter_gpu` already exists, and it is far from a prototype** —
[`flutter_scene`](https://pub.dev/packages/flutter_scene) 0.20.0 by Brandon DeRosier (bdero),
the author of Impeller and of Flutter GPU itself. Flutter GPU was created precisely so that
Scene could be moved out of the engine and into an ordinary Dart package.

What it already ships today:

| Subsystem | State in flutter_scene 0.20.0 |
|---|---|
| PBR + IBL | present, including a procedural studio environment, sky materials, live IBL rebake, HDR/EXR |
| Lights and shadows | directional / point / spot, shadow casting with caching |
| Post-processing | tonemap, exposure, bloom, fog, god rays, SSR, DOF, AA |
| Materials | its own `.fmat` format, vertex+fragment stages, **shader hot reload** |
| Geometry | instancing, automatic LODs, procedural builders, geometry readback |
| Assets | glTF `.glb` at runtime + precompilation into `.fsceneb` (flatbuffers), KTX2 + mips, `.fstex` |
| Animation | skinning, blended animation system, KHR_materials_variants |
| Exotica | 3D Gaussian splatting (`.ply`, `.splat`) |
| Integration | `SceneView` (imperative + declarative API), **interactive Flutter widgets on 3D surfaces** with pointer raycasting, semantics/screen reader, split-screen, multi-view, frame capture into `ui.Image` |
| Ecosystem | physics (Rapier, box3d), audio (SoLoud, FMOD), Scene Editor with an MCP server |
| Platforms | iOS, Android, macOS, Windows, Linux + **web via its own WebGL2 backend** |

So the first decision is strategic rather than technical:

1. **Use `flutter_scene`** — if the goal is "ship 3D in an app".
2. **Fork / extend `flutter_scene`** — if you need your own materials, your own pipeline, your
   own scene format, but do not want to write an RHI, a glTF importer and IBL prebaking from
   scratch.
3. **Write your own engine from scratch** — if the goal is learning, a specific problem domain
   (CAD, geodata, scientific visualisation, voxels, 2.5D stylisation), or a fundamentally
   different architecture (ECS, data-oriented, GPU-driven).

The rest of this document is material for option 3 (and it doubles as a map of what would have
to be written in option 2).

---

## 1. What web engines provide: a subsystem comparison

### 1.1 Three.js
A library, not an engine: it gives you a scene graph, maths, a renderer and loaders; everything
else comes from `examples/jsm` and the ecosystem.

- Core: the `Object3D` hierarchy, `BufferGeometry`, maths (vectors, matrices, quaternions, curves).
- Two renderers: the classic `WebGLRenderer` (imperative, GLSL, `WebGLPrograms`/`WebGLState`)
  and `WebGPURenderer` — built on **node materials and TSL** (Three Shading Language): shaders
  are written in JS as a node graph and transpiled into WGSL or GLSL. Compute shaders go through
  TSL as well.
- Post-processing on WebGPU is a new stack, with effects composed out of nodes.
- Shadows: `BasicShadowMap`, `PCFShadowMap`, `PCFSoftShadowMap`, VSM.
- Raycasting, GLTF and many other loaders, serialisation, camera controllers, audio, helpers,
  an editor, a TSL transpiler, a Chrome DevTools extension.

**What to take:** the structure of the maths library, the `BufferGeometry` attribute model, the
loader API, `Raycaster`, the set of camera controllers.

### 1.2 Babylon.js 8.x
A complete engine with editors and everything included.

- A tiered RHI: `AbstractEngine` → `ThinEngine` → `Engine` / `WebGPUEngine` /
  `NativeEngine` (iOS/Android/Windows) / `NullEngine` (headless, tests, server-side rendering).
  **This is exactly the abstraction we need** for "flutter_gpu + web fallback + headless tests".
- All core shaders exist in both GLSL and WGSL — no conversion layer.
- **Node Render Graph / FrameGraph** (8.0, alpha): the render pipeline as a node graph with a
  visual editor. Full control over the frame without hand-written pass code.
- `PrePassRenderer` + MRT for deferred effects; DefaultRenderingPipeline (bloom, DOF, SSR, SSAO2, …).
- IBL shadows (contributed by Adobe): both light **and** shadows are approximated from the
  environment image. GI.
- Materials: `StandardMaterial` (Blinn-Phong), `PBRMaterial`, `NodeMaterial` (graph → GLSL/WGSL),
  `ShaderMaterial`.
- Animation: clips, groups, skeletal animation, morph targets.
- Separate large subsystems: particles (CPU/GPU/node-based), physics (plugins), GUI (2D + 3D +
  editor), WebXR, audio (AudioV2), Inspector, Playground, Sandbox, Gaussian splatting,
  glTF/OBJ/STL/SPLAT loaders, glTF/USDZ export.

**What to take:** the RHI tiering, the FrameGraph idea, the Standard/PBR/Custom material split,
`PickingInfo`, `NullEngine` for golden tests.

### 1.3 PlayCanvas
The most "mobile-oriented" of the three — and therefore the most useful for a Flutter target.

- **Clustered lighting by default** (since 1.56): the scene is split into 3D clusters and lights
  are bound only to the ones they touch. Up to 254 omni/spot lamps, and turning a light on or off
  **without recompiling shaders** — critical where runtime compilation does not exist at all.
- Shadow maps and cookie textures are rendered **into an atlas** rather than into separate
  textures, so that all of them are available to the shader at once.
- FrameGraph: rendering is described as a set of passes, their dependencies and their targets.
  The post-process stack is built on it: TAA, Bloom, DOF, SSAO, Vignette.
- WebGL2 + WebGPU (beta), unified GSplat.

**What to take:** clustered forward as the primary lighting scheme, the shadow atlas, the idea of
"change lighting without rebuilding shaders" — which follows directly from the flutter_gpu
constraints.

### 1.4 Summary: what people expect from a modern engine

| Axis | Three.js | Babylon.js 8 | PlayCanvas |
|---|---|---|---|
| Backend abstraction | 2 renderers | 5 engines, including headless | 2 backends |
| Shader authoring | TSL (graph → WGSL/GLSL) | NodeMaterial (graph → GLSL/WGSL) | shader chunks + defines |
| Frame graph | none (manual composer) | FrameGraph + visual editor | FrameGraph |
| Lighting scheme | forward, per-object limits | forward + prepass/deferred | **clustered forward** |
| GI | none (IBL only) | IBL shadows, GI | lightmaps, volumetric |
| Editor | third-party | Inspector + 4 node editors | full web editor |
| Compute | via TSL/WebGPU | WebGPU | WebGPU |

---

## 2. What `flutter_gpu` actually gives you (and what it does not)

Verified against [`api.flutter.dev/flutter/flutter_gpu`](https://api.flutter.dev/flutter/flutter_gpu/)
and the [engine docs](https://github.com/flutter/engine/blob/main/docs/impeller/Flutter-GPU.md).

### 2.1 The public API surface

About 20 classes in total. It is a thin wrapper over the Impeller HAL, at a "Metal/Vulkan-lite"
level:

- Resources: `GpuContext`, `DeviceBuffer`, `HostBuffer` (a bump allocator over a list of
  `DeviceBuffer` blocks — a ready-made per-frame ring buffer), `BufferView`, `Texture`,
  `ShaderLibrary`, `Shader`.
- Pipeline: `RenderPipeline`, `RenderTarget`, `ColorAttachment`, `DepthStencilAttachment`,
  `ColorBlendEquation`, `StencilConfig`, `SamplerOptions`, `UniformSlot`, `Viewport`, `Scissor`,
  `DepthRange`.
- Execution: `CommandBuffer`, `RenderPass`.

`RenderPass` can do: `bindPipeline`, `bindUniform`, `bindTexture`, `bindVertexBuffer`,
`bindIndexBuffer`, `clearBindings`, `setPrimitiveType`, `setCullMode`, `setWindingOrder`,
`setPolygonMode` (including wireframe), `setViewport`, `setScissor`, `setStencilConfig`,
`setStencilReference`, `setDepthWriteEnable`, `setDepthCompareOperation`,
`setColorBlendEnable`, `setColorBlendEquation`, `draw()`.

`GpuContext.createTexture(storageMode, width, height, {format, sampleCount, coordinateSystem,
textureType, enableRenderTargetUsage, enableShaderReadUsage, enableShaderWriteUsage})`,
`createDeviceBuffer`, `createHostBuffer`, `createCommandBuffer`,
`doesSupportOffscreenMSAA`, `minimumUniformByteAlignment`.

### 2.2 Capabilities you can build on

| Available | What it means for the engine |
|---|---|
| `sampleCount` + `doesSupportOffscreenMSAA` | MSAA for offscreen targets is available |
| `TextureType.textureCube` | IBL and cube shadow maps are possible |
| `r16g16b16a16Float`, `r32g32b32a32Float` | a full HDR pipeline and tonemapping |
| `d24UnormS8Uint`, `d32FloatS8UInt`, `s8UInt` | depth + stencil, hence portals, outlines, decals, reversed-Z |
| A complete stencil API (per-face) | outlines, masks, CSG effects |
| `setPolygonMode` | wireframe debugging for free |
| `HostBuffer` | per-frame uniform allocations without writing your own allocator |
| `enableShaderWriteUsage` | a hint that storage textures are on the horizon |
| `PolygonMode`/`WindingOrder`/`CullMode` | basic state is fully controllable |

### 2.3 The limitations are the architectural forks

**(1) Shaders are compiled AOT into a shader bundle. There is no runtime compilation.**
`.vert`/`.frag` in GLSL → a `.shaderbundle.json` manifest → the build hook of the
`flutter_gpu_shaders` package (via experimental Dart **Native Assets**) → a `.shaderbundle`.

Consequence: **a node-material graph in the style of Babylon NodeMaterial or Three TSL is
impossible at runtime.** The options are:
- An **uber-shader** with branches on uniform flags (the PlayCanvas clustered-lighting route:
  "turn a light on without recompiling"). The cost is registers and dynamic branching.
- **Pre-generating permutations** at build time: a Dart code generator expands a graph or a
  feature set into N `.frag` variants and puts them into the bundle. A designer-facing graph is
  still possible, but only in the editor, not in the app.
- A hybrid: an uber-shader for the "dynamic" part (light count, presence of maps) plus
  permutations for what really changes the structure (skinning, instancing, alpha mode).

**(2) The shader bundle format is tied to the Flutter version and can change.**
The engine will have to be rebuilt and re-verified for every master update. This calls for CI
that builds bundles on several revisions, plus golden render tests.

**(3) Master channel only.** Plus `flutter config --enable-native-assets`
(and `--enable-dart-data-assets` if you follow the `.fmat` approach from flutter_scene).
Desktop requires `--enable-impeller`.

**(4) Web is not supported.** It is no accident that flutter_scene carries **its own WebGL2
backend**. If web is a requirement, you need an RHI abstraction (at the level of Babylon's
`AbstractEngine`) and a second backend via `dart:js_interop`. That doubles the renderer work.

**(5) Compute passes are not exposed in the public `flutter_gpu`.** Compute exists in Impeller,
but the documented Dart API does not surface it. So the following are unavailable: GPU particles
on compute, GPU skinning, GPU culling, indirect draw, IBL prefiltering in compute, GPU sorting of
transparent objects. All of that has to be done on the CPU or emulated with render passes (IBL
prefilter — by rendering into mip levels; that is exactly why flutter_scene requires master
≥ 2026-06-09, with render-to-mip-level support).

**(6) No compressed pixel formats** (ASTC/BC/ETC2) in the public `PixelFormat`, and no
`texture2DArray`/`texture3D`. Consequences:
- KTX2/Basis will have to be **transcoded into an uncompressed** format on the CPU (memory and
  load time!), or you wait for and verify an enum extension on master — flutter_scene advertises
  KTX2 with mips, so something already exists there. ⚠️ Check this first.
- Shadows and cookies go **into an atlas**, not into a texture array (as PlayCanvas does).
- Colour grading LUTs are 2D-tiled, not 3D textures.
- Light clusters are packed into a 2D texture or a buffer, not into 3D.

**(7) `draw()` has no `instanceCount` in the documented API.** flutter_scene claims instancing —
either through per-instance vertex attributes, or the API appeared later. ⚠️ Check.

**(8) Dart GC.** Every `Vector3` is a heap object. In hot loops (culling, transform updates,
particles) you need pools, `Float32List` storage (SoA) and in-place `Matrix4` operations. This
separates a Dart engine from a JS engine more than it seems: GC jank will eat the frame budget
faster than draw calls will.

---

## 3. The list of required features

Priorities: **P0** — without it you cannot show a spinning textured cube; **P1** — without it you
cannot show a proper glTF scene; **P2** — what makes it an engine; **P3** — what makes people
choose an engine.

### Layer 0. RHI / a wrapper over flutter_gpu

- [ ] **P0** `GraphicsDevice`: a wrapper over `GpuContext`, querying and caching capabilities
      (`doesSupportOffscreenMSAA`, `minimumUniformByteAlignment`, supported formats).
- [x] **P0** Loading a `ShaderLibrary` from a bundle, a shader registry keyed by name, typed
      uniform block descriptions (generated from GLSL so that offsets are not written by hand).
- [x] **P0** **A `RenderPipeline` cache** keyed by (shader × vertex layout × blend × depth × stencil × sample count).
      Creating a pipeline is expensive — the cache is mandatory, with warm-up at startup.
- [x] **P0** Buffer allocators: a static `DeviceBuffer` for geometry, a per-frame `HostBuffer` for
      uniforms, suballocation for small things. A ring of 3 `HostBuffer`s, one per frame in flight.
- [ ] **P0** Resource lifetime management: explicit `dispose`, ref counting, deferred release
      after N frames (the GPU is still reading).
- [ ] **P1** A pool of render targets and textures reused by (size, format, usage) — on mobile,
      per-frame memory is critical.
- [ ] **P1** A `CommandEncoder` abstraction over `CommandBuffer`/`RenderPass` so that the upper
      layers do not know about flutter_gpu.
- [ ] **P2** A second backend (WebGL2 via `dart:js_interop`) if web is needed, or a `NullDevice`
      for headless tests.
- [ ] **P2** A validation layer in debug: checking bindings, formats, missing uniforms.

### Layer 1. Maths

- [x] **P0** Use `vector_math` (`Vector2/3/4`, `Matrix3/4`, `Quaternion`, `Aabb3`, `Sphere`,
      `Plane`, `Frustum`, `Ray`, `Obb3`) — no need to rewrite it.
- [x] **P0** In-place / allocation-free wrappers for hot paths plus a pool of temporary vectors.
      `readPosition(out)` and the like.
- [x] **P0** `Transform`: TRS with lazy matrix recomputation, a dirty flag, local↔world.
      Implemented with version counters: there is no separate update pass.
- [ ] **P1** Euler angles with axis orders, matrix decomposition, `slerp`/`nlerp`, spherical
      coordinates.
- [ ] **P1** Curves and splines (Catmull-Rom, Bezier, path), easing functions.
- [x] **P2** Intersections: ray×AABB/sphere/triangle/OBB/plane, sphere×frustum, sweep tests.
      AABB, sphere and triangle (Möller–Trumbore) are done, with `out` parameters and a `-1`
      sentinel instead of a nullable double. OBB, plane and sweeps are not.
- [ ] **P2** SoA transform storage (`Float32List`) instead of an array of objects.

### Layer 2. Scene graph

- [x] **P0** `Node` with parent/children, local and world transforms, dirty flag propagation up
      and down.
- [x] **P0** `Scene` as the root plus traversal, `MeshNode`, `CameraNode`, `LightNode`.
- [x] **P1** Visibility, layers/culling masks, tags, lookup by name/path. Tags are not done.
- [x] **P1** **Frustum culling** + hierarchical bounding volumes (AABB bottom-up). World bounds
      are cached by `worldVersion`; hierarchical AABBs are absent.
- [ ] **P2** A spatial index (BVH or loose octree) for culling and raycasting.
- [ ] **P2** LOD groups with automatic switching by screen size.
- [ ] **P2** Decide: a classic object tree or **an ECS with archetypes**. For Dart the argument
      for ECS is stronger than usual, because of GC and linear traversal.
- [ ] **P3** Occlusion culling (no compute — only CPU software or hi-z through depth
      downsampling).
- [ ] **P3** Scene streaming, prefabs / subtree instancing.

### Layer 3. Geometry

- [x] **P0** `VertexLayout` / attribute descriptors, `Mesh` = vertex buffer + index buffer +
      submeshes.
- [x] **P0** Primitives: box, plane, sphere (UV + ico), cylinder, cone, torus, capsule, quad,
      grid. Built on the `Shape` abstraction, plus `LatheShape`.
- [ ] **P1** Utilities: normal recomputation, tangent generation (mandatory for normal maps),
      vertex welding/deduplication, merge, flip, AABB/sphere computation.
- [ ] **P1** Skinning: bone matrices in a uniform buffer (mind the size limit!) or in a texture.
- [ ] **P1** Instancing: per-instance attributes in a separate vertex buffer
      (⚠️ check whether `draw()` has `instanceCount` on master).
- [ ] **P2** Morph targets (positions/normals, weights).
- [ ] **P2** Static batching (merge by material), a `BatchedMesh` equivalent.
- [ ] **P2** Procedural builders (extrude, revolve, tube, text geometry), CSG.
- [x] **P2** Geometry readback (needed by physics and by raycasting against live geometry).
      flutter_gpu cannot read a buffer back, so `GpuMesh` retains the `MeshData` it was uploaded
      from instead; `keepSourceData: false` opts out where memory matters more than picking.
- [ ] **P3** Automatic LOD generation (mesh simplification), meshopt-compatible vertex order
      optimisation.

### Layer 4. Cameras and input

- [x] **P0** `PerspectiveCamera`, `OrthographicCamera`, view/projection, frustum extraction.
- [ ] **P0** **Reversed-Z** and (optionally) an infinite far plane — otherwise z-fighting on
      mobile with d24.
- [x] **P1** Controllers: orbit, first-person, fly, trackball. Orbit only.
- [x] **P1** **A Flutter gesture bridge → camera**: `Listener`/`GestureDetector`, pinch zoom,
      two fingers = pan, inertia. On mobile this is half of the perceived quality.
- [ ] **P2** Multiple viewports, split-screen, mini-map, render-to-widget.
- [ ] **P2** Camera jitter for TAA, physically correct exposure (aperture/shutter/ISO).

### Layer 5. Materials and shading

- [x] **P0** Settle the strategy: **uber-shader vs pre-generated permutations vs hybrid** (see §2.3).
      This is the most expensive decision in the project — reworking it later hurts. We chose AOT
      permutations, one shader per lighting model.
- [x] **P0** `Material` with typed uniforms and texture slots, `UnlitMaterial`.
- [x] **P1** **PBR metal-roughness**, glTF-compatible: baseColor, metallic, roughness, normal,
      occlusion, emissive, ORM packing, per-map UV set and `KHR_texture_transform`. So far only
      baseColor, metallic and roughness; no normal, AO or emissive maps.
- [x] **P1** Alpha modes: opaque / mask (cutoff) / blend, double-sided, vertex colours. Blend and
      double-sided are there; cutoff is not applied in the shader, and vertex colours are decoded
      but not shaded.
- [ ] **P1** A "GLSL uniform block → Dart class" code generator, so bindings are type-safe.
- [ ] **P2** Additional models: toon/cel, matcap, gradient, wireframe, unlit-emissive.
- [ ] **P2** glTF extensions: clearcoat, sheen, transmission, volume, iridescence, anisotropy,
      emissive_strength, specular.
- [ ] **P2** **Shader hot reload** in debug (flutter_scene does it — the bar is set).
- [ ] **P3** A visual material graph **in the editor** with code generation into the bundle.
- [ ] **P3** Order-independent transparency (weighted blended), refraction.

### Layer 6. Lighting and shadows

- [x] **P1** Directional, point, spot; attenuation, cone falloff, intensities in physical units.
      All three are shaded, with glTF's inverse-square falloff plus the range window and the
      smooth cone ramp. Intensities are still unitless multipliers rather than lumens.
- [x] **P1** **The lighting scheme**: forward with a lamp limit → later **clustered forward**.
      On tile-based mobile GPUs deferred loses; clustered is the right target. Forward with a
      limit of 8 is done: the lights live in `vec4 x[8]` uniform arrays with the count as a
      uniform, so switching a light on or off leaves the pipeline alone. Which eight matter when
      there are more is the question clustered forward answers; today the extras are dropped and
      counted.
- [ ] **P1** **IBL**: irradiance (SH9 or a small cubemap) + a prefiltered specular cubemap (GGX
      across mip levels) + a BRDF LUT. Prefiltering is done with render passes into mip levels,
      since there is no compute. ⚠️ Requires render-to-mip-level on master.
- [ ] **P1** Shadow maps for directional light (one map → CSM later), PCF filtering, bias/normal
      offset.
- [ ] **P2** **A shadow atlas** (all lights in one texture — there are no texture arrays).
- [ ] **P2** Cascaded shadow maps, cube shadows for point lights, spot shadows.
- [ ] **P2** SSAO/GTAO, contact shadows, ambient occlusion from maps.
- [ ] **P3** Light probes, lightmaps, IBL shadows (as in Babylon 8), volumetric light / god rays.
- [ ] **P3** Area lights (LTC), light cookies.

### Layer 7. Render pipeline / frame graph

- [x] **P0** `Renderer`: build the draw list, sort it, run the passes, present the frame.
- [x] **P0** Flutter integration: render to a texture → `ui.Image` → widget, correct
      `devicePixelRatio`, resize, `Ticker`/`SchedulerBinding` as the time source.
- [x] **P1** Sorting: opaque by (pipeline, material, mesh) + front-to-back; transparent
      back-to-front by depth. A radix sort over packed keys, with the pipeline as the high bits.
- [x] **P1** Tonemapping (Khronos PBR Neutral) + exposure. Done.
- [ ] **P1** An HDR target (`r16g16b16a16Float`). Right now tonemapping is applied in the shader
      right before writing into an 8-bit target, so there is no intermediate HDR buffer — and it
      will be needed for bloom and for anything that reads luminance above 1.
- [x] **P1** Correct colour management: linear space internally, sRGB on output.
- [x] **P1** MSAA + resolve, an (optional) depth prepass, clearing/storing attachments with the
      right `LoadAction`/`StoreAction` (on mobile this is a direct bandwidth saving). The depth
      prepass was not done.
- [ ] **P2** **A frame graph**: passes as nodes with declared inputs and outputs, automatic target
      reuse and ordering. The Babylon 8 / PlayCanvas route. Expensive, but otherwise
      post-processing turns into spaghetti.
- [ ] **P2** A post-processing stack: bloom, FXAA/SMAA, vignette, grain, chromatic aberration,
      colour grading (2D-tiled LUT), fog (linear/exp/height).
- [ ] **P3** TAA (needs a motion vector pass + jitter), DOF, SSR, motion blur, god rays.
- [ ] **P3** MRT / prepass for screen-space effects (⚠️ check support for several
      `ColorAttachment`s in one `RenderTarget`).

### Layer 8. Animation

- [x] **P1** `AnimationClip` + tracks (translation / rotation / scale / weights / arbitrary
      property), step / linear / cubicspline interpolation (the full glTF set). Weights are
      decoded but have nothing to drive until morph targets exist; arbitrary properties are not
      done.
- [x] **P1** `AnimationPlayer`: play/pause/seek/loop/speed, bound to frame time. Wrap modes are
      once / loop / ping-pong, and playback takes a delta so the caller chooses the clock.
- [ ] **P1** `Skeleton` + joint hierarchy, inverse bind matrices, application to skinning.
- [ ] **P2** Blending: layers, crossfade, additive, per-bone masks.
- [ ] **P2** Morph target weights in animation.
- [ ] **P3** IK (two-bone, FABRIK, look-at), a state machine / blend tree, retargeting.
- [x] **P3** Procedural animation, tweens, spring/physics-based (can lean on the Flutter approach).

### Layer 9. Assets

- [x] **P1** **A glTF 2.0 / GLB loader** — done for the geometry part: the container, buffers
      (BIN chunk / base64 / external files), accessors with stride, normalized and sparse, the
      node graph with TRS and matrices, metal-rough materials, images, strip/fan conversion into
      triangles, flat normal generation per the spec, mirrored transform detection, the node
      hierarchy kept index-aligned with the file, and animations. Still to do: skins, cameras,
      morph targets.
- [ ] **P1** Loading in an **`Isolate`**: JSON parsing, image decoding, decompression — all off
      the UI thread, handed over via `TransferableTypedData`. Otherwise loading janks.
- [ ] **P1** An asset cache with ref counting, load cancellation, progress.
- [ ] **P2** **Our own binary scene format** (flatbuffers, like `.fsceneb`) + an offline converter:
      zero-parse loading instead of parsing glTF at runtime.
- [ ] **P2** Textures: mip chains, sRGB flags, KTX2 → ⚠️ find out whether master has compressed
      `PixelFormat`s; if not — transcoding to RGBA8 and honest memory accounting.
- [ ] **P2** HDR/EXR for environment maps, equirect → cubemap conversion.
- [ ] **P2** Meshopt decompression (realistic in Dart), Draco (needs native/FFI — more expensive).
- [ ] **P2** Hot reload of models/textures/environments in debug.
- [ ] **P3** Export (glTF/USDZ), streaming, virtual textures.

### Layer 10. Interaction

- [x] **P1** CPU raycasting against the scene (through a BVH), a `HitResult` with point, normal,
      UV, submesh. `Raycaster` casts from NDC or from widget coordinates, rejects on the same
      cached world sphere culling uses, then tests triangles in the mesh's own space — the ray is
      transformed, not the geometry. Still a linear pass over the mesh registry; the BVH replaces
      that first stage without touching the rest.
- [ ] **P2** Raycasting against skinned geometry, GPU picking via an id buffer.
- [ ] **P2** **Flutter widgets in 3D space** with forwarded pointers — a unique advantage of
      Flutter over web engines; flutter_scene already does it.
- [ ] **P2** Gizmos: translate/rotate/scale for an editor.
- [ ] **P3** Accessibility: semantics nodes for 3D objects (flutter_scene has this too).

### Layer 11. Particles and VFX

- [ ] **P2** A CPU particle system (there is no compute): emitters, modifiers, curves,
      billboard/stretched/mesh rendering, instancing.
- [ ] **P2** Sprites/billboards, wide lines (as geometry — there are no native thick lines),
      trails, decals (via stencil / projection).
- [ ] **P3** Sky/atmosphere (procedural, Hillaire), water surfaces, terrain.
- [ ] **P3** GPU particles via a vertex shader + ping-pong state textures (working around the
      absence of compute).

### Layer 12. Text in 3D

- [ ] **P2** An SDF/MSDF font atlas + renderer, or rasterising Flutter text into an atlas.
- [ ] **P2** Screen-space captions and labels as ordinary Flutter widgets on top of the scene
      (simpler and better looking than in web engines).

### Layer 13. Physics (integration, not our own implementation)

- [ ] **P3** A physics world abstraction plus backends. Realistic routes: Rapier via FFI, Jolt via
      FFI, or pure Dart for simple cases. The ecosystem already has `flutter_scene_rapier` and
      `flutter_scene_box3d` — worth studying.
- [ ] **P3** Collision shapes from geometry, a character controller, raycast queries against
      physics.

### Layer 14. Tooling and DX

- [x] **P1** A debug overlay: FPS, UI/raster time, draw calls, triangles, resource memory. We have
      UI and raster durations from `FrameTiming`, renderer CPU time, submit time, draws, pipeline
      switches, culled count, vtx/tri and MSAA state. Resource memory is still missing.
- [x] **P1** Debug drawing: wireframe (`setPolygonMode`, free), normals, bounding boxes, light
      gizmos, axes, grid. All of it except the ground grid, plus camera frusta; the whole overlay
      is one `PrimitiveType.line` draw out of a reusable buffer.
- [x] **P1** Profiling through the `dart:developer` Timeline (`startSync`/`finishSync`) with frame
      phases marked up; profile **only in profile/release**. Phases: `Renderer.render`,
      `RenderList.build`, `RenderList.sort`, `Renderer.encodeDraws`, `DebugDraw.build`,
      `DebugDraw.encode`, `CommandBuffer.submit`, plus async `TimelineTask` spans around model
      decoding.
- [ ] **P2** **Golden-image render tests** in CI — the only protection against a new master
      revision silently ruining the picture.
- [ ] **P2** CI that builds shader bundles on several master revisions.
- [ ] **P3** A scene editor (a separate project in terms of scope).

---

## 4. Verified against the sources (Flutter 3.44.6, stable)

It turned out that `flutter_gpu` ships inside the SDK even on stable —
`bin/cache/pkg/flutter_gpu`, 1757 lines of Dart in total. That made it possible to close all four
questions by reading the code rather than guessing from the docs. Below are facts, not
assumptions.

| Question | Answer on stable 3.44.6 | Where to look |
|---|---|---|
| Compressed formats (ASTC/BC/ETC2) | **No.** Exactly 16 `PixelFormat` values, all uncompressed | `lib/src/formats.dart:36` |
| `instanceCount` in `draw()` | **No.** `void draw()` takes no parameters at all | `lib/src/render_pass.dart:450` |
| MRT | **Structurally present**: `RenderTarget.colorAttachments` is a `List`, and `_setColorAttachment(ctx, index, …)` is called in an `indexed` loop. `setColorBlendEnable` accepts a `colorAttachmentIndex` | `lib/src/render_pass.dart:222,240,354` |
| Render-to-mip-level | **There are no mips at all.** `Texture` has no `mipCount`, `overwrite()` writes only the base level, and there is only `getBaseMipLevelSizeInBytes()` | `lib/src/texture.dart:82,96` |

Additional findings (important ones that were not in the docs):

- **Mipmaps do not exist as a concept.** This is harsher than "no compressed formats": without a
  mip chain there is no trilinear filtering (minification aliases), no prefiltered specular for
  IBL, no bloom over a mip pyramid. `MipFilter` is present in `SamplerOptions`, but it is
  meaningless with a single level. That is exactly why `flutter_scene` requires master from
  2026-06-09 — render-to-mip-level landed there.
- **`sampleCount` is only 1 or 4** — the check is explicit, anything else throws
  (`texture.dart:30`).
- **`StorageMode.deviceTransient` = tile memory.** For MSAA and depth attachments this is a direct
  saving of memory and bandwidth on mobile; the spike uses it. Such textures cannot be bound to a
  shader and cannot be `LoadAction.load`ed.
- **`Texture.asImage()`** is a direct path from a GPU texture to a `ui.Image` without a CPU copy.
  This is the bridge into the widget tree.
- **`UniformSlot` provides reflection**: `sizeInBytes` and `getMemberOffsetInBytes(name)`. Uniform
  block offsets do not need to be hard-coded — and should not be, because the GLSL alignment rules
  determine them anyway.
- **Uniform blocks are reflected by the STRUCT TYPE name, textures by the variable name.** For
  `uniform FrameInfo { … } frame_info;` the reflection key is `FrameInfo`, while for
  `uniform sampler2D base_color_texture;` it is `base_color_texture`. A mismatch is not caught at
  binding time: `getUniformSlot` returns an object, and only `sizeInBytes == null` reveals that
  the block is missing.
- **Unused members of a uniform block disappear from reflection.** A shader that does not read
  `light_direction` will return `null` for its offset. The uniform-writing code must tolerate
  missing members, otherwise the unlit model crashes.
- **`#include <...>` in GLSL works** (verified with impellerc and `--include=shaders`). It is the
  only way to guarantee that all shader permutations declare the same uniform block.
- **The cost of permutations is measurable**: a bundle with one fragment shader is 12.5 KB, one
  with six lighting models plus a vertex shader is 80 KB.
- **`impellerc` supports `--input-type=comp`**, so compute exists in the offline compiler but was
  not exposed in the Dart API. The limitation is on the bindings side, not the backend.

### What only showed up at runtime

Reading the sources is not enough — the following surfaced only on a live GPU, and every one of
them fails "silently", without a single error in the log:

1. **Flutter GPU is enabled at the application level.** The `FLTEnableFlutterGPU` key in
   `Info.plist`, or the `--enable-flutter-gpu` flag. Without it `ShaderLibrary.fromAsset` throws at
   startup — the only one on this list that is at least visible. `FLTEnableImpeller` is needed
   separately: on macOS Impeller is not yet the default renderer, and without that key the built
   application only launches via `flutter run --enable-impeller` and crashes on a double click.
2. **`Viewport` and `Scissor` default to zero size,** and the API does not complain about drawing
   into such a rectangle. Set them explicitly every frame.
3. **Reflection cannot be trusted on the question of "bind or not".** If a shader *declared* a
   uniform block (for instance, pulled it in through a shared `#include`) but reads nothing from
   it, reflection still reports the block with a **non-zero size**, whereas the compiled Metal
   function has no corresponding buffer at all: the signature degenerates into
   `normals_fragment_main(in [[stage_in]])`. Binding such a "phantom" block yields a `SIGSEGV`
   inside `setFragmentBuffer:offset:atIndex:` — a native crash without a Dart stack trace. A
   `sizeInBytes == null || == 0` check **does not save you**. The engine has to know from its own
   permutation metadata which blocks the shader actually uses, and a shader that does not need
   material inputs should not declare them. Our `Normals` debug model stepped on this; the cure is
   splitting the shared header (`lib/color.glsl` without uniforms, `lib/surface.glsl` with them)
   plus an explicit `LightingModel.usesFragInfo` flag.
4. **There is no non-indexed draw.** `draw()` takes no parameters, and binding only a vertex
   buffer produces nothing: the call succeeds, the draw counter goes up, and not a pixel changes.
   The debug line overlay hit this — 30 vertices bound, uniform block reflected at the right size
   and offset, output empty. The fix is to bind an identity `0, 1, 2, …` index buffer, which for a
   line list carries no information at all. Worth keeping in a device buffer that only grows,
   rather than re-uploading a constant every frame.
5. **Arrays in a uniform block work.** This was the one open question behind the whole lighting
   design, and the answer is unambiguous: `vec4 lights[8]` survives into the compiled Metal
   struct, and reflection reports the block at the std140 size with the array's base offset in
   the right place — 160 bytes for `vec4 + vec4[8] + vec4`, with the member after the array at
   144. Individual elements are *not* reflected (`lights[0]` returns null), so the Dart side
   writes the array as one contiguous block from its base offset, which is correct because the
   std140 stride for a `vec4` array is a flat 16 bytes. `shaders/spike_array.frag` keeps the
   probe for the next SDK bump.
6. **`CommandBuffer.submit()` is asynchronous.** Calling `HostBuffer.reset()` right after it
   rewinds a bump allocator the GPU is still reading from. The symptom is not a crash but flickering
   geometry and lighting under load, which is far harder to diagnose. The cure is a ring of host
   buffers sized by the number of frames in flight (3 for us).

It is worth noting separately that the most time-expensive mistake was not in flutter_gpu at all
but in our own projection matrix: `Matrix4.setEntry` takes `(row, column)`, and two elements of the
depth row are easy to swap. The result is a black viewport with no errors whatsoever. That kind of
thing is caught by a unit test without a GPU (`test/projection_test.dart`), and it is an argument
for keeping the camera and the maths in a layer that does not depend on flutter_gpu.

What remains unverified: MRT only by code structure, its runtime behaviour was not tested; a
benchmark of draw calls and GC pauses at 10k transforms was not done.

---

## 5. Recommended sequence

1. **A spike**: a triangle → a textured cube with a transform and depth testing. Along the way,
   answer the 4 questions from §4.
2. **Layers 0 + 1 + 2 (P0)**: the RHI wrapper, the pipeline cache, allocators, the scene graph,
   the camera, input.
3. **The first milestone**: a glTF model with a PBR material and IBL, MSAA, tonemapping, an orbit
   camera. At this point it becomes clear whether the chosen shader strategy holds up.
4. **Layers 6–7 (P1)**: shadows, the HDR pipeline, sorting, bloom.
5. **Layers 8–9 (P1)**: animation, skinning, asynchronous loading in an Isolate, our own binary
   format.
6. **The frame graph** — before post-processing becomes unmanageable.
7. Then on through the P2/P3 priorities, depending on the problem domain.

---

## Sources

- [flutter_gpu library — Dart API](https://api.flutter.dev/flutter/flutter_gpu/)
- [Flutter-GPU.md — engine docs](https://github.com/flutter/engine/blob/main/docs/impeller/Flutter-GPU.md)
- [Getting started with Flutter GPU — Flutter Blog](https://flutter.dev/blog/getting-started-with-flutter-gpu)
- [What Is Flutter GPU: How It Works, When to Use It, Limitations — LeanCode](https://leancode.co/glossary/flutter-gpu)
- [flutter_scene — pub.dev](https://pub.dev/packages/flutter_scene)
- [bdero/flutter_scene — GitHub](https://github.com/bdero/flutter_scene)
- [Introducing Babylon.js 8.0](https://babylonjs.medium.com/introducing-babylon-js-8-0-77644b31e2f9)
- [Announcing Babylon.js 8.0 — Windows Developer Blog](https://blogs.windows.com/windowsdeveloper/2025/03/27/announcing-babylon-js-8-0/)
- [BabylonJS/Babylon.js — DeepWiki overview](https://deepwiki.com/BabylonJS/Babylon.js/1-overview)
- [mrdoob/three.js — DeepWiki](https://deepwiki.com/mrdoob/three.js)
- [Three.js — WebGPURenderer manual](https://threejs.org/manual/en/webgpurenderer.html)
- [Clustered Lighting — PlayCanvas Developer Site](https://developer.playcanvas.com/user-manual/graphics/lighting/clustered-lighting/)
- [PlayCanvas Engine](https://playcanvas.com/products/engine)
- [[Impeller] Support compute passes/shaders — flutter/flutter#109346](https://github.com/flutter/flutter/issues/109346)
