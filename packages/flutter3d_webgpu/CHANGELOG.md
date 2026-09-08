## 0.5.2

* **Every shader the engine asks for, in WGSL, with the reflection beside it.**
  `tool/generate_shaders.dart` reads the manifest `impellerc` and the WebGL
  generator read, prepares each of the 39 stages, and hands it to
  `glslangValidator` and then to `naga`. All 39 compile, and all 39 come back
  through `naga --input-kind wgsl`, which is a different question from whether
  naga could write them. `tool/ci.sh` regenerates the table and diffs it.
* **The reflection is written by the packer, not read back out of the WGSL.**
  A `GPUShaderModule` cannot be asked what it declares and a pipeline layout has
  to state it, so `webgpu_bundle_section.dart` carries attributes by name,
  location and format; uniform blocks by name, group, binding, size and member
  offsets; and samplers by name and the two bindings each takes. The offsets are
  computed from the GLSL by std140 and held against glslang's own `Offset`
  decorations on every block of every stage, which is the only place the two
  could disagree.
* **naga will not read a combined sampler**, and says so as `invalid id %14`
  with no file and no construct. Only the declarations are edited — a
  `texture2D`, a `sampler` and a `#define` that puts them back together — so all
  59 `texture()` calls and 5 `textureLod()` calls pass through untouched.
* **`--keep-coordinate-space`, which is not optional.** naga 30.0.1 otherwise
  appends `gl_Position.y = -(gl_Position.y)` to every vertex entry point, and
  nothing fails: the WGSL compiles, the pipeline builds, and every scene comes
  back upside down. Both facts are tests rather than memories.
* **A varying's location is decided across the manifest.** WebGPU does not
  link, so a pair whose two sides number their varyings from their own
  declarations draws the wrong picture with nothing to say so. Locations are a
  function of the name, grouped into families by which names ever appear in one
  stage — four families, the widest of eight, because there are seventeen
  varyings and sixteen locations.
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
