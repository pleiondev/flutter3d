# flutter3d

A 3D engine spike on **Flutter GPU**. The research that led to this structure, and
the full list of engine features with priorities, is in [RESEARCH.md](RESEARCH.md).

What works today:

- a CPU-side geometry layer with no GPU dependency: vertex layouts, `MeshData`,
  `MeshBuilder`;
- **surfaces of revolution** (`LatheShape`) as the base generator — sphere,
  cylinder, cone, torus, capsule and disc all derive from it, plus an arbitrary
  profile (the "vase"); shapes are values (`Shape`), not static methods;
- six **switchable lighting models**, each its own pre-built fragment shader:
  Unlit, Lambert, Blinn-Phong, PBR (GGX), Toon, Normals;
- **decoders for glTF 2.0 / GLB and Wavefront OBJ** behind one `ModelDocument`
  abstraction with shared `SurfaceMaterial` / `TextureBinding` / `EncodedImage`,
  so the GPU upload path is written once for both formats;
- decoding on a **background isolate** plus a reference-counted asset cache;
- a **scene graph**: `SceneNode` with version stamps instead of dirty flags,
  `CameraNode` + `Projection`, `LightNode`, an orbit camera driven by gestures;
- frustum culling, draw-call sorting with the pipeline as the high-order key,
  a pipeline cache, 4x MSAA, depth testing, wireframe, linear-space shading with
  tone mapping (Khronos PBR Neutral) and exposure;
- **observability**: a line-based debug overlay (bounds, vertex normals, light
  gizmos, world axes, camera frusta) drawn in one call, `dart:developer` Timeline
  spans around every frame phase, and a frame panel with UI/raster/render/submit
  timings next to draw, pipeline-switch and cull counts;
- 221 tests — geometry, projection, scene, sorting, debug draw, glTF and OBJ —
  all without a GPU.

## Running

```bash
# 1. Build the shader bundle (required after any Flutter SDK change)
./tool/build_shaders.sh

# 2. Run
flutter run -d macos
```

The `--enable-impeller` and `--enable-flutter-gpu` flags are not needed: both are
switched on through `macos/Runner/Info.plist`, so the built app also works when
launched by double-clicking it.

### Capturing a frame

Judging a render by eye does not scale, and grabbing the window with
`screencapture` needs a logged-in session with the display awake. The demo can
therefore write the render target straight to a PNG and quit:

```bash
flutter run -d macos \
  --dart-define=FLUTTER3D_CAPTURE=shot.png \
  --dart-define=FLUTTER3D_CAPTURE_FRAME=200 \
  --dart-define=FLUTTER3D_DEBUG_DRAW=bounds,normals,lights,axes,frusta \
  --dart-define=FLUTTER3D_SOURCE=teapot
```

A relative capture path lands in the app's sandbox temp directory, and the run
prints the absolute path along with the frame's draw, pipeline-switch, cull and
debug-line counts. `FLUTTER3D_SOURCE` matches a model chip by substring.

## Loading models

Both decoders emit a **shared abstraction**, `ModelDocument`: a list of
`ModelSurface`, a list of `SurfaceMaterial`, a list of `EncodedImage`, and
`warnings`. That is what makes `ModelAsset.fromDocument()` the single upload path
(mesh and image deduplication, material conversion), and it means adding a third
format is a matter of writing a decoder rather than touching the loader.

Materials are normalized to metal-rough, because that is what glTF defines and what
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
(`assets/samples/teapot.obj`): `v` and `f` only, 1202 vertices, 2256 triangles, no
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
| Normals | an absent NORMAL produces **flat** normals, as the spec requires, which de-indexes the mesh |
| Node graph | `matrix` and TRS, accumulated transforms, meshes reused across nodes, cycle guard |
| Materials | metal-rough, all texture slots, alphaMode/cutoff, doubleSided, `KHR_materials_unlit`, `KHR_materials_emissive_strength` |
| Mirroring transforms | detected from the determinant's sign; the winding order is flipped per instance |

Not there: skinning, animation, morph targets (parsed only as far as the node
graph), Draco and meshopt (reported in `warnings`), KTX2, TEXCOORD_1 and up.

Non-fatal decoding problems land in `warnings` and are surfaced in the UI — a
skipped primitive or an ignored extension explains a model that looks odd but
still loaded.

The sample models in `assets/samples/` are the official Khronos
[glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets), picked to
cover all three ways of storing the data. See
[assets/samples/ATTRIBUTION.md](assets/samples/ATTRIBUTION.md).

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
| Shaders stop loading after `flutter upgrade` | The shader bundle format is tied to the Flutter version. Re-run `./tool/build_shaders.sh` |
| A draw is submitted, the counter goes up, nothing appears | There is **no non-indexed draw**. `draw()` with only a vertex buffer bound succeeds and renders nothing. Bind an index buffer even when the indices are the identity `0, 1, 2, …` sequence — the debug line overlay keeps one in a device buffer that only grows |
| `PathAccessException … Operation not permitted` when writing a file | macOS Flutter apps are sandboxed. Anything outside `~/Library/Containers/<bundle id>/Data` is refused, so frame captures resolve relative paths against the app's own temp directory |

## Layout

```
shaders/
  mesh.vert                     vertex shader (this is what defines the vertex layout!)
  debug_line.vert               vertex shader for the debug overlay's own layout
  lib/color.glsl                colour space and output, no uniforms
  lib/surface.glsl              the material interface shared by lighting models
  lighting/*.frag               one shader per lighting model, plus debug_line.frag
  flutter3d.shaderbundle.json   bundle manifest
tool/build_shaders.sh           calls impellerc directly, no Native Assets
tool/bench/bench.dart           the AOT benchmark behind docs/FFI-analysis.md
lib/src/engine/geometry/        CPU geometry, knows nothing about the GPU
lib/src/engine/scene/           scene graph, cameras, lights, orbit controller
lib/src/engine/render/          renderer, render list, materials, sorting, debug draw
lib/src/engine/assets/          glTF and OBJ decoders, isolate loading, cache
lib/src/spike/                  demo glue and the frame capture hook
test/                           221 tests, all runnable without a GPU
```

## The key architectural consequence

Shaders are compiled **ahead of time** into a bundle; there is no runtime
compilation. A material graph in the style of Babylon's `NodeMaterial` or three.js
TSL is therefore impossible: every lighting model is a separate pre-built shader,
and every shader is a separate `RenderPipeline`.

Hence the pipeline cache, the shared GLSL header (`shaders/lib/surface.glsl`) that
guarantees an identical uniform block across permutations, and tolerance for
missing uniform members — a shader that does not read `light_direction` loses it
from reflection. The cost is visible: the bundle grew from 12.5 KB with one shader
to 97 KB with seven.

It also makes the pipeline the most expensive state change in a pass, which is why
it is the **high-order term** when the render list is sorted — see
[docs/FFI-analysis.md](docs/FFI-analysis.md) for the measurements behind that.
