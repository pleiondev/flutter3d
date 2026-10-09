/// The crypt's fog: thicker on the floor than at the vault, as a still,
/// cold, damp room keeps its mist.
library;

import 'package:flutter3d/flutter3d.dart' show FogSettings, LinearColor;
import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;

/// The fog [level] is drawn with, standing where a player's eye stands
/// [eye] m over the floor they start on; none while [on] is false.
///
/// **As thick as the document says at the eye, thicker below it and
/// thinner above.** The level's density was tuned looking down corridors at
/// eye height, so it is kept there: [FogSettings.baseHeight] is the eye
/// over the floor the player starts on. Under it the mist thickens towards
/// the flags and over it thins into the vault, falling by e over [_depth] —
/// the height under which a fog is reported as shallow fog, ground fog that
/// lies in a layer, in the codes airfields report weather in ("MI",
/// shallow: less than 2 m above the ground — ICAO Annex 3, and WMO-No. 306,
/// code table 4678). A torch's room seen from the stair is then clearer at the
/// lintel than at the floor, and a room seen down into from a gallery reads
/// as a pool of mist.
FogSettings cryptFog(Level level, {required double eye, bool on = true}) =>
    FogSettings(
      color: LinearColor(level.fogColor.x, level.fogColor.y, level.fogColor.z),
      density: on ? level.fogDensity : 0.0,
      heightFalloff: 1.0 / _depth,
      baseHeight: _floorOf(level) + eye,
    );

/// A shallow fog's depth, m (ICAO Annex 3; WMO-No. 306).
const double _depth = 2.0;

/// The floor the player starts on: where the level spawns them, or the
/// origin's floor for a level that spawns nobody.
double _floorOf(Level level) {
  for (final e in level.entities) {
    if (e.type == 'player_spawn') return e.position.y;
  }
  return 0.0;
}
