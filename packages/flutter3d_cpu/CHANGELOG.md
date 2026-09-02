## 0.4.2

* **A bundle loaded from bytes answers with the Dart this backend has.**
  `CpuDevice.loadShaders` compiles nothing — there is nothing here to compile
  — so `CpuLoadedShaderLibrary` answers each name the bundle claims with the
  device's own stage under that name, and refuses a bundle naming a stage it
  has no Dart for, naming the stages. An application's own look reaches this
  backend the way it always has, as a Dart stage handed to `CpuDevice.shaders`;
  the bundle that names it on the hardware backends then loads here too.
  `CpuShaderLibrary` caches its handles so their identity survives a refresh.

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
