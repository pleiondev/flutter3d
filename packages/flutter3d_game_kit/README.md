# flutter3d_game_kit

Gameplay parts for flutter3d games, one library each. A game takes the parts it wants by importing their libraries; `package:flutter3d_game_kit/flutter3d_game_kit.dart` exports all of them.

Nothing here builds native code. The parts that need the physics core in C (ragdolls, burning wrecks, party sessions and the elements heard) are [`flutter3d_game_physics`](https://pub.dev/packages/flutter3d_game_physics).

| Library | Was | What it is |
| --- | --- | --- |
| `reactions.dart` | `flutter3d_addon_reactions` | What an event in a flutter3d game looks and feels like |
| `soundtrack.dart` | `flutter3d_addon_soundtrack` | What a flutter3d game sounds like, kept apart from playing it |
| `ghost.dart` | `flutter3d_addon_ghost` | A rival or a past run, drawn from a recorded track |
| `seeded_levels.dart` | `flutter3d_addon_seeded_levels` | Levels nobody built, each made from its seed when the player reaches it |
| `world.dart` | `flutter3d_addon_world` | The world around the part a game simulates |

## `reactions.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_reactions`.*

What an event in a flutter3d game looks and feels like: particle bursts,
smoke that lingers, the camera kicked, shaken or widened, a pulse in the
player's hand, a flash on the screen, and the sound that belongs with them.

A `Reaction` is a decision, not an effect. The game decides it from a step
or from the events the step published, a test asserts it with no device, and
the frame performs it. That split is why it exists: the games this came out
of had their particles in private methods of a widget nothing could mount, so
no test had ever mentioned a particle, and a hit that showed nothing was
something somebody had to happen to notice.

| Type | What it is |
|---|---|
| `Reaction` | Bursts (`Shown`), `Lingering` plumes, `Felt` jolts, `Heard` sounds, `Haptic` pulses and whether the screen flashes. `showIn(particles)` and `feel(rig)` perform it |
| `Lingering` | An emission that outlives its event, under a key of its own, so two plumes in one doorway stay two |
| `Felt`, `Jolt` | The camera's three verbs, `kick`, `shake` and `widen`, as a description applied to a `CameraRig` |
| `Haptic` | A pulse of the device: `selection`, `light`, `medium`, `heavy` |
| `ScreenFlash` | A flash that fades by the step, fired at the player's own brightness setting |
| `ReactionTable` | Rules keyed by event type, run in the order the events happened |
| `ReactionsPlugin` | The table heard from the engine's bus, on the frame channel |

### Manifest

`ReactionsPlugin`:

- **id** `flutter3d_game_kit/reactions.dart`, or the one passed in, when one engine
  has two tables;
- **apiVersion** 1.0;
- **touches** `view`, so switching it is not written into a replay;
- **backends** all of them;
- **permissions** none;
- **dependsOn** nothing.

It has no plugin marker: it is built around the game's own
table, so discovery has nothing to construct. A game hands it to its loop.

A step a rollback runs again is not shown twice. The frame channel hands an
event out again only when it changed, marked `resimulated`, and the plugin
skips it unless `showCorrections` is set.

### Example

```dart
import 'package:flutter3d_game_kit/reactions.dart';

final table = ReactionTable()
  ..on<Landed>((e, out) {
    out.bursts.add(Shown(Effects.dust, e.at));
    if (e.speed > 6.0) out.jolts.add(Felt.kick(Vector3(0.0, -0.15, 0.0)));
    out.haptics.add(Haptic.light);
  })
  ..on<Exploded>((e, out) {
    out.flash = true;
    out.lingering.add(
      Lingering(Object(), Effects.smoke, e.at, perSecond: 34, seconds: 0.85),
    );
  });

final reactions = ReactionsPlugin(table);
final loop = EngineLoop(input: input, plugins: [genre, reactions]);
final flash = ScreenFlash(fadePerSecond: 4.0);

// Each frame:
final reaction = reactions.take()
  ..showIn(particles)
  ..feel(camera.rig, haptic: settings.haptics);
if (reaction.flash) flash.fire(settings.screenFlash);
```

A game that decides from its simulation's state as well as its events —
how hard a landing was, which projectiles burst this step — writes a
`ReactionBuilder` itself, lets the table fill the event-keyed part, and
calls `build()`.

### Where it came from

The dungeon, the platformer and racing each wrote a `Reaction` class in
`reactions.dart`: one with lingering smoke and a flash, one with camera
jolts, one with the sound of hitting a wall. This is the union of the three,
and the camera's verbs, the flash's fade and the bursting moved with it.
Each game keeps its own decider, the thin part that says which of its events
shows what: the dungeon's rules are a `ReactionTable`.

## `soundtrack.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_soundtrack`.*

What a flutter3d game sounds like, kept apart from playing it: a cue sheet
keyed by events, footsteps paid for in metres, and sounds with a lifetime.
The fires and water of the elements are heard through `ElementSounds`, in
`flutter3d_game_physics`' `elements.dart`.

Deciding what a step sounds like is a fact about the simulation, and a test
can ask about it with no device. Both games this came out of found real
silence once they could: six sounds missing from one bank, four weapons
sharing two sounds in the other. The game's own cue lists, its `SoundDef`s
and which event plays which, stay with the game as data.

| Type | What it is |
|---|---|
| `CueSheet` | Sounds keyed by event type, run in the order the events happened |
| `SoundtrackPlugin` | A cue sheet heard from the engine's bus on the frame channel, and played |
| `Footsteps` | A step every `stride` metres walked across the ground, none in the air |
| `Sustained`, `Voice` | A sound with a lifetime, begun, followed and ended by one key |
| `Sounding` | One step's one-shots and sustained voices |
| `SustainedVoices` | Plays a `Sounding`, keeping a voice per key |

`Heard`, `SoundDef` and `SoundBank` are `flutter3d_audio_core`'s, exported
here so a sheet needs one import.

### Manifest

`SoundtrackPlugin`:

- **id** `flutter3d_game_kit/soundtrack.dart`, or the one passed in;
- **apiVersion** 1.0;
- **touches** `view`, so switching it is not written into a replay;
- **backends** all of them;
- **permissions** none;
- **dependsOn** nothing.

It has no `flutter3d_plugins:` marker: it is built around the game's own
sheet and audio scene, so discovery has nothing to construct. A game hands
it to its loop. An event a rollback hands out again (`resimulated`) is not
played twice unless `playCorrections` is set.

### Example

```dart
import 'package:flutter3d_game_kit/soundtrack.dart';

final cues = CueSheet()
  ..on<Jumped>((e, out) => out.add(Heard(Sounds.jump, e.at)))
  ..on<DoorRefused>((e, out) => out.add(Heard(Sounds.locked, e.at)));

final loop = EngineLoop(
  input: input,
  plugins: [genre, SoundtrackPlugin(cues, scene: () => audio.scene)],
);

// Footsteps by distance, in the game's own step:
final feet = Footsteps(stride: 2.2);
if (feet.walked(body.position, grounded: body.isGrounded)) {
  audio.scene.play(Sounds.step, body.position);
}
```

### Where it came from

The dungeon's and the platformer's `soundtrack.dart` each counted footsteps
the same way and switched over their events the same way; the dungeon's also
had the sustained voices of its doors and lifts, and `FrameEffects` the map
that played them. Their `element_sounds.dart` played the same three
recordings at two reaches. Both games now hear their events through
`CueSheet`s and count steps with `Footsteps`; the elements went to
`flutter3d_game_physics` with `ElementSounds`, and the dungeon passes it its
own `ElementCues`.

What stayed in the games is theirs: the `Sounds` banks of all four, racing's
`CarVoice` (one engine per car, modulated rather than begun and ended), and
racing's elements, which hold a wash to each car in the water rather than a
fall.

## `ghost.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_ghost`.*

A rival or a past run, drawn from a recorded track. Three pieces, each
usable alone:

| Piece | What it does |
|---|---|
| `Ghost` | a node put where a `Tape` was at a moment of it — standing on a model's floor, turned by its facing, lifted along the track's own up — and hidden before the track starts and after it ends |
| `Ghost.look`, `Ghost.haunt`, `Ghost.build` | the ghost's material (translucent, unlit, writing no depth), every part of a model made of it, and a ghost of the game's own model or of a fallback while that loads |
| `ghostOfRun` | the track of one body through a shared run: the tape played again through the game's own staging when it can be, the run's pose record when it cannot (other physics, another simulation, a level edited as it went), and the reason when neither will do |
| `BestRun` | the best run made in one place, sampled as it is played and kept between launches in `Storage`: against the record rather than the session, never throwing on a document that will not read |

A ghost is not in the collision world and is not stepped: it cannot be
hit, and it cannot block the run being played. It goes with the replay
promise of 1.0: a run's pose record plays on any build, so a ghost can
always be drawn from one.

### Not a plugin

A ghost is drawn by the game that owns its scene, on the game's own clock,
so there is nothing for a plugin host to install and the pubspec carries no
`flutter3d_plugins:` marker.

### Example

```dart
import 'package:flutter3d_game_kit/ghost.dart';

final best = BestRun(storage: storage, name: 'best-$course.json')..load();

// Each step of a run:
best.watch(elapsed, position: body.position, yaw: body.yaw);
// When it ends:
if (best.finished(elapsed)) say('A new best.');

// The ghost of the best run, from the game's own model.
final ghost = Ghost.build(
  scene,
  look: Ghost.look(),
  model: playerModel,
  fallback: () {
    final stand = MeshNode(box, Ghost.look(), name: 'ghost');
    scene.add(stand);
    return stand;
  },
);

// Each frame:
if (best.best case final track?) ghost.showAt(elapsed, track);
```

And a shared run, raced:

```dart
final (:ghost, :says) = ghostOfRun(
  level,
  run,
  body: 'player',
  simulation: mySimulationVersion,
  replay: () => replayHeadless(level, run), // the game's own staging
);
```

### Where it came from

The platformer demo's `ghost.dart` (the runner's ghost, and the shared run
raced from its tape or its pose record) and the racing demo's
`ghost_car.dart` (the ghost car and the best lap on disk) drew the same
thing two ways. What stayed in each demo is what is its own: the
platformer's headless staging of a level and where a runner's feet are; the
racing demo's lap document (written by its genre package), one file per
circuit, and where a car keeps its heading and its up.

## `seeded_levels.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_seeded_levels`.*

Levels nobody built, each made from its seed when the player reaches it.
A seeded level is named `generated:<seed>` wherever a level would name its
asset: a level's `next`, a save's current level, a run's first one. The same
seed makes the same level, so a save opens it again and a run through them
replays.

| Member | What it does |
|---|---|
| `SeededLevels.first(seed)` | The name of the first seeded level a game opens |
| `SeededLevels.seedOf(asset)` | The seed a name carries, or null for an asset of the game's own |
| `SeededLevels.level(seed, first:)` | The level document, made off the drawing thread, with `next` naming the following seed |
| `SeededLevels.rulesFor` | The game's `LevelRules` for a depth, counted from the first seed |

A library, not a plugin: it registers nothing with the engine, so the pubspec
has no `flutter3d_plugins:` marker.

### Example

```dart
import 'package:flutter3d_game_kit/seeded_levels.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

LevelRules crowded(int depth) => LevelRules(
  name: 'Below, ${depth + 1}',
  perRoom: <({Map<String, Object?> entity, int count})>[
    (entity: const <String, Object?>{'type': 'pickup'}, count: 1 + depth),
  ],
);

const below = SeededLevels(rulesFor: crowded);

Future<Level> open(String asset, {required int firstSeed}) async {
  final seed = below.seedOf(asset);
  return seed == null
      ? await loadLevelAsset(asset)
      : await below.level(seed, first: firstSeed);
}

// From an ending: the first of them.
run.load(below.first(firstSeed));
```

### Where it came from

The dungeon demo's depths, the levels past its last crypt. The rules are
the dungeon's and stay in it (`apps/flutter3d_demo_dungeon/lib/src/depths.dart`):
what a room holds and how fast it fills is a game's choice.

## `world.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_world`.*

The world around the part a game simulates: the hour of the day and the
sky it is seen through, and the ground going on past the simulated square
out to the horizon.

| Class | What it does | Settings |
|---|---|---|
| `Daylight` | The hour, the sun and moon lights, and the physical sky; `flutter3d_game_physics` adds `lightWater`, the light on an `Elements` water | `secondsPerHour` (50), `sunIntensity` (2.6), `moonShare` (0.12), `air`, `noon` |
| `Horizon` | A far floor and a level far surface in rings round the simulated square, out to 1.5 km | `size`, `floorCell`, `surfaceCell`, `ground`, `farDepth` (34 m) |

**The sky is the air, not a colour.** `Daylight.sky` is a `PhysicalSky` with
the sun where the hour puts it, so the morning is pale, the evening red, and
the stars come out on their own. `light` points a sun and a moon along the
hour, each in what the air leaves of it, and only the one in the sky casts
the shadows: the renderer shadows the first directional light that asks.

**The moon is a game's moon**, far brighter than the real one, which a frame
at one exposure shows as black. `moonShare` is a choice about play.

**The ground stays the game's.** `Horizon.ground` is asked for the drawn
ground's height at the edge, so the far floor meets it without a seam, and
eases down to `farDepth` over a few hundred metres.

Both are in one package because both dress the world around the simulated
part and each is one class. A library, not a plugin: nothing here registers
with the engine, so the pubspec has no plugin marker.

### Example

```dart
import 'package:flutter3d_game_kit/world.dart';

final day = Daylight();

loop.addSystem('world.day', LoopPhase.animate, (frame) {
  day
    ..advance(frame.dt)
    ..light(sun: sun, moon: moon);
});
final settings = RenderSettings(sky: day.sky);

Horizon(
  size: 64.0,
  floorCell: 0.5,
  surfaceCell: 1.0,
  ground: terrain.heightAt,
).addTo(device, scene, floor: sand, surface: water.material);
```

### Where it came from

`Daylight` is the sandbox demo's day and night. `Horizon` is the Reef demo's
open sea past the reef, whose terrain function stays in Reef: the ground of
a world belongs to the game that shapes it.
