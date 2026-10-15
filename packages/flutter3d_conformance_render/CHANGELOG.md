## 1.0.0-rc.1+1

- **Breaking: the render checks are named like tools.**
  `render.lit model`, `render.lit model defaults` and `render.light type`
  are `render.litModel`, `render.litModelDefaults` and `render.lightType`;
  the other four keep their names. A check name is data: the `check` field
  of a conformance report, an entry of a suite, the word a test runner's
  name is matched by. A space in it was the one thing in the engine's names
  a reader had to quote, and after 1.0 a rename would break every report
  reader. A structure rule holds every check name to the words of
  `ToolName.pattern`, and every render check to `render.<word>`.

## 1.0.0-rc.1

- **`render.lit model defaults`** (new, 7 checks): a box drawn through a
  plugin's lit model by a material that sets nothing is the box drawn with
  every member at its declared default and every texture of its own white.
- **The render checks run on a GPU backend.** `device:` is a
  `RenderCheckDevice`, which may open with an `await` as WebGPU does, and
  `materials:` (a `RenderCheckMaterials`) hands the renderer the plugin's
  stages loaded from its bundle on that device, consulted before the
  device's own.
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
