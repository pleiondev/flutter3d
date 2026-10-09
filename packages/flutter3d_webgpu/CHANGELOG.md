## 1.0.0-rc.1

- **Breaking: `engineShaders` is `webGpuEngineShaders`.** `flutter3d_webgl`
  had the same name for its own table, so an application that opens WebGPU
  and falls back to WebGL could not import both libraries.
- **Depends on `flutter3d_foundation` instead of the plugin API**, for the
  exceptions its refusals extend.

- **`createPipelineAsync` and `createComputePipelineAsync` are real.** A
  compute pipeline is built whole through `createComputePipelineAsync`, and
  a refusal completes the future with the error. A render pipeline is a
  stage pair until a draw says the rest (targets, blend, depth, stencil),
  so `createPipelineAsync` records the pair and **warms** it: it is built
  through `createRenderPipelineAsync` in each of the last
  `WebGpuDevice.warmStateLimit` draw states the device has built a
  pipeline in, into the cache a draw looks in. A draw in a state nobody
  drew before still builds synchronously.
- **`releaseSampler` drops the `GPUSampler`** made for a description, with
  the bind groups that hold it; `ShaderHandle.dispose` lets a module go.
- **Breaking: a WebGPU section that will not read throws
  `BundleSectionFormatException`** (from `flutter3d_shaders`), where
  `decodeWebGpuSection` threw the SDK's `FormatException`; the device still
  answers a `ShaderBundleException` naming the bundle.

- **Breaking: one way to open the backend.** `openWebGpu` is gone:
  `WebGpuDevice.open` takes the engine's stages by default, completes with a
  `WebGpuDevice` rather than a nullable one, and throws a
  `DeviceUnavailableException` where there is no WebGPU.
- **Breaking: the reflection classes are this backend's own.**
  `WebGpuStage`, `WebGpuBlock`, `WebGpuBlockMember`, `WebGpuSampler`,
  `WebGpuAttribute` and `encodeWebGpuSection` are no longer exported; a
  bundle's stages are still read with `decodeWebGpuSection` as a
  `WebGpuSectionStages`.
- **Breaking: the device follows the HAL** — `readPixels` is `readback`,
  `createTextureWithDescriptor` is `createTexture`, the creators throw where
  they answered null, and `readBufferSync`, which only ever refused, is gone.
- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `RenderTargetSpec` is `RenderTargetDescriptor`, `VertexLayoutSpec`
  is `VertexLayoutDescriptor`. Every settings class is `final` with a
  `const` constructor and a `copyWith` over every field; a nullable field
  is reset with `copyWith(clearX: true)`. `dart fix` carries the renames.
- **Breaking: public constants are lowerCamelCase, without the k prefix,
  as Effective Dart asks.** `kTwoDimensional` is `twoDimensional`. The
  values are the same; `dart fix` carries the renames.
- **Breaking: `WebGpuDevice.create` is `open`, and
  `createTextureFromEncodedImage` is `decodeTexture`**: a device is opened,
  bytes are decoded, and `create` is the synchronous verb.
- **Breaking: WebGPU is not in the API.** The JavaScript bindings (`GPU*`),
  the translation tables (`gpu*`), the pipeline cache, the encoders and
  `WebGpuDevice`'s browser-typed members are not exported. An application
  needs `openWebGpu`, `WebGpuDevice` and `WebGpuFramePresenter`.
- **Debug groups, labels and device loss reach the browser.** Encoders push
  and pop the browser's debug groups, `setLabel` names textures, buffers,
  query sets and compute pipelines, and `WebGpuDevice.lost` reports the
  device's `lost` promise.

- **Breaking:** `GpuDeviceError` is `GpuDeviceException`, with the same
  constructor and members, extending `ResourceException` from
  `flutter3d_plugin_api`. A browser refusing a call is not a programmer's
  mistake. `dart fix` renames it (`webgpu-GpuDeviceError`).
- **`webGpuFullscreenUvLocation()`**, where the engine's full-screen stages
  read `v_uv`, for a full-screen stage in the material language written at
  run time.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **Depth is `depth32float-stencil8` where the adapter grants it — `A2.8`**,
  and the device then reports `DeviceFeature.reversedDepth`.
  `depth24plus-stencil8` may be stored either way, and the browser does not
  say which. The engine's table is regenerated: the opaque variants, the
  depth pre-draw, the shadow map's storage mode and the sky's depth.

- **A material loaded while the game runs draws here.**
  `webGpuMaterialHost()` hands `flutter3d_plugin_runtime`'s `RuntimeShaders`
  the engine's compiled `Unlit` stage with its reflection, and a plugin's
  material without a `light` block is spliced into it as WGSL — no
  compiler in the browser. A test hands the result to naga.

- **The WebGPU section reads every version up to its own.** A section with
  no version is version 1, and only a newer one is refused. That refusal is
  marked `stale`, and the build rebuilds the bundle when the section's
  version moves.

- **Breaking: `WgslModuleCompiler` can no longer be implemented outside their
  own library: it is an `abstract base mixin class` now, so a game or a test
  mixes it in (`with`) and its class is `final` or `base`. A member added to
  it in a 1.x release arrives with a body, which an `implements` could not
  have taken without breaking somebody.

- **Breaking: `engine_compute_shaders.dart` is no longer a public library.**
  Only the device reads `engineComputeShaders`, so the generated table lives
  under `lib/src/`; `engine_shaders.dart` stays public, because
  `WebGpuDevice.open` takes its stages.

- **This device answers the capability contract as one set.** `features`,
  `limits` and `textureFormatSupport` are decided from what the adapter
  granted, `webgpuDeviceFeatures` and `webgpuTextureFormatSupport` state the
  rules on the VM, and the `supportsX` getters are answered from them through
  `DeviceCapabilityForwarders`, each with the answer it gave before. The
  device now requests every optional feature it can report when the adapter
  offers it: unclipped depth, indirect first instance, dual-source and
  float32 blending, `rg11b10ufloat` targets, `f16`, subgroups, clip distances
  and multi-draw-indirect, beside the five it already asked for.

- **The rest of the GPU, on the API that defined most of it.** Textures of
  every shape through `createTextureWithDescriptor`, `writeTexture` at any
  level, layer and row stride, general buffers with mapping both ways,
  transfer passes (buffer and texture copies, `clearBuffer`, explicit
  resolves), occlusion and timestamp query sets, render bundles, indexed,
  non-indexed, indirect and multi draws, depth bias, write masks, depth clamp,
  min/max and dual-source blending, comparison samplers and level clamps, and
  compute passes that bind buffer ranges, textures, storage textures and
  laid-out uniform bytes and dispatch indirectly. The depth bias, write masks
  and unclipped depth are part of the pipeline signature, since WebGPU bakes
  them into the pipeline.

- **What WebGPU does not have is refused by name.** Border colours, ASTC HDR,
  pipeline statistics and synchronous readback are absent from the API;
  storage in vertex and fragment stages waits on the section's reflection
  carrying storage bindings. Each throws `UnsupportedCapability` before it
  looks at the handle it was given, and the pre-1.0 refusals — the blend
  constant, `PolygonMode.line` — are now that same type.

- **The section format grew two things, and old sections read unchanged.**
  `WebGpuTextureDimension` has `1d`, `2d-array`, `3d` and `cube-array`, and a
  sampler may be a comparison one, written only when it is. A compute stage
  can declare sampled and storage textures; the generator does not write any
  yet, so the engine's own stages answer false for them.

- A compute pass destroys the uniform buffers it made once it is submitted,
  rather than keeping one per bind for the life of the device.

- **Splat clouds are sorted on this device's compute — `H11`.** The
  compute table carries `SplatSortCount`, `SplatSortScan` and
  `SplatSortScatter`, and a storage buffer asked to be bindable as indices
  is made with `INDEX` in its usage. `splat_sort_gpu_test.dart` holds the
  order to the CPU's for a hundred thousand splats and the picture to the
  byte; the splat references did not move.

- **A stage loaded from a bundle says what it declares.**
  `WebGpuStage.declared` is the section's own blocks and samplers, which on
  this backend are the pipeline's layout, and a loaded library hands it to
  the renderer as the handle's `kept`. Without it the renderer asked the
  lighting model what to bind, and a lit material that declares a map it
  never reads had the draw refused.

- The shader table regenerated for `OutlineMask` and `HighContrast`, and
  `high-contrast` in the reference set.
- The shader table regenerated for the caustic stages.
- The shader table regenerated for the painted, unclamped transmittance.
- The shader table regenerated for `ShadowTransmittance` and the coloured
  sun shadow (`ShadowSettings.translucentCasters`).

- **Alpha to coverage**: a pipeline's `alphaToCoverageEnabled`, part of its
  signature, set only where the pass multisamples.

- **The generated tables carry the orthographic camera's paths**, and
  `orthographic-metal` is in the WebGPU reference set.

- **The generated tables carry the debug views**, and `debug-view-split`
  is in the WebGPU reference set.

- **`LensFlare` translated, and the composite's distortion**, through
  glslang and naga; both lens scenes match Impeller's to the pixel.

- **SMAA 1x's three stages translated**, through glslang and naga like every
  other stage; `smaa-teapot` is in the WebGPU reference set and matches
  Impeller's to the pixel.

**The generated tables carry the decal stage** of `flutter3d_shaders`,
through glslang and naga like every other stage.

**The generated tables carry `PlanarReflection` and
`RenderTextureEncode`**, through glslang and naga like every other stage,
and the `planar-mirror` and `render-texture` goldens are in this set, both 0
of 172800 pixels from Impeller.

**The generated tables carry `SkyPhysical`, `SkyPhysicalVertex` and the
height fog in `ApplyFog`**, through glslang and naga like every other stage.

**`prepareStage`, the WGSL compile and the section writer moved to
`flutter3d_shaders`** for the reason that package's changelog gives. The
tools and tests here import them from `package:flutter3d_shaders/compile.dart`,
and `flutter3d_webgl` is no longer a dev dependency: it was here only for
`resolveIncludes`.

- **Images are decoded by the browser, with mips drawn on the GPU.**
  `WebGpuDevice` is an `EncodedImageUpload`: `createImageBitmap` decodes and
  scales to the cap, `copyExternalImageToTexture` fills level zero, and a
  small render pass draws each level from the one above. The interop gains
  `GPUQueue.copyExternalImageToTexture` and its two descriptors.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.2+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2` and `vector_math` 2.4.3, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.8.2

**The generated tables carry the PCSS receiver-plane bias** of
`flutter3d_shaders` 0.8.2, through glslang and naga like every other stage.

It asks for `^0.8.2` of `flutter3d_shaders`, `flutter3d_cpu`,
`flutter3d_core` and `flutter3d_webgl`.

## 0.8.1

**The generated tables carry the contact shadow resolve stage**, through
glslang and naga like every other, and the sun's normal offset held to a
texel of its cascade. Twelve golden scenes move a shadow edge by about a
pixel; WebGPU still draws them as WebGL does.

It asks for `^0.8.1` of `flutter3d_core`, `flutter3d_shaders`,
`flutter3d_cpu`, `flutter3d_conformance` and `flutter3d_webgl`.

## 0.8.0

**A declared slot left unbound is named.** The bind group still fills it with
a zeroed block or a white texel, because WebGPU refuses an incomplete group,
but now says which slot in `debugDrainErrors`; it used to fill it in silence
and drew cleanly through a missing bind Metal failed on. `bindTexture` returns
false for a sampler the stage does not declare.

**Compute runs here.** `supportsCompute` is true: storage buffers, compute
pipelines with a bind group layout per group the stage names, compute passes
encoded as they go, and `readBuffer` through a mappable staging buffer.
Compute stages come from their own manifest, `flutter3d.compute.json` in
`flutter3d_shaders`, through the same glslang and naga, into a new generated
library, `engine_compute_shaders.dart`, which CI holds fresh. `PrefixSum`, a
scan of 1024 integers in one workgroup, is the first stage and the one the
conformance suite runs. `H6`

**The GPU says how long each labelled pass took.** Where the adapter grants
`timestamp-query` the device asks for it, `supportsGpuTimestamps` is true, and
each labelled pass writes two timestamps. The next `beginFrame` resolves them
and hands `GpuFrameTimings` to the `onGpuTimings` listener once the GPU has
written them, a frame or two late. Up to 64 passes a frame are timed and the
rest are drawn untimed. A pass that drew nothing and reported a negative time
is left out of the report. `H2`

**A frame can be presented brighter than white.** On a display the browser
reports as `(dynamic-range: high)`, `hdrOutputFormats` answers `rgba16float`,
and `copyToCanvas` reconfigures the canvas to the frame's format with
extended tone mapping, and back to standard for an 8-bit frame. Nothing
changes until a frame is rendered with `OutputTransform.extendedSrgb`, which
is off by default.

**`supportsFloat32Filtering` answers what the adapter granted**: the device
already asked for `float32-filterable`, and the EVSM shadow filter now asks
the device before it runs. `supportsIndependentBlend` is true, since every
colour target of a WebGPU pipeline has always carried its own equation.

**Tile memory means something here too.** Where the browser's
`GPUTextureUsage` lists `TRANSIENT_ATTACHMENT`, a single-level
`deviceTransient` target is allocated with it, and every pass that attaches
one clears it and discards it, the only operations WebGPU allows. On an older
browser the target is the plain attachment it was. `H7`

**A pass loads or clears depth as the descriptor says, and always stores
it**, so a later pass can test against it. Outside a transient attachment
there is no tile memory for a discard to save, and a stored depth buffer is
one a debugger can look at.

**The WGSL table is rebuilt against `flutter3d_shaders` 0.8.0 and holds 78
stages, up from 49**, every one still through glslang and naga. The new ones
are the velocity, temporal, layered-material, impostor, fog, shadow-filter,
transparency, scene-copy, occlusion, probe, exposure, six-way particle,
unsorted splat and field stages that `flutter3d_core` 0.8.0 draws with.
Upgrade this package with it. Each stage now carries what its compiled
function kept and its block layouts into `ShaderHandle.kept` and
`ShaderHandle.layouts`.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.4

**The generated WGSL table is rebuilt against `flutter3d_shaders` 0.7.4**,
which `flutter3d_core` 0.7.4 binds: `BloomInfo.tint` and `ShaftInfo.sun` are
uniforms only these stages declare, and all forty-nine stages still pass
glslang and naga. Nothing else in this package changed. It asks for
`flutter3d_shaders` ^0.7.4.

## 0.7.1

**Pipelines are cached on the compiled modules, not on stage names**, so a hot
reload takes effect and an application's `Pbr` no longer collides with the
engine's. A BGRA readback returns RGBA as the contract says, releasing a
texture drops its cached bind groups, and a cube mip chain that is too long is
refused when it is made.

The shader table is regenerated from `flutter3d_shaders` 0.7.1.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

**Breaking.** `WebGpuDevice.present` is gone with `GraphicsDevice.present`
itself (mcp-01n), split into two public methods a presenter builds from:
`copyToCanvas` and `applyCanvasStyle`. The canvas itself stays private — this
package depends on neither `package:web` nor anything else that would hand an
element to a caller outside its own file — so, unlike `flutter3d_webgl`,
`applyCanvasStyle` carries the CSS-mapping switch rather than a presenter
widget doing it externally. The new `WebGpuFramePresenter` widget calls both;
`presentFrame` in `flutter3d_app` builds one. Floors to `flutter3d_hardware`
`^0.7.0` and `flutter3d_conformance` `^0.7.0`.

**The canvas takes the size of the frame it is handed.** A surface renders at
its layout size times the device pixel ratio, and the canvas was made once, at
whatever `openDevice` was given. A texture-to-texture copy cannot scale, so on
a display with a ratio above one 0.6.0 presented the frame's top-left corner
and CSS stretched it over the element: a magnified crop whose centre sat below
and to the right of the middle of the screen. `copyToCanvas` resizes the
canvas to the frame when the two differ, compared before assigning because
writing either dimension resets the drawing buffer, and the scaling is left to
`objectFit`. The reference pictures could not have caught it. They compare
rendered textures, and this was the step after.

**`overwriteGeometry` and `overwriteTexture`.** `queue.writeBuffer` and
`queue.writeTexture`, both complete in the same turn. The byte layout of an
RGBA8 region is computed directly. Nothing about it is a compressed block, so
the helper the compressed upload path uses does not apply.

**`maxColorAttachments` answers 4**, a constant, and a pass that asks for more
throws `UnsupportedError` from `beginRenderPass`.

**The generated WGSL table is rebuilt against `flutter3d_shaders` 0.7.0.**
`engine_shaders.dart` gains `Fxaa`, `SsaoBlur`, `ContactShadow`, `LightShafts`,
`DepthOfField`, `ViewportShade`, `ShadowDepthMasked`, `ShadowDistanceMasked`,
`Splat` and `PolylineVertex`, and the regenerated `Composite`, `BloomUpsample`,
shadow and surface stages. `engine_shaders_test.dart` now holds the table to
`kRequiredShaders` instead of to counts written as literals, which had gone
stale the first time a pass was added.

**The archive carries a skill**, `skills/flutter3d-webgpu-two-barrels/`, about
which of the two libraries to import, the shader toolchain flags and what the
device declines. `dart run skills@ get` installs it for a coding agent.

## 0.6.0

**The first release, and it takes the set's number rather than a first number of
its own.** This package has been in the publishing order since before it had a
device; what it was waiting for was a frame it could draw and a recorded
reference set to be held to, and it now has both. It goes out with the engine it
implements, at the version that engine declares, because a backend resolved
against a different `flutter3d_hardware` than the renderer above it is the one
mistake a floor exists to prevent. Everything below is what it is, not what
changed.

**What the fourth backend became, in one paragraph, because the entries below
are the road and this is the destination.** It opens a real WebGPU device,
records passes through it, and hands Flutter a frame; all thirty-nine of the
engine's stages compile, from the generated table and from a bundle handed over
as bytes alike; and `flutter3d_conformance` answers **33 of 33** against a live
adapter in Chrome — the same list the other three backends are held to, run as an
ordinary test file rather than as an application somebody watches, because Chrome
has a WebGPU device inside `flutter test` and that is the one arrangement
Impeller cannot have. Two of the thirty-three pass by *declining*, and each
decline is a capability this device says false to by name rather than a method
that quietly does nothing: **the blend constant** (WebGPU has `"constant"` and
`"one-minus-constant"` and no colour/alpha split to form `BlendFactor.blendAlpha`
with) and **wireframe** (no polygon fill mode in the API at all). What separates
those two from a gap is only that they are declared, which this package learned
by getting it wrong once: `createCubeRenderTarget` returned null while
`supportsCubeTextures` said true, and the suite failed it instead of declining
it.

**The compression families are asked for, and the asking is the whole of it.**
`supportsTextureFormat` answered false for every block-compressed layout because
`create` requested none of the three features — an honest sentence about this
device's request rather than about WebGPU. The adapter is now asked which of
`texture-compression-bc`, `-etc2` and `-astc` it carries and exactly those are
requested, because `requestDevice` handed a feature the adapter lacks **rejects
the promise** instead of answering with a lesser device: a constant list of wants
is a game that does not start on the first machine missing one. The capability
answers from `gpuDevice.features` — what was granted — rather than from the list
of wants, since a device may be given less than it asked for. Uploading a level
is block arithmetic and not texel arithmetic: `writeTexture`'s `bytesPerRow` is a
row of *blocks* and `rowsPerImage` counts block rows, so an 8x8 BC1 level is two
rows of sixteen bytes and a level narrower than a block is one whole block. The
conformance check `a compressed format it supports samples its colour back`
stops declining itself and draws a block of each family the adapter carries.
Three formats stay false on every adapter there will ever be — `a8UNormInt`,
which WebGPU dropped for `r8unorm` plus a swizzle, and the two HDR ASTC layouts,
which no feature exposes — and a compressed *render target* is refused by name,
because a spelling is not permission to draw into one.

**A float target reads back as a picture, and looking for the check that would
have said so found there is none.** `readPixels` answered null for anything but
the two eight-bit RGBA layouts, while the contract names that method as *the* way
to read a float target: `readback` refuses a float format above every backend and
its message says to come here. WebGPU has no format-converting readback —
`copyTextureToBuffer` hands over the bytes as stored, where `glReadPixels`
converts — so the float target is drawn into an eight-bit one by a full-screen
`textureLoad` pass and the copy is made from that, at the price of a pass and an
allocation per call. The finding beside it: **nothing in `flutter3d_conformance`
asks any backend to read a float target back.** Every readback in that suite is
`r8g8b8a8UNormInt` and the only check naming a float format asserts the refusal
of `readback`. It is not added there, because such a check would fail on WebGL2
today, where `readPixels(RGBA, UNSIGNED_BYTE)` of an RGBA16F attachment is an
`INVALID_OPERATION` that leaves a pack buffer of zeros and a future completing
successfully with a black picture. The promise is witnessed in
`test/webgpu_draw_test.dart` instead, and that hole is stated rather than
silently inherited. Multisampled and `deviceTransient` targets stay null and the
refusal is shared: `readbackRegionOf` states it for every backend, and here a
multisampled target has no `TEXTURE_BINDING` either, so the conversion pass could
not sample one.

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
