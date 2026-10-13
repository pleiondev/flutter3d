# flutter3d_conformance_render

What a plugin adds to the frame, drawn on a backend and checked: the render
half of flutter3d's conformance suite.

```dart fragment
import 'package:flutter3d_conformance_render/flutter3d_conformance_render.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';

// `HairPlugin`, `hairShaders` and `hairModel` are the plugin's own.

void main() => runPluginRenderConformance(
  HairPlugin.new,
  backend: 'cpu',
  device: () => CpuDevice(width: 32, height: 32, shaders: hairShaders()),
  points: PluginRenderPoints(litModel: hairModel),
);
```

A plugin names the points it reaches in `PluginRenderPoints`, and each one
is drawn through the renderer on the device the suite is given:

- **render.nodes**: every node the plugin places runs in a frame, and none
  once the plugin is switched off.
- **render.lit model**: a box drawn through the plugin's lit model is a
  picture of its own, and every block and texture of its slot table reaches
  the stage.
- **render.light type**: a box lit by the plugin's light type alone is lit.
- **render.decal**: the decal pass runs with the plugin's stage and paints
  the floor.
- **render.velocity**: the node reading the velocity runs after the camera
  velocity, with neither of the engine's readers on.
- **render.shadows**: each producer the technique hands the frame is run.

A device that draws no picture, a recording fake, is held to the structure,
and the checks that compare pictures are declined with the reason.

**Why it is not part of `flutter3d_conformance`.** That package is the
contract every backend runs against itself as a dev dependency, and the
plugin suite of the loop. Neither needs the renderer, and these checks do,
so they live here and a backend's tests do not pull the engine in.
