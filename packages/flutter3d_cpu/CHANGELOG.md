## 0.4.2

* **`maxAnisotropy` is one, and means it.** This rasteriser picks one level
  per triangle and takes one tap, so a sampler asking for eight is honoured
  on the hardware backends and ignored here — and the device says so rather
  than promising taps it does not take. `anisotropic-floor` is recorded in
  this backend's own set without them, and the cross-backend budget for the
  scene is the measured size of that difference, which is the one place the
  two sets are allowed to disagree on purpose.
* **A bundle loaded from bytes answers with the Dart this backend has.**
  `CpuDevice.loadShaders` compiles nothing — there is nothing here to compile
  — so `CpuLoadedShaderLibrary` answers each name the bundle claims with the
  device's own stage under that name, and refuses a bundle naming a stage it
  has no Dart for, naming the stages. An application's own look reaches this
  backend the way it always has, as a Dart stage handed to `CpuDevice.shaders`;
  the bundle that names it on the hardware backends then loads here too.
  `CpuShaderLibrary` caches its handles so their identity survives a refresh.
* **A refresh that drops a stage in use is refused, naming it.**
  `CpuLoadedShaderLibrary` remembers every name it answered with a handle,
  and a bundle that no longer names one of them is refused before it is
  taken — the contract `LoadedShaderLibrary.refresh` now states, kept the
  same way on every backend. Only a name that was handed out counts: a
  stage the bundle claimed and nobody asked for may come and go.
* **`readback`, at once.** Nothing here is in flight — the pass that wrote the
  floats ran to the end before `submit` returned — so the region is converted
  on the spot and the future is complete when it is handed back, which is the
  honest answer and what lets the engine's own tests of the callers run in a
  plain `flutter test`: a dark room climbing to the ceiling, two boxes picked
  apart.
* `Luminance` and `ObjectId` transcribed from the GLSL; `auto-exposure` joins
  the golden set at 0.581% from Impeller.
* **Alpha masking, transcribed.** `ReadSurface`'s discard under the cutoff
  had been left out on the grounds that no fixture exercised it; the picking
  stage needed the same hole, and an id pass that discards where the scene
  pass does not would pick what the eye cannot see. `readSurface` now answers
  null for a masked fragment under its cutoff and every lit model hands the
  null on, `ObjectId` samples the texture against `IdInfo.mask` the way the
  GLSL does, and the test is a red fence with a hole in front of a white box:
  the pick through the hole says box, and so does the pixel.
* **A stencil buffer, a byte per pixel beside the depth.** Every one of the
  eight operations, both masks, the reference and a state per face, tested
  before the depth test and applied after the fragment stage — so a discard
  writes nothing, as it does on hardware — with a fixture per rule in
  `stencil_test.dart`. Nothing is asked per fragment while the test is off,
  so the thirty-four scenes that never mention it draw as they did.
* **The blend equation, factor by factor.** Two states were recognised by
  testing two of their factors, and `BlendState.keepDestination` — zero and
  one — read as one and one. Every factor is a line now; the four that need
  a blend constant throw, because the interface has no way to set one.
* `XrayShader`, the transcription of `xray.frag`: the albedo and not one word
  about the surface, so `FragmentContext.surface` is left null and the encoder
  writes nothing to attachment one.
* `stencil-xray` joins the golden set.

## 0.4.1

* The lightmapped vertex stage and the lightmap term in the four lit models,
  transcribed from the GLSL; the mesh varyings grow by the coordinate.
* **A compressed format is refused by name, and asked about first.**
  `createTextureFromPixels` used to read block bytes as RGBA8 and hand back
  a texture full of noise; it throws naming the format now, and
  `supportsTextureFormat` says no to every block-compressed value before a
  loader gets that far, because this backend samples raw texels and always
  will.

## 0.4.0

* **`CpuFrame` disposes its images.** It had no `dispose` at all — one leaked
  `ui.Image` per presented frame — and two in-flight decodes could finish out
  of order. The previous image is disposed when a new one lands, the fresh one
  when the widget is already gone, and a sequence number keeps a stale frame
  from overwriting a newer one.

## 0.3.0

* The composite pass mirrors the grading, vignette, grain and dispersion the
  hardware backends apply, so the two reference sets stay comparable.
* Cube texture uploads validate each mip level's size rather than accepting
  anything that fits.

## 0.2.0

* `flutter3d_hardware` rasterised in Dart with no GPU under it: what the golden
  images are drawn with, and what a test renders a whole frame through.
* Deliberately shares nothing with either hardware backend — no driver, no
  shading language, no command buffer — which is what makes agreeing with them
  mean something.
