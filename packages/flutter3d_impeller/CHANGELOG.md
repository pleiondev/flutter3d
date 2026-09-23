## 0.8.0

**`bindTexture` returns false for a slot the stage does not declare**, which
flutter_gpu reports by throwing "Failed to bind texture". It was the one
uncaught throw behind every polyline from 0.7.0 to 0.7.2.

**A uniform member that overruns its block is refused by name**, as the web
backends refuse it. It used to land on the next member's bytes, or throw an
anonymous `RangeError`.

**`tool/stage_bindings.dart` writes `flutter3d_shaders`' `stageBindings`** off
impellerc's Metal reflection, and `stage_bindings_test.dart` holds the
committed table to a fresh compile. `impellercPath()` finds the compiler for
both.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Installed from pub.dev, it builds again.** 0.7.0's build hook looked for
`.dart_tool/package_config.json` above its own root, which for an installed
package is the pub cache, where there is none. Every `flutter test`, `flutter
run` and `flutter build` of a consuming project failed before its first test,
although the archive already carried the compiled bundle. The hook now keeps
the bundle that is there when the GLSL sources cannot be seen, and still
recompiles in a checkout that can see them.

**`build_shader_bundle` writes into this package, wherever it is run from.**
It used `Directory.current` as the package root, so run from a consuming
project it wrote the bundle into that project's `assets/`, where nothing loads
it. It now resolves this package through the package config.

**On Windows the compiler is `impellerc.exe`**, and the hook looks for that
name. It looked for `impellerc`, so the Windows desktop build could not make a
bundle.

**A region overwrite on a BGRA texture keeps red and blue where they were**, and
a half-float radiance cube with mips is no longer refused for a size check
that assumed four bytes a texel.

The compiled bundle in this archive is built from `flutter3d_shaders` 0.7.1.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

**Breaking.** `GpuRenderBackend.present` is gone with `GraphicsDevice.present`
itself (mcp-01n). `GpuFrameImage`, the widget it used to return, is unchanged
and now exported from this package's own barrel (`gpu_device.dart` re-exports
`gpu_frame_image.dart`).

**`ensureGpuBackendRegistered`, new.** This backend registers its own opener
and presenter with `flutter3d_hardware`'s device registry, rather than
waiting for `flutter3d_app` to know it exists — calling it once is now the
whole of what an assembly layer owes this package. Floors to
`flutter3d_hardware` `^0.7.0`.

**The shader bundle is built by a hook.** `hook/build.dart` compiles
`flutter3d_shaders`' manifest through `impellerc` into
`assets/shaders/flutter3d.shaderbundle` during `flutter run` and
`flutter build`, so an application draws a frame without anybody having run
`tool/build_shaders.sh` first. It calls `impellerc` from the Flutter SDK's
artifact cache directly and fails with a `BuildError` that says to run
`flutter precache` when the binary is not there. `flutter analyze` runs no
hooks and fails on the missing asset in a fresh checkout, so
`dart run flutter3d_impeller:build_shader_bundle` does the same compile from
a command line. Both go through `buildShaderBundle` in
`lib/src/shader_bundle_build.dart`. `hooks` `^2.0.0` and `flutter3d_shaders`
`^0.7.0` are dependencies now for this, the second so that a consumer's own
`pub get` puts the GLSL where the hook looks for it. The published archive
still carries a prebuilt bundle, and `tool/build_shaders.sh` is unchanged.

**`overwriteGeometry` and `overwriteTexture`.** Geometry goes through
`DeviceBuffer.overwrite`. flutter_gpu's `Texture` has no partial write, only a
whole mip level, so a region here is a readback of the base level, a patch in
memory and an overwrite of the whole level. This is the backend the method is
asynchronous for, and a caller patching small regions every frame pays for the
full level each time.

**`maxColorAttachments` answers 2 where `supportsRenderToMip` is true and 1
where it is not.** That is an inference. flutter_gpu publishes no MRT
capability and no backend name, and the probe that would settle it is the
call that ends the process on the OpenGL ES path. A pass that asks for more
than the answer throws `UnsupportedError` from `beginRenderPass` instead.

**The bundle holds the engine's ten new stages** and the changed `Composite`,
`BloomUpsample`, shadow and surface sources, compiled from `flutter3d_shaders`
0.7.0. No Dart in this package changed for them. One of those sources is a
fix that matters on this backend alone: `shadow_depth.frag` no longer
declares `FogInfo`, a block it never read, which on Vulkan collided with the
vertex stage's first binding and had a Galaxy A55 refuse the pipeline.

**The archive carries two skills** for a coding agent,
`skills/flutter3d-impeller-shader-bundle/` and
`skills/flutter3d-impeller-driver-crash/`, the second about a build that dies
on one device and not the others. `dart run skills@ get` installs them.

## 0.6.0

* **A floor, and no code.** The device, the encoder and the shader build are
  byte for byte 0.5.2's. What moved is the one line that names
  `flutter3d_hardware`, now `^0.6.0`: the bundle format and the section names
  this backend reads live in that package, and a floor is where a resolver is
  told which version of them this one was built against.
* The bundle it refuses and the bundle it accepts are unchanged; a
  `flutter3d.shaderbundle` built for 0.5.2 still loads.

## 0.5.2

* No Dart moved. This package ships `assets/shaders/flutter3d.shaderbundle`,
  built by impellerc from `flutter3d_shaders` GLSL, and 0.5.2 of those shaders
  added `lib/morph.glsl` and the morph block and sampler to four vertex stages
  — so this package's contents changed even though nothing here was edited.
* One thing worth recording for whoever meets it next: **impellerc aborts on
  `texelFetch` in a vertex stage**, with a SIGABRT and no diagnostic. Reading
  texel centres with `texture()` is the way past it, and it is why the shader
  is handed the texel size in a uniform instead of asking `textureSize`.

## 0.5.1

* **The shader bundle is rebuilt, and this release exists for that alone.**
  No API change and no line of Dart moved. This package ships
  `assets/shaders/flutter3d.shaderbundle`, which is `impellerc` output compiled
  from `flutter3d_shaders`' GLSL — so a change to that GLSL is a change to this
  package's contents even when nothing here is edited. `flutter3d_shaders`
  0.5.1 added `forward` to the `FogInfo` block and changed what the surface
  buffer's alpha means; an application on `flutter3d` 0.5.1 with this package at
  0.5.0 would have been binding a uniform member its compiled shaders did not
  declare, and reconstructing screen-space effects from a depth in the wrong
  units.
* **The gap is the interesting part, and it is a second version of a mistake
  this package has already made once.** 0.4.0 shipped *without* the bundle
  because the file is gitignored; 0.5.0 shipped *with* a bundle that no longer
  matched its sources. Both are the same failure — a compiled artefact whose
  freshness nothing checked at publish time — and `tool/structure.dart`'s
  *the compiled shader bundle is not older than its sources* rule only holds it
  inside this repository, where the file exists. What it cannot see is the copy
  already on pub.dev.

## 0.4.5

* **A uniform block missing a member the caller named now throws, and used to
  return.** The block case is unchanged and still answers false — a compiler
  drops a whole block nothing reads, which is ordinary. What changed is the
  member case: the offset came back null, this backend skipped the write, and
  the member's bytes stayed zero. Zero is a plausible value for nearly
  everything that goes through a uniform block, so the picture came out wrong
  with nothing logged, while the same bundle raised a named exception in a
  browser — the web backend has refused this all along. `ARCHITECTURE.md` §7.1
  said the refusal was the rule; only the HAL's own doc comment said otherwise,
  on the grounds that "the unlit model legitimately has no `light_direction`",
  which it has: `FragInfo` is declared once and included whole. Checked on a
  device: all 39 goldens draw and the conformance suite passes 23.
* **Anisotropic filtering, through the sampler it always built.**
  `SamplerOptions.anisotropy` is forwarded as flutter_gpu's `maxAnisotropy`
  and `maxAnisotropy` on the device is `gpuContext.maxSamplerAnisotropy` —
  sixteen on every Metal and Vulkan device this has met. Nothing clamps
  here, because flutter_gpu clamps inside its own bind and says so; the
  sampler cache keys on the field, so eight taps and one are two objects.
  `anisotropic-floor` joins the golden set.
* **A bundle loaded from bytes, and refused when its SDK is not this one.**
  `GpuRenderBackend.loadShaders` reparses `impellerc` output through
  `ShaderLibrary.fromBytes`, and `GpuLoadedShaderLibrary.refresh` through
  `reinitializeFromBytes`, so a handle already handed out wraps the stage that
  now carries the new code. The header's SDK token is held to `runningSdk` —
  the first token of `Platform.version` — before the section is looked at:
  the bundle format is tied to the Flutter version, and a stage compiled for
  another one draws something else rather than failing to parse. A mismatch,
  a missing `impeller` section and bytes flutter_gpu cannot parse are all
  `ShaderBundleRefused` naming the bundle. `impellerSectionOf` is the pure
  half, tested without a device.
* `tool/conformance.sh` also wants the example's own loadable bundle built,
  since the harness is the example and its pubspec now declares the asset.
* **A refresh is held to the header's stage list before flutter_gpu sees a
  byte.** A bundle that no longer names a stage already handed out is
  refused, naming it, rather than reparsed over a live handle — the contract
  `LoadedShaderLibrary.refresh` states. And `GpuLoadedShaderLibrary` keeps
  the SDK token its load was given, so a library loaded against one token is
  never refreshed against another.
* The editor's hot-reload loop — the packed engine bundle loaded over the
  engine's own asset, a stage edited, rebuilt and repacked — was exercised
  on this backend: the reloaded `Pbr` took the edit on the next frame, which
  is what `reinitializeFromBytes` marking every stage dirty buys even when
  the entry points collide with the asset bundle's.
* **`readback`, through a staging texture rather than a buffer.** flutter_gpu
  3.47 has `copyTextureToBuffer` and no way for Dart to read the
  `DeviceBuffer` it fills, so the copy goes texture to texture into a pooled
  staging texture — a command on a command buffer submitted in order, which is
  what makes the answer the frame before — and the bytes come off it through
  `asImage().toByteData()` in `submit`'s completion callback, once the queue
  says the copy ran. Nothing blocks; the pool grows to however many readbacks
  are in flight — one for the exposure meter, which waits for its answer
  before it asks again, and one for each pick asked in the same breath.
  Checked on the GPU by
  the two new conformance checks and by the `auto-exposure` golden, whose
  metered frame reproduced to the pixel.
* **A refused copy gives its staging texture back.** flutter_gpu throws rather
  than returns false when `copyTextureToTexture` or `submit` is refused
  outright, and the staging texture taken for that readback was never
  returned to the pool — GPU memory nothing can free, since flutter_gpu has
  no dispose, with `debugReadbackStagingCount` climbing by one per refusal as
  the only sign. Every path out of `read` now returns it.
* The bundle gains `Luminance` and `ObjectId`; `ObjectId` samples the
  material's texture against its cutoff, so a pick through a masked
  material's hole answers with what is behind it.
* **`GpuImageSurface` was measured, and not taken.** flutter_gpu 3.47's
  presentable surface does the job the renderer's ring of finished frames
  does by hand — keep a texture out of rotation while Flutter still reads
  it. `tool/surface_probe.sh` runs the probe: the same clear-only pass
  through that ring and through a surface, 240 frames each at 1280×800 with
  Flutter drawing every one, and prints what each costs. Same UI-thread cost
  and the same interval between frames, no copy on either path; then the
  surface holding five textures at four megabytes of short-lived allocation
  per frame and forty-seven with none at all, against the ring's two. Only
  those two rates were run, so the count a real frame would pay is a range
  rather than a number. The forty-seven is what shows the mechanism — a
  texture counts as reusable only once the collector has freed the native
  wrappers a frame makes — and the ring's two is the count of the variant
  that makes the surface's own promise, keeping the presented frame back a
  frame longer.
  The script is the only part that lives here; the probe itself is in the
  engine's example beside the entry point that runs it, since it reaches
  flutter_gpu directly and is no part of this backend's API. The numbers and
  the verdict are ARCHITECTURE §15.
* **The stencil passes through.** `setStencil` becomes `setStencilConfig`
  for both faces or one call per face, `setStencilReference` its own, and
  `DepthTarget`'s stencil load, store and clear reach the
  `DepthStencilAttachment`. `supportsStencil` answers from whether the
  context names a depth-stencil format at all. `stencil-xray` joins the
  golden set, and the conformance suite marks a stencil and reads it back
  through this backend.
* **A pass renders into a cube face and a mip level.** `ColorTarget.face`
  becomes the attachment's slice and `ColorTarget.mipLevel` its mip index,
  which flutter_gpu validates against the texture and refuses out loud;
  `createCubeRenderTarget` allocates a device-private cube with render-target
  usage and a chain, and `supportsRenderToMip` repeats
  `doesSupportFramebufferRenderMipmap` — true on Metal and Vulkan, false on
  the OpenGL ES path. The bundle gains `ProbePrefilter`; `probe-car` joins
  the golden set.
* **A blend state naming the blend constant is refused rather than drawn.**
  flutter_gpu's `RenderPass` has no blend-constant setter, so this backend
  answers false to `supportsBlendColor`; `setBlendColor` throws, and so does
  `setBlend` handed a state that reads the constant. It used to hand those
  four factors on and let Impeller multiply by its own transparent black,
  which lost the term with no error anywhere.

## 0.4.4

* The bundle gains `MeshLightmappedVertex` and every lit stage binds a
  lightmap; `lightmapped-room` joins the golden set.
* **Block-compressed textures upload, and the device is asked first.**
  `createTextureFromPixels` stops requesting render-target usage for a
  compressed format, which flutter_gpu refuses before the allocation, and
  `supportsTextureFormat` repeats flutter_gpu's own per-family answer — BC on
  a desktop GPU, ETC2 and ASTC on a mobile one, all three on Apple silicon.
  The conformance suite now draws a BC1 and an ETC2 block through this
  backend and reads the colour back, which had never been done.

## 0.4.3

* The pubspec declares its platforms instead of leaving them to pub.dev's
  detector: every native platform — Android, iOS, macOS, Windows, Linux —
  and deliberately not the web, which is what `flutter3d_webgl` exists for.

## 0.4.2

* **The package actually ships its shaders this time.** 0.4.1 claimed this
  fix and repeated the failure: its `.pubignore` replaced only the package
  directory's gitignore, while `*.shaderbundle` is excluded by the repository
  ROOT's — which still applied from above. The explicit `!*.shaderbundle`
  negation is the whole difference, and this release was checked by reading
  the dry-run's file list before uploading, which is the step 0.4.1 skipped.

## 0.4.1

* **The package ships its shaders.** 0.4.0 declared
  `assets/shaders/flutter3d.shaderbundle` and did not contain it: the bundle
  is generated and gitignored, and pub packages by the gitignore — so every
  hosted consumer failed at build with "No file or variants found for asset".
  A `.pubignore` now decides what the archive carries, and the bundle rides
  along, built fresh at publish. Found the first time anything resolved this
  backend from pub.dev alone.

## 0.4.0

* **`present` owns its image.** It returns `GpuFrameImage`, a widget that
  creates the `ui.Image` in its state, disposes the previous one when the
  frame changes and the last one in `dispose` — which ends the one undisposed
  image per presented frame. `readPixels` disposes its image too.
* **A workaround for flutter_gpu's `HostBuffer`**, whose overflow branch
  appends a block per boundary crossing and never reuses the tail, so a frame
  writing over a megabyte of transients parked a megabyte for ever.
  `BlockCursor` counts crossings and `beginFrame` recreates a slot's buffer at
  32, at the reset point whose own comment is the safety argument; the clause
  names the upstream file and dies with the SDK upgrade.
* Texture creation validates pixel sizes before allocating rather than after.

## 0.3.0

* `tool/conformance.sh` runs the conformance suite against a live GPU and
  returns an exit code. Until it existed, the only thing checking this backend
  was somebody remembering to look at a list.

## 0.2.0

* A host buffer ring sized by the frames in flight, because submission is
  asynchronous and resetting a bump allocator the GPU is still reading flickers
  rather than crashes.
* The build script prints the compiled binding table, so the engine's
  hand-written permutation metadata cannot drift from what the compiler kept.

## 0.1.0

* `flutter3d_hardware` over `flutter_gpu`: the backend a desktop build draws
  through, and the only place in the stack that names a graphics API.
* A shader bundle built from `flutter3d_shaders` by `tool/build_shaders.sh`.

* **Anisotropic filtering, through the sampler it always built.**
  `SamplerOptions.anisotropy` is forwarded as flutter_gpu's `maxAnisotropy`
  and `maxAnisotropy` on the device is `gpuContext.maxSamplerAnisotropy` —
  sixteen on every Metal and Vulkan device this has met. Nothing clamps
  here, because flutter_gpu clamps inside its own bind and says so; the
  sampler cache keys on the field, so eight taps and one are two objects.
  `anisotropic-floor` joins the golden set.
* **A bundle loaded from bytes, and refused when its SDK is not this one.**
  `GpuRenderBackend.loadShaders` reparses `impellerc` output through
  `ShaderLibrary.fromBytes`, and `GpuLoadedShaderLibrary.refresh` through
  `reinitializeFromBytes`, so a handle already handed out wraps the stage that
  now carries the new code. The header's SDK token is held to `runningSdk` —
  the first token of `Platform.version` — before the section is looked at:
  the bundle format is tied to the Flutter version, and a stage compiled for
  another one draws something else rather than failing to parse. A mismatch,
  a missing `impeller` section and bytes flutter_gpu cannot parse are all
  `ShaderBundleRefused` naming the bundle. `impellerSectionOf` is the pure
  half, tested without a device.
* `tool/conformance.sh` also wants the example's own loadable bundle built,
  since the harness is the example and its pubspec now declares the asset.
* **A refresh is held to the header's stage list before flutter_gpu sees a
  byte.** A bundle that no longer names a stage already handed out is
  refused, naming it, rather than reparsed over a live handle — the contract
  `LoadedShaderLibrary.refresh` states. And `GpuLoadedShaderLibrary` keeps
  the SDK token its load was given, so a library loaded against one token is
  never refreshed against another.
* The editor's hot-reload loop — the packed engine bundle loaded over the
  engine's own asset, a stage edited, rebuilt and repacked — was exercised
  on this backend: the reloaded `Pbr` took the edit on the next frame, which
  is what `reinitializeFromBytes` marking every stage dirty buys even when
  the entry points collide with the asset bundle's.
* **`readback`, through a staging texture rather than a buffer.** flutter_gpu
  3.47 has `copyTextureToBuffer` and no way for Dart to read the
  `DeviceBuffer` it fills, so the copy goes texture to texture into a pooled
  staging texture — a command on a command buffer submitted in order, which is
  what makes the answer the frame before — and the bytes come off it through
  `asImage().toByteData()` in `submit`'s completion callback, once the queue
  says the copy ran. Nothing blocks; the pool grows to however many readbacks
  are in flight — one for the exposure meter, which waits for its answer
  before it asks again, and one for each pick asked in the same breath.
  Checked on the GPU by
  the two new conformance checks and by the `auto-exposure` golden, whose
  metered frame reproduced to the pixel.
* **A refused copy gives its staging texture back.** flutter_gpu throws rather
  than returns false when `copyTextureToTexture` or `submit` is refused
  outright, and the staging texture taken for that readback was never
  returned to the pool — GPU memory nothing can free, since flutter_gpu has
  no dispose, with `debugReadbackStagingCount` climbing by one per refusal as
  the only sign. Every path out of `read` now returns it.
* The bundle gains `Luminance` and `ObjectId`; `ObjectId` samples the
  material's texture against its cutoff, so a pick through a masked
  material's hole answers with what is behind it.
* **`GpuImageSurface` was measured, and not taken.** flutter_gpu 3.47's
  presentable surface does the job the renderer's ring of finished frames
  does by hand — keep a texture out of rotation while Flutter still reads
  it. `tool/surface_probe.sh` runs the probe: the same clear-only pass
  through that ring and through a surface, 240 frames each at 1280×800 with
  Flutter drawing every one, and prints what each costs. Same UI-thread cost
  and the same interval between frames, no copy on either path; then the
  surface holding five textures at four megabytes of short-lived allocation
  per frame and forty-seven with none at all, against the ring's two. Only
  those two rates were run, so the count a real frame would pay is a range
  rather than a number. The forty-seven is what shows the mechanism — a
  texture counts as reusable only once the collector has freed the native
  wrappers a frame makes — and the ring's two is the count of the variant
  that makes the surface's own promise, keeping the presented frame back a
  frame longer.
  The script is the only part that lives here; the probe itself is in the
  engine's example beside the entry point that runs it, since it reaches
  flutter_gpu directly and is no part of this backend's API. The numbers and
  the verdict are ARCHITECTURE §15.
* **The stencil passes through.** `setStencil` becomes `setStencilConfig`
  for both faces or one call per face, `setStencilReference` its own, and
  `DepthTarget`'s stencil load, store and clear reach the
  `DepthStencilAttachment`. `supportsStencil` answers from whether the
  context names a depth-stencil format at all. `stencil-xray` joins the
  golden set, and the conformance suite marks a stencil and reads it back
  through this backend.
* **A pass renders into a cube face and a mip level.** `ColorTarget.face`
  becomes the attachment's slice and `ColorTarget.mipLevel` its mip index,
  which flutter_gpu validates against the texture and refuses out loud;
  `createCubeRenderTarget` allocates a device-private cube with render-target
  usage and a chain, and `supportsRenderToMip` repeats
  `doesSupportFramebufferRenderMipmap` — true on Metal and Vulkan, false on
  the OpenGL ES path. The bundle gains `ProbePrefilter`; `probe-car` joins
  the golden set.

## 0.4.4

* The bundle gains `MeshLightmappedVertex` and every lit stage binds a
  lightmap; `lightmapped-room` joins the golden set.
* **Block-compressed textures upload, and the device is asked first.**
  `createTextureFromPixels` stops requesting render-target usage for a
  compressed format, which flutter_gpu refuses before the allocation, and
  `supportsTextureFormat` repeats flutter_gpu's own per-family answer — BC on
  a desktop GPU, ETC2 and ASTC on a mobile one, all three on Apple silicon.
  The conformance suite now draws a BC1 and an ETC2 block through this
  backend and reads the colour back, which had never been done.

## 0.4.3

* The pubspec declares its platforms instead of leaving them to pub.dev's
  detector: every native platform — Android, iOS, macOS, Windows, Linux —
  and deliberately not the web, which is what `flutter3d_webgl` exists for.

## 0.4.2

* **The package actually ships its shaders this time.** 0.4.1 claimed this
  fix and repeated the failure: its `.pubignore` replaced only the package
  directory's gitignore, while `*.shaderbundle` is excluded by the repository
  ROOT's — which still applied from above. The explicit `!*.shaderbundle`
  negation is the whole difference, and this release was checked by reading
  the dry-run's file list before uploading, which is the step 0.4.1 skipped.

## 0.4.1

* **The package ships its shaders.** 0.4.0 declared
  `assets/shaders/flutter3d.shaderbundle` and did not contain it: the bundle
  is generated and gitignored, and pub packages by the gitignore — so every
  hosted consumer failed at build with "No file or variants found for asset".
  A `.pubignore` now decides what the archive carries, and the bundle rides
  along, built fresh at publish. Found the first time anything resolved this
  backend from pub.dev alone.

## 0.4.0

* **`present` owns its image.** It returns `GpuFrameImage`, a widget that
  creates the `ui.Image` in its state, disposes the previous one when the
  frame changes and the last one in `dispose` — which ends the one undisposed
  image per presented frame. `readPixels` disposes its image too.
* **A workaround for flutter_gpu's `HostBuffer`**, whose overflow branch
  appends a block per boundary crossing and never reuses the tail, so a frame
  writing over a megabyte of transients parked a megabyte for ever.
  `BlockCursor` counts crossings and `beginFrame` recreates a slot's buffer at
  32, at the reset point whose own comment is the safety argument; the clause
  names the upstream file and dies with the SDK upgrade.
* Texture creation validates pixel sizes before allocating rather than after.

## 0.3.0

* `tool/conformance.sh` runs the conformance suite against a live GPU and
  returns an exit code. Until it existed, the only thing checking this backend
  was somebody remembering to look at a list.

## 0.2.0

* A host buffer ring sized by the frames in flight, because submission is
  asynchronous and resetting a bump allocator the GPU is still reading flickers
  rather than crashes.
* The build script prints the compiled binding table, so the engine's
  hand-written permutation metadata cannot drift from what the compiler kept.

## 0.1.0

* `flutter3d_hardware` over `flutter_gpu`: the backend a desktop build draws
  through, and the only place in the stack that names a graphics API.
* A shader bundle built from `flutter3d_shaders` by `tool/build_shaders.sh`.
