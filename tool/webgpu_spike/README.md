# webgpu_spike

This is a spike, not a backend. It answers one question with code: is
`flutter3d_hardware` a contract, or is it OpenGL's conventions under neutral
names? WebGPU puts that question most sharply, because it disagrees with OpenGL
about nearly every convention involved: where row zero of a render target is,
what clip depth maps onto, which way a rectangle is measured, which winding is
front-facing, and where rasteriser state lives.

It draws one triangle through the contract and reads it back. Everything else
throws, and each throw says which kind it is: ordinary work the spike did not
do, or a point where the contract and the API do not meet.

## The answer

**Four points of the contract** would have to change, and three of the four are
closed by adding to it rather than by touching anything that exists. They are
listed in `lib/src/webgpu_contract_gaps.dart`, in this order:

1. `BlendFactor.blendAlpha, BlendFactor.oneMinusBlendAlpha`, by rewriting.
   OpenGL, Metal and Vulkan all split the blend constant into a per-channel
   colour and a broadcast alpha. `BlendFactor` mirrors that split, and WebGPU
   has only the colour half. `GraphicsDevice.supportsBlendColor` is one answer
   for all four constant-reading factors, so a backend that has two of them
   cannot say so: it must answer false and lose the two it could have honoured.
   Splitting the capability changes what `true` promises, and the three
   existing backends are written against that promise. This is the only entry
   that is not an addition, and the feature it costs is one nothing in the
   engine uses today.
2. `ShaderBundle.webgpuSection`, by addition. One `const String` beside
   `impellerSection` and `webglSection`.
3. `ShaderBundle`: reflection beside the code — block, sampler and attribute
   names. By addition. WGSL keeps `@group`, `@binding` and `@location` and
   drops every name before the browser sees the module, and `GPUShaderModule`
   reflects nothing. `PassEncoder.bindUniformBlock` takes a block name,
   `bindTexture` takes a sampler name, and `InputAttribute.name` says outright
   that it uses a name because the two hardware backends agree about names.
   Impeller gets its reflection from `impellerc`'s flatbuffer and WebGL2 gets
   it from the context; a WGSL section has to carry its own. It is the same
   constant as (2), listed separately because this is where the actual work is.
4. `GraphicsDevice.createPipeline`, the null layout, by addition. Null means
   "the backend works it out from the shader", and every pipeline in the engine
   still passes null. This API offers nothing to work it out from. The same
   sidecar as (3) closes it. Making the layout required instead would change
   every call site in the engine, where the sidecar changes one package.

## What did **not** have to change, which is the larger half of the answer

Each of these was a suspect, and the contract already handles each one by asking
the backend instead of assuming an answer:

- The framebuffer origin. `FramebufferOrigin` has both values and
  `toFramebufferOrigin` corrects at the boundary. WebGPU answers `topLeft`,
  which is the value the engine's own rectangles and readbacks were written
  for, so the backend that pays for this convention is WebGL2.
- The depth range. `DepthRange` has both values, the engine builds for
  `zeroToOne`, and `toDepthRange` corrects. WebGPU answers `zeroToOne` and the
  correction is skipped.
- Rectangles from the top left, and viewports. `ScreenRect` is stated from the
  top left, and WebGPU's `setViewport`/`setScissorRect` take it unchanged. The
  WebGL2 backend has a `_flipY` for exactly this; WebGPU needs none.
- A clear covers the whole attachment however the scissor is set. In WebGPU a
  clear is a load operation, so this comes free. GL had to be made to do it.
- `setBlend`'s `attachment` index. WebGPU gives every colour target its own
  blend equation, so it is the one implementation that can honour the index
  without an optional extension. The contract already permits that.
- Uniform block layout. The contract leaves byte packing to the backend. Every
  uniform in the engine is a float vector, a matrix or an array of either, and
  WGSL's uniform address space lays those out exactly as std140 does. The
  assumption nobody wrote down happens to hold here too.
- `GeometryUsage`. It was added for WebGL2, where a buffer is bound to its
  target for life. A WebGPU buffer declares `VERTEX` or `INDEX` at creation and
  cannot be rebound either, so this is not a quirk of one API after all.
- Multisampling. `ColorTarget.resolveTexture` beside a resolving `StoreAction`
  is exactly WebGPU's `resolveTarget` beside a store op.
- `supportsWireframe`, `supportsBlendColor`, `supportsStencil`,
  `supportsRenderToMip`, `supportsTextureFormat`. All five are questions WebGPU
  can answer, which is what they were added for.
- `present` returning a widget. The contract asks for a widget because a
  `ui.Image` is an Impeller shape. WebGPU shows a canvas, the way the WebGL2
  backend already does.
- `onFrameComplete` and `readback`. `queue.onSubmittedWorkDone()`, and
  `copyTextureToBuffer` plus `mapAsync`, keep both promises, including the
  stricter one: a readback is the texture as the passes *before* the call left
  it.
- Which winding is front-facing. This was measured, not reasoned; see below.

## The winding, which was going to be a fifth point and is not

This one was reasoned wrong and then measured. The reasoning is written up here
because it is sound and somebody will follow it again.

The contract does not say which space a winding is measured in, and so far it
has not needed to. OpenGL takes the signed area in window coordinates with y
running up. The software rasteriser measures in its own top-left space and says
so where it tests the sign. Impeller's convention is Metal's. All three agree
that `WindingOrder.counterClockwise` means counter-clockwise in clip space,
which is how every mesh in the engine is wound. WebGPU's framebuffer
coordinates run y down, the same choice Vulkan made, and a Vulkan port really
does have to cross the winding over or flip the viewport. So `gpuFrontFace` was
written crossed, mapping `counterClockwise` to `"cw"`, and the triangle came
back as the clear colour.

`webgpu_triangle_test.dart` draws the two-by-two of winding against cull mode on
a real GPU. Under `"ccw"`, a clip-space counter-clockwise triangle is
front-facing. WebGPU agrees with the other three and the mapping is straight
through. The correction the argument predicted does not exist, and this is the
one answer in the spike that only a draw could give.

That leaves a gap in the documentation, not in the interface: one sentence in
`formats.dart` saying that a winding is measured in clip space would have made
the argument unnecessary. It changes no behaviour anywhere, so it is not counted
above.

## Two things a new backend gets wrong on the first run

Neither needs a change to the contract. In both, the obvious translation is
refused by the browser, not by the compiler, so both are written down where the
next reader will meet them.

Row padding in a readback. `copyTextureToBuffer` will not write rows packed
tighter than 256 bytes, and `GraphicsDevice.readback` promises the region's own
width times four. The spike makes the copy wide and repacks it.
`paddedBytesPerRow` does the arithmetic; the case it exists for is a width that
is already aligned and must not be rounded up.

Four-byte writes, and an absent member versus a null one. `writeBuffer` refuses
a length that is not a multiple of four. The smallest draw in the engine hits
this at once, since three sixteen-bit indices are six bytes, and rounding the
buffer up does not help because the constraint is on the write. Separately, a
`GPUColorTargetState` with `blend: null` is a `TypeError`, while the same
dictionary with the member left out means blending is off. `PassEncoder.setBlend`
takes a nullable state, so the obvious translation writes exactly the spelling
this API refuses.

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

A directory in `packages/` with a pubspec is a package. The "the publishing
order names every package" rule in `tool/structure.dart` would then require it
in the numbered publishing list in `ARCHITECTURE.md`, whose heading says it is
the order used on the day the packages went out. Nothing here is ever going
out. Adding the spike to that list to satisfy a scan would put something
false into the one document that records how a release is made, and turning the
rule off would be worse. So the spike lives with the other programs this
repository runs on itself, and `tool/ci.sh` runs its tests by name.

## Running it

```
cd tool/webgpu_spike
flutter test                      # the translations, the key, this document
flutter test --platform chrome    # and the triangle, where there is a GPU
```

Where the browser has no `navigator.gpu`, the browser run reports instead of
failing. A headless runner usually has none, and a spike that found no GPU has
established nothing and should say so.
