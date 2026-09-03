## 0.4.5

* **`readback`, through a staging texture rather than a buffer.** flutter_gpu
  3.47 has `copyTextureToBuffer` and no way for Dart to read the
  `DeviceBuffer` it fills, so the copy goes texture to texture into a pooled
  staging texture — a command on a command buffer submitted in order, which is
  what makes the answer the frame before — and the bytes come off it through
  `asImage().toByteData()` in `submit`'s completion callback, once the queue
  says the copy ran. Nothing blocks; the pool grows to however many readbacks
  are in flight, two for a meter that asks every frame. Checked on the GPU by
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
