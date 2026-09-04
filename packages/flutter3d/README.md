# flutter3d

**An independent implementation of a real-time 3D engine for Flutter**, written
from the geometry layer up. It is not a fork, a binding or a wrapper around
another engine, and it is not affiliated with the Flutter team.

Homepage: **<https://flutter3d.pleion.dev>** · API reference:
**<https://flutter3d.pleion.dev/docs>** · Source:
**<https://github.com/pleiondev/flutter3d>**

## What it is good at

- **Three graphics backends behind one interface.** `flutter_gpu` on desktop,
  WebGL2 in a browser, and a software rasteriser with no GPU at all. User code
  names none of them, and a fourth changes nothing above the HAL — which is
  checked by a conformance suite rather than asserted.
- **Rendering that can be tested without a graphics card.** The software backend
  gives a second, independently written set of reference images, so a golden that
  passes is two implementations agreeing rather than one agreeing with itself.
  `flutter3d_testing` hands that to a game as a one-call API.
- **Three genre templates, each with a playable demo** — shooter, platformer and
  racing. They are packages rather than samples, so a new game starts from one
  instead of from an empty screen, and they are the reason the engine's boundaries
  are real: nothing in `packages/flutter3d*` may name a genre, and a scan enforces
  it.
- **A deterministic simulation.** A fixed step that reaches for no clock and no
  loose dice, a generator whose state can be written down, and `InputTape` — so a
  run replays exactly, a bug arrives as a file attached to a report, and a test can
  play a whole level.
- **A game layer that does not depend on the renderer.** Collisions, input and
  the step are reachable from an ordinary unit test, which is where the bugs that
  never appear in a screenshot live.
- **Extension points instead of forks**: a decoder for a model format the engine
  does not know, a decoder for a material format, a system added to somebody
  else's simulation step, a contributor drawing into somebody else's render pass,
  and a lighting model of your own if you build your own shader bundle.
- **Its own level format and editor**, validated before a run, reporting the
  coordinate of a problem rather than "the file is broken".

`ARCHITECTURE.md` at the repository root is how all of it fits together and why.

What works today:

- a CPU-side geometry layer with no GPU dependency: vertex layouts, `MeshData`,
  `MeshBuilder`;
- **surfaces of revolution** (`LatheShape`) as the base generator — sphere,
  cylinder, cone, torus, capsule and disc all derive from it, plus an arbitrary
  profile (the "vase"); shapes are values (`Shape`), not static methods;
- six **switchable lighting models**, each its own pre-built fragment shader:
  Unlit, Lambert, Blinn-Phong, PBR (GGX), Toon, Normals;
- **skinning**: glTF skins decoded into a `Skeleton` of ordinary scene nodes, a
  separate skinned vertex stage with 64 joint matrices in a uniform array, four
  weights a vertex, and bounds taken from the posed skeleton rather than the
  bind pose;
- **`.f3d`**, the engine's own container: an offline converter does the decoding
  once and the loader hands out typed-data views over the file, which takes the
  teapot from 4.54 ms as OBJ to 1.1 us — with the two renders identical pixel
  for pixel;
- **a BVH** over world bounds, shared by culling and picking and rebuilt only
  when something moves, plus **LOD groups** that switch by screen coverage;
- **directional shadows**: the pass is a render view whose camera is the light,
  with an orthographic volume fitted to the scene, linear depth in a colour
  target because depth textures cannot be sampled, front-face culling, PCF 3x3
  and both a depth bias and a normal offset;
- **an HDR pipeline**: the scene renders into `r16g16b16a16Float`, and tone
  mapping, exposure and the sRGB encode happen in a composite pass — which is
  what lets **bloom** exist at all, built from a chain of half-size targets
  rather than from mip levels — flutter_gpu had none when it was written, and
  now that it does, a bloom chain still wants separate targets it can blur
  between;
- **material maps**: normal (with a full TBN), ORM, occlusion and emissive, plus
  alpha masking and vertex colours — with neutral fallback textures instead of
  per-map flags, so the shader needs no branch and the engine no bookkeeping;
- **tangents**: generated with Lengyel's method where a mesh has none, taken
  analytically where the surface knows them, and checked against a real
  exporter's output on `NormalTangentMirrorTest`;
- **up to eight lights of any type** — directional, point and spot with glTF's
  inverse-square falloff, range window and cone ramp — packed into `vec4[8]`
  uniform arrays with the count as a uniform, so switching a light on or off
  never rebuilds a pipeline;
- **decoders for glTF 2.0 / GLB and Wavefront OBJ** behind one `ModelDocument`
  abstraction with shared `SurfaceMaterial` / `TextureBinding` / `EncodedImage`,
  so the GPU upload path is written once for both formats;
- decoding on a **background isolate** plus a reference-counted asset cache;
- a **scene graph**: `SceneNode` with version stamps instead of dirty flags,
  `CameraNode` + `Projection`, `LightNode`, an orbit camera driven by gestures;
- frustum culling, draw-call sorting with the pipeline as the high-order key,
  a pipeline cache, 4x MSAA, depth testing, wireframe (Impeller only — see
  `RenderSettings.wireframe`), linear-space shading with
  tone mapping (Khronos PBR Neutral) and exposure;
- **observability**: a line-based debug overlay (bounds, vertex normals, light
  gizmos, world axes, camera frusta) drawn in one call, `dart:developer` Timeline
  spans around every frame phase, and a frame panel with UI/raster/render/submit
  timings next to draw, pipeline-switch and cull counts;
- **CPU picking**: ray/AABB, ray/sphere and Möller–Trumbore ray/triangle, a
  `Raycaster` that casts from widget coordinates, and tap-to-select in the demo
  with the hit outlined by the debug overlay;
- **glTF transform animation**: all three interpolations (`STEP`, `LINEAR`,
  `CUBICSPLINE` with authored tangents), slerped rotations, an `AnimationPlayer`
  with play/pause/seek/speed and once/loop/ping-pong, and the decoded node
  hierarchy rebuilt on instantiation so an animated parent carries its subtree;
- 822 tests — geometry, projection, scene, sorting, debug draw, intersections,
  raycasting, animation, skinning, lighting, tangents, render targets, BVH, LOD,
  glTF, OBJ and `.f3d` — all without a GPU.

## Running

```bash
# 1. Build the shader bundle (required after any Flutter SDK change).
#    It lands in packages/flutter3d_impeller/assets/shaders/, an asset of that
#    package rather than this one, so a dependent application loads it as
#    packages/flutter3d_impeller/assets/shaders/flutter3d.shaderbundle —
#    the string GpuRenderBackend.defaultBundleAsset holds — without declaring
#    anything. Generated, so it is not in the repository; the published package
#    carries a built one, so this step is for a checkout.
(cd ../flutter3d_impeller && ./tool/build_shaders.sh)

# 2. Build the demo's own bundle, which it loads at runtime rather than links.
#    Declared as an asset in example/pubspec.yaml and gitignored like the one
#    above, so without it the build stops before the demo opens.
(cd example && ./tool/build_shaders.sh)

# 3. Run the demo
(cd example && flutter run -d macos)
```

The `--enable-impeller` and `--enable-flutter-gpu` flags are not needed: both are
switched on through the application's `Info.plist`, so the built app also works
when launched by double-clicking it. Note **the application's** — these are
per-app settings, so every app that draws through this package has to set them
for itself.

### Capturing a frame

Judging a render by eye does not scale, and grabbing the window with
`screencapture` needs a logged-in session with the display awake. The demo can
therefore write the render target straight to a PNG and quit:

```bash
flutter run -d macos \
  --dart-define=FLUTTER3D_CAPTURE=shot.png \
  --dart-define=FLUTTER3D_CAPTURE_FRAME=200 \
  --dart-define=FLUTTER3D_DEBUG_DRAW=bounds,normals,lights,axes,frusta \
  --dart-define=FLUTTER3D_SOURCE=teapot \
  --dart-define=FLUTTER3D_SPIN=false \
  --dart-define="FLUTTER3D_LIGHTS=key light,spot light" \
  --dart-define=FLUTTER3D_ANIM_TIME=0.75
```

A relative capture path lands in the app's sandbox temp directory, and the run
prints the absolute path along with the frame's draw, pipeline, light, cull and
debug-line counts. `FLUTTER3D_SOURCE` matches a model chip by substring;
`FLUTTER3D_SPIN=false` stops the turntable so two captures differ only by what
is being tested; `FLUTTER3D_LIGHTS` names which lights start switched on; `FLUTTER3D_ANIM_TIME`
freezes any clip at a given second, without which two captures of an animated
model are not comparable — a format that loads faster starts playing sooner.

## Loading models

Both decoders emit a **shared abstraction**, `ModelDocument`: a list of
`ModelSurface`, a list of `SurfaceMaterial`, a list of `EncodedImage`, and
`warnings`. That is what makes `ModelAsset.fromDocument()` the single upload path
(mesh and image deduplication, material conversion), and it means adding a third
format is a matter of writing a decoder rather than touching the loader.

Materials are normalised to metal-rough, because that is what glTF defines and what
the shaders implement. OBJ predates PBR, so its parameters are **explicitly
approximated**: `Kd` becomes the base colour, the Phong exponent `Ns` becomes
roughness, and a bright neutral `Ks` is the only hint of metalness available. The
approximation is documented in `MtlMaterial` rather than hidden.

Decoding runs on a background isolate. **File reads stay on the UI isolate** and
sibling files are requested back over a port — see the pitfalls table for why the
obvious alternative does not work.

### Wavefront OBJ

| | |
|---|---|
| Faces | `v`, `v/vt`, `v//vn`, `v/vt/vn`; negative (relative) indices; polygons fanned into triangles |
| Vertices | deduplicated by the (position, UV, normal) triple — the unit OBJ actually addresses |
| Normals | when `vn` is absent, **smooth** normals are generated (area-weighted). Unlike glTF the format prescribes nothing, files routinely omit them, and the geometry they omit them for is curved — flat normals on a teapot look broken. `flat` and `none` are also available |
| UVs | V is flipped by default: OBJ texture space has its origin at the bottom left. This is the single most common cause of upside-down textures on OBJ imports |
| Groups | `g`, `o` and `usemtl` start a new surface, so a multi-material file yields several draws |
| Materials | `.mtl` through a resolver: `newmtl`, `Kd`, `Ks`, `Ns`, `d`, `Tr`, `map_Kd` |
| Robustness | unknown directives, malformed faces and missing libraries go to `warnings` rather than failing the file |

The test model is the [Utah teapot](https://github.com/mauricelam/Teapot)
(`flutter3d_samples`): `v` and `f` only, 1202 vertices, 2256 triangles, no
normals and no materials — exactly the case that needs normal generation.

## glTF / GLB

The layer in `lib/src/engine/assets/gltf/` depends on neither flutter_gpu, `dart:io`
nor `dart:ui`: external files arrive through an `AssetUriResolver` callback and
images are handed back still encoded. That is what makes it testable without a GPU
or a Flutter binding, and usable from an isolate.

What is supported:

| | |
|---|---|
| Containers | `.glb` (chunk parser with padding, unknown chunks ignored) and `.gltf` |
| Buffers | the GLB `BIN` chunk, base64 `data:` URIs, external files through a resolver |
| Accessors | every componentType, `byteStride` (interleaved data), `normalized` with the symmetric clamp for signed types, sparse, and accessors with no bufferView (zeros) |
| Topologies | TRIANGLES; STRIP and FAN are rewritten as triangle lists so no pipeline permutation is needed per topology |
| Attributes | POSITION, NORMAL, TEXCOORD_0, TANGENT, COLOR_0 — only those the target `VertexLayout` declares are read |
| Tangents | TANGENT when the file has it, otherwise generated with Lengyel's method as the spec requires |
| Normals | an absent NORMAL produces **flat** normals, as the spec requires, which de-indexes the mesh |
| Node graph | `matrix` and TRS, accumulated transforms, meshes reused across nodes, cycle guard |
| Materials | metal-rough, all texture slots, alphaMode/cutoff, doubleSided, `KHR_materials_unlit`, `KHR_materials_emissive_strength` |
| Mirroring transforms | detected from the determinant's sign; the winding order is flipped per instance |
| Node hierarchy | kept index-aligned with the file, transform-only nodes included, because animation channels address nodes by index |
| Skins | `joints`, `inverseBindMatrices`, `skeleton`, and JOINTS_0/WEIGHTS_0; a primitive with joint attributes gets the skinned vertex layout, chosen from the data rather than from the caller |
| Animations | all samplers and channels; `STEP`, `LINEAR` and `CUBICSPLINE`; translation, rotation, scale and weights (weights decoded but not applied) |

Not there: morph targets, cameras, Draco and meshopt (reported in `warnings`),
TEXCOORD_1 and up. KTX2 is read — `KHR_texture_basisu`'s Basis ETC1S files
transcode to RGBA8, and a file's own BC, ETC2 or ASTC blocks upload as they
are where the device samples them — with UASTC and Zstandard still refused by
name.

Non-fatal decoding problems land in `warnings` and are surfaced in the UI — a
skipped primitive or an ignored extension explains a model that looks odd but
still loaded.

The sample models are the official Khronos
[glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets), picked to
cover all three ways of storing the data. They live in
[`flutter3d_samples`](../flutter3d_samples) — a dev dependency of this package
and not a real one, so a game gets the decoders without 4.1 MB of the fixtures
they were checked against. Their terms are in
[ATTRIBUTION.md](../flutter3d_samples/assets/ATTRIBUTION.md).

## The `.f3d` container

[ARCHITECTURE.md](../../ARCHITECTURE.md), section 14, measured the decoders and
found the format matters far more than the language: the same geometry is about 360x slower to load as OBJ
text than as a binary buffer, and native code does not close that. `.f3d` moves
the parse off the device entirely.

```bash
dart run tool/convert_asset.dart ../flutter3d_samples/assets/teapot.obj \
  -o ../flutter3d_samples/assets/f3d/teapot.f3d
```

Vertex and index arrays are stored exactly as `MeshData` holds them, so loading
builds `Float32List.view`s over the file rather than copies — every blob entry
is 4-byte aligned precisely so those views are legal. A section directory rather
than fixed header fields, so a reader skips a kind it does not know and the
version only has to change when an existing record does.

It slots in without touching anything: `F3dDocument` is a `ModelDocument`, so
`ModelAsset.fromDocument`, the resource cache and instancing are all unchanged —
which is what that abstraction was introduced for. The converter re-reads what it
wrote and compares it against the source before reporting success.

| teapot | load |
|---|---|
| OBJ (parse, dedup, smooth normals) | 4.54 ms |
| `.f3d`, every array touched | 1.1 us |

The file is larger than its source — 102 KB against 69 KB for the teapot —
because indices stay 32-bit and nothing is compressed. That is the trade the
format is making: narrowing indices or deflating the blob would reintroduce the
per-load work it exists to remove.

## Pitfalls already hit

None of these are project setup — they are conditions without which Flutter GPU
either does not start or silently renders nothing. Worth keeping to hand.

| Symptom | Cause and fix |
|---|---|
| `Failed to initialize ShaderLibrary: Flutter GPU must be enabled via the Flutter GPU manifest setting` | Flutter GPU is enabled **per application**, not just per channel. Set `FLTEnableFlutterGPU` to `true` in `macos/Runner/Info.plist` (already done), or pass `--enable-flutter-gpu`. On Android the key is `io.flutter.embedding.android.EnableFlutterGPU` in `AndroidManifest.xml` |
| `Failed to initialize ShaderLibrary: Flutter GPU requires the Impeller rendering backend, but Impeller is not enabled` | Impeller is not the default renderer on macOS yet. Without `FLTEnableImpeller` set to `true` in `Info.plist` (already done) the app only works through `flutter run --enable-impeller`, and double-clicking the built `.app` fails |
| `The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 10.15, but the range of supported deployment target versions is 12.0 to 27.0.x` | `flutter create` generates 10.15 and current Xcode will not build it. Raised to 12.0 in `macos/Runner.xcodeproj/project.pbxproj` |
| `Bad state: The shader has no uniform block named "frame_info"` | Impeller reflects a uniform block under its **struct type name**, not the variable name. For `uniform FrameInfo { … } frame_info;` the key is `FrameInfo`. Textures are the opposite: `bindTexture` looks them up by variable name (`base_color_texture`) |
| `SIGSEGV` in `AGXG15XFamilyRenderContext setFragmentBuffer:offset:atIndex:` inside `RenderPass::Draw()` | A shader *declared* a uniform block (via a shared `#include`) but never reads it. Reflection still reports the block with a non-zero size while the compiled Metal function binds no buffer for it, and binding that phantom block kills the process with no Dart stack trace. Checking `sizeInBytes` is **not enough**: the permutation needs explicit metadata (`LightingModel.usesFragInfo`), and a shader with no material inputs should not declare the block at all — which is why the header is split into `lib/color.glsl` and `lib/surface.glsl` |
| Geometry and lighting flicker under load | `CommandBuffer.submit()` is **asynchronous**. Calling `HostBuffer.reset()` right after it rewinds a bump allocator the GPU may still be reading, so the next frame overwrites live uniform data. Use a ring of ~3 host buffers, one per frame in flight |
| The model is clipped against the near plane, or "half of it vanished" | `vector_math.makePerspectiveMatrix` produces OpenGL depth `[-1, 1]` while Impeller follows the Metal/Vulkan convention `[0, 1]`. Our matrix lives in `PerspectiveProjection.toMatrix` (`lib/src/engine/scene/camera_node.dart`) |
| Everything is culled away | Y must **not** be flipped in the projection: Metal NDC has +Y up while the framebuffer origin is top-left, which already gives the right orientation. Flipping mirrors the image and therefore reverses on-screen winding, so culling discards exactly the visible faces |
| A black viewport with no errors at all | `Viewport` and `Scissor` default to a **zero-sized** rect and the API does not complain about drawing into one. Set both explicitly every frame |
| The scene is all ambient, as if the light shone away from the camera | Getters shaped like `readDirection([out])` ended in `result.normalized()`, which returns a **new** vector and leaves `out` holding the un-normalized, un-negated value. The renderer read its own variable rather than the return value, so the light direction was inverted: `N·L` went negative and clamped to zero. Normalize **in place** (`normalize()`), and pin it with `expect(returned, same(out))` |
| `Binding has not yet been initialized` when reading assets off the UI isolate | `BackgroundIsolateBinaryMessenger.ensureInitialized(token)` grants a background isolate a working channel but creates no `ServicesBinding`, and `rootBundle` resolves through `ServicesBinding.instance`. Routing `flutter/assets` by hand fails deeper still — Flutter's own reply handler throws on a cast. Keep file reads on the UI isolate and request siblings over a port |
| Shaders stop loading after `flutter upgrade` | The shader bundle format is tied to the Flutter version. Re-run **both** builders: `flutter3d_impeller/tool/build_shaders.sh` for the bundle every application links, and `flutter3d/example/tool/build_shaders.sh` for the one the demo loads at runtime. The second fails by name rather than by format — `loadShaders` refuses a bundle it cannot read, so the symptom is a demo that opens and draws nothing |
| A normal-mapped surface lights from the wrong side, on half the model | The bitangent sign. glTF's bitangent is `cross(normal, tangent) * w`, and it is **minus** dP/dv — texture V grows downwards while a normal map's green channel points up. Deriving `w` from `+dP/dv` gives tangent directions that agree with an exporter to seven digits and signs that are backwards everywhere, which only shows up on mirrored UV islands. `NormalTangentMirrorTest` settles it: it ships authored tangents for geometry `NormalTangentTest` leaves bare |
| A texture is bound but the shader has no such slot | The compiler drops a sampler whose result never reaches the output, exactly as it does an unused uniform block. A model that samples a map and then ignores the value — Lambert reading metallic-roughness — ends up without the slot. `tool/build_shaders.sh` prints the compiled binding table so the metadata can be checked against it |
| `A command encoder is already encoding to this command buffer` | Metal allows one open encoder per command buffer, and flutter_gpu has no way to end a `RenderPass`. A multi-pass frame needs a **command buffer per pass**, submitted in order — buffers on the same queue execute in submission order, so that is also how the passes get sequenced |
| The background washes out after moving to an HDR target | The clear colour is authored display-referred, but the scene target holds linear light and the composite pass encodes on the way out. Convert the clear to linear or it goes through the encode twice |
| Shadows look right but toggling them changes nothing | Check the setting actually reaches `RenderSettings`. A control wired to the panel but not to the renderer looks completely convincing, and the way to find out is to capture the same frame with the feature on and off and diff the two — a zero difference is the whole answer |
| A draw is submitted, the counter goes up, nothing appears | There is **no non-indexed draw**. `draw()` with only a vertex buffer bound succeeds and renders nothing. Bind an index buffer even when the indices are the identity `0, 1, 2, …` sequence — the debug line overlay keeps one in a device buffer that only grows |
| `PathAccessException … Operation not permitted` when writing a file | macOS Flutter apps are sandboxed. Anything outside `~/Library/Containers/<bundle id>/Data` is refused, so frame captures resolve relative paths against the app's own temp directory |
| The view stops turning when the cursor reaches the edge of the window | Flutter exposes no pointer lock on any desktop platform. `packages/pointer_lock` supplies it on macOS by turning off the association between the physical mouse and the on-screen cursor, which leaves `mouseMoved` events arriving with their deltas while the cursor stays put |
| `failed to bind texture` on one lighting model and not the others | The model's metadata claims a sampler the compiled shader does not have. `LightingModel` now asserts that a model sampling no material maps cannot sample the metallic-roughness one either — Unlit sat in exactly that state and nothing exercised it, because the demo hardcoded PBR on every material it loaded |
| Golden references that all pass and all look the same | Five of the six lighting goldens recorded byte-identical images: the scene's lighting model reached the UI field but never the materials, so every one rendered as PBR. The check that found it is worth keeping as a habit — swap one reference for another's and confirm the comparison **fails**. A golden suite that cannot fail is worse than none, because it is believed |
| No cursor anywhere after a hot restart | A plugin holding the pointer outlives the Dart isolate, because the engine's registrar owns it. The Dart side comes back remembering nothing, so nothing asks for the cursor back. `MouseCapture` issues a reset on construction for exactly this |

## Layout

```
tool/bench/                     the AOT benchmarks behind ARCHITECTURE.md §14
tool/convert_asset.dart         glTF / GLB / OBJ -> .f3d, run offline
lib/src/engine/geometry/        CPU geometry, knows nothing about the GPU
lib/src/engine/animation/       clips, tracks, sampling, the player
lib/src/engine/math/            ray intersections, allocation-free
lib/src/engine/scene/           scene graph, cameras, lights, orbit, raycasting
lib/src/engine/render/          renderer, render list, materials, sorting, debug draw
lib/src/engine/assets/          glTF, OBJ and .f3d decoders, isolate loading, cache
example/lib/                    the demo, and the frame capture hook
test/                           822 tests, all runnable without a GPU
```

The GLSL is not here. Every shader this package draws with lives in
[`packages/flutter3d_shaders`](../flutter3d_shaders) — the vertex stages that
define the layouts, one fragment shader per lighting model, the shadow and sky
stages, the post chain and the headers they share — because an extension package
includes those headers and would otherwise depend on the whole engine to reach
them.

This package is one of twenty-four; see the [repository README](../../README.md)
for how the game layer, the backends and the genre templates sit around it.

The scene layer holds a `MeshGeometry`, not a `GpuMesh`. Bounds, culling, framing
and picking need no device, and requiring one would have meant none of them could
be unit tested — the renderer is the only place that cares whether the geometry
was actually uploaded. `CpuMesh` is the implementation for geometry that is
queried but never drawn.

## The key architectural consequence

Shaders are compiled **ahead of time** into a bundle; there is no runtime
compilation. A material graph assembled while the game runs is
therefore impossible: every lighting model is a separate pre-built shader,
and every shader is a separate `RenderPipeline`.

Hence the pipeline cache, the shared GLSL header (`flutter3d_shaders/shaders/lib/surface.glsl`) that
guarantees an identical uniform block across permutations, and tolerance for
missing uniform members — a shader that does not read `light_direction` loses it
from reflection. The cost is visible: the bundle grew from 12.5 KB with one shader
to 97 KB with seven.

It also makes the pipeline the most expensive state change in a pass, which is why
it is the **high-order term** when the render list is sorted — see
[ARCHITECTURE.md](../../ARCHITECTURE.md), section 14, for the measurements.

The same constraint is why lighting is a uniform array rather than a permutation
per light count. Verified rather than assumed: `vec4 lights[8]` survives into the
compiled Metal struct, and reflection reports the block at its std140 size with
the array's base offset intact. Individual elements are not reflected, so the
whole array is written from that base — correct because the std140 stride for a
`vec4` array is a flat 16 bytes. The probe is kept in `flutter3d_shaders/shaders/spike_array.frag`
for the next SDK bump. The payoff is measurable: a capture with three lights and
one with a single light both report **one** pipeline.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an **independent
implementation** of a 3D engine for Flutter — not a fork or a binding of
another engine, and not affiliated with the Flutter team. Three switchable
rendering backends: Impeller via Flutter GPU, WebGL2, and a software
rasteriser. glTF, OBJ and `.f3d` loading, six lighting models, shadows, bloom,
skinning, animation, BVH culling and picking; a deterministic fixed-step game
layer with collision, navigation, positional audio, and gamepad and touch
input. Three example games — shooter, platformer, racing — each built on its
genre package: [`flutter3d_game_shooter`](../flutter3d_game_shooter),
[`flutter3d_game_platformer`](../flutter3d_game_platformer),
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from the
editor's scaffold, which writes one from a template: <https://flutter3d.pleion.dev/first-project/>.
Documentation: <https://flutter3d.pleion.dev>.
