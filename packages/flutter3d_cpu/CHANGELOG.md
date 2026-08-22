## 0.1.0

* `flutter3d_graphics` rasterised in Dart, with no GPU under it: what the golden
  images are drawn with, and what a test can render a whole frame through.
* Deliberately shares nothing with either hardware backend — no driver, no
  shading language, no command buffer — which is what makes agreeing with them
  mean something.
