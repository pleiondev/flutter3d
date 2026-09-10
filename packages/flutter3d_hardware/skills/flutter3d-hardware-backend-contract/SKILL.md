---
name: flutter3d-hardware-backend-contract
description: Use when writing a flutter3d graphics backend, calling GraphicsDevice or CommandEncoder directly, or testing rendering with the fake device that records draws.
---

# The vocabulary a frame is written in

Types only: `GraphicsDevice`, `CommandEncoder`, handles, formats, pipelines,
samplers, render targets — and no implementation. An engine written against this
can be handed a backend as a value, which is what lets a software rasteriser
draw the frame a GPU drew and a test check that it did.

**Nothing here may name a graphics API.** Not Metal, Vulkan, WebGL or
`flutter_gpu`; `dart run tool/structure.dart` fails on the word, and that rule
is why the fourth backend cost nothing above this layer.

## Drawing, in the order the calls have to happen

```dart
device.beginFrame();
final pass = device.beginRenderPass(RenderPassDescriptor(
  colors: [ColorTarget(texture: colour, loadAction: LoadAction.clear)],
  depth: DepthTarget(texture: depth),
));
pass.setViewport(rect);
pass.setScissor(rect);
pass.bindPipeline(pipeline);
pass.bindVertexBuffer(geometry, vertexCount);
pass.bindIndexBuffer(indices, IndexType.uint32, indexCount);
pass.bindUniformBlock('FrameInfo', bytes);
pass.bindTexture('base_color_texture', handle, SamplerOptions());
pass.draw();
pass.submit();
```

**Viewport and scissor default to a zero-sized rect** and no backend complains
about drawing into one. A black frame with no error is usually this.

**There is no non-indexed draw.** `draw()` with only a vertex buffer succeeds
and renders nothing; bind an index buffer even for the identity sequence.

**A uniform block is addressed by its block name, a texture by its variable
name.** For `uniform FrameInfo { … } frame_info;` the key is `FrameInfo`.
`bindUniformBlock` returns whether the block was there, because a shader that
never reads one loses it from reflection and binding a phantom block is a
segfault on some devices.

**One encoder per pass.** A multi-pass frame is a pass each, submitted in order;
they execute in submission order.

## What is deliberately absent

No device enumeration, no swapchain, no window, no context-loss policy, no
shader compiler. An application opens a backend and hands it over. `present()`
is the one call returning a Flutter `Widget`.

An interface can only say a call exists. What a backend must *do* — a clear
covering the whole attachment, uploaded pixels keeping their row order — is
`flutter3d_conformance`. A new backend is finished when that suite passes, not
when it compiles.

## Testing without a device

```dart
import 'package:flutter3d_hardware/testing.dart';

final device = FakeBackend();
renderer.render(device, scene);

final pass = device.passes.single;
expect(pass.recordedOf<RecordedDraw>(), hasLength(3));
expect(pass.recordedOf<RecordedPipeline>(), hasLength(1));
```

Every pass keeps its calls in order in `commands`, each a `Recorded…` value.
That is how a test asserts sorting, culling and state changes — the questions a
screenshot cannot answer. `releasedTextures`, `releasedGeometry` and `disposed`
answer whether what was allocated was handed back.

`RenderTargetPool` keys targets by `RenderTargetSpec` and reuses them across
frames, so a post chain does not allocate one per pass per frame.
