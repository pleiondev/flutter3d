## 0.5.0

**Breaking.** Three closed types open, four per-step fields go, and the genre
ships its readouts.

* **`AmmoType`, `MonsterState` and `WeaponBehaviour` are open.** A game written
  on this template can say its weapon fires cells, that its monster is fleeing,
  and that its shot is a beam that charges. Both enums lose `values`: a list of
  everything that exists cannot be kept once anybody can add to it, and it was
  the wrong question — `Arsenal.carrying` answers what a HUD wanted, and both
  restores read the names the file holds, which is what lets a game's own
  ammunition survive a round trip.
* **`firedThisStep`, `usedThisStep`, `damageTakenThisStep`, `foundThisStep` and
  `hits` are gone.** What a game gets is `GameSimulation.events`, which carries
  two of anything and says what order it was in: a shotgun's eight pellets are
  eight `ShotLanded` rather than a list read beside a flag.
* **`ChaseBrain` says what it does with a state it does not know: nothing.** It
  leaves the monster where the game's own code put it, because a brain that
  guessed would fight the game for control of its monster.
* **Readouts, not a HUD.** `HealthBar`, `AmmoReadout` and `KeyPips` take the
  genre's own types, because pulling the numbers out is where every game got
  the same three details wrong — the fists printing `0`, armour drawn as a
  second bar, a key ring showing a key that had been used.
* **`Difficulty` is read in two places**: what the player deals, which
  multiplies with berserk rather than losing to it, and what the player takes,
  in the one method every source arrives at.

## 0.4.1

* **The sensor.** A power-up that shows what walks behind the walls, as
  silhouettes, for as long as it lasts: `PowerUpGift('sensor')` in the
  sample gifts and `Inventory.hasSensor` beside the other two, which is the
  one power-up the renderer reads rather than the simulation. A gift rather
  than a setting so that seeing through a wall is a thing a level hands out
  and takes back.
* **The sample vocabulary speaks `reflection_probe`.** `sampleRegistry`
  includes `ReflectionProbeKind`, so a level of this game may place a probe
  per room and a key or a barrel in it reflects the torch-lit walls around
  it rather than a sky a crypt does not have.

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
