## 0.5.2

**What the fourth backend became, in one paragraph, because the entries below
are the road and this is the destination.** It opens a real WebGPU device,
records passes through it, and hands Flutter a frame; all thirty-nine of the
engine's stages compile, from the generated table and from a bundle handed over
as bytes alike; and `flutter3d_conformance` answers **33 of 33** against a live
adapter in Chrome — the same list the other three backends are held to, run as an
ordinary test file rather than as an application somebody watches, because Chrome
has a WebGPU device inside `flutter test` and that is the one arrangement
Impeller cannot have. Three of the thirty-three pass by *declining*, and each
decline is a capability this device says false to by name rather than a method
that quietly does nothing: **the blend constant** (WebGPU has `"constant"` and
`"one-minus-constant"` and no colour/alpha split to form `BlendFactor.blendAlpha`
with), **wireframe** (no polygon fill mode in the API at all), and **every
block-compressed format** (the device requests no compression family, and
sampling one it did not request is a validation error rather than a slow path).
What separates those three from a gap is only that they are declared, which this
package learned by getting it wrong once: `createCubeRenderTarget` returned null
while `supportsCubeTextures` said true, and the suite failed it instead of
declining it.

**Reflection probes are on, and lifting that refusal took no code at all —
which is the finding.** `supportsRenderToMip` answered false for one iteration
and had a reason: `ReflectionProbeNode.supportedOn` asks for a cube to draw six
views into *and* a chain to convolve them down, and while the cube was null a
yes here would have handed the renderer a probe and got a crash where a skip
belonged. The cube arrived, the false stayed, and by then it guarded nothing.
There was no mip-generation pass to write either: this API has no
`generateMipmap` and the engine never wants one — `Renderer._prefilterProbe`
writes each level itself as a full-screen pass whose colour target names a face
and a level, and on this backend `baseArrayLayer` and `baseMipLevel` on a plain
2D view are that pair, with the pass's initial viewport taken from the view and
so already covering the level rather than the texture. What proves it is a
picture: `probe-car` records here and lands on Impeller's reference at **0 of
172800 pixels, worst channel 0** — a mirrored ball whose reflection agrees to
the texel with a backend compiling the same GLSL through a different compiler on
the same GPU. The set now holds forty-two of the forty-three scenes.

**Two conformance checks stopped shrugging, at the same count.** The suite still
reports 33 of 33, and two of those thirty-three used to decline themselves from
the inside on this capability: `checkRenderToCubeFaceAndMip` allocated one level
instead of two and asked only about the face, and `checkPassViewportCoversTheLevel`
returned before it drew anything. Both ask the whole question now. A count that
does not move is exactly how a half-answered check hides, and it is worth saying
that the number was never the thing to read.

**It is not what a browser build opens, and that is a decision about bytes.**
`flutter3d_backend` still gives a web build WebGL2 and tries WebGPU first only
behind `--dart-define=FLUTTER3D_WEBGPU=true`; the engine's example takes
`?backend=webgpu` from the URL instead, so one dart2js run still serves
forty-three golden scenes and both browser backends. The probe cannot be a
compile-time question — whether `navigator.gpu` yields an adapter depends on the
browser, the driver and a blocklist — so a build that can try it carries it:
2,529,865 bytes of `main.dart.js` on `apps/flutter3d_demo_strategy` without the
flag against 2,906,514 with it, **376,649 bytes and 14.9%**, measured on two
builds of one checkout. WebGL2 stays the default because it is the browser
backend three shipped games have been looked at on and the one with a recorded
reference set behind it; moving every browser build onto the newer API would
change what those games draw and charge each of them those bytes, and neither is
a decision to make on a game's behalf.

**And its shaders are the first in this repository that are not the same text.**
WGSL is a different language and no browser takes SPIR-V, so `flutter3d_shaders`
reaches this backend through `glslangValidator` and `naga` rather than through a
compiler or a translator — which is why the six-stage uniformity fix below edits
GLSL that all four backends read, and why a byte-identical software golden set is
not evidence that the edit was neutral.

* **A bundle can now be packed with a section this backend reads**, which was
  the last thing standing between `loadShaders` and a picture.
  `tool/pack_wgsl_section.dart` takes an application's manifest and writes the
  `webgpu` section — the same preparation, the same `glslangValidator` and
  `naga`, the same std140 cross-check the engine's own table goes through — and
  `flutter3d_webgl/tool/pack_shaders.dart` copies it into the bundle under
  `--webgpu`, unread, the way it copies impellerc's. It is a program of its own
  because everything the section is made of belongs here and the WebGL package
  does not depend on this one. Varyings are numbered against the engine's
  manifest rather than the bundle's, because a loaded fragment stage is paired
  with a vertex stage the engine compiled long before and WebGPU joins the two
  by `@location` alone; a bundle that would renumber the engine's varyings is
  refused at the packer with both locations named. Missing compilers are not a
  failure — the packer exits 3 saying which program is absent, and the bundle
  comes out with two sections, because the CI that is green today installs
  neither. `loaded-shader` is recorded as a result, at `0 of 172800` against
  Impeller, and is out of the table of refusals.
* **The device and the shader library are one backend now.** Both halves of the
  same wave were written in parallel: the device declared a private class for
  the engine's stages, the library declared a one-method compiler interface,
  and neither knew the other. The private class is gone. The device *is* the
  compiler — `WgslModuleCompiler` over `GPUDevice.createShaderModule` — and the
  engine's stages and a bundle loaded from bytes go through the same library,
  the same pipeline record and the same refusals. `WebGpuStageProgram` and
  `WebGpuPipelineProgram` are gone with it; what a handle carries is
  `WebGpuShader` and `WebGpuPipeline`, in a file that imports no browser
  binding, so the vertex layout arithmetic and every refusal are asserted on
  the VM in a second.
* **A bind group layout names every stage that declared the binding**, which is
  the one line the shader library gives up by refusing to import a browser
  binding: it states two booleans per binding and `webgpu_types.dart` turns them
  into a `GPUShaderStage` word. That word was the constant `vertex` for a while,
  which is not a wrong picture and not an exception — the layout is legal, the
  pipeline built over it comes back marked invalid, and every pass that sets it
  draws nothing. Fifteen checks read black. `gpuShaderStageOf` is now a named
  function with `webgpu_types_test.dart` on it, asking the four cases directly
  and asking a whole stage pair's group shapes again, in a second and with no
  adapter. The first textured draw reads the browser's verdict *before* any
  texel, so a descriptor this backend gets wrong is reported in the browser's
  own words rather than as a colour that should have been red.
* **`loadShaders` loads.** It reads the bundle's fourth section, refuses by name
  where there is no section for this backend, where the section is not the
  document the codec reads, and where it says it is a shape this build does not
  know. A reload compiles every stage in use before it swaps any of them, so a
  bundle that dropped a stage still in use leaves the library drawing what it
  drew; a `ShaderHandle` already handed out keeps its identity, and a pipeline
  built before the reload keeps its own two modules until the renderer relinks.
* **The engine's thirty-nine stages compile when a name is asked for**, not when
  a device opens. A scene binds a handful of them, and the rest were a pause the
  frame paid for shaders it never drew with.
* **`createCubeRenderTarget` makes a cube.** It answered null on the grounds
  that a cube a probe can draw into is only useful beside a chain it can filter
  into — and the conformance suite disagreed, because `supportsCubeTextures`
  answering true is read as a promise that a pass can name a face. That was a
  gap wearing a refusal's clothes. `supportsRenderToMip` stays false and stays a
  real refusal, which is what keeps a reflection probe switched off rather than
  half-implemented.
* **The conformance suite runs against a live device, in Chrome.** Thirty-three
  checks, thirty-three passed: the same list the other three backends are held
  to, run the way the WebGL2 backend runs it — as a test rather than as an
  application, because Chrome has a real WebGPU device inside `flutter test`.
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
  `getCompilationInfo`. Asking for it found six of the engine's own stages this
  implementation refused, which is the first check in the repository that
  could have.
* **All thirty-nine stages compile here now**, and the test says so as an
  absence rather than a count. `Pbr`, `BlinnPhong`, `Lambert`, `Toon`,
  `Reflections` and `Ssao` called `textureSample` under a branch a quad need not
  take together — a light facing away, a cascade that misses, a ray off the
  frame, a degenerate tangent — which naga accepts and a browser does not. The
  GLSL now reads the single-level targets with `textureLod` at level zero and
  hoists the one sample whose mip chain is real above its branch; the three
  other backends draw the same pictures they drew before, byte for byte.
* **A platform view whose pin the device can empty.** The registry has no
  unregister and never will, so the factory closure holds a cell rather than the
  canvas; `dispose` nulls it, unconfigures the canvas context and destroys the
  device, which is a complete teardown the WebGL2 backend cannot reach.
* **No row is turned over on the way back.** WebGPU's framebuffer origin is the
  top left, so a readback kept in order is already what the contract promises —
  and a flip carried across from the backend that needs one gives a frame that
  reads back correctly and presents upside down.
* **A shader library over the sidecar, and a loadable one beside it.** A name
  is looked up, a module is compiled for it once and the handle keeps it. There
  is no link step in WebGPU, so the WebGL2 backend's second cache — programs by
  the pair of stages — has nothing to hold and is gone; what it knew is not.
  Its program cache was once keyed on `vertex+fragment` spelled out, and two
  layered libraries can both answer `Pbr`. Here the module is a field of the
  object a `ShaderHandle` carries, so there is no map from a word to a module
  for two libraries to collide in.
* **The three reflection procedures are one lookup.** WebGL asks the context
  for its attributes, its uniform blocks and its samplers once a program has
  linked; a `GPUShaderModule` answers none of that and cannot be made to. So a
  pipeline reads the same three things out of the bundle's fourth section, and
  the record it builds is the shape `WebGlProgram` is — attributes in location
  order, blocks by name, samplers by name — because the section is the file
  version of exactly that record.
* **A pipeline answers with a declared vertex layout as well as without one.**
  Five places in the engine hand a `VertexLayoutSpec` in, and a path built on
  reflection alone would leave every one of them broken. A layout names its
  attributes and WebGPU wants locations, so both forms resolve through the same
  table: without a layout the attributes are interleaved in location order, the
  way every draw in this engine packed a vertex before instancing; with one,
  each buffer keeps its stride and its step mode and each attribute takes its
  location from the section. A layout that leaves an input unfed is refused
  naming the input, because WebGPU refuses such a pipeline with a message about
  a shader location and nothing else.
* **The fourth section carries its own version, and the container does not
  move.** `ShaderBundle.formatVersion` is a fact about the header and the
  section table that three shipped backends read unchanged; the reflection's
  shape is an agreement between one packer and one backend and will move again.
  Raising the outer version to say the inner one changed would refuse every
  bundle in existence to Impeller, WebGL2 and the software rasteriser, none of
  which can see this section at all. A document that does not say which shape it
  is is read as the shape that shipped.
* **A reload compiles everything before it swaps anything.** A stage that no
  longer compiles, or that the new bundle dropped while it was in use, refuses
  the whole reload by name and leaves the library drawing what it drew — so an
  editor that rebuilt a bundle wrongly keeps its picture. A handle already
  handed out keeps its identity and gets new code behind it; a pipeline built
  before the reload keeps the modules it was built from until the renderer
  relinks, which is the old picture rather than a missing one. Nothing has to be
  retired to arrange that, where GL had to keep a program alive by hand.
* **A block or a sampler that two stages put in two places is refused.** One
  name has to mean one binding, because that is what `bindUniformBlock` and
  `bindTexture` take. Not hypothetical: `VertexTextureProbeVertex` binds
  `ProbeInfo` at group 0 and `ProbePrefilter` binds a block of that name at
  group 1, and the engine's own table is what the test pairs to prove it.
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
* Version 0.5.2 to match the three backends it joins, and `pub publish` is still
  not run for it: being in the publishing order and being published are
  different things. The condition it was set was that it could draw, and it
  draws. What it waits for now is the next release the other unpublished
  packages are waiting for, and a recorded reference set of its own — a backend
  whose pictures nothing compares is one whose regressions arrive as a report
  from whoever happened to look.
