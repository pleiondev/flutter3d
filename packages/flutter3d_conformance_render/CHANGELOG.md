## 1.0.0-rc.1

- **New: the render checks, as a package of their own.**
  `runPluginRenderConformance` and `checkPluginRender` draw a plugin's
  points in the frame on a backend, named by `PluginRenderPoints`: its
  nodes run and stop with it, its lit model draws with every block and
  texture of its slot table reaching the stage, its light type lights a
  box on its own, its decal stage paints, its velocity reader runs after
  the camera velocity, and its shadow producers run. A device that draws
  no picture is held to the structure and the rest is declined. They were
  `package:flutter3d_conformance/plugin_render.dart` before this release
  was published; they need the renderer, `flutter3d_core`, and
  `flutter3d_conformance`, which every backend takes as a dev dependency,
  no longer does.
