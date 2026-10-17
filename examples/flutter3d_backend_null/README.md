# A backend from outside

A graphics backend written as somebody outside this repository would write
one: `package:flutter3d_hardware` for the device contract and the handles,
`package:flutter3d_shaders/backend.dart` for the material compiler, every
engine package by path, and no `src/` import. The structure rule `an
outside example reaches only the published API` reads every file here and
holds it to that.

It has no GPU. `NullDevice` keeps textures in memory, clears, uploads,
overwrites, copies and reads them back, and refuses every pipeline at its
first draw. The engine's renderer runs on it, and a frame reports each
pipeline it drew with as refused, once. That is the point: every member a
backend for Vulkan, Metal, Direct3D or a server renderer writes is here,
with the drawing taken out, so a new backend starts from something that
already passes conformance and grows from there.

`flutter3d create plugin --kind backend` writes this package under the
name you give it. A test in `flutter3d_build` holds the template to these
files, so the two cannot drift.

## What is where

- `lib/flutter3d_backend_null.dart`: `registerNullBackend`, which adds the
  device to an engine's `DeviceRegistry` and its compiler to a
  `MaterialCompilerRegistry`, and `NullMaterialCompiler`, which turns a
  material into this backend's section of a shader bundle.
- `lib/src/null_device.dart`: the device. One `open({width, height})`, as
  every backend opens; the features it reports, which conformance holds
  true both ways; the handles it makes with `wrapTexture`, `wrapGeometry`,
  `wrapPipeline` and `wrapShader`.
- `lib/src/null_pass.dart`: a render pass, which implements only the
  members of `PassEncoder` without a body (every feature-gated member
  refuses by default), and a transfer pass that copies textures.
- `lib/src/null_texels.dart`: what a texture holds, four floats a texel.
  A backend over a real API keeps its textures in that API instead.

## Tests

```bash
dart test
```

- `test/conformance_test.dart` runs `flutter3d_conformance` on the device:
  every check but the shader tier, which needs a backend that draws.
- `test/null_device_test.dart` opens the device through a registry, loads
  a bundle whose material section this backend's compiler wrote, and draws
  a frame with the engine's renderer.

`flutter3d_testing`'s `renderFrame(device: NullDevice.open, ...)` draws a
frame on it the same way from a Flutter test.

## Growing it into a backend

1. Draw: compile the engine's stages for your API (`compileStage` in
   `package:flutter3d_shaders/compile.dart` gives SPIR-V and your
   language's text), answer them from `shaders`, bind by `stageBindings`,
   and stop refusing pipelines. Then add `shaderChecks` to the
   conformance run.
2. Report each feature as you implement it; the capability check fails on
   one reported and not done, and on one done and not reported.
3. Compile materials: write your stages into your section in
   `NullMaterialCompiler.compile`'s place.
