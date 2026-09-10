---
name: flutter3d-impeller-driver-crash
description: Use when a build dies on one device and not the others — a native crash with no Dart stack trace, a pipeline the driver refuses, or a picture that is right everywhere except on one phone. Says how to tell the engine's fault from ours, and what to do about each.
---

# When one device kills the process

A crash with no Dart in it is three suspects: this backend, the Flutter engine
under it, and the vendor's driver under that. They are told apart by the
backtrace and by two probes, and the order below is cheapest first.

## Read the tombstone before anything else

    adb logcat -b crash -d | rg "backtrace|#0[0-9]|Cause"

Every frame in `libflutter.so` and none in `/vendor/lib64/hw/vulkan.*.so` means
the engine dereferenced something; the driver never saw it. Frames in the
vendor library, reached *through* `libflutter.so`, mean the engine handed the
driver something it did not like. The two lead to different places, and the
distinction takes ten seconds.

`fault addr` is worth reading. A small number — `0x3c`, `0x218` — is a member
offset from a null pointer, so the object was missing rather than corrupt.

## Make the engine name the shader

The engine reports a refused pipeline as
`Could not create graphics pipeline: ErrorUnknown` with an **empty label**,
because flutter_gpu builds its pipelines without one. Two ways to find out
which:

* **Trace this backend.** `GpuRenderBackend.createPipeline` knows the two
  shader names; a `debugPrint` there names the pipeline the driver refused, and
  the pass descriptor beside it names the target it was for.
* **Ask Vulkan.** Validation layers ship in a *locally built* debug engine, not
  in the SDK's. With one built, `flutter run --enable-vulkan-validation` (or
  `am start … --ez enable-vulkan-validation true`) turns `ErrorUnknown` into the
  VUID that was broken and a link to the rule. That is how
  `VUID-VkDescriptorSetLayoutCreateInfo-binding-00279` — two descriptors on one
  binding number — was found behind a shader that worked on every other device.

## Take flutter3d out of the picture

A dozen lines of `flutter_gpu` reproduce most backend-level failures without
this engine at all: create the textures, build a `RenderTarget`, call
`createRenderPass`, submit. Walk the shapes one at a time and log *before* each
attempt — a crash kills the process, so the last line printed names the shape
that did it.

Two things worth knowing about that harness, because both cost a day:

* the same program on macOS/Metal is the control. A shape that throws on Metal
  and crashes on Vulkan is an engine bug, not a driver quirk;
* a render target with a depth attachment and **no colour attachment** is not
  supported — `RenderTarget::IsValid()` says so — and until it is fixed
  upstream, the Vulkan backend crashes rather than refusing it.

## What has already been found this way

| Symptom | Where it lives |
|---|---|
| depth-only render target → `SIGSEGV` on Vulkan, `Failed to begin RenderPass` on Metal | engine: `RenderPassVK` skips `RenderTarget::IsValid()` |
| a pass whose colour texture is reused with a *different* depth texture → `VUID-VkRenderPassBeginInfo-framebuffer-parameter`, then a crash | engine: the framebuffer cache is keyed on colour attachment zero alone, so it hands back a framebuffer holding the previous depth's image view |
| a refused pipeline is bound anyway and kills the process | engine: `RenderPass::Draw` checks the pipeline with `FML_DCHECK`, which release builds compile out |
| `Could not create graphics pipeline` for one shader only | ours: a stage declaring a uniform block it does not read — see `flutter3d-shaders-one-copy` |

The first three are engine bugs with local patches; the fourth is the one to
check first, because it is the only one this repository can fix on its own.

## Before blaming anything

`io.flutter.embedding.android.EnableFlutterGPU` in the manifest. Without it
`openDevice` falls back to the software rasteriser, which draws the right
picture at two frames a second and reports nothing — a performance mystery
rather than a crash, and the cheapest of all of these to rule out.
