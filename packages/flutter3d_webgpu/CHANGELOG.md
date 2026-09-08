## 0.5.2

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
