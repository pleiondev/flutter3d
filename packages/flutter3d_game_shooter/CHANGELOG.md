## 0.7.0

* **Breaking. The readouts are in `bridge.dart`.** `HealthBar`, `AmmoReadout`,
  `KeyPips` and `ReadoutStyle` are widgets, and the simulation's barrel names
  no Flutter now; import `package:flutter3d_game_shooter/bridge.dart` for them.
  `WeaponView` was there already. `doc/boundary-0.7.0.md` has the same move for
  the platformer and racing.
* **Breaking. `flutter3d_game` is no longer a dependency.** The simulation
  imports `flutter3d_sim` by name rather than through `flutter3d_game`, which
  stopped re-exporting it. A game that reached `flutter3d_game` or a simulation
  type through this package's pubspec alone names them in its own.
* **`sample.dart` gains `Staged`, `stage()` and `agentStartingInventory()`.**
  Promoted from `flutter3d_sim_mcp`'s own `staging.dart` — a fourth copy of
  `apps/flutter3d_demo_dungeon`'s composition, kept there only because
  `tool/structure.dart`'s "no package depends on an application" rule meant
  that package could not reach the original. It already depended on this one
  for the genre itself, so the composition moves to where it can be named
  once instead of copied. Deliberately smaller than the app's own `stage()` —
  no mechanisms, no breaches, no automap — for the reason that copy's own doc
  comment already gave.
* **`package:flutter3d_game_shooter/staging.dart`: the shipped game's assembly,
  and the game as a `HeadlessGame`.** The full `stage(level, world, input:,
  registry:, inventory:)` moved here from
  `apps/flutter3d_demo_dungeon/lib/src/staging.dart`, with the automap and the
  breaches the copy above leaves out, and `startingInventory()` is what a
  player starts a level holding. `ShooterHeadlessGame` implements
  `flutter3d_sim`'s `HeadlessGame` over the sample roster: its `name` is
  `shooter`, its one button is `fire`, and `start` answers a `HeadlessRun` a
  tool can step and read. `ShooterHeadlessGame(extra:)` takes entity kinds this
  package cannot know, which is how a level with a `widget_surface` entity in
  it loads headless. This library and `sample.dart` both declare a `Staged` and
  a `stage`, so a file that imports the two hides one pair.
* **A spawned monster carries the name its level gave it.**
  `Bestiary.spawn(name:)` passes an entity's `name` to the `Actor`, which is
  what `ActorSystem.byName` and `remapEntitySave` in `flutter3d_sim` 0.7.0 read.
* The monsters, the weapons, the inventory and the step order are otherwise
  0.6.0's. The floors on `flutter3d`, `flutter3d_physics` and `flutter3d_sim`
  are `^0.7.0`.

## 0.6.0

* **Floors, and no code.** The monsters, the weapons, the inventory and the step
  order are byte for byte 0.5.1's. The four lines that changed are the floors on
  `flutter3d`, `flutter3d_game`, `flutter3d_physics` and `flutter3d_sim`, all
  `^0.6.0` — the versions this genre was built and tested against in the one
  resolve the workspace performs.

## 0.5.1

* The player's aim, the shotgun's spread, a wave's ring of spawn points and the
  melee cone call `Portable` rather than `dart:math`, so a run replays
  identically in a browser and on the VM. See `flutter3d_sim` 0.5.1 for what
  that is and why. No API change; a saved run from 0.5.0 replays a hair
  differently in its last bits.

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
* **A second trigger.** `WeaponDef.alternate` is a whole `WeaponDef`, so an
  alternate fire is described exactly as a weapon is. One cooldown, shared,
  because it is one weapon in one pair of hands; `canFireAlternate` is a second
  getter rather than `canFire` gaining a parameter, because turning a published
  getter into a method is a change every caller has to make.
* **Magazines and reloading.** Null by default, so a weapon without one is
  untouched by any of it. Per weapon rather than per arsenal — the first
  version shared one count, so a rifle would have been full because the pistol
  was. A weapon starts full, a reload never conjures rounds nobody carries, and
  the weapon stays selectable while it runs.
* **`PatrolBrain` and `Spawner`.** A crypt whose monsters all stand still until
  seen reads as a museum; a room that can fill after the player is in it was
  entirely unavailable. `ChaseBrain` is `base` so a game can build on it the
  way `PatrolBrain` does.

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
