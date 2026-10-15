---
name: flutter3d-hardware-backend-contract
description: Use when writing a flutter3d graphics backend (a fifth one, outside the engine's repository), calling GraphicsDevice or CommandEncoder directly, running the conformance suite on a device, or testing rendering with the fake device that records draws.
---

# The vocabulary a frame is written in

Types only: `GraphicsDevice`, the encoders, handles, formats, pipelines,
samplers, render targets, and no implementation. An engine written against
this is handed a backend as a value, which is what lets a software rasteriser
draw the frame a GPU drew and a test check that it did.

**Nothing here may name a graphics API.** Not Metal, Vulkan, WebGL or
`flutter_gpu`; `dart run tool/structure.dart` fails on the word.

## A new backend starts from the null backend

```bash
dart run flutter3d_build:flutter3d create plugin --kind backend --name flutter3d_vulkan
```

writes `examples/flutter3d_backend_null` under the package's name
(`VulkanDevice`, `VulkanPass`, `registerVulkanBackend`,
`VulkanMaterialCompiler`). It has no GPU: it keeps textures in memory,
clears, uploads, copies and reads them back, and refuses every pipeline at
its first draw. It passes every conformance check but the shader tier as
written, using published libraries only. Grow it from there; do not start
from an empty class.

## The 1.0 contract, in five lines

- **One `open`.** Every backend opens as
  `static Future<D> open({required int width, required int height})`, the
  `BackendOpener` shape. `DeviceRegistry.addBackend`, `runDeviceConformance`
  and `flutter3d_testing`'s `renderFrame(device:)` all take it as it is.
- **Bodies on everything gated.** `GraphicsDevice`, `PassEncoder`,
  `TransferEncoder` and `ComputeEncoder` are base classes; every member a
  `DeviceFeature` gates has a default that refuses with the feature named.
  Implement the members without a body, override a gated one when you add
  its feature to `features`. A minor adds members only with a body.
- **`backend.dart` makes handles.** `wrapTexture`, `wrapGeometry`,
  `wrapPipeline`, `wrapShader` (and the buffer, query and fence ones) from
  `package:flutter3d_hardware/backend.dart`, with your device as `owner`;
  call `debugCheckLive` before using a handle you were given.
- **A material compiler per backend.** Register a `MaterialCompiler`
  (`package:flutter3d_shaders/backend.dart`) with the engine's
  `MaterialCompilerRegistry`: it writes your section of a shader bundle from
  a `.f3dmat`, and your `loadShaders` reads that section back.
- **The shader contract.** `requiredShaders` is what your bundle answers to;
  `stageBindings` and `uniformBlocks` (in `backend.dart`) are what a draw
  binds; `compileStage(glsl, name:, fragment:, target:)` in
  `package:flutter3d_shaders/compile.dart` gives SPIR-V and your language;
  CONTRACTS ("The shader ABI") lists the entry points and `F3D_*` defines.

## Capabilities

`device.features` is a `DeviceFeatures` set; ask `features.has(feature)`.
There are no `supportsX` getters. A call that needs a feature the device
lacks throws `UnsupportedCapabilityException` naming it: `refuse(feature)`
inside a device, `device.features.require(feature, backend: name)` in a pass.
Report a feature exactly when you implement it; conformance fails a feature
reported and not done, done and not reported, or refused by another name.

## Drawing, in the order the calls have to happen

```dart
device.beginFrame();
final pass = device.beginRenderPass(RenderPassDescriptor(
  colors: [ColorTarget(texture: color, loadAction: LoadAction.clear)],
  depth: DepthTarget(texture: depth),
));
pass.bindPipeline(pipeline);
pass.bindVertexBuffer(geometry, vertexCount);
pass.bindIndexBuffer(indices, IndexType.int32, indexCount);
pass.bindUniformBlock(vertexStage, 'FrameInfo', {'mvp': matrix});
pass.bindTexture(fragmentStage, 'base_color_texture', handle);
pass.draw();
pass.submit();
```

**A pass's initial viewport covers its attachment's level**, and a clear
covers the whole attachment whatever the scissor says.

**`draw()` is indexed.** A draw without an index buffer is
`drawNonIndexed`, which needs `DeviceFeature.nonIndexedDraw`.

**A uniform block is addressed by its block name, a texture by its variable
name,** each on the stage that declares it. For
`uniform FrameInfo { … } frame_info;` the key is `FrameInfo`. Both binds
answer whether the stage has the slot: false for one it lacks, never a
throw; a backend without reflection answers true.

**`bindPipeline` forgets every binding**, even when the same pipeline is
bound again.

**A pipeline the API will not build is reported, not thrown**:
`device.pipelineRefusals.report(handle, PipelineRefusedException(...))`,
skip the draw, rebuild at the next use while `report` answered true.

**One encoder per pass.** Passes execute in submission order.

## Reading back

`readback(texture, {region})` returns the texture as the passes submitted
before the call left it, rows from the top, without stalling. Ask
`readbackConverts` and `readbackRegionOf` rather than deciding which
formats and regions are allowed: they refuse what the contract refuses, the
same way on every backend.

## What is deliberately absent

No device enumeration, no swapchain, no window, no Flutter `Widget`. An
application opens a backend through the engine's `DeviceRegistry`; a backend
that shows frames registers a presenter with `addPresenter<D>`, and
`presentFrame()` in `flutter3d_app` looks it up.

## Conformance

An interface can only say a call exists. What a backend must *do* is
`flutter3d_conformance`, and a backend is finished when it passes, not when
it compiles.

```dart
void main() => runDeviceConformance(
  backend: 'vulkan',
  makeDevice: VulkanDevice.open,
  // Before the backend draws: every check but the shader tier.
  checks: conformanceChecks.where((c) => !shaderChecks.contains(c)).toList(),
);
```

Leave `checks:` out to run everything. A check a device cannot be asked
declines through `decline(device, why)` and is reported as skipped with that
sentence, never as passed; write new checks the same way.

## Drawing the engine's frames on a device in a test

```dart
final frame = await renderFrame(
  width: 320, height: 180,
  device: VulkanDevice.open,           // null: the software rasteriser
  build: (request) => buildScene(request.device),
);
```

`testReplay(device:)` draws a replay's goldens on one device for the run;
`drawOnce` draws with a device and `Renderer` the test holds. Keep each
backend's goldens in their own directory.

## Testing without a device

```dart
import 'package:flutter3d_hardware/testing.dart';

final device = FakeBackend();
final renderer = Renderer.create(device: device);
renderer.render(width: 64, height: 64, scene: scene, views: [CameraView(camera: camera)]);

final pass = device.passes.last;
expect(pass.recordedOf<RecordedDraw>(), hasLength(3));
expect(pass.recordedOf<RecordedPipeline>(), hasLength(1));
```

Every pass keeps its calls in order in `commands`, each a `Recorded…` value.
That is how a test asserts sorting, culling and state changes, the questions
a screenshot cannot answer. `liveHandles` lists what was made and not given
back; `releasedTextures`, `releasedGeometry` and `isDisposed` answer the
rest. `refusingPipelines:` makes the fake a driver that refuses a pipeline
at its first draw.
