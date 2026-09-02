## 0.4.5

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
