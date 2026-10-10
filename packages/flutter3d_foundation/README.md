# flutter3d_foundation

The values every flutter3d package speaks, in the one package all of them
can depend on. It depends on `vector_math` and nothing else.

- **`Flutter3dException`** is the root of everything the engine throws, with
  its four families: `Flutter3dFormatException` (bytes that are not what
  they claim), `CapabilityException` (a device or platform that does not do
  what was asked), `PluginException` (a plugin that will not install) and
  `ResourceException` (a file, tool or service that is not there).
- **`WorldPosition`** is a place in the world in double precision, and
  **`LinearColor`** the engine's one colour type. `toVector3Relative`,
  `toWorldPosition`, `toLinearColor`, `toVector3` and `toVector4` cross into
  `vector_math`'s float32 vectors, naming the origin a position is narrowed
  against.
- **`FormatSpec`** and **`FormatDocument`** are the envelope every JSON file
  the engine writes starts with (`{"format": …, "version": …, "requires":
  …, "generator": …}`), the chain of migrations that lifts an older one, and
  the rule that unknown keys are kept. `DocumentFormatException` is what the
  envelope refuses with.
- **`Issue`** and **`IssueSink`** are how a library reports what it could
  not do, and **`Registration`** is what every registry hands back.
- **`Portable`** is `sin`, `cos`, `atan2`, `exp`, `pow` and the rest,
  computed from operations IEEE 754 pins, so a fixed step gives the same
  bits on every platform.

`docs/CONTRACTS.md` in the repository gives the units all of these are in.

## Where these came from

Until 1.0.0-rc.1 the exceptions, the positions, the colour, the envelope
and `Registration` were in `flutter3d_plugin_api`, and the crossings and
`Portable` in `flutter3d_physics`. `flutter3d_plugin_api` still re-exports
what it had, so a plugin sees no change. A package that used the plugin API
only for these (the hardware layer, the backends, the shaders) depends on
this package instead.

```dart
import 'package:flutter3d_foundation/flutter3d_foundation.dart';

final spawn = const WorldPosition(12000.0, 1.8, -4500.0);
final local = spawn.toVector3Relative(cameraPosition); // float32, near zero
```
