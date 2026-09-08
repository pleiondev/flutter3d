## 0.6.0

* **A floor, and no code.** The runner, the coins, the hazards and the
  checkpoints are byte for byte 0.5.2's. `flutter3d_game` is required at
  `^0.6.0`, and the floor is still the only place the chain can be said: the
  runner switches on `CollisionHeightfield`, which arrives here through two
  re-exports, and nothing else can state which version underneath has it.

## 0.5.2

* **The runner stands on ground made of samples.** `CollisionHeightfield`
  joined the sealed hierarchy of collision shapes, and a sealed hierarchy is
  what made the compiler name every switch that had to think about it — the
  runner's included — rather than letting one fall through to a default and
  answer wrongly for ever. It answers with the standing half-height, the same
  as it does for a box.
* Needs `flutter3d_game` 0.5.1 or above, which is where that shape reaches this
  package from. A floor rather than a note: the type arrives through a
  re-export, so nothing else can say which version underneath has it.

## 0.5.1

* The runner's facing, its movement wish and the swinging blocks call
  `Portable` rather than `dart:math`, so a run replays identically in a browser
  and on the VM. See `flutter3d_sim` 0.5.1 for what that is and why. No API
  change; a saved run from 0.5.0 replays a hair differently in its last bits.

## 0.5.0

**Breaking.** Fifteen per-step fields become events, and the genre ships its
readouts.

* **The simulation's five channels and the runner's ten are gone.** Two of them
  were bools that could carry one of a thing: two enemies stomped in a step
  made one sound, and a level whose checkpoints differ could not say which had
  just been passed. What replaces them is `PlatformerSimulation.events`, which
  the runner writes into as well — so a landing and the block that gave way
  under it arrive one after the other rather than as two flags on two objects.
* **`Runner.poundedThisStep` survives, and says why**: the simulation reads it
  later in the same step to shatter the block underfoot. That is wiring; what a
  game should read is `Landed.pounded`.
* **The game's walk over every mechanism, once a frame, is gone.** Springs,
  crumbling platforms and breakable blocks are reported by the simulation on
  the pass it already makes.
* **`PurseReadout` and `LivesStrip`.** The purse draws what is in it rather
  than a fixed list of kinds, and a run with no life limit draws nothing at
  all.
* **`Difficulty` is read in `Runner.applyDamage`**, the one door damage reaches
  the runner through.
* **Slopes, gliding and water.** A ramp is quicker down than up — by scaling
  the speed asked for rather than adding a push, because the controller's own
  friction eats any push a walkable slope could justify. A held jump turns a
  fall into a drift, after the apex, so the two meanings of that button do not
  fight. Water is a volume rather than a surface, with its tuning on the pool
  so a stream and a tar pit are two different pools.
* **Points, power-ups and a camera that looks up the road.** Collectibles gain
  a worth separate from how many they are; a chain of them is worth more and
  breaks on a death. The follow camera leads by a third of a second of travel,
  horizontally only.

## 0.4.1

* **`Hunter`**, an enemy that comes after the player across the gaps: it
  follows the level's flow field and jumps where the field says the next
  step is a jump, on a grid baked with the enemies' `JumpReach`. `kind:
  hunter` in a level's `enemy` entity, with `sight` and `patience`; it
  needs no route.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* A second genre, and the instrument that tested the first: a runner who jumps
  twice and dashes, coins, hazards, moving platforms, gates and a summit.
* Acceptance was "no edit to the engine" and it took five, all in input, each
  of which generalised the engine rather than accommodating a game.
