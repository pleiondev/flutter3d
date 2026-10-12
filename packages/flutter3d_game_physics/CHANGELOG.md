## 1.0.0-rc.1

- **Breaking: `RagdollCorpses.begin` takes one `ActorDeathContext`**, as
  every `ActorCorpses` does now.
- **`BurningWreck.fromJson` throws a `SnapshotFormatException`** for a
  row that is not a wreck; the component's codec still skips the row.
- **`ElementSounds` takes `cues:` and `bus:` by name**, so it can take
  another in a minor.
- **The wrecks are drawn from what they publish.** `BurningWrecks` is the
  simulation's half alone: made over an `ElementsSimulation`, with no
  device, it places, lights and lets go the wrecks and publishes each as a
  `BurningWreck` (its body, whether it is oil, where it lies, how it is
  turned, whether it burns; `toJson`, `fromJson` and a `ComponentCodec`).
  `WreckLooks(scene, device).show(published)` draws the slicks from those
  rows, so the wrecks draw the same wherever the elements are stepped.
- **Which crash breaks a car's tank, by its standard.** `FuelCell` says
  whether a crash that took so much speed out of a car breaks its fuel
  cell: `FuelCell.racing` stands the FIA's 15 m/s frontal impact test of a
  Formula One chassis, `FuelCell.road` FMVSS No. 301's 48 km/h barrier. What
  the tank spills burns on a burner fed that much fuel and goes out when it
  is burnt (`Fires.setBurner`'s `fuel`).
- **A body wading is heard.** `ElementSounds.wade(scene, waders, dt)` plays
  a splash as each `Wader` goes into water fast enough, as loud as it goes
  and not again for a moment, and holds a wash to each one ploughing
  through, apart from the falls; `ElementCues` gains `wash` (the falls'
  unless given) and `wading` (`WadingHearing.standard`, a walker;
  `WadingHearing.car`), and `ElementCues.circuit` is the racing demo's
  cues, so its own copy of them can go.
- **A body dies with its tone up.** `SkeletonRagdoll` and
  `RagdollCorpses` take `tone:` (`MuscleTone.human` by default, null for a
  body limp from the start): the body takes the killing blow as one and
  goes limp over a fifth of a second. Struck low in the back, at the root
  of its chest bone, the dungeon's runner now ends lying, its head 0.1 m
  up, where it sat propped on its elbows at 0.6. `RagdollCorpses.blowAt`
  says how far up the chest bone the blow lands, 0.75 unless set.

- **The Quaternius profile names each joint's group.** Its spine, neck,
  shoulders, elbows, hips and knees are of `JointGroup.spine` and the
  rest, so `JointTissue.human` holds each at the end of its range with the
  stiffness measured for it, stiffening past the limit, where every joint
  had one linear 3000 N·m/rad. Struck at the top of the chest with the
  pelvis held, a relaxed spine now gives about 0.35 rad past its limit,
  where it gave 0.06; thrown back on a floor, it stays inside its range,
  as before.

- **The Quaternius profile moves as a body does.** The spine, the neck,
  the shoulders and the hips are `RagdollSwing`s with the American Academy
  of Orthopaedic Surgeons' ranges of normal motion (the spine bends forward
  80 degrees and back 25, where symmetric cones of half a radian held it at
  its limit in flexion), measured from the anatomical position against the
  figure's own forward and up, so T-pose arms are limited as arms hanging
  at the side and cannot hang plumb behind a body on its back.
  **Breaking:** `SkeletonRagdoll(friction:)` is gone for `tissue:`, a
  `JointTissue`.

- **The killing blow lands on the upper chest.** It landed at the chest
  bone's root, the small of the back below the centre of mass, where it
  knocked the hips out and sat a corpse down on its arms; now it turns the
  body back over its feet. The wrong tails of the right upper arm and thigh
  had hidden it, by tipping every body over sideways.

- **Breaking: `elements.dart` and `party.dart` re-export nothing.** `Audible`
  and `PhysicsHearing` are `flutter3d_effects`', `PartySeat` is
  `flutter3d_net`'s and `SimulationVersion` is `flutter3d_plugin_api`'s.

- **The skeleton's ragdoll lives with the corpses.** `SkeletonRagdoll`,
  `RagdollProfile`, `RagdollPart`, `RagdollLying` and `RagdollGetUp` moved
  here from `flutter3d_physics_native`, which names no scene any more;
  `ragdoll.dart` exports them beside `RagdollCorpses`.
- **Breaking: `RagdollCorpses` falls by its world.** The `gravity`
  parameter of `RagdollCorpses(` is gone: a corpse falls by the collision
  world's `properties`. Its `mass` defaults to `referenceBodyMass` (73 kg)
  and `RagdollCorpses.defaultPush` is that times two metres a second.
- **New: the gameplay parts that need the native physics core**, split out
  of `flutter3d_game_kit` so a game that uses none of them compiles no C:
  `ragdoll.dart`, `wrecks.dart` and `party.dart`, which were
  `flutter3d_addon_ragdoll`, `flutter3d_addon_wrecks` and
  `flutter3d_addon_party`, and `elements.dart`, with `ElementSounds` and
  `ElementCues` from the soundtrack and `Daylight.lightWater` from the world
  as the `DaylightOnWater` extension. `flutter3d_game_physics.dart` exports
  them all. `dart run flutter3d_build:migrate` moves a project's
  dependencies and imports; the packages' own histories are in
  `doc/changelogs/`.

### `ragdoll.dart`, from `flutter3d_addon_ragdoll` 1.0.0-rc.1

- **Actors that fall as bodies when they die.** `RagdollCorpses` is an
  `ActorCorpses`: handed to `ActorVisuals`, it takes a dead actor's skeleton
  over and lets it fall in the physics core against the level and the
  actors still standing. A rig the ragdoll profile does not name keeps its
  death clip.

- **Pushed away from the blow.** `pushedFrom` says where the killing blow
  came from, and the chest is thrown away from there, level and a little up.
  The push, the body it lands on and the body's mass are a game's to set.

- **Display, not simulation.** The bodies step on the frame, in fixed
  sixtieths of their own and at most four a frame, and are in no save or
  replay: nothing in a step asks where a body lies.

- **From the dungeon demo**, which now hands it the player's position as
  where each blow came from.

### `wrecks.dart`, from `flutter3d_addon_wrecks` 1.0.0-rc.1

- **Wrecks that burn and sink, on the elements.** `BurningWrecks` places
  what a hit leaves in a game's `Elements` and holds a blast's fireball to
  it: `oil` is a slick of crude afloat and alight, drawn black and glossy,
  carried off by the current while the hull goes down under it; `timbers`
  is a heap of wood burning where it fell. The physics core's heat burns
  them as long as their fuel lasts, and the elements draw the flames and
  the smoke.

- **Let go behind the player.** `step` is told how far the player has come
  along the way the game travels, `along`, and lets go of every wreck more
  than `behind` metres back. `clear` puts every fire out for a new run.

- **From the River demo**, whose tankers and depots leave these behind.

- **`BurningWrecks` takes `elements` and `device`** as plain positional
  parameters rather than `this._elements` and `this._device`, which put a
  private name in the API. Callers pass them as before.

### `party.dart`, from `flutter3d_addon_party` 1.0.0-rc.1

- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `PartySession.full` is `isFull`. `dart fix` carries the renames.
- **Breaking: `RoomSession.create` is `host`**, beside `join`: `create` is
  the synchronous verb, and this one opens a session on the relay.
- **The relay is asked with the whole `SimulationVersion`**, and
  `SideRecording` takes the `physics` its side plays on.
- **Party sessions for any game.** `PartySession<G>` makes, joins or finds
  a party on the relay and hands the seat to the game's own `stage`; the
  relay settles the size and the slot. `seats` refuses a party bigger than
  the game can stage, before anything is staged.

- **The simulation's version always goes with the ask.** `PartySession`
  and `RoomSession` require a `SimulationVersion` and send it as
  `relayVersionOf` reads it, `engine × 1000 + game`. A party used to ask
  with none, which met only builds that named none; now a build on other
  rules is turned away with the relay's reason.

- **A room for two, and one side's run.** `RoomSession` seats the maker at
  0 and the one who joins at 1, and keeps why the relay closed it.
  `SideRecording` keeps a side's start, input tape and settled digests as a
  `Demo`, so the two sides' files can be compared.

- **No `dart:io`.** Writing the run to a file is left to the application,
  so the package runs on the web.
