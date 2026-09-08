## 0.5.2

* **`webgpu_interop.dart`: WebGPU's interfaces and dictionaries as
  `dart:js_interop` declarations.** Bind group layouts and bind groups, pipeline
  layouts, samplers, the canvas context, depth and stencil state, multisampling,
  texture views by mip level and array layer, and `queue.writeTexture` — none of
  which the spike this package grew from had, and none of which a backend can be
  written without. Descriptors are object-literal constructors, so a misspelt
  member is a compile error rather than a `TypeError` from inside
  `createRenderPipeline`; where WebGPU forbids a *combination* the choice is a
  named constructor, because an absent dictionary key and an explicit `null` are
  different things to this API and `blend: null` is the spelling it refuses.
* **The parameters a triangle can leave at zero are all present.** A vertex or
  index buffer offset, a first index, a base vertex, a first instance: each of
  them is a wrong picture rather than an error when it is dropped, and a backend
  that packs two meshes into one allocation and forgets one draws the other mesh
  in silence. Twelve tests in Chrome ask about each in turn, every one against a
  control draw that comes back the other colour — a test that only checked
  "green arrived" would pass on a backend that had stopped reading the parameter
  and happened to be pointing at green.
* **`gpuChecked`, and error scopes used from the first day rather than the
  first bug.** WebGPU validates asynchronously: a bad descriptor yields an
  object that does not work and a complaint on the browser console that no Dart
  program ever sees. Bracketing a call in a validation scope is the only way one
  becomes a thrown `GpuDeviceError`, which is what the conformance suite's
  refusal checks are written expecting.
* **The flag constants are written out rather than imported.** The spike reached
  into `package:web` for `$GPUBufferUsage` and its four siblings, which cost it
  a dependency for twenty-five integers. They are asserted against the
  specification here instead, and this package depends on nothing but the
  contract.
* **The package exists, and nothing in it opens a device.** A fourth backend is
  three or four branches of work, and every one of them wants a `pubspec.yaml`,
  an `analysis_options.yaml` and a place in the publishing order. Written once,
  first, they are a merge that never happens.
* **`webgpu_formats.dart`, moved from `tool/webgpu_spike` unchanged.** Every
  enumeration the contract names, translated to the string the WebGPU
  specification spells it with, plus the readback row padding, the four-byte
  write padding and `WebGpuPipelineKey`. The sixteen tests that came with it are
  held against the specification's own value sets, and they run on the VM: the
  file imports neither `dart:js_interop` nor `package:web`, which is the
  property that lets a typo in `"less-equal"` fail in a second rather than in a
  browser on a machine with a GPU.
* Two blend factors answer null and stay that way. `BlendFactor.blendAlpha` and
  its complement are `CONSTANT_ALPHA`, which WebGPU cannot form in the colour
  equation at all; `supportsBlendColor` is the contract's own way of asking,
  and this backend will answer false. Nothing in the engine, the games or the
  site builds a blend constant, so the contract is untouched.
* Version 0.5.2 to match the three backends it joins, and `pub publish` is not
  run for it: being in the publishing order and being published are different
  things, and this one goes out when it draws.
