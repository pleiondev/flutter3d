# webgpu_spike

**A spike, not a backend.** It exists to answer one question with code: is
`flutter3d_hardware` a contract, or is it a description of OpenGL's conventions
wearing neutral names? WebGPU is the sharpest way to ask, because it disagrees
with OpenGL about nearly every convention the question is about — where row zero
of a render target is, what clip depth maps onto, which way a rectangle is
measured, which winding is front-facing, and where rasteriser state lives.

It draws one triangle through the contract and reads it back. Everything else
throws, and every throw says which of two things it is: ordinary work the spike
did not do, or a point where the contract and the API do not meet.

## The answer

**Four points of the contract** would have to change, and three of the four are
closed by adding to it rather than by touching anything that exists. They are, in
`lib/src/webgpu_contract_gaps.dart` and in this order:

1. `BlendFactor.blendAlpha, BlendFactor.oneMinusBlendAlpha` — **by rewriting.**
   OpenGL, Metal and Vulkan all split the blend constant into a per-channel
   colour and a broadcast alpha; `BlendFactor` mirrors that split and WebGPU has
   only the colour half. `GraphicsDevice.supportsBlendColor` is one answer for
   all four constant-reading factors, so a backend with two of them has no way
   to say so — it must answer false and lose the two it could have honoured.
   Splitting the capability changes what `true` promises, and the three existing
   backends are written against that promise. This is the only entry that is not
   an addition, and it costs a feature nothing in the engine uses today.
2. `ShaderBundle.webgpuSection` — **by addition.** One `const String` beside
   `impellerSection` and `webglSection`.
3. `ShaderBundle`: reflection beside the code — block, sampler and attribute
   names — **by addition.** WGSL keeps `@group`, `@binding` and `@location` and
   drops every name before the browser sees the module, and `GPUShaderModule`
   reflects nothing. `PassEncoder.bindUniformBlock` takes a block name,
   `bindTexture` takes a sampler name, and `InputAttribute.name` says outright
   that a name is used because the two hardware backends both agree about names.
   Impeller gets its reflection from `impellerc`'s flatbuffer and WebGL2 from the
   context; a WGSL section has to carry its own. Same constant as (2), listed
   apart because it is what the work actually is.
4. `GraphicsDevice.createPipeline`, the null layout — **by addition.** Null means
   "the backend works it out from the shader", which is what every pipeline in
   the engine still passes; there is nothing on this API to work it out from.
   Closed by the same sidecar as (3). Making the layout required instead would
   change every call site in the engine rather than one package.

## What did **not** have to change, which is the larger half of the answer

Each of these was a suspect, and each one the contract already handles by asking
rather than assuming:

- **The framebuffer origin.** `FramebufferOrigin` has both values and
  `toFramebufferOrigin` corrects at the boundary. WebGPU answers `topLeft`, which
  is the value the engine's own rectangles and readbacks were written for — so
  the backend that pays for this convention is WebGL2, not WebGPU.
- **The depth range.** `DepthRange` has both values, the engine builds for
  `zeroToOne`, and `toDepthRange` corrects. WebGPU answers `zeroToOne` and the
  correction is skipped.
- **Rectangles from the top left, and viewports.** `ScreenRect` is stated from
  the top left and WebGPU's `setViewport`/`setScissorRect` take it unchanged. The
  WebGL2 backend has a `_flipY` for exactly this and WebGPU needs none.
- **A clear covers the whole attachment however the scissor is set.** A load
  operation in WebGPU, so it is free. GL had to be made to do it.
- **`setBlend`'s `attachment` index.** WebGPU gives every colour target its own
  blend equation, so it is the one implementation that could honour the index
  without an optional extension. The contract already permits that.
- **Uniform block layout.** The contract says how the bytes are packed is the
  backend's business. Every uniform in the engine is a float vector, a matrix or
  an array of either, and WGSL's uniform address space lays those out exactly as
  std140 does — so the assumption nobody wrote down happens to be true here too.
- **`GeometryUsage`.** Added for WebGL2, where a buffer is bound to its target
  for life. A WebGPU buffer declares `VERTEX` or `INDEX` at creation and cannot
  be rebound either, so this turned out not to be one API's wart.
- **Multisampling.** `ColorTarget.resolveTexture` beside a resolving
  `StoreAction` is exactly WebGPU's `resolveTarget` beside a store op.
- **`supportsWireframe`, `supportsBlendColor`, `supportsStencil`,
  `supportsRenderToMip`, `supportsTextureFormat`.** All five are questions with
  answers here, which is what they were added for.
- **`present` returning a widget.** The contract asks for a widget precisely
  because a `ui.Image` is an Impeller shape; WebGPU shows a canvas the way the
  WebGL2 backend already does.
- **`onFrameComplete` and `readback`.** `queue.onSubmittedWorkDone()` and
  `copyTextureToBuffer` plus `mapAsync` answer both promises, including the sharp
  one — that a readback is the texture as the passes *before* the call left it.
- **Which winding is front-facing.** Measured rather than reasoned; see below.

## The winding, which was going to be a fifth point and is not

This one was reasoned wrong and then measured. It is written up because the
reasoning is good and somebody will do it again.

The contract does not say which space a winding is measured in. It has not needed
to: OpenGL takes the signed area in window coordinates whose y runs up, the
software rasteriser measures in its own top-left space and says so where it tests
the sign, and Impeller's is Metal's — all three agree that
`WindingOrder.counterClockwise` means counter-clockwise **in clip space**, which
is what every mesh in the engine is wound as. WebGPU's framebuffer coordinates
run y down, the same choice Vulkan made, and a Vulkan port genuinely does have to
cross the winding over or flip the viewport. So `gpuFrontFace` was written
crossed — `counterClockwise` to `"cw"` — and the triangle came back the clear
colour.

`webgpu_triangle_test.dart` draws the two-by-two of winding against cull mode on
a real GPU. **Under `"ccw"` a clip-space counter-clockwise triangle is
front-facing**, so WebGPU agrees with the other three and the mapping is straight
through. The correction the argument predicted is not there, and this is the one
answer in the spike that only a draw could give.

What is left is a gap in the *documentation* rather than in the interface: one
sentence in `formats.dart` saying that a winding is measured in clip space would
have made the argument unnecessary. It changes no behaviour anywhere, which is
why it is not counted above.

## Two things a new backend gets wrong on the first run

Neither is a change to the contract; both are places where the obvious
translation is refused by the browser rather than by the compiler, so both are
written down where the next reader meets them.

**Row padding in a readback.** `copyTextureToBuffer` will not write rows packed
tighter than 256 bytes, and `GraphicsDevice.readback` promises the region's own
width times four. The copy is made wide and repacked. `paddedBytesPerRow` is the
arithmetic, and the case it exists for is a width that is already aligned and
must not be rounded up.

**Four-byte writes, and an absent member against a null one.** `writeBuffer`
refuses a length that is not a multiple of four — which the smallest draw in the
engine hits at once, three sixteen-bit indices being six bytes — and rounding the
buffer up does not help, because the constraint is on the write. And a
`GPUColorTargetState` with `blend: null` is a `TypeError`, where the same
dictionary with the member left out is blending off; `PassEncoder.setBlend` takes
a nullable state, so the obvious translation writes exactly the spelling this API
refuses.

## What is here

| File | What it is |
| --- | --- |
| `lib/src/webgpu_conventions.dart` | Every translation, in pure Dart. Runs on the VM. |
| `lib/src/webgpu_contract_gaps.dart` | The four, as data. |
| `lib/src/webgpu_interop.dart` | The slice of WebGPU a triangle needs, hand-written: `package:web` carries the flag constants and none of the interfaces. |
| `lib/src/webgpu_spike_device.dart` | A `GraphicsDevice` as far as one triangle needs one. |
| `lib/src/webgpu_spike_encoder.dart` | A `CommandEncoder` that accumulates state and looks a pipeline up at the draw. |
| `lib/src/webgpu_triangle.dart` | The triangle. |

## Why it is under `tool/`

A directory in `packages/` with a pubspec is a package, and
`tool/structure.dart`'s "the publishing order names every package" rule then
requires it in `ARCHITECTURE.md`'s numbered publishing list — whose own heading
says it is the order used on the day the packages went out. Nothing here is ever
going out. Adding it to that list to satisfy a scan would write something false
into the one document that records how a release is made, and turning the rule
off is worse. So the spike lives with the other programs this repository runs on
itself, and `tool/ci.sh` runs its tests by name.

## Running it

```
cd tool/webgpu_spike
flutter test                      # the translations, the key, this document
flutter test --platform chrome    # and the triangle, where there is a GPU
```

The browser run reports rather than fails where the browser has no
`navigator.gpu` — a headless runner usually has none, and a spike that found no
GPU has established nothing and should say so.
