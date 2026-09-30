# A Gauntlet-like co-op dungeon crawler — plan

Date: 2026-09-30. Branch `river-0.8.3`. A plan for a top-down, up-to-four-player
dungeon crawler in the shape of Atari's 1985 arcade game, built on what the
engine already has. The working title is open; like River Sortie, the game
gets a name of its own rather than the original's.

## What the game needs

- One to four heroes on one screen, each on a controller, each a class with
  its own speed, armour, shot and magic.
- Health that drains by itself every second; food restores it.
- Mazes full of monsters: a hundred to two hundred alive at once, poured out
  by generators until a generator is destroyed.
- Keys that open doors, potions that clear the screen, treasure for score, an
  exit to the next level.
- Death, which drains health and cannot be killed by shots; a thief who takes
  an item and runs.
- A shared camera that keeps everyone in frame and does not let a hero walk
  off the edge.
- An announcer's voice ("the warrior needs food").

## Current state — what the plan rests on

Facts read in the tree (paths under `packages/`):

- **Monsters and their minds exist.** `flutter3d_sim/lib/src/actors/`
  (`ActorSystem`, `Brain`, damage, death, saves) and
  `flutter3d_game_shooter/lib/src/chase_brain.dart` (sees, hesitates, comes,
  hits), `patrol.dart`, `monsters.dart`, `bestiary.dart`.
- **Navigation for a crowd exists, for one goal.**
  `flutter3d_sim/lib/src/nav/flow_field.dart` sweeps Dijkstra once from the
  goal and every agent reads its direction as an array lookup; one field per
  body class (`Navigation.fieldFor`). `FlowField.update(Vector3 goal)` takes a
  single goal.
- **Everything targets one focus, by design.** `actor_system.dart` §"Nothing
  targets anything but the focus": one `focus` the caller names each step,
  which is also what makes one flow field enough. `Brain.focus` reads it.
- **The shooter's simulation has one player.** `flutter3d_game_shooter/lib/src/simulation.dart:155`
  (`final Player player`).
- **Arriving monsters exist, in finite waves.** `spawner.dart`: a `Spawner` is
  a `Mechanism` (like a door), fired by a signal or a zone, releasing `Wave`s
  of a fixed `count`.
- **Doors, keys, pickups, secrets, inventory.** `Mechanism`, `pickup.dart`,
  `collector.dart`, `inventory.dart`, `secret.dart` in the shooter package.
- **Levels.** `flutter3d_editor_core/tool/levels/dungeon.dart` builds a
  dungeon level; `flutter3d_app/lib/src/level/` loads one, with visibility
  culling and shared meshes.
- **Four controllers.** `pad_input`: `Gamepad(index:)` reads a player's slot
  on macOS, iOS, Android and the web (commit `653881c6`).
- **Drawing a crowd.** `InstancedMeshNode` (`flutter3d_core/.../instanced_mesh_node.dart`)
  and `BillboardAtlas` in `flame_flutter3d` (one texture, one material, one
  card set per image for any number of billboards).
- **Sound, particles, online.** `flutter3d_audio`, `flutter3d_particles`,
  `flutter3d_net` (rollback `NetSession`, WebSocket and WebRTC transports).

## What is missing

1. **More than one player.** The single `focus` and the single-goal flow
   field are the two load-bearing assumptions to change; the simulation's one
   `Player` is the third.
2. **A horde.** Nothing has run two hundred actors at once; the cost of
   thinking, moving and colliding them is unmeasured, and it matters most on
   the web and the CPU backend.
3. **Generators.** A spawner that pours without end, keeps a cap on how many
   of its monsters live, and can be shot to pieces.
4. **A shared camera** for several heroes.
5. **The rules**: drain, food, potions, classes, Death, the thief, score,
   exits, the announcer.

## Design

### Several foci, one sweep

The flow field sweeps from every hero at once: a multi-source Dijkstra seeded
with each hero's cell at cost zero. While relaxing it records, per cell, which
source the cheapest path came from (`_source[cell]`). An agent then gets both
its direction and *which hero it is heading for* from one lookup, and that
hero is its focus. Still one sweep per body class per step in which any hero
changed cell, so the cost stays independent of the number of monsters.

- `FlowField.update(Vector3 goal)` stays and becomes the one-source case of
  `updateAll(List<Vector3> goals)`.
- `ActorSystem.focus` stays, as "the focus of an actor that has not asked";
  `ActorSystem.foci` is added, and `Brain.focus` returns the focus the field
  assigned to this actor's cell, falling back to the nearest by straight line
  where the field has no answer.
- The design note in `actor_system.dart` is rewritten rather than
  contradicted: still no infighting, still no per-actor search; the target is
  now "the nearest hero by walking", which the sweep already knows.

### The simulation

A new package, `flutter3d_game_crawler`, beside the other genre packages. It
uses `flutter3d_sim` and the parts of `flutter3d_game_shooter` it needs
(pickups, inventory, mechanisms, `ChaseBrain` as the base of its monsters)
rather than making the shooter multi-player: the shooter's first-person
player, weapons and HUD are not what a crawler has. Anything both need moves
down into `flutter3d_sim` or stays in the shooter and is imported.

- `Hero`: a class (`warrior`, `valkyrie`, `wizard`, `elf`) as data, health
  with a per-second drain, keys, potions, score, a controller slot.
- `Generator`: a `Mechanism` with health, a monster kind, a period and a cap
  on its live monsters; destroyed, it stops.
- Death and the thief as brains: Death drains on contact and ignores damage;
  the thief goes for the hero with the most items, takes one and makes for
  the nearest exit.
- Deterministic, fixed-step, with a save, like the shooter's simulation, so a
  replay and a rollback session both work.

### The camera

A camera component that frames the bounding box of the living heroes from
above at a fixed pitch, eased, with a minimum and maximum height, and that
reports the visible rectangle to the simulation, which keeps heroes inside it
(the arcade's rule: nobody drags the others off screen).

### Drawing the horde

Monsters of one kind are instances of one mesh (`InstancedMeshNode`), or
billboards from one `BillboardAtlas` for a pixel-art look. Either way the draw
count is per kind, not per monster.

## Milestones

Each ends with tests; new tests move the counts `tool/structure.dart` holds.

- **M0 — the horde, measured. A gate.** A headless benchmark: a dungeon
  level, one flow field, two hundred `ChaseBrain` actors, stepped for ten
  seconds; time per step on the VM, and the same scene drawn per frame on the
  CPU backend and on WebGL. If a step costs more than a few milliseconds,
  the fix (think staggering, which `ActorSystem` already schedules; cheaper
  monster-to-monster separation) comes before anything else.
- **M1 — several foci.** Multi-source `FlowField`, `ActorSystem.foci`,
  `Brain.focus` per actor. Tests: two heroes at the two ends of a corridor,
  monsters in between split by walking distance; the one-goal behaviour
  unchanged (the existing navigation tests pass as they are).
- **M2 — heroes and the camera.** `Hero`, classes, drain, food, keys and
  doors, the shared camera and the screen-edge rule, four pads through
  `pad_input`. A playable empty maze for four.
- **M3 — generators and the horde on screen.** `Generator`, instanced or
  billboard monsters, shots, melee, potions.
- **M4 — Death, the thief, score, exits, levels.** Several levels from the
  dungeon tool, the announcer through `flutter3d_audio`.
- **M5 — the app.** `apps/flutter3d_demo_crawler`: title, character select,
  levels, game over; macOS, the web, Android.
- **M6 (later) — online co-op.** Through `flutter3d_net`'s rollback session,
  which is why M1–M4 keep the simulation deterministic.

## Risks and open questions

- **The horde's cost on the web** is the largest unknown; M0 exists to answer
  it before it shapes everything else.
- **Monster-to-monster crowding.** Two hundred bodies in corridors need
  separation; `CollisionWorld` movers may be too exact and too slow for it,
  and a cheap steering push may be the better answer.
- **Shooter or new package.** The plan chooses a new package; if the shooter's
  simulation turns out to generalise cheaply to several players, merging is
  the smaller change.
- **Flame or not.** River Sortie is built on Flame through `flame_flutter3d`,
  whose input bridge already reads a second controller. This plan does not
  use Flame: the crowd, navigation and mechanisms live in `flutter3d_sim` and
  the shooter, not in the bridge.
