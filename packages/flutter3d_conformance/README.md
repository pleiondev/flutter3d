# flutter3d_conformance

What `flutter3d_hardware` requires of a backend, as a suite the backend runs
against itself.

```dart
void main() => runConformance(device);
```

An interface can only say that a call exists. This says that a clear covers the
whole attachment, that uploaded pixels keep their row order, that the HDR format
the backend names is really renderable, and that every stage pair the engine
links does link.

The last check catches real mistakes regularly. A varying that a fragment stage reads and no
vertex stage writes is a hard error in a browser, and invisible on a backend
whose pipelines were linked ahead of time. The check catches on one backend a
mistake that would ship on another.

## Plugins

A plugin runs the other half of the package, `package:flutter3d_conformance/plugins.dart`,
from its own test suite:

```dart fragment
import 'package:flutter3d_conformance/plugins.dart';

// `WindPlugin` and `world` are the plugin's and the application's own.
void main() => runPluginConformance(
  WindPlugin.new,
  harness: PluginHarness(
    setUp: (loop) => loop
      ..snapshots.add(world.snapshotPart)
      ..addSystem('world', LoopPhase.physics, world.step),
  ),
);
```

The world the plugin acts on is the loop's: `setUp` puts the application's
state in `loop.world` or adds a `SnapshotPart` for it, and the checks
capture, restore and digest it through `EngineLoop.snapshots`, the same path
a rollback and a replay take.

The 8 plugin checks:

- **plugin.manifest**: the id is well formed, the API version installs, every
  permission is one the engine knows, a budget reads, the manifest survives
  being written out and read back, and the plugin installs. A view plugin
  that adds a step system is refused here.
- **plugin.switch**: switched off at a step boundary, the loop is exactly what it is
  without the plugin, and switched back on, exactly what it was with it. Both
  switches are journalled at their steps.
- **plugin.names**: every phase, system and event the plugin adds to the loop is in
  its namespace, `<namespace>.<name>`.
- **plugin.determinism**: every step is run twice from one state, and the first
  system whose two answers differ is named with its plugin. Two fresh runs
  must also publish the same events and leave the same world.
- **plugin.backends**: the plugin installs and steps on every backend its manifest
  names, and is switched off with a reason on one it does not.
- **plugin.budget**: no step publishes more events than `budget.eventsPerStep`, and
  the median cost of a step with the plugin, less without it, stays within
  `budget.stepMicroseconds`. Timing is measured on the machine running the
  suite, so it takes the median of seven batches and allows the declared
  budget and nothing more.
- **plugin.materials**: every physical material the plugin adds to the engine's
  `MaterialCatalog` is under its own id (`<namespace>.<name>`), names a
  `source` for each property group, gives a liquid's or a gas's density and
  viscosity, and keeps every number in SI within what anything real has, so a
  density in g/cm³ or a temperature in °C is caught. Each pair it measures
  has one of its own in it and a source, and all of it is gone when the
  plugin is switched off. A plugin that brings none passes.
- **plugin.render**: installed on the software backend with the harness's
  registries, whether the plugin places nodes in the frame. One that does
  names `render.nodes` in its outcome's `requires`, and the render checks of
  `flutter3d_conformance_render` on `cpu` are then part of its badge.

`checkPluginConformance` returns the same outcomes as a list, for a tool that
reports rather than fails.

### The badge

**flutter3d conformant**: `checkPluginConformance` passes every check on every
declared backend, with a world given to determinism and a budget declared and
kept, on the plugin API version in its manifest. `earnsBadge(outcomes)`
answers it. A declined check (no world, no budget, assertions off) is
reported as skipped, never as passed, and keeps the badge away. A plugin
that draws earns it only with the render checks it requires passed on
`cpu`, and keeps it only while no render check it ran failed on any
backend.

`runPluginConformance` writes what it found to `<package>.conformance.json`
beside your pubspec once its checks have run: the `f3d.conformance` report,
with the badge `earnsBadge` gave, `conformant@1.0` or none. That file is the
badge's one record. `flutter3d_build`'s `plugin.report` reads it, and so does
the plugin catalogue, so publish it with the package. In the pubspec, say
which suite it passed:

```yaml
flutter3d_plugins:
  conformance: conformant@1.0
```

```markdown
![flutter3d conformant](https://img.shields.io/badge/flutter3d-conformant-2ea44f)
```

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
implementation of a 3D engine for Flutter. It is not a fork or a binding of
another engine, and it is not affiliated with Google or the Flutter project. It has four
switchable rendering backends: Impeller via Flutter GPU, WebGL2, WebGPU and a
software rasteriser. It loads glTF, OBJ and `.f3d`, and has six lighting models,
shadows, bloom, skinning, animation, BVH culling and picking, plus a
deterministic fixed-step game layer with collision, navigation, positional
audio, and gamepad and touch input. Four example games (shooter, platformer,
racing, strategy) are each built on a genre package:
[`flutter3d_game_shooter`](https://pub.dev/packages/flutter3d_game_shooter),
[`flutter3d_game_platformer`](https://pub.dev/packages/flutter3d_game_platformer),
[`flutter3d_game_racing`](https://pub.dev/packages/flutter3d_game_racing),
[`flutter3d_game_strategy`](https://pub.dev/packages/flutter3d_game_strategy).
A new game starts from the editor's scaffold, which writes one from a template:
<https://flutter3d.pleion.dev/first-project/>. Documentation:
<https://flutter3d.pleion.dev>.
