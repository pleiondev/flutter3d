## 0.5.2

* **A device, an encoder and a frame that comes back as pixels.** `openWebGpu`
  asks for an adapter and then a device, answers null where a browser has
  neither, and turns that null into the one `StateError` worth putting on a
  screen. A pass opens in the encoder's constructor, the six rasteriser setters
  go into private fields, and the real `GPURenderPipeline` is looked up at the
  draw — which is the divergence `command_encoder.dart` predicted for Vulkan
  and turned out to have described this backend as well.
* **The pipeline signature is wider than the spike's ten fields**, and the
  vertex layout is the field that had to be added. `GraphicsDevice.createPipeline`
  says why: two layouts over one stage pair are two pipelines, and handing the
  first back for the second is a draw that reads instance data as vertices —
  a picture, and no error anywhere. The stencil and a blend equation per colour
  attachment joined it for the same reason. A `flutter3d_webgpu.dart` importer
  gets the signature and the cache without a browser, and the tests that ask
  which two states are one pipeline run on the VM.
* **`setBlend`'s attachment index reaches the hardware**, which no other backend
  here can do. WebGPU gives every colour target its own blend equation in the
  pipeline; Impeller honours the index through flutter_gpu, WebGL2 would need an
  optional extension and the software rasteriser keeps one state for the pass.
  A pass with two attachments blending differently is drawn and read back.
* **One bump allocator per kind of transient upload, rewound at `beginFrame`.**
  The WebGL2 backend makes a buffer per binding — 1552 in one measured frame —
  and gets away with it because a GL driver owns the fencing. `queue.writeBuffer`
  copies into the queue's own staging and schedules the write on the queue, so a
  frame's rewind cannot reach a frame the GPU is still on; growth retires the
  old buffer rather than destroying one a bind group still names. The whole
  argument is at the top of `webgpu_resources.dart`.
* **Bind groups and samplers are cached instead of allocated per draw.** A
  uniform block is bound with a dynamic offset, so one group serves a frame of
  forty materials against one camera block, and a sampler is one object per
  distinct `SamplerOptions` — which is the whole of what GL needed four
  `texParameteri` per bind for.
* **The resolve target is attached, not merely mapped.** `gpuResolves` had been
  written and tested and wired to nothing; a store action translated without it
  is multisampling computed and thrown away, and the resolve target reading what
  was in it before.
* **`debugTrackedResourceCount`, the error scopes and `dispose_test.dart` are in
  the first commit**, before anything drew. WebGPU validates asynchronously —
  a pipeline is returned whether or not the descriptor was legal — so a backend
  that means to report a refusal has to bracket its calls, and a bad shader is
  not even that: the module is created and the line number is only in
  `getCompilationInfo`. Asking for it found six of the engine's own stages that
  this implementation refuses, which is the first check in the repository that
  could have.
* **Six fragment stages do not compile here yet**, and the count is a test
  rather than a note. `Pbr`, `BlinnPhong`, `Lambert`, `Toon`, `Reflections` and
  `Ssao` call `textureSample` from non-uniform control flow, which naga accepts
  and a browser does not. The fix is in the GLSL, not in this package.
* **A platform view whose pin the device can empty.** The registry has no
  unregister and never will, so the factory closure holds a cell rather than the
  canvas; `dispose` nulls it, unconfigures the canvas context and destroys the
  device, which is a complete teardown the WebGL2 backend cannot reach.
* **No row is turned over on the way back.** WebGPU's framebuffer origin is the
  top left, so a readback kept in order is already what the contract promises —
  and a flip carried across from the backend that needs one gives a frame that
  reads back correctly and presents upside down.
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
