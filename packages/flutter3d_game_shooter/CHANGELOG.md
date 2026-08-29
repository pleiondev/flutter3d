## 0.4.0

* The weapon holder sits at its rest position from construction rather than
  from the first simulation step, so the frame every start shows no longer
  draws the weapon at the origin, inside the camera. The light it is drawn
  under is the renderer's fix — the studio's own lights are uploaded now —
  and `weapon_view_light_test.dart` holds both.

## 0.3.0

* `ShooterPhases` names the points inside the step a game can hang its own
  rules off, and the simulation announces every one of them unconditionally — a
  phase that exists only on levels with doors is a phase nobody can rely on.

## 0.2.0

* The parts of a first-person shooter that are not parts of an engine: monsters
  with brains, weapons with recoil and spread, hitscan and projectiles, keys,
  doors and a way down.
* Extracted from the game layer, which is what made the engine's boundaries
  real rather than asserted.
