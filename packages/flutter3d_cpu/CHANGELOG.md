## 0.4.2

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
