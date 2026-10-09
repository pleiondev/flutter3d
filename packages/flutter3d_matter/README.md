# flutter3d_matter

What a flutter3d world and the things in it are made of, with nothing that
moves them.

- **`WorldProperties`**: a world's gravity, its air (temperature, pressure,
  the density derived from them), its wind and the medium things move
  through. One value, held by the world and read by everything in it: the
  rigid bodies, the characters, the cloth, the particles, the audio's
  Doppler shift. Immutable; a level's `world` block lays its own fields over
  a game's with `WorldProperties.fromJson(json, base: game)`.
- **`standard_world.dart`**: the values a world nobody configured starts
  with (`standardGravity`, `standardAtmosphere`, `standardAirTemperature`,
  `standardAirDensity`, `standardSpeedOfSound`), written once, and the laws
  that derive the air (`airDensityAt`, `speedOfSoundAt`).
- **`PhysicalMaterial`**: one substance, by groups (mechanical, fluid,
  thermal, acoustic, optical, electrical), each citing where its numbers
  come from. `MaterialPair` is a measurement of two of them together.
- **`MaterialCatalog`**: the materials an engine knows, by a namespaced id:
  `f3d.<name>` for the engine's own (`Materials`), `<pluginId>.<name>` for
  a plugin's, which it adds through `host.registry<MaterialCatalog>()`.
- **`physical_constants.dart`**: the constants of nature the engine uses,
  the same in every world.

The step rate is not here: how often a world is stepped is the loop's,
`WorldTiming` in `flutter3d_sim`.

```dart
import 'package:flutter3d_matter/flutter3d_matter.dart';

final moon = WorldProperties.standard.copyWith(
  gravity: Vector3(0.0, -1.62, 0.0),
  airPressure: 1e-3,
);
final seawater = MaterialCatalog.builtIn().require('f3d.seawater');
```

`docs/CONTRACTS.md` in the repository gives the unit of every number here.
Until 1.0.0-rc.1 all of it was in `flutter3d_physics`, which still
re-exports it.
