---
name: flutter3d-game-shooter-arsenal-and-step
description: Use when building or extending a first-person shooter on flutter3d — weapons and monsters as data, the step order, and the line between this package and the engine below.
---

# Vocabulary lives here, machinery lives below

`flutter3d_game` knows what a body, a brain, a mechanism and a step are, and not
what any of them are for. `Inventory`, `Gift`, `Arsenal`, `Monsters` and
`GameSimulation` answer that machinery with content.

Start a shooter by depending on this package rather than copying out of it:

| | |
|---|---|
| `GameSimulation` | the step order: aim, fire, projectiles, blasts, actors, pickups, mechanisms |
| `Arsenal`, `WeaponDef`, `WeaponBehaviour` | hitscan, projectile and blast as data rather than three classes |
| `Bestiary`, `MonsterDef`, `ChaseBrain` | what a monster does when it sees you, hears you, and is hurt |
| `Inventory`, `Gift`, `Pickup` | what is carried, given, and refused because you are full |
| `Player` | an eye, a body, and what it is holding |

`lib/sample.dart` is this repository's own roster, to read and to replace.

## Weapons and monsters are data

Add a weapon as a `WeaponDef` with a `WeaponBehaviour`, not as a class. Three
behaviours cover a shooter: hitscan (a ray resolved this step), projectile (a
body that travels and can be outrun), blast (a radius that asks every
`Damageable` it reaches). A fourth kind of gun is nearly always a fourth set of
numbers.

Same for monsters: a `MonsterDef` names the numbers, `ChaseBrain` is the state
machine, the `Bestiary` is what a level's `MonsterKind` validates against. A
monster needing a different mind gets its own `Brain`; one needing different
reach gets different numbers.

## Step order

`GameSimulation` owns it, and the phases are named in `step_phases.dart` rather
than left implicit in one long method. Aim before firing, so a shot uses this
step's aim. Projectiles and blasts before actors, so a monster killed this step
does not also act. Pickups after actors, mechanisms last, and `publish()` at the
very end — a button pressed with the use key runs after mechanisms have stepped.

Pass one `GameRandom` to the simulation, the actor system and `Hitscan`, or two
loads of the same save agree until the first flinch roll.

## Nothing here draws

No import reaches the renderer, and a test holds that line — `WeaponView` draws,
which is why it is in `bridge.dart` and outside the barrel. The bugs a shooter
actually has are invisible in a picture: a shot that misses at a low frame rate,
a pickup taken twice in one step, a door that will not move because somebody is
riding it.

## Two things easy to leave out

`HitZones` decides what a shot is worth by where it lands — two zones and no
more, because a head worth aiming for and legs worth not aiming for is what a
player can feel at this range, and six would be five nobody can tell apart. The
measurement (`Actor.fractionUp`) is the engine's; what the fractions mean is
here.

`Secret` is a trigger and a flag, found once and never again. Walking back
through is not another secret.

Still missing on purpose: monsters chase the player and never each other, and
nothing here keeps a score.
