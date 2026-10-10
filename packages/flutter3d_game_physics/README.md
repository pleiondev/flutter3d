# flutter3d_game_physics

Gameplay parts for flutter3d games that need the native physics core, one library each. A game takes the parts it wants by importing their libraries; `package:flutter3d_game_physics/flutter3d_game_physics.dart` exports all of them.

They were in [`flutter3d_game_kit`](https://pub.dev/packages/flutter3d_game_kit) until 1.0.0-rc.1, and are kept apart so a game that uses none of them builds no C: `flutter3d_physics_native`'s build hook compiles the core and fetches wgpu-native for every application that depends on it.

| Library | Was | What it is |
| --- | --- | --- |
| `ragdoll.dart` | `flutter3d_addon_ragdoll` | Actors that fall as bodies when they die, in place of a death clip |
| `wrecks.dart` | `flutter3d_addon_wrecks` | What a hit leaves burning |
| `party.dart` | `flutter3d_addon_party` | Local and network party sessions for a flutter3d game on the relay of [`flutter3d_net`](https://pub.dev/packages/flutter3d_net) |
| `elements.dart` | `ElementSounds` of `flutter3d_addon_soundtrack`, `Daylight.lightWater` of `flutter3d_addon_world` | The fires and water of `flutter3d_effects` heard, and the water lit by the hour |

## `ragdoll.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_ragdoll`.*

Actors that fall as bodies when they die, in place of a death clip.
`RagdollCorpses` is the `ActorCorpses` an `ActorVisuals` asks the moment it
sees a modelled actor dead: the actor's skeleton goes limp into a ragdoll in
the physics core (`flutter3d_physics_native`), which falls against the level
as the collision world has it, and every frame the bodies are written back
into the joints.

| Setting | Default | What it is |
|---|---|---|
| `pushedFrom` | none | Where the killing blow came from, asked when an actor dies |
| `push` | 120 N s | How hard the blow throws the chest away from there |
| `chest` | `'Torso'` | The ragdoll body the push lands on |
| `mass` | 60 kg | What a whole body weighs |
| `gravity` | the Earth's | The fallen's own world's pull |

A rig the ragdoll profile does not name is left to its death clip: `begin`
answers false.

**Display, not simulation.** The bodies step on the frame, in fixed steps
of a sixtieth and at most four a frame, and are not in a save or a replay. A
game's step never asks where a body lies.

A library, not a plugin: it registers nothing with the engine, so the
pubspec has no plugin marker.

### Example

```dart
import 'package:flutter3d_game_physics/ragdoll.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

final visuals = ActorVisuals(
  scene,
  appearance: appearance,
  device: device,
  corpses: RagdollCorpses(
    level.collision,
    pushedFrom: () => player.body.position,
  ),
);
```

### Where it came from

The dungeon demo's dead, which fall this way when the run has the physics
core. On the reference physics the dungeon hands no corpses, and its actors
play their death clips.

## `wrecks.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_wrecks`.*

What a hit leaves burning: fires of the physics core's own heat in a game's
`Elements` (`flutter3d_effects`), lit by a blast's fireball, burning as long
as their fuel lasts and lighting what stands close enough.

| Member | What it places |
|---|---|
| `oil(at)` | Sixty kilograms of crude spread over the water, a slick three metres by one and a half, afloat and alight; the current carries it and its fire off, and it is drawn as a black film as glossy as water |
| `timbers(at)` | A 160 kg heap of wood, fixed where it fell and burning |
| `step(distance)` | Lets go of every wreck more than `behind` metres back along `along` |
| `clear()` | Puts every fire out, for a new run |
| `bodies` | The wrecks still held |

`along` is the way the player travels, −z unless a game says otherwise, and
`behind` is forty metres unless it says otherwise. The fireball is
`BurningWrecks.fireball`: a hundred kilowatts a square metre from gas at
1300 K, for one second.

A library, not a plugin: the elements step and draw the fires, and this
registers nothing with the engine, so the pubspec has no plugin marker.

### Example

```dart
import 'package:flutter3d_game_physics/wrecks.dart';

final wrecks = BurningWrecks(elements, device);

void onHit(Target target, Vector3 at) => switch (target) {
  Target.tanker => wrecks.oil(at),
  Target.depot => wrecks.timbers(at.clone()..y = 0.5),
};

// Every frame, with how far the player has come.
wrecks.step(distance);
```

### Where it came from

The River demo, whose tankers spill burning oil on the water and whose
depots burn on the bank.

## `party.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_party`.*

Local and network party sessions for a flutter3d game on the relay of
[`flutter3d_net`](https://pub.dev/packages/flutter3d_net): a party seated
by one code or among strangers, a room for two, and one side's run kept as
a `.f3drun`. Every ask carries the game's simulation version, so a build on
other rules is turned away by the relay with a reason instead of being
seated in a game that parts at its first contact.

| Piece | What it is |
|---|---|
| `PartySession<G>` | A party of up to a full table, made or joined by code, or found among strangers who asked for the same game. The relay gives the slot; `stage` makes the game for it. |
| `RoomSession` | A room for two: the maker plays seat 0, the one who joins seat 1. The socket for a rollback session, and why the relay closed it. |
| `SideRecording` | One machine's own side of a session as a `Demo`: its start, its input tape, the digests of what it settled. |
| `partyCode`, `physicsTerms`, `relayVersionOf` | A code with no `0`/`O` or `1`/`I`; the physics backend every machine must share; a `SimulationVersion` as the one number a relay compares. |

It is a library, not a plugin: a screen opens a session when a player asks
for one, and nothing is installed into the loop. What a session steps, the
game's own rollback over the seat's wire, stays the game's.

### Example

```dart
import 'dart:math' as math;

import 'package:flutter3d_game_physics/party.dart';

final party = await PartySession.open<MyGame>(
  relayBase: Uri.parse('wss://relay.example/'),
  simulation: mySimulationVersion,
  terms: physicsTerms,
  game: 'my_game/harbour',
  find: true,
  size: 4,
  seats: 8,
  newCode: () => partyCode(math.Random()),
  stage: (PartySeat seat) => MyGame(wire: seat.wire, players: seat.size),
);
print('send a friend ${party.code}; you are player ${party.slot}');
```

A room for two:

```dart
final room = await RoomSession.host(
  relayBase: relay,
  code: partyCode(math.Random()),
  simulation: mySimulationVersion,
  terms: physicsTerms,
);
final recording = SideRecording(
  start: sim.save(),
  level: 'assets/levels/harbour.json',
  levelHash: level.digestHex,
);
// Each step: recording.record(input), then advance the rollback session
// with `onSettled: recording.settled`. At the end, `recording.toDemo()`.
```

### Where it came from

The racing demo's party and two-car sessions. What was a race's — the grid,
staging the cars, the number of laps — stayed in the demo as a thin
adapter over these classes. The party used to ask the relay with no
simulation version, so it met only other builds that named none, which is
every build of every game; `PartySession.open` requires one.

Writing a run to a file is the application's: this package reaches no
`dart:io`, and runs on the web.

## `elements.dart`

*Until 1.0.0-rc.1, part of `flutter3d_game_kit`'s `soundtrack.dart` and `world.dart`.*

The elements of `flutter3d_effects`, met by the rest of a game: the fires,
falls and splashes `PhysicsHearing` reports, played as held voices, and the
water lit by the hour of the day.

| Type | What it is |
|---|---|
| `ElementCues` | Which recordings the elements play; `near` is the effects package's own |
| `ElementSounds` | `PhysicsHearing`'s fires, falls and splashes played, each fire and fall a held voice |
| `DaylightOnWater` | `lightWater` on `flutter3d_game_kit`'s `Daylight`: the sun's light and the sky on an `Elements` water |

### Example

```dart
import 'package:flutter3d_game_kit/world.dart';
import 'package:flutter3d_game_physics/elements.dart';

final elementSounds = ElementSounds();
final day = Daylight();

loop.addSystem('world.day', LoopPhase.animate, (frame) {
  day
    ..advance(frame.dt)
    ..light(sun: sun, moon: moon)
    ..lightWater(elements);
  elementSounds.play(audio.scene, elements.hearing);
});
```
