/// What a level is seen through: the sky over it and the fog in it.
///
/// **The physical sky (`P5`), lit from where the level's own sun is.** A
/// level document names one directional light, and the sky is the air's
/// scattering of a sun standing the other way along it: so the sky is the
/// colour the light falling on the stones says it should be, at whatever
/// hour a level is lit for, without a colour typed for either. The stars are
/// the air's too: `PhysicalSky` brings them out as the sun goes down, and a
/// level whose sun has set shows them without asking. Every level shipped
/// now is lit by a sun 58° up, which puts out every star; a night level is
/// a level document with its sun under the horizon.
///
/// **The fog the level names, lying low.** Its colour and density are the
/// document's; it thins upwards by the engine's `FogSettings` default, half
/// every fourteen metres from the ground, so what a level raises — the
/// spire's top, the ascent's last stair — stands out of the haze the pits
/// are full of.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// The sky over [level]: the default air, with the sun where the level's
/// directional light comes from, or straight overhead for a level with
/// none.
SkySettings levelSky(Level level) {
  final sun = level.lights
      .where((light) => light.type == LevelLightType.directional)
      .firstOrNull;
  return SkySettings(
    enabled: true,
    physical: const PhysicalSky(),
    directionToSun: sun == null
        ? Vector3(0.0, 1.0, 0.0)
        : (-sun.direction).normalized(),
  );
}

/// The fog in [level]: the colour and density the document gives it,
/// thinning upwards by [FogSettings.defaultHeightFalloff] from height
/// nought, where the levels' walkways are.
///
/// **The document's colour, not the sky's.** Daylight haze is the sky's
/// light scattered back, and coloured so the Cisterns at their 0.006 per
/// metre — 650 m of visibility by Koschmieder's 3.912/σ — went milk white
/// end to end. But a level's fog is the air of that place, which its author
/// chose: the Cisterns' damp teal, the Foundry's smoke. Those are kept.
FogSettings levelFog(Level level) => FogSettings(
  color: level.fogColor.toLinearColor(),
  density: level.fogDensity,
  heightFalloff: FogSettings.defaultHeightFalloff,
);
