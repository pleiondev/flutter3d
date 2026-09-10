---
name: flutter3d-webgpu-two-barrels
description: Use when working on the flutter3d WebGPU backend — which of the two libraries to import, the shader toolchain flags, what the device declines, and where a frame's buffers live.
---

# Two barrels, and the import decides where the code runs

`flutter3d_webgpu.dart` is pure Dart — the format table, the pipeline signature,
the shader map — and its tests run on the VM in about a second. A typo in
`"less-equal"` is a failed unit test there rather than a browser refusing a
pipeline at run time.

`flutter3d_webgpu_web.dart` is everything reaching for `dart:js_interop`: the
device, the encoder, the frame arenas, the bindings. Import it only from code
compiled for a browser.

```dart
final device = await openWebGpu(width: 960, height: 540);
```

Most applications call `openDevice` from `flutter3d_backend` instead.
WebGPU is opened only behind `--dart-define=FLUTTER3D_WEBGPU=true` (the engine's
example takes `?backend=webgpu`), because a probe able to call either opener
keeps both backends reachable and dart2js ships what it can reach — 376,649
bytes of `main.dart.js` on the strategy demo.

## The generated WGSL, and three flags that are not optional

```
dart run tool/generate_shaders.dart     # writes lib/engine_shaders.dart
```

It rewrites each stage's GLSL declarations, then runs `glslangValidator -V
--auto-map-locations` and `naga --keep-coordinate-space`. Both tools must be on
`PATH`; `tool/ci.sh` regenerates and diffs, so a stale table fails the build.

**naga will not read a combined sampler.** `uniform sampler2D tex` gives SPIR-V
that `spirv-val` accepts and naga refuses with `invalid id %14`, naming neither
file nor construct. Each sampler is a `texture2D`, a `sampler` and a `#define`
that puts them back together.

**`--keep-coordinate-space` is load-bearing.** Without it naga appends
`gl_Position.y = -(gl_Position.y)` to every vertex entry point: the WGSL
compiles, the pipeline builds, and every scene comes back upside down.

**Varying locations are decided across the manifest, not inside a file.** WebGPU
does not link — two modules are compiled apart and joined by location alone — so
a stage declaring its own varying before its include shifts one side of a pair
and draws the wrong picture silently. Locations are a function of the name,
grouped into families by co-occurrence, because there are seventeen varyings and
sixteen locations.

**`textureSample` may only be called from uniform control flow.** Six fragment
stages sampled under a branch the four invocations of a quad need not take
together; naga accepted them and the browser refused at the first pipeline as
`invalid due to a previous error`, naming no line, one fault at a time. The cure
is in the GLSL: single-level targets read with `textureLod` at level zero, and
the normal map — which has a real mip chain — hoisted above the branch instead.
`test/open_test.dart` asserts nothing is refused, so a stage that reacquires the
fault fails rather than raising a count.

## What the device declines, and why a decline is not a gap

Every no is a declared capability rather than a method that quietly does
nothing, because a refusal and a gap look identical from outside.

- **The blend constant.** WebGPU has `"constant"` and `"one-minus-constant"` and
  no colour/alpha split, so two `BlendFactor` values translate to null and
  `supportsBlendColor` answers false.
- **Wireframe.** No polygon fill mode. Line primitives with an index buffer
  built for them is the renderer's decision, as on WebGL2.
- **Three formats.** `a8UNormInt` and the two HDR ASTC layouts have no WebGPU
  spelling on any adapter there will ever be.

Block-compressed formats **are** supported, and the shape of the asking is worth
copying: `requestDevice` handed a feature the adapter lacks rejects the promise
rather than answering with a lesser device, so ask the adapter what it has and
request the intersection. `supportsTextureFormat` answers from
`gpuDevice.features` — what was granted — because a capability answering from a
wish tells a loader to upload a texture the browser will not take. Uploading is
block arithmetic: `bytesPerRow` counts a row of *blocks*, `rowsPerImage` counts
block rows.

A refusal that outlives its reason is worse than the gap it guarded. Two were
lifted that way, the cube render target and render-to-mip, after the conformance
suite failed rather than declined.

## Where a frame's buffers live

One bump allocator per kind of transient upload, rewound at `beginFrame`. Safe
under a frame the GPU has not finished because `queue.writeBuffer` copies into
the queue's staging at the moment of the call and schedules the write on the
queue, so frame N's write, N's pass, N+1's write and N+1's pass run in that
order however far behind the GPU is. An arena that outgrows itself keeps the old
buffer rather than freeing it, because a bind group made earlier in the frame
names it.

Readback of a float target has no format conversion here —
`copyTextureToBuffer` hands over bytes as stored — so it is drawn into an
eight-bit target by a full-screen `textureLoad` pass and copied from that. The
eight-bit path stays a plain copy.
