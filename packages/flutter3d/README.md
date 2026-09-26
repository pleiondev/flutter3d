# flutter3d

An independent implementation of a real-time 3D engine for Flutter, written
from the geometry layer up. It does not fork, bind or wrap another engine, and
it is not affiliated with the Flutter team.

Homepage: **<https://flutter3d.pleion.dev>** · API reference:
**<https://flutter3d.pleion.dev/docs>** · Source:
**<https://github.com/pleiondev/flutter3d>**

## What it is good at

- **Three graphics backends behind one interface.** `flutter_gpu` on desktop,
  WebGL2 in a browser, and a software rasteriser with no GPU at all. User code
  names none of them, and adding a fourth changes nothing above the HAL. A
  conformance suite checks that claim.
- **Rendering that can be tested without a graphics card.** The software backend
  gives a second, independently written set of reference images, so a passing
  golden means two implementations agree, not one agreeing with itself.
  `flutter3d_testing` hands that to a game as a one-call API.
- **Three genre templates, each with a playable demo:** shooter, platformer and
  racing. They are packages, so a new game starts from one instead of from an
  empty screen. They also keep the engine's boundaries real: nothing in
  `packages/flutter3d*` may name a genre, and a scan enforces it.
- **A deterministic simulation.** A fixed step that reads no clock and rolls no
  loose dice, a generator whose state can be written down, and `InputTape`. A
  run replays exactly, a bug arrives as a file attached to a report, and a test
  can play a whole level.
- **A game layer that does not depend on the renderer.** Collisions, input and
  the step are reachable from an ordinary unit test, which is where you find the
  bugs that never show up in a screenshot.
- **Extension points instead of forks**: a decoder for a model format the engine
  does not know, a decoder for a material format, a system added to somebody
  else's simulation step, a contributor drawing into somebody else's render pass,
  and a lighting model of your own if you build your own shader bundle.
- **Its own level format and editor.** A level is validated before a run, and a
  problem is reported with its coordinate instead of "the file is broken".

`ARCHITECTURE.md` at the repository root explains how all of it fits together
and why.

What works today:

- a CPU-side geometry layer with no GPU dependency: vertex layouts, `MeshData`,
  `MeshBuilder`;
- surfaces of revolution (`LatheShape`) as the base generator. Sphere,
  cylinder, cone, torus, capsule and disc all derive from it, plus an arbitrary
  profile (the "vase"). Shapes are values (`Shape`), not static methods;
- six switchable lighting models, each its own pre-built fragment shader:
  Unlit, Lambert, Blinn-Phong, PBR (GGX), Toon, Normals;
- skinning: glTF skins decoded into a `Skeleton` of ordinary scene nodes, a
  separate skinned vertex stage with 64 joint matrices in a uniform array, four
  weights per vertex, and bounds taken from the posed skeleton instead of the
  bind pose;
- `.f3d`, the engine's own container. An offline converter does the decoding
  once and the loader hands out typed-data views over the file, which takes the
  teapot from 4.54 ms as OBJ to 1.1 us, with the two renders identical pixel
  for pixel;
- a BVH over world bounds, shared by culling and picking and rebuilt only when
  something moves, plus LOD groups that switch by screen coverage;
- directional shadows. The pass is a render view whose camera is the light,
  with an orthographic volume fitted to the scene, linear depth in a colour
  target (depth textures cannot be sampled), front-face culling, PCF 3x3, and
  both a depth bias and a normal offset;
- an HDR pipeline. The scene renders into `r16g16b16a16Float`, and tone
  mapping, exposure and the sRGB encode happen in a composite pass. That pass is
  what makes bloom possible. Bloom is built from a chain of half-size targets
  instead of mip levels: flutter_gpu had no mip levels when it was written, and
  now that it does, a bloom chain still wants separate targets it can blur
  between;
- material maps: normal (with a full TBN), ORM, occlusion and emissive, plus
  alpha masking and vertex colours. Missing maps get neutral fallback textures
  instead of per-map flags, so the shader needs no branch and the engine no
  bookkeeping;
- tangents: generated with Lengyel's method where a mesh has none, taken
  analytically where the surface knows them, and checked against a real
  exporter's output on `NormalTangentMirrorTest`;
- eight lights per draw, out of as many as a scene holds. Directional, point
  and spot lights use glTF's inverse-square falloff, range window and cone ramp,
  and are packed into `vec4[8]` uniform arrays with the count as a uniform, so
  switching a light on or off never rebuilds a pipeline. A scene with eight or
  fewer is packed in scene order and every draw sees the same eight. Past that,
  each object gets the eight that actually reach it, ranked by the attenuation
  the shader itself will compute and tie-broken by scene order so the picture
  does not flicker. No shader changed to make that work;
- decoders for glTF 2.0 / GLB and Wavefront OBJ behind one `ModelDocument`
  abstraction with shared `SurfaceMaterial` / `TextureBinding` / `EncodedImage`,
  so the GPU upload path is written once for both formats;
- decoding on a background isolate, plus a reference-counted asset cache;
- a scene graph: `SceneNode` with version stamps instead of dirty flags,
  `CameraNode` + `Projection`, `LightNode`, an orbit camera driven by gestures;
- frustum culling, draw-call sorting with the pipeline as the high-order key,
  a pipeline cache, 4x MSAA, depth testing, wireframe (Impeller only, see
  `RenderSettings.wireframe`), linear-space shading with
  tone mapping (Khronos PBR Neutral) and exposure;
- observability: a line-based debug overlay (bounds, vertex normals, light
  gizmos, world axes, camera frusta) drawn in one call, `dart:developer` Timeline
  spans around every frame phase, and a frame panel with UI/raster/render/submit
  timings next to draw, pipeline-switch and cull counts;
- CPU picking: ray/AABB, ray/sphere and Möller-Trumbore ray/triangle, a
  `Raycaster` that casts from widget coordinates, and tap-to-select in the demo
  with the hit outlined by the debug overlay;
- glTF transform animation: all three interpolations (`STEP`, `LINEAR`,
  `CUBICSPLINE` with authored tangents), slerped rotations, an `AnimationPlayer`
  with play/pause/seek/speed and once/loop/ping-pong, and the decoded node
  hierarchy rebuilt on instantiation so an animated parent carries its subtree;
- 1580 tests covering projection, scene, sorting, debug draw, raycasting,
  animation, skinning, lighting, render targets, BVH, LOD, glTF, OBJ and `.f3d`,
  plus a real frame drawn through `flutter3d_cpu`'s software rasteriser for the
  ones that need one, all without a GPU. The geometry the engine is written in
  (`MeshData`, the shape generators, tangents, morph targets and `Ray`) is
  [`flutter3d_core`](https://pub.dev/packages/flutter3d_core)'s geometry library,
  with its own suite, and this package exports it whole.

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

You do not need the `--enable-impeller` and `--enable-flutter-gpu` flags. Both
are switched on in the application's `Info.plist`, so the built app also works
when launched by double-clicking it. These are per-app settings, so every app
that draws through this package has to set them in its own `Info.plist`.

### Capturing a frame

Judging a render by eye does not scale, and grabbing the window with
`screencapture` needs a logged-in session with the display awake. So the demo
can write the render target straight to a PNG and quit:

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
debug-line counts. `FLUTTER3D_SOURCE` matches a model chip by substring.
`FLUTTER3D_SPIN=false` stops the turntable so two captures differ only by what
is being tested. `FLUTTER3D_LIGHTS` names which lights start switched on.
`FLUTTER3D_ANIM_TIME` freezes any clip at a given second; without it, two
captures of an animated model are not comparable, because a format that loads
faster starts playing sooner.

## Loading models

Both decoders emit one shared abstraction, `ModelDocument`: a list of
`ModelSurface`, a list of `SurfaceMaterial`, a list of `EncodedImage`, and
`warnings`. That makes `ModelAsset.fromDocument()` the single upload path
(mesh and image deduplication, material conversion), and adding a third format
means writing a decoder without touching the loader.

Materials are normalised to metal-rough, because that is what glTF defines and
what the shaders implement. OBJ predates PBR, so its parameters are approximated:
`Kd` becomes the base colour, the Phong exponent `Ns` becomes roughness, and a
bright neutral `Ks` is the only hint of metalness available. `MtlMaterial`
documents the approximation.

Decoding runs on a background isolate. File reads stay on the UI isolate, and
sibling files are requested back over a port. The pitfalls table explains why
the obvious alternative does not work.

### Wavefront OBJ

| | |
|---|---|
| Faces | `v`, `v/vt`, `v//vn`, `v/vt/vn`; negative (relative) indices; polygons fanned into triangles |
| Vertices | deduplicated by the (position, UV, normal) triple, which is the unit OBJ actually addresses |
| Normals | when `vn` is absent, smooth normals are generated (area-weighted). Unlike glTF, the format prescribes nothing, files routinely omit normals, and the geometry they omit them for is curved, where flat normals look broken: on a teapot, for instance. `flat` and `none` are also available |
| UVs | V is flipped by default, because OBJ texture space has its origin at the bottom left. This is the most common cause of upside-down textures on OBJ imports |
| Groups | `g`, `o` and `usemtl` start a new surface, so a multi-material file yields several draws |
| Materials | `.mtl` through a resolver: `newmtl`, `Kd`, `Ks`, `Ns`, `d`, `Tr`, `map_Kd` |
| Robustness | unknown directives, malformed faces and missing libraries go to `warnings` instead of failing the file |

The test model is the [Utah teapot](https://github.com/mauricelam/Teapot)
(`flutter3d_samples`): `v` and `f` only, 1202 vertices, 2256 triangles, no
normals and no materials, which is exactly the case that needs normal
generation.

## glTF / GLB

The layer in `lib/src/engine/assets/gltf/` depends on neither flutter_gpu,
`dart:io` nor `dart:ui`. External files arrive through an `AssetUriResolver`
callback, and images are handed back still encoded. That keeps it testable
without a GPU or a Flutter binding, and usable from an isolate.

What is supported:

| | |
|---|---|
| Containers | `.glb` (chunk parser with padding, unknown chunks ignored) and `.gltf` |
| Buffers | the GLB `BIN` chunk, base64 `data:` URIs, external files through a resolver |
| Accessors | every componentType, `byteStride` (interleaved data), `normalized` with the symmetric clamp for signed types, sparse, and accessors with no bufferView (zeros) |
| Topologies | TRIANGLES; STRIP and FAN are rewritten as triangle lists so no pipeline permutation is needed per topology |
| Attributes | POSITION, NORMAL, TEXCOORD_0, TANGENT, COLOR_0; only those the target `VertexLayout` declares are read |
| Tangents | TANGENT when the file has it, otherwise generated with Lengyel's method as the spec requires |
| Normals | an absent NORMAL produces flat normals, as the spec requires, which de-indexes the mesh |
| Node graph | `matrix` and TRS, accumulated transforms, meshes reused across nodes, cycle guard |
| Materials | metal-rough, all texture slots, alphaMode/cutoff, doubleSided, `KHR_materials_unlit`, `KHR_materials_emissive_strength` |
| Mirroring transforms | detected from the determinant's sign; the winding order is flipped per instance |
| Node hierarchy | kept index-aligned with the file, transform-only nodes included, because animation channels address nodes by index |
| Skins | `joints`, `inverseBindMatrices`, `skeleton`, and JOINTS_0/WEIGHTS_0; a primitive with joint attributes gets the skinned vertex layout, chosen from the data and not by the caller |
| Animations | all samplers and channels; `STEP`, `LINEAR` and `CUBICSPLINE`; translation, rotation, scale and weights |
| Morph targets | POSITION, NORMAL and TANGENT deltas, packed into a texture the vertex stage samples; a node's or mesh's rest weights; up to eight targets blended at once |

Compressed geometry (`KHR_draco_mesh_compression` and `EXT_meshopt_compression`)
is decoded. If a Draco payload does not decode, that primitive is dropped and
the reason goes into `warnings`. KTX2 is read: `KHR_texture_basisu`'s Basis
Universal files, ETC1S and UASTC LDR, unpack to RGBA8 with or without
Zstandard, and a file's own BC, ETC2 or ASTC blocks upload as they are where
the device samples them. TEXCOORD_1 and up are not supported.

Non-fatal decoding problems land in `warnings` and are shown in the UI. A
skipped primitive or an ignored extension explains a model that looks odd but
still loaded.

The sample models are the official Khronos
[glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets), picked to
cover all three ways of storing the data. They live in
[`flutter3d_samples`](https://pub.dev/packages/flutter3d_samples), which is a dev
dependency of this package and not a regular one, so a game gets the decoders
without the 4.1 MB of fixtures they were checked against. Their terms are in
[ATTRIBUTION.md](https://github.com/pleiondev/flutter3d/blob/main/packages/flutter3d_samples/assets/ATTRIBUTION.md).

## The `.f3d` container

[ARCHITECTURE.md](https://github.com/pleiondev/flutter3d/blob/main/ARCHITECTURE.md), section 14, measured the decoders and
found that the format matters far more than the language: the same geometry
loads about 360x slower as OBJ text than as a binary buffer, and native code
does not close that gap. `.f3d` moves the parse off the device entirely.

```bash
dart run flutter3d_build:convert ../flutter3d_samples/assets/teapot.obj \
  -o ../flutter3d_samples/assets/f3d/teapot.f3d
```

Vertex and index arrays are stored exactly as `MeshData` holds them, so loading
builds `Float32List.view`s over the file instead of copies. Every blob entry is
4-byte aligned so that those views are legal. The file uses a section directory
instead of fixed header fields, so a reader skips a kind it does not know, and
the version only has to change when an existing record does.

Nothing else had to change to support it. `F3dDocument` is a `ModelDocument`,
so `ModelAsset.fromDocument`, the resource cache and instancing are all
unchanged; that abstraction was introduced for this. The converter re-reads what
it wrote and compares it against the source before reporting success.

| teapot | load |
|---|---|
| OBJ (parse, dedup, smooth normals) | 4.54 ms |
| `.f3d`, every array touched | 1.1 us |

The file is larger than its source (102 KB against 69 KB for the teapot),
because indices stay 32-bit and nothing is compressed. That is deliberate:
narrowing indices or deflating the blob would bring back the per-load work the
format exists to remove.

## Pitfalls already hit

These are not project setup. They are conditions without which Flutter GPU
either does not start or silently renders nothing.

| Symptom | Cause and fix |
|---|---|
| `Failed to initialize ShaderLibrary: Flutter GPU must be enabled via the Flutter GPU manifest setting` | Flutter GPU is enabled per application, not just per channel. Set `FLTEnableFlutterGPU` to `true` in `macos/Runner/Info.plist` (already done), or pass `--enable-flutter-gpu`. On Android the key is `io.flutter.embedding.android.EnableFlutterGPU` in `AndroidManifest.xml` |
| `Failed to initialize ShaderLibrary: Flutter GPU requires the Impeller rendering backend, but Impeller is not enabled` | Impeller is not the default renderer on macOS yet. Without `FLTEnableImpeller` set to `true` in `Info.plist` (already done) the app only works through `flutter run --enable-impeller`, and double-clicking the built `.app` fails |
| `The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 10.15, but the range of supported deployment target versions is 12.0 to 27.0.x` | `flutter create` generates 10.15 and current Xcode will not build it. Raised to 12.0 in `macos/Runner.xcodeproj/project.pbxproj` |
| `Bad state: The shader has no uniform block named "frame_info"` | Impeller reflects a uniform block under its struct type name, not the variable name. For `uniform FrameInfo { … } frame_info;` the key is `FrameInfo`. Textures are the opposite: `bindTexture` looks them up by variable name (`base_color_texture`) |
| `SIGSEGV` in `AGXG15XFamilyRenderContext setFragmentBuffer:offset:atIndex:` inside `RenderPass::Draw()` | A shader declared a uniform block (via a shared `#include`) but never reads it. Reflection still reports the block with a non-zero size while the compiled Metal function binds no buffer for it, and binding that phantom block kills the process with no Dart stack trace. Checking `sizeInBytes` is not enough. The permutation needs explicit metadata (`LightingModel.usesFragInfo`), and a shader with no material inputs should not declare the block at all, which is why the header is split into `lib/color.glsl` and `lib/surface.glsl` |
| Geometry and lighting flicker under load | `CommandBuffer.submit()` is asynchronous. Calling `HostBuffer.reset()` right after it rewinds a bump allocator the GPU may still be reading, so the next frame overwrites live uniform data. Use a ring of ~3 host buffers, one per frame in flight |
| The model is clipped against the near plane, or "half of it vanished" | `vector_math.makePerspectiveMatrix` produces OpenGL depth `[-1, 1]` while Impeller follows the Metal/Vulkan convention `[0, 1]`. Our matrix lives in `PerspectiveProjection.toMatrix` (`lib/src/engine/scene/camera_node.dart`) |
| Everything is culled away | Y must not be flipped in the projection. Metal NDC has +Y up while the framebuffer origin is top-left, which already gives the right orientation. Flipping mirrors the image and therefore reverses on-screen winding, so culling discards exactly the visible faces |
| A black viewport with no errors at all | `Viewport` and `Scissor` default to a zero-sized rect, and the API does not complain about drawing into one. Set both explicitly every frame |
| The scene is all ambient, as if the light shone away from the camera | Getters shaped like `readDirection([out])` ended in `result.normalized()`, which returns a new vector and leaves `out` holding the un-normalized, un-negated value. The renderer read its own variable instead of the return value, so the light direction was inverted: `N·L` went negative and clamped to zero. Normalize in place (`normalize()`), and pin it with `expect(returned, same(out))` |
| `Binding has not yet been initialized` when reading assets off the UI isolate | `BackgroundIsolateBinaryMessenger.ensureInitialized(token)` grants a background isolate a working channel but creates no `ServicesBinding`, and `rootBundle` resolves through `ServicesBinding.instance`. Routing `flutter/assets` by hand fails deeper still, because Flutter's own reply handler throws on a cast. Keep file reads on the UI isolate and request siblings over a port |
| Shaders stop loading after `flutter upgrade` | The shader bundle format is tied to the Flutter version. Re-run both builders: `flutter3d_impeller/tool/build_shaders.sh` for the bundle every application links, and `flutter3d/example/tool/build_shaders.sh` for the one the demo loads at runtime. The second fails by name, not by format: `loadShaders` refuses a bundle it cannot read, so the symptom is a demo that opens and draws nothing |
| A normal-mapped surface lights from the wrong side, on half the model | The bitangent sign. glTF's bitangent is `cross(normal, tangent) * w`, and it is minus dP/dv, because texture V grows downwards while a normal map's green channel points up. Deriving `w` from `+dP/dv` gives tangent directions that agree with an exporter to seven digits and signs that are backwards everywhere, which only shows up on mirrored UV islands. `NormalTangentMirrorTest` settles it: it ships authored tangents for geometry `NormalTangentTest` leaves bare |
| A texture is bound but the shader has no such slot | The compiler drops a sampler whose result never reaches the output, exactly as it does an unused uniform block. A model that samples a map and then ignores the value (Lambert reading metallic-roughness) ends up without the slot. `tool/build_shaders.sh` prints the compiled binding table so the metadata can be checked against it |
| `A command encoder is already encoding to this command buffer` | Metal allows one open encoder per command buffer, and flutter_gpu has no way to end a `RenderPass`. A multi-pass frame needs a command buffer per pass, submitted in order. Buffers on the same queue execute in submission order, so that is also how the passes get sequenced |
| The background washes out after moving to an HDR target | The clear colour is authored display-referred, but the scene target holds linear light and the composite pass encodes on the way out. Convert the clear to linear or it goes through the encode twice |
| Shadows look right but toggling them changes nothing | Check that the setting actually reaches `RenderSettings`. A control wired to the panel but not to the renderer looks completely convincing. To find out, capture the same frame with the feature on and off and diff the two; a zero difference means the setting never arrived |
| A draw is submitted, the counter goes up, nothing appears | There is no non-indexed draw. `draw()` with only a vertex buffer bound succeeds and renders nothing. Bind an index buffer even when the indices are the identity `0, 1, 2, …` sequence; the debug line overlay keeps one in a device buffer that only grows |
| `PathAccessException … Operation not permitted` when writing a file | macOS Flutter apps are sandboxed. Anything outside `~/Library/Containers/<bundle id>/Data` is refused, so frame captures resolve relative paths against the app's own temp directory |
| The view stops turning when the cursor reaches the edge of the window | Flutter exposes no pointer lock on any desktop platform. `packages/pointer_lock` supplies it on macOS by turning off the association between the physical mouse and the on-screen cursor, which leaves `mouseMoved` events arriving with their deltas while the cursor stays put |
| `failed to bind texture` on one lighting model and not the others | The model's metadata claims a sampler the compiled shader does not have. `LightingModel` now asserts that a model sampling no material maps cannot sample the metallic-roughness one either. Unlit was in exactly that state and nothing exercised it, because the demo hardcoded PBR on every material it loaded |
| Golden references that all pass and all look the same | Five of the six lighting goldens recorded byte-identical images: the scene's lighting model reached the UI field but never the materials, so every one rendered as PBR. The check that found it is worth keeping as a habit: swap one reference for another's and confirm the comparison fails. A golden suite that cannot fail is worse than none, because people believe it |
| No cursor anywhere after a hot restart | A plugin holding the pointer outlives the Dart isolate, because the engine's registrar owns it. The Dart side comes back remembering nothing, so nothing asks for the cursor back. `MouseCapture` issues a reset on construction for this case |

## Layout

```
tool/bench/                     the AOT benchmarks behind ARCHITECTURE.md §14
bin/convert.dart                glTF / GLB / OBJ -> .f3d — a thin wrapper;
                                 the converter itself is flutter3d_build
lib/src/engine/geometry/        DeviceMesh: the mesh that has met the device
lib/src/engine/animation/       clips, tracks, sampling, the player
lib/src/engine/scene/           scene graph, cameras, lights, orbit, raycasting
lib/src/engine/render/          renderer, render list, materials, sorting, debug draw
lib/src/engine/assets/          glTF, OBJ and .f3d decoders, isolate loading, cache
example/lib/                    the demo, and the frame capture hook
skills/                         the conventions, as agent skills — see below
bin/skills.dart                 what copies them into a project that uses this
test/                           1580 tests, all runnable without a GPU
```

The GLSL is not here. Every shader this package draws with lives in
[`packages/flutter3d_shaders`](https://pub.dev/packages/flutter3d_shaders): the
vertex stages that define the layouts, one fragment shader per lighting model,
the shadow and sky stages, the post chain and the headers they share. They are
separate because an extension package includes those headers and would
otherwise depend on the whole engine to reach them.

This package is one of thirty-eight; see the [repository README](https://github.com/pleiondev/flutter3d/blob/main/README.md)
for how the game layer, the backends and the genre templates sit around it.

## The conventions, unpacked into your repository

```bash
dart run skills@ get                 # every dependency's skills, this one included
dart run flutter3d:skills            # only this package's, into ./.claude/skills
dart run flutter3d:skills --list     # name them and stop
dart run flutter3d:skills --into docs/skills
```

There are eight skills. One covers how a scene is built and a frame drawn. The
other seven are each tied to something a machine here already checks: the
structure scan, the rule that a test is shown to fail before it is believed,
the determinism machinery a replay is measured with, the golden sets and how
they are recorded, why a frame draws nothing, what each layer may import, and
which files are generated rather than written.

Every package in this repository ships its own, named for the package the way
`dart run skills@ get` requires: a skill whose directory does not start with its
package's name is skipped silently.

Skills are prose, and prose that lives in one repository is invisible to
everyone else. An agent working in your game cannot read a `CONTRIBUTING.md`
out of a version-stamped pub cache directory, so this command copies the files
to where the agent does look: `.claude/skills` under the current directory by
default. The copy travels with your code, gets reviewed with your code, and is
yours to edit afterwards, so a file you have changed is left alone unless you
pass `--force`.

The scene layer holds a `MeshGeometry`, not a `GpuMesh`. Bounds, culling,
framing and picking need no device, and requiring one would have made all of
them impossible to unit test. The renderer is the only place that cares whether
the geometry was actually uploaded. `CpuMesh` is the implementation for geometry
that is queried but never drawn.

## The key architectural consequence

Shaders are compiled ahead of time into a bundle; there is no runtime
compilation. So a material graph assembled while the game runs is impossible:
every lighting model is a separate pre-built shader, and every shader is a
separate `RenderPipeline`.

That is the reason for the pipeline cache, for the shared GLSL header
(`flutter3d_shaders/shaders/lib/surface.glsl`) that guarantees an identical
uniform block across permutations, and for tolerating missing uniform members:
a shader that does not read `light_direction` loses it from reflection. The
cost shows in the bundle size, which grew from 12.5 KB with one shader to 97 KB
with seven.

It also makes the pipeline the most expensive state change in a pass, which is
why it is the high-order term when the render list is sorted. See
[ARCHITECTURE.md](https://github.com/pleiondev/flutter3d/blob/main/ARCHITECTURE.md), section 14, for the measurements.

The same constraint is why lighting is a uniform array instead of a permutation
per light count. This was verified: `vec4 lights[8]` survives into the compiled
Metal struct, and reflection reports the block at its std140 size with the
array's base offset intact. Individual elements are not reflected, so the whole
array is written from that base, which is correct because the std140 stride for
a `vec4` array is a flat 16 bytes. The probe is kept in
`flutter3d_shaders/shaders/spike_array.frag` for the next SDK bump. A capture
with three lights and one with a single light both report one pipeline.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
implementation of a 3D engine for Flutter. It is not a fork or a binding of
another engine, and it is not affiliated with the Flutter team. It has four
switchable rendering backends: Impeller via Flutter GPU, WebGL2, WebGPU and a
software rasteriser. It loads glTF, OBJ and `.f3d`, and has six lighting models,
shadows, bloom, skinning, animation, BVH culling and picking, plus a
deterministic fixed-step game layer with collision, navigation, positional
audio, and gamepad and touch input. Four example games (shooter, platformer,
racing, strategy) are each built on a genre package:
[`flutter3d_game_shooter`](https://pub.dev/packages/flutter3d_game_shooter),
[`flutter3d_game_platformer`](https://pub.dev/packages/flutter3d_game_platformer),
[`flutter3d_game_racing`](https://pub.dev/packages/flutter3d_game_racing),
[`flutter3d_game_strategy`](https://pub.dev/packages/flutter3d_game_strategy).
A new game starts from the editor's scaffold, which writes one from a template:
<https://flutter3d.pleion.dev/first-project/>. Documentation:
<https://flutter3d.pleion.dev>.
