## 0.4.5

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
