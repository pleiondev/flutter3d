# The abstraction boundary — decisions for the 0.5.0 release

A template must not force specific object types onto anyone. An enum can hold
an object's class, but extending it later breaks someone else's `switch`
statement — which makes adding a value to a published package a breaking
change. That is the whole distinction below: what is **machinery** here
(closed correctly — the set is finite and ours) and what is **content**
(closed wrongly — the set belongs to the game built on top).

Decisions made by Dmitrii on 2026-09-04. Released as **one 0.5.0** across every
package touched, because opening these breaks the published
`flutter3d_game_shooter` 0.4.1.

## Open

| Type | Package | How | Why |
|---|---|---|---|
| `AmmoType` | `flutter3d_game_shooter` | like `LightingModel` — a `final class` with constants | a game writes its own weapon and cannot say what it fires |
| `MonsterState` | `flutter3d_game_shooter` | same | six states and nine `switch`es; no room to add fleeing or summoning |
| `WeaponBehaviour` | `flutter3d_game_shooter` | drop `sealed`, let a game's own subclass override the simulation | no way to invent a new way of delivering a shot |
| `Projection` | `flutter3d` | drop `sealed` | a third party cannot add a sheared projection, and portals are already on the roadmap |
| `AssetSource` | `flutter3d` | open it with a resolver registry | the background isolate rebuilds a resolver from its description; there is no way to add a source of one's own — a network, an archive |
| `ActivationOutcome` | `flutter3d_game` | drop `sealed` | a game with its own outcome cannot add it |
| `PadStickUse` | `pad_input` | open it | which way a stick routes is the game's own call |

## Leave closed

| Type | Why it is machinery |
|---|---|
| `RunStatus<L>` | run state every one of the three games' screens is built on; the set is finite and ours |
| `ResourceSize` | a fraction of the frame or pixels — an exhaustive pair, there is no third way to name a size |
| the HAL's own enums | mirror flutter_gpu; a third-party backend must handle every value |
| `ShadowCasting` in the level format | a closed list on purpose: a document the engine reads cannot name a mode the engine does not know |

## The rules that hold this in place

- **A boundary rule in `tool/structure.dart`, with a table of exceptions** —
  so the next enum does not appear in a published package silently. The table
  lists the machinery above and asks every row to give a reason.
- **An unfamiliar value in an open vocabulary** is handled **differently in
  different places, but always written down**: every point where the engine
  or the template meets a value it does not know says, in its own doc
  comment, what it does — ignore it, throw, or fall back — and why that is
  the right call there.
- **A value added to a HAL enum** is written into the CHANGELOG as breaking,
  even when it looks like an addition: a third-party backend must handle
  every value.

## The genre seam (2026-09-04 decisions, part two)

Working through the genre half of the templates produced a list of gaps; the
first one taken is the seam that runs through all of them.

- **A simulation reports what happened through a typed stream of events that
  knows nothing about sound.** A genre package does not depend on
  `flutter3d_audio`: it says "a shot fired," not "play this sound." The event
  set is **open** — a game adds its own.
- **Difficulty is an open settings object with ready-made levels**, the same
  shape as `LightingModel`: multipliers, three or four named constants, and a
  game can build its own.
- **A genre's own HUD lives in the genre package.** Depending on Flutter from
  inside a template is accepted deliberately: a seam running the right
  direction matters more than keeping the package clean.

## What breaks now so it does not break later (2026-09-04 decisions, part three)

0.5.0 is a breaking release regardless, so anything that would have to break
later breaks here instead.

- **`abstract base class` on every open type** — `GameEvent`, `Projection`,
  `PadStickUse`, `ActivationOutcome`, `Shape`, `DerivedShape`,
  `ProceduralTexture`, and whatever opens after these. `implements` is
  refused, `extends` stays available: adding a member with a default
  implementation after this breaks nobody. The cost is that someone else's
  subclass carries `final`/`base`/`sealed`.
- **All nine callback typedefs take a context object**, not a positional
  list: there is no other way to add a parameter later.
- **`IssueSink` collapses into one** — it was declared identically in
  `flutter3d_audio` and `flutter3d_game`, and merging the two later would
  have been breaking.
- **The trace document gets a `formatVersion`** — the one format with no
  version number; a level, a sidecar, settings, a demo, a snapshot and a
  `.fmat` all already have one.
- **135 public `final List<...>` fields are sorted through**: a hot-loop
  buffer stays mutable and says so; a summary read from outside narrows to an
  immutable view.

## Public collections: what was measured, and what was done

The decision was "sort through the ones read from outside and narrow them."
The sorting is a measurement, not a hunch:

| | |
|---|---|
| public collection fields in published packages | **174** |
| of those, mutated from another file | 34 |
| never mutated from outside at all | 140 |
| of those, read from **another package** — the real surface | 87 |
| of those, filled once rather than every frame | 61 |
| of those, on a `const` class, where a wrapper would have cost `const` | 40 |
| left worth wrapping | **21** |

**Nine narrowed.** The type stays `List<T>`/`Map<K,V>`, and the constructor
hands back an immutable view: reading still works the way it worked, an
outside mutation now fails loudly — and measurement confirmed there was no
such mutation to begin with. These are `LoadedLevel.issues`,
`ModelNode.joints`, `Skeleton.joints`, `ModelAsset.skins`,
`GltfAsset.buffers`, `CpuShaderLibrary.stages`, `Detonation.damage`, and
three on `WebGlProgram`.

**Twelve left alone, and that is not something left undone.** `GameConfig.settings`,
`Material.parameters`, `Arsenal.slots`, `RacingSimulation.inputs`,
`RaceState.progress`, `Level.materials` and the like are exactly what a game
writes into. Wrapping them would take away the very capability they are
public for.

**Forty on `const` classes are untouched.** A wrapper needs a computation in
the initializer, which `const` does not allow, and giving up `const` on the
value costs more than guarding against a mutation nobody performs.

## Difficulty: where it applies, and where it does not

`Difficulty` lives in `flutter3d_sim` — it is about the step, not about
Flutter. Its four axes are chosen so that none of them belongs to any one
genre: how much the player takes, how much they deal, how sharp the
opposition is, and how much assistance is on.

- **The shooter** reads two: `damageDealt` multiplies alongside berserk
  (rather than replacing it), `damageTaken` sits behind the single door all
  damage reaches the player through. `opponentReaction` reaches the monsters
  through `Bestiary`.
- **The platformer** reads one — `damageTaken`, in `Runner.applyDamage`,
  where every source of damage arrives.
- **Racing reads none of them, and that is not something left undone.** Its
  AI has no reaction delay and no rubber-banding to multiply. Inventing a
  number would mean inventing a mechanic; that is item 21 of the genre-gap
  list, and it waits its own turn rather than hiding behind a setting.

## The HUD: where the line was drawn

The decision was "a genre's own HUD lives in the genre package." Drawn this
way: the genre carries the **readout**, the game carries the layout.

There was nothing to move over wholesale. The dungeon's HUD is four hundred
lines holding the frame counter, the voice count, the particle count, the
message line and the screen flash — all of it belongs to that game, not to
the shooter. What in it is genre-shaped is a handful of numbers, and every one
of them had been drawn wrong at least once:

- fists printed `0` instead of `∞`, because the number came from
  `currentAmmo`;
- armour was drawn as a second bar next to health, which reads as double
  health;
- the lap counter showed `0 / 3` on the first lap and `4 / 3` on the last,
  because `RacerProgress.lap` counts **completed** laps.

So every widget takes the genre's own type — `Arsenal`, `Inventory`,
`Purse`, `RaceState` — rather than numbers pulled out of it: pulling them out
is exactly where the mistake happened. And every one takes a `ReadoutStyle`,
because colour and placement are the game's own business.

## Genre gaps: what gets done and what gets struck

Of the twenty-two items the analysis turned up, thirteen are closed. Of the
nine left, six get done: reloading, water and gliding, score and streaks,
restarting, starting-grid order, run statistics.

**Three are struck, and that is a decision, not something falling behind.**
The shooter's boss, the platformer's boss, and a tutorial walkthrough are a
specific game's own content, not genre machinery. A boss is a monster with
several behaviour sets; everything it would be assembled from already exists
(`Brain` is open, `MonsterState` is open, spawners already launch waves). A
walkthrough is a level and its own messages. A template that shipped its own
boss would be forcing a specific object onto everyone — exactly what this is
built to avoid.
