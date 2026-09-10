---
name: flutter3d-impeller-shader-bundle
description: Use when a flutter3d desktop or mobile build will not start, draws nothing, or fails to bind a texture — most failures here are the shader bundle or the per-app GPU manifest keys.
---

# The backend that names flutter_gpu, and the bundle it loads

```dart
final device = await GpuRenderBackend.create();
final renderer = Renderer.create(device: device);
```

`create` is static because loading the bundle is asynchronous, and it throws
when the bundle is missing: a renderer without shaders draws a black screen with
a null somewhere in it. An application with its own compiled shaders passes them
as `extraBundles`, searched before the engine's; a named bundle that is not
found throws by name, because a silent fallback to the engine's stage of the
same name looks like the effect being wrong rather than absent.

## Building the bundle

    ./tool/build_shaders.sh                    # in a checkout of this package
    dart run flutter3d_impeller:build_shaders  # from another package

Generated and gitignored, so a fresh checkout has none; a published copy carries
one. The bundle is an asset of *this* package, so a dependent application loads
it without declaring anything.

**Run it again after every shader edit.** The GLSL lives in `flutter3d_shaders`
and editing it changes nothing an application loads until this rebuilds. The
failure that follows is `failed to bind texture` — the renderer binds a slot the
new GLSL declares and the compiled binary has not got — and the message names
neither the shader nor the edit. `dart run tool/structure.dart` compares the
bundle against its sources and says which are newer.

## Before it will start at all

Flutter GPU and Impeller are enabled **per application**. In
`macos/Runner/Info.plist` set `FLTEnableImpeller` and `FLTEnableFlutterGPU`; on
Android the key is `io.flutter.embedding.android.EnableFlutterGPU` in
`AndroidManifest.xml`. Without them the app only runs through `flutter run
--enable-impeller --enable-flutter-gpu`, and the built `.app` fails on a
double-click. A structure rule checks this.

| Symptom | Cause |
|---|---|
| `Failed to initialize ShaderLibrary…` | the manifest keys above |
| `The shader has no uniform block named "frame_info"` | Impeller reflects a block under its **struct type name** (`FrameInfo`); textures are looked up by variable name |
| `Could not create graphics pipeline: ErrorUnknown`, then `SIGSEGV` a second later | a declared uniform block the stage never reads. On Vulkan it collides with the vertex stage's binding and the pipeline is refused; the crash lands wherever the dead pipeline is next touched — `RenderPass::Draw()` or `RenderPass::Begin()` — and only on drivers strict enough to refuse. See below for how to make the engine say which shader |
| Geometry flickers under load | `submit()` is asynchronous; a `HostBuffer.reset()` right after rewinds an allocator the GPU is still reading. Ring three host buffers |
| `A command encoder is already encoding…` | one open encoder per command buffer: a pass needs its own |
| Shaders stop loading after `flutter upgrade` | bundle format is tied to the SDK. Rebuild, re-record goldens, read the diff |

## Depth, winding and the near plane

Impeller follows the Metal/Vulkan depth convention `[0, 1]`, so
`vector_math.makePerspectiveMatrix` (OpenGL's `[-1, 1]`) clips geometry against
the near plane; the engine's own matrix is `PerspectiveProjection.toMatrix`.

Do **not** flip Y in the projection. Metal NDC has +Y up while the framebuffer
origin is top left, which already gives the right orientation; flipping mirrors
the image, reverses on-screen winding, and culling then discards exactly the
faces that should be visible.
