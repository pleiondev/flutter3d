## Unreleased

- **A level's tree reaches its monsters.** `SpawnContext.level` is the
  level being spawned, set by `spawnInto`, so a kind can resolve the names
  an entity gives. `HasBehaviourTree` is any brain that runs a tree, and
  `BehaviourBrain.pathOf` and `goalOf` read whichever brain it is.

- **A cutscene can ask an actor for a gesture.** A `play` cue names a
  clip; the actor stands, and on the cue's own step the player asks for it
  through `Mind.gesture`, `ActorSystem.gesture` and `ActorStrides.gesture`,
  which does nothing by default. Asked once, on that step, so a restore
  past it asks nothing again.

- **A loop can run steps now.** `GameLoop.runSteps` steps through the
  same door as `advance` — a tape being recorded gets each step, a tape
  being played gives one — without handing out any look or touching the
  clock, which is how a cutscene is skipped: its remaining steps run in
  one frame and a replay of the run steps them all. A cutscene camera's
  field of view is vertical degrees and forty-five unless a key says, the
  engine's own lens.

- **A level has cutscenes.** A `cutscene` entity carries its sequence
  document in its `sequence` property and `CutsceneKind` reads it for the
  game's step rate, reporting a document that does not read as a
  validation error with each problem. It spawns a `Cutscene` mechanism: a
  trigger, a button or a relay that names it starts it, it plays in the
  mechanisms' step, directs the actors while it plays and lets go at its
  end, plays once unless told otherwise, and is saved by name — a run
  restored mid-cutscene is the director again and steps on to the same
  bits. Its signals are drained from `Cutscene.signals`.

- **A cutscene directs actors.** A sequence's `actors` cues tell an actor
  by name to walk to a mark over the navigation mesh, look at a point,
  stand, or go back to its brain. `ActorSystem.director` takes an
  `ActorDirector`: an actor it directs neither thinks nor acts that step
  and is steered instead, and `SequencePlayer` is one, directing until a
  release or its end. Which cue an actor is under follows from the step,
  so a cutscene restored mid-walk steps on to the same bits.

- **A cutscene is a document played in the fixed step.**
  `Sequence.read` takes a camera's keys on a path, subtitles, a fade and
  signals, in seconds, and turns every moment into the step it falls on
  for the game's rate, refusing a document with every problem and where
  it is. `SequencePlayer` has one integer of state: each step it fires the
  signals that step reaches as `SequenceSignal` events, once each and in
  order, and a restore carries on without firing any twice. The camera
  runs along curves through its keys, on each key on its step, eased if
  asked; the subtitles and the fade are read for the frame drawn between
  two steps. A skip is the rest of it stepped undrawn, which ends where
  watching it ends.

- **A level keeps its behaviour trees.** `Level.behaviours` holds them by
  name as the documents `BehaviourTree.read` takes, written only when
  there are some; an entity names the one it runs in a `behaviour`
  property. `BehavioursRead` is the `LevelRule` a game brings with its own
  `BehaviourKinds`: every tree reads, and every entity names a tree the
  level has.

- **A breach says what it broke.** `Breaches.onHole` is told the box of
  every hole as it is blown, after the brushes are cut, and
  `Breaches.onRestore` when a restore has put the walls back and blown the
  saved holes again — so whatever was baked from the brushes can follow.

- **A navigation mesh can have a part of it baked again.**
  `NavMeshConfig.tileSize` cuts the lattice into tiles, a region never
  crosses a tile's edge, and `NavMesh.rebake` bakes again only the tiles
  a change reaches, outlines their neighbours again against them and cuts
  the polygons again from every outline. The result is the changed level
  baked whole, digest for digest, on the mesh's own `NavLattice`, which
  `bake(lattice:)` takes. On the dungeon's levels at a quarter-metre
  lattice and four-metre tiles a broken wall is baked again in 2 to 5 ms,
  against 6 to 40 for the whole. Tiled, `maxEdgeError` stays under half a
  cell: a simplified edge then never crosses a cell's centre, so a floor
  reaching one cell into a tile is not simplified away and the mesh still
  covers exactly what the grid covers. Untiled meshes, the default, bake
  as before, digests and all. Refused for meshes with jumps or islands
  dropped.

- **One navigation mesh per width of body.** `ActorSystem.navMeshes`
  replaces the single mesh: a mesh is eroded by one radius, and a body
  wider than it was baked for was routed through gaps it does not fit.
  `navMeshFor` gives each body the narrowest mesh still as wide as it is,
  and none to a body wider than all of them. `NavMesh.bakeLevelFor` bakes
  a set from a roster's radii and heights, one per erosion, each for the
  widest and tallest body that shares it.

- **Finding which polygon a point is on no longer looks at all of them.**
  `NavMesh.polygonsAt` asks only the polygons indexed under the point's
  lattice column. On the platformer's ascent, 576 polygons, it went from
  most of a route's cost to a third of a microsecond, and a route across
  the level takes about twenty.

- **Actors walk past each other.** `Avoidance` is ORCA: each neighbour
  rules out the velocities that meet it within a horizon, each body takes
  half the turning, and the velocity picked is the one nearest the wanted
  one that every neighbour allows, or the one that breaks them least.
  `ActorSystem.avoidance`, when set, puts every living actor on the ground
  through it against the living actors within reach, nearest first. The
  wish it hands the controller points along the difference between the
  velocity picked and the body's own, as long as the speed picked, which
  is how the controller lands on a velocity rather than half turning
  towards it. Nothing is kept between steps. Null, the default, changes
  nothing.

- **A navigation mesh knows how high its floors are between its
  corners.** A floor and the ramp up from it can be one polygon, and its
  corners alone made the flat before the ramp a slope. The mesh keeps the
  floors a body may stand on, column by column, and `heightAt` answers
  with the column's floor nearest what the corners say. The floors are in
  `digest`, so every mesh's digest moved. A route's costs are 32-bit, as
  the web has them.

- **An actor walks to a point over a navigation mesh.**
  `ActorSystem.navMesh`, when set, is what `steerTowards`, and so the
  `goTo` leaf, routes over: to the next corner, and at a link's take-off
  a jump, asked for only once the body is running at the landing, since
  air control adds speed only along the wish. The route is found again
  every step from where the body is and nothing of it is kept, so a run
  restored mid-walk steps on to the same bits. A body that overshoots onto
  a floor's eroded rim routes back from `NavMesh.nearestPolygon`, and one
  at the end of a route that cannot arrive stops there. Null, the
  default, walks straight as before.

- **A navigation mesh can be baked with jumps.** `NavMesh.bake(jumps:)`
  scans the bake's own floors, in whole voxels, for the gaps, ledges and
  drops of at most `maxFall` that reach jumps, and keeps the shortest
  between each pair of polygons as a `NavMeshLink`. A floor's eroded rim
  is a run-up, not a gap, so no link crosses a floor a body already walks;
  something solid at the body's height is a ledge it lands on or a wall.
  `route(jumps:)` takes the links within the body's own reach and says in
  `NavMeshRoute.jumps` which legs are flights. A mesh baked without a reach
  has the digest it had before.

- **A navigation mesh finds the way across itself.** `NavMesh.route`
  runs A* over the polygons, entering each at the midpoint of the edge it
  was reached through, then pulls a string through the shared edges, so a
  body walks from corner to corner and every leg stays on the mesh.
  `costOf` prices a metre of each area, one or more, and infinity keeps a
  route off an area. A goal nobody can reach gives a route marked
  incomplete that ends at the point nearest it, on the polygon nearest
  it. Costs are counted in whole millimetres and ties go by the mesh's own
  order, so a route is the same on every machine. `polygonAt` picks, of
  the polygons over a point, the one whose surface is nearest its height;
  `heightAt` and `closestPointOn` read the surface.

- **What steps the animations is saved with the actors.** `ActorStrides`
  is an abstract class now, with `save` and `restore` doing nothing by
  default. `ActorSystem.save` writes its state beside the system's own,
  and `restore` hands it back with the actors as they now are. A rewind or
  a replay steps on to the same strides with no line in a game's save.

- **An actor's animation can walk its body.** `ActorSystem.strides`
  takes an `ActorStrides`. Once a step, for every actor, after its brain
  has acted, dead or alive, it is asked how far the actor's own stride
  carried it. The body is swept that far in place of its brain's wish.
  The simulation knows nothing of animation; a game answers through this.
  Null, the default, changes nothing.

- **A brush can say where it draws.** `Brush.drawOrder`, `drawOrder` in the
  document and written only when it is not nought, is the engine's
  `MeshNode.drawOrder` for level geometry: a water surface after the floor
  under it, a decal brush over a wall. Brushes at different places in the
  order are never one batch, since a batch draws as one; a breach keeps the
  order of the brush it cut.

- **A `.f3drun` carries the levels edited under the run.**
  `Demo.levelSwaps` holds each one as a `DemoLevelSwap`: the step it took
  effect before and the whole document, since the edited level exists in no
  asset a replay could look up. On reading, the document is checked against
  the hash written beside it, and swaps out of step order or past the end of
  the tape are refused. A run with swaps is written as format 2, so an older
  build refuses it instead of replaying it into a divergence; a run without
  any is still written as 1. `f3drun_info` lists the swaps.
- **`DigestTrace.forgetAfter`** drops the checkpoints after a step, for a
  run that was lived again from there.
- **`LevelPatch` carries an edit as the rows that changed.**
  `LevelPatch.between` matches brushes, lights and entities by the digest
  of each row (a deleted brush is one edit, not every row after it), takes
  materials by name and every other key whole. `applyTo` refuses a level
  other than the one the patch was made against, a row that is not the one
  it names, and a result that is not the level it was meant to make; when
  it applies, it says what changed without comparing the two documents.
  `LevelPatch.staleCode` is the error a game answers a refused patch with.
- **Behaviour trees and utility choices as data.** `BehaviourTree.read`
  takes a JSON document of `sequence`, `selector`, `utility`, `invert`,
  `alwaysSucceed`, `cooldown` and leaves, and answers a tree or every
  problem with where it is. Leaves and utility considerations are registered
  by kind in `BehaviourKinds`, which comes with the ones the engine's `Mind`
  can already do (`goToFocus`, `goTo`, `wait`, `seesFocus`, `check`, `set`,
  `markFocus`, …). `BehaviourBrain` runs a tree; everything it knows is a
  `Blackboard` component, so a snapshot or a rewind brings a decision back
  half made. A board ticked by another tree starts again rather than resuming
  at node numbers that now name something else.
- **`bisectTapes` finds where two runs part.** Each side is a
  `ReplaySide` — a start, a tape and the simulation's step, restore and
  capture — that keeps the states it has been asked for and plays on from
  the nearest. The search compares digests and reads the full snapshots
  once, at the step it names; it says whether that step's input differed,
  and through an `EntityLayout` which entity and component moved.
  `bracketFromTraces` narrows the search to one checkpoint interval of two
  `DigestTrace`s.
- **`EntityTracks`** reads a run as one lane per component of each entity,
  holding only the steps a value changed and closing a lane when the
  component goes. `EntityLayout.ecs` reads an `EcsWorld.save()`,
  `EntityLayout.rows` one row per entity. `RewindBuffer.oldestStep` is the
  left end of a scrubber.
- **A save says what version of the game wrote it, and an old one is
  migrated.** `SaveSchema` is a game's list of migrations, and its version is
  their count, so the version cannot move without one. `upgrade` brings an
  older run up and refuses a newer one, saying it is newer, rather than
  misreading it. `SaveRecord` is the save document: level, snapshot, schema,
  step and a digest of the run. `SaveRecord.read` never throws.
- **`resolveSaves` decides between two copies of a save** by digest and step,
  against the digest both last agreed on: the same run is in sync, a side
  still at the base lost to the one that moved, otherwise the further run
  wins, and two different runs equally far along go to the player.
- **A run leaves the machine only with the player's yes.**
  `TelemetryConsent` keeps the answer with the wording it was given to and
  when; a grant to an older wording does not count, and a damaged settings
  file reads as not asked. `TelemetryUpload.prepare` is the only way to build
  an upload and refuses without consent; it drops `Demo.recordedBy`, and the
  consent travels with the run so a server can refuse one that has none.
  `TelemetryUploader` checks consent on every send; `HttpTelemetrySink`
  posts through a `JsonPost` the caller hands in, so this package still
  imports no network.
- **`resimulate` plays a demo again and says what it did.** It checks the
  level hash, the starting state and every checkpoint, and returns a sealed
  `Resimulation`: the level changed, the start differs, the replay diverged
  (with the step), or it retraced, with the run, its outcome and a trail of
  positions.
- **`Heatmap`** bins trails into cells, counting samples and distinct runs,
  and marks where runs were lost. Its JSON is the playtest report's, so the
  editor reads both.

- **Photo mode's camera.** `PhotoCamera` flies with the world paused: look,
  tilt, zoom, and moves along its own axes with up being the world's. It is
  held on a tether round where the player stood, inside the level's box when
  there is one, and out of the walls by sweeping each move and sliding along
  what it meets. It starts by sweeping out from the player to where the game's
  camera was, so a chase camera left behind a wall does not start the photo
  there. `shouldPause` takes `photoMode`, which pauses whatever the pointer and
  the pad say, since both are flying the camera.

- **A level bakes into a navigation mesh as well as a grid.**
  `NavMesh.bake` and `NavMesh.bakeLevel` voxelise the brushes and the
  `Heightfield`, keep the floors an agent fits on and can step between
  (`NavMeshConfig`: height, step, radius, slope), erode them by the radius,
  cut them into regions, outline those, and cut the outlines into convex
  polygons with their neighbours and an area each. Unlike `NavGrid` it keeps
  a walkway and the floor under it, and walks up a ramp rather than reading
  it as a riser. Integers from the voxeliser on, so `NavMesh.digest` is the
  same on every platform; the VM and Chrome agree on six scenes, and the
  test holds them. The mesh is eroded by `NavGrid`'s own clearance rule and
  covers exactly the cells a flow field for the same body accepts. It is
  the first part of N2; the path search over it comes next.

- **A level can be shared behind a short code.** `ShareBundle` is a level
  document, its hash and optionally a `.f3drun` through it, refused when the
  run was recorded in another version of the level. `RunService` speaks the
  `v1/shares` routes over a transport the game hands in, so the package
  still has no dependency for it, and answers every call with `ServiceDone`
  or `ServiceRefused` rather than throwing. `cloud/server` speaks this
  protocol.
- **A number tuned while the game runs is on the tape.** `InputState.tune`
  sets a tunable for one step, `InputFrame.tunes` records it, playback
  applies it, and `Tunables` is the step's side: named values with defaults,
  taken from the input before the step reads them, saved into a snapshot so
  a rewind comes back with the old value. A run tuned as it was played
  replays like any other.
- **`firstDifferingPath` moved here from `flutter3d_net`**, which still
  exports it. **`RewindBuffer.keyframesAfter`** reads the snapshots held.

- **`diffLevel` says who has to act on an edit.** It compares two versions
  of a level part by part and splits the change: lights, materials, fog and
  music can be patched into a running scene; brushes, entities, the ground,
  recipes and the next level are the simulation's, and go through a timeline
  branch. Conservative on purpose: a brush that only changed material is
  still the simulation's, since its surface falls back to its material.
- **`RewindBuffer.rebaseAt`** makes one keyframe the oldest thing held, for a
  change to the world the snapshots do not carry.

## 0.8.1+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2` and `vector_math` 2.4.3, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.8.1

**Several things to chase, and one sweep to chase them by.**
`ActorSystem.step` takes `foci:`, a list of `FocusPoint`s, beside the single
`focus:` it always took. `FlowField.updateAll` and `Navigation.updateAll`
sweep from every goal at once and record which one each cell's route ends at
(`FlowField.sourceAt`, `Navigation.targetOf`), so each actor attends to the
focus nearest by walking at the cost of one sweep per class of body; without
navigation it is the nearest in a straight line. `Mind.focus`,
`focusBody` and `focusVelocity` are the attended one's, `Mind.focusIndex`
says which, and `ActorSystem.focusVelocityOf` reads any of them. A single
focus behaves exactly as before.

**Damage to a focus is counted per focus.** `ActorSystem.hurtFocus(body,
amount)` credits whichever focus owns the body that was hit and says whether
one did; `damageToFoci` has the totals by index and `damageToFocusThisStep`
remains their sum. `focusBody` is set by `step`, as it always was; setting
it by hand still compiles and is deprecated, since the next `step`
overwrites it.

**A save carries every focus.** One focus is written as `lastFocus`, as
before; several as `lastFoci`.

**An actor born during play can be built again from a save.** A snapshot
fills in a world that already exists, so an actor spawned after the level
loaded had nothing to be filled in when the save was loaded afresh.
`ActorSystem.spawn(entity:)` builds an actor under an entity a restore put
back, and `EcsWorld.vacant` says whether a slot is one: restore the
allocation, build each recorded actor under its own entity, restore again for
the numbers. Same index, same order, so a restored run thinks on the same beat
as the one that was saved.

**A rollback to before something was taken puts it back.** `Takeable.restore`
removed the trigger of a thing that had been taken and never re-added it, so a
rollback past a pickup left it drawn and untakeable for the rest of the run.

## 0.8.0

**A level can carry the recipe for a room in place of its brushes.** A
document's optional `recipes: [{kind, seed, params}]` list is read into
`Level.recipes` as `LevelRecipe`s and written back as it was, so an editor
that saves the level keeps the recipe. `expandRecipes(level)` turns them into
brushes, entities and lights, and everything that uses a level calls it: the
validator, the collision world, navigation, the lightmap bake and the
visibility bake, whose brush hash covers the expansion. `levelKits` has three
kits, each drawing its chances from `GameRandom` seeded with the recipe's
`seed`: `room` (walls with doorways cut in them, reflection probes and
optional clutter), `corridor` and `scatter`. A recipe no kit can build throws
a `LevelFormatException` naming it. A level without recipes reads, writes and
hashes as before.

**`LevelSketch` is the wall arithmetic the kits draw with.** It writes the rows
a document would, so a tool that generates level files can use the same code.
`roundDecimal` rounds on the exact binary value with ties to even, the rule
the shipped level documents were written with.

**`BrushGeometry.build(perBrush: true)` makes one surface per brush.** Each
`BrushSurface` then says which brush it is in `brush`, which is how a picture
can name the brush under a pixel. The default groups brushes by material as
before.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**A level without fog comes back without fog.** `Level.toJson` wrote
`fogColor` even when the document never named one, and wrote the default back
through float32, so a hand-written level failed a round trip on that key.

**A level light's `castsShadow`, when absent, follows its type.** A
directional light casts and a point or spot light does not. The renderer now
reads the flag on the sun, and a level that never named it, `map_a.json`
among them, keeps its sun shadow. `toJson` writes the key only when it
differs from that default.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

* **Breaking. A `Demo` carries what a replay is verified against.** The
  constructor requires `levelHash`, `buildStamp` and `checkpoints`, a
  `DigestTrace`, beside the level name, the start and the tape, and takes
  `platform`, `recordedBy` and `dataSources` as optional. `Demo.fromJson`
  throws `DemoFormatException` for a file without the first three, so a demo
  written by 0.6.0 does not open; `formatVersion` is still 1. With them a
  reader can tell that the level changed since the recording, and a replay can
  be compared checkpoint by checkpoint against the run it claims to repeat.
  `Demo.fileExtension` is `.f3drun`.
  `DigestTrace` gained `toJson` and `fromJson` for this, with
  `DigestTraceFormatException`, and `Level.digestHex` and `contentDigestHex`
  produce the eight hex digits a `levelHash` holds.
* **A level's ground is in its collision world.** `Level.addTo` adds the
  level's `Heightfield` as one static `CollisionHeightfield`, placed so that a
  ray fired down lands where `heightAt` says the surface is. It added the
  brushes and nothing else before, so a level whose ground was a field drew a
  hill that a body fell through. A level with no field gets what it always
  got. `Heightfield.copyOfSamples` is new and is how the shape gets its
  numbers without sharing a list with a field that may be edited.
* **Ground in tiles, at a level of detail chosen by distance.**
  `HeightfieldTiles(field, tileCells:, levels:)` cuts a `Heightfield` into
  tiles a power of two cells wide and builds any tile at any level as a
  `BrushSurface`, level `l` keeping every `2^l`-th sample. Seams are closed
  with skirts: each tile edge is copied straight down, so a tile's triangles
  never depend on its neighbours and a gap two levels open has ground behind
  it. The skirt depth is measured, the furthest any level's edge strays from
  the full-resolution line, doubled. Normals come from the full-resolution
  field at every level, so a seam does not show as a change of shade.
  `TileLevelChooser` gives level `l` out to `nearest * 2^l` metres with a band
  of 0.15 either side of each threshold, and keeps what a tile had inside the
  band. Not built: geomorphing between levels and tile streaming.
* **`HeadlessGame` and `HeadlessRun`: a game as a tool that plays it blind
  needs one.** A run answers `step`, `save`, `outcome`, `position`, `eye`,
  `aim`, a one-sentence `summary` and a `reading` as data; a game names its
  `buttons`, its `registry()` and how to `start` a level. They sit here,
  beside `RunOutcome`, because the tools live above the genres and a genre
  package depends on neither a tool nor anything that draws. Before this a
  tool imported one genre and called its types.
* **A value from outside the simulation is an input to the step that read
  it.** `EduDataSource.sample(step)` is a named stream sampled once per fixed
  step, `SamplerDataSource` is the deterministic one this package can prove
  without a socket, and `DataSourceRegistry.replace` swaps a source under the
  same name from that call on. `resolveBindings` reads an entity's `bindings`
  against the registry and answers target path to value; what a target means
  is the host's decision. `DataSourceTrace` records those values a step at a
  time the way `InputTape` records a controller, rides in `Demo.dataSources`,
  and `firstStepWhere(path, test)` finds the first step a recorded reading
  satisfies a condition.
* **`StepTimeTrace`: what each step cost, keyed by step number.** `record`
  times one call with a `Stopwatch` and `observe` takes a duration measured
  elsewhere; `every` defaults to 1. A step number survives a replay on another
  machine and a timestamp does not, which is why `DigestTrace` is keyed the
  same way.
* **`remapEntitySave` carries an `EcsWorld` save across an edited level.** It
  rewrites a `save()` document from the entity indices it was written at to
  the ones a reloaded level hands out, matching by name, and reports the names
  it could not place in `dropped`. `EcsWorld` is unchanged, since `restore`
  already reads any document shaped like its own save. `Actor.name`,
  `ActorSystem.spawn(name:)`, `ActorSystem.byName` and
  `ActorSystem.nameList()` are where the names come from.
* **An entity with no position stops gaining one on save.** `EntityDef.toJson`
  wrote `at` unconditionally, and four level documents with a non-spatial
  entity came back from a round trip with an invented `[0, 0, 0]`. It is
  written when the source had it or when the position is not zero, the way
  `yaw` and `name` beside it already were.
* Still plain Dart. The floor on `flutter3d_physics` is `^0.7.0`. The archive
  carries `skills/flutter3d-sim-fixed-step/` for a coding agent, installed
  with `dart run skills@ get`.

## 0.6.0

* **A floor, and no code.** The step, the ECS, levels, navigation, saves and
  replays are byte for byte 0.5.2's. The one line that changed is the floor on
  `flutter3d_physics`, now `^0.6.0`, and it is stated for the reason it was
  stated before: ground is split across the two packages — `Heightfield` here is
  the data, `CollisionHeightfield` there is what a body stands on — so a
  resolver free to reach further back would hand a caller the first without the
  second.
* Still plain Dart. Nothing here imports Flutter, and a server replaying a run
  needs no SDK to do it.

## 0.5.2

Ground made of samples, and a crowd that walks over it.

* **`Heightfield`: the first sloped ground this level format has.** A `Brush` is
  a box, so until now the only slope a level could describe was the ramp a wedge
  makes. A field is `columns * rows` heights, `cellSize` metres apart, with an
  `origin` where sample `(0, 0)` sits, and it answers `heightAt`, `normalAt` and
  `slopeAt` about the ground rather than building anything.
  The answers are about **the triangles that are drawn, not a bilinear sheet**.
  Four samples make a quad and a quad is two triangles, so a quad is only flat
  when its corners agree; interpolating bilinearly instead describes a surface
  nobody draws, and at the centre of a cell the two differ by a quarter of
  `h00 + h11 - h10 - h01` — a unit hovering over one half of the quad and sunk
  into the other. So the field finds the triangle the point is in. The split is
  fixed at `(0,0)–(1,1)` and written down once, because a mesh builder that
  chose the other diagonal would draw ground this class does not describe and
  the only symptom would be a body standing slightly in the air.
  `slopeAt` reports radians from flat and refuses to say what is walkable — a
  tank and a scout disagree about the same hillside — and it reaches for
  `Portable.atan2` rather than `math.acos`, because `acos` is the platform's
  libm and the rule *a step asks no machine for an answer* is what keeps a run
  verified in a browser agreeing with the run a player made.
* **A level can carry one.** `Level.heightfield` is an optional section, read
  and written by `Heightfield.fromJson` / `toJson`. The heights travel as base64
  of a `Float32List`'s bytes, the way `LevelVisibility` carries its cells:
  sixteen thousand samples spelled out as JSON digits is a megabyte nobody reads
  and every editor reformats. The four numbers a person might edit by hand stay
  plain.
* **`HeightfieldGeometry` emits a `BrushSurface`**, not a new type. Terrain is
  not a brush, but what the type holds is plain arrays, and the twenty lines in
  `flutter3d_bridge` that interleave them into a vertex layout do not care where
  the triangles came from — so ground draws with no new code downstream. Its
  normals are averaged from central differences while `Heightfield.normalAt`
  returns the triangle's own: one answers what the ground looks like, the other
  what a body is standing on, and the disagreement is the point.
* **`NavGrid.bakeHeightfield`: a second source for the same lattice.** `bake`
  measures its grid from brushes and stamps each cell with the solid under it;
  ground made of samples has no brushes and its extent is the field's own, so
  the two share the cell format and nothing else. Steepness is what makes ground
  unwalkable here — `maxSlope` defaults to 0.698 radians, a hair under forty
  degrees — with `blocked` for the ground refused for a reason that is not its
  shape.
  **The step height is derived from the slope rather than taken from a level.**
  On terrain the rise between neighbouring cells is not a ledge, it is the
  hillside the slope test just allowed, so the default is the tallest rise the
  steepest walkable cell can have: `tan(maxSlope) * cellSize * 1.001`, which is
  0.42 m at the default half-metre cell. Left at the 0.4 a level's bake uses, a
  two-metre grid over ground of one part in five puts a rise of 0.4 against a
  limit of 0.4 and lets float rounding decide: 112 of 240 uphill moves survived
  the comparison and the rest were called walls. The derived height allows all
  240, and the half-metre bake all 4032 of its own.

## 0.5.1

* **`Portable`: the transcendental functions a step is allowed to call.**
  `sin`, `cos`, `sinCos`, `tan`, `atan`, `atan2`, `asin` and `exp`, built out of
  `+`, `-`, `*`, `/`, `sqrt` and the bytes of a double — all of which the
  specification pins — so two platforms cannot disagree about them. That is not
  a theoretical worry: `parity_test.dart` swept twelve `dart:math` functions
  over twenty thousand arguments under the VM and under Chrome, and only `sqrt`
  and `pow` gave the same bits. A car built on the rest replayed differently in
  a browser at twenty-three checkpoints of forty, which is a verifying server
  that cannot verify. It is forty of forty now.
  Accuracy is held to two units in the last place against `dart:math` by
  `portable_math_test.dart`, because portable and wrong is a physics bug no
  parity test could report.
* **`solver_parity_test.dart`: the rigid-body solver replays bit for bit**,
  in a browser and on the VM. Predicted — `flutter3d_physics` calls no
  transcendental — and measured anyway, because the three ways it could still
  have diverged are the broadphase's ordering, a long chain of non-associative
  additions, and a browser's `int` being a `double` under the spatial grid.
* `Motion.easeFactor`, `Interpolated` and the actor system's facing now call it
  rather than `dart:math`. `tool/structure.dart`'s new rule *a step asks no
  machine for an answer* is what keeps them there.

## 0.5.0

**Breaking.** A step can say what happened, and four types stop being closed.

* **`GameEvent` and `GameEvents`: what a step did, drained by whoever owns
  it.** A buffer rather than a stream, because a stream delivers on a later
  microtask and two simulations here reproduce a recorded run exactly — an
  event arriving between two steps is the one state no replay can reproduce.
  `ActorSystem` writes into the simulation's buffer at the moment of a death,
  so a monster killed by this step's shot lands after the shot that killed it;
  two lists read afterwards can only say that both occurred. `ActorHurt` is
  now the event rather than a value copied into one, and `ActorDied` says who
  caused it. `StepEvents.has` and `.count` answer the two questions every
  reader asks of a drained step.
* **`Difficulty`: four axes a genre applies where it decides.** What the player
  is hurt by, what their attacks are worth, how quickly the opposition reacts,
  and how much of the genre's help is on. A value class rather than an enum, so
  a game writes its own — or builds one from a slider, which a list of four
  cannot express. `opponentReaction` is a duration, so the harder settings have
  less of it.
* **`ActivationOutcome` is open**, and `abstract base`. Nothing ever switched
  over its three cases exhaustively, so sealing bought nothing and cost a game
  the ability to say what happened at its own door.
* **`StepSystem` takes a `StepContext`.** A function type is frozen the day it
  is published; the context carries `dt` and the phase, which the old shape
  could not, and can grow a field instead of breaking every system.
* **`Difficulty`, `Powers`, `Scoring` and `RunStats`.** Four pieces every genre
  wanted and at most one of them had written. Powers came out of the shooter,
  which keeps every question it answered and delegates the counting. Scoring is
  the question a tally cannot answer — what those counts were *worth*, and
  whether they came close enough together to be worth more. RunStats counts
  events, and counts nothing until a game says what to recognise.
* **`CharacterController.groundNormal`** — it measured the floor's normal to
  decide whether the body was standing on it and threw it away, so nothing
  above could tell a flat floor from a ramp.

## 0.4.2

* **A brush can say how it casts, not only whether.** `shadowCasting` in the
  document is one of `on`, `off`, `doubleSided` or `shadowsOnly` — the engine
  has had four modes since `ShadowCastingMode` was written and the format had
  two, so the two it could not ask for were the two it most needed: both faces
  recorded, for a wall one brush thick whose lit side and dark side are a
  metre apart, and a proxy that casts without being drawn. `Brush.castsShadow`
  is now the two-state view of `Brush.shadowCasting` and goes on meaning what
  it meant, an unknown word is refused with the four in the message, and a
  document that said nothing goes on saying nothing. Surfaces are batched by
  the mode rather than by the boolean, because a batch is the smallest thing
  that can answer.
* **A breach keeps the baked light on the walls it did not touch.**
  `Breaches.origins` says which authored brush each current brush was cut out
  of, and `BrushGeometry.build(origins:)` uses it to find the planned face a
  piece's face is part of and measure its place inside it —
  `LightmapLayout.uvOfPoint` and `isOnPlane` are that arithmetic. Before it,
  redrawing a level after one hole meant no atlas at all and every wall in
  every room fell back to flat ambient at once. The faces the blast itself
  made take the neutral texel, which is the one part of a breached wall
  nothing ever baked.
* **A level can ask to be reflected.** `EntityTypes.reflectionProbe` is the
  format's word for a point a room is reflected from, and
  `ReflectionProbeKind` is the kind that validates one: `radius`,
  `intensity`, `faceSize`, `levels`, `near` and `far` are all optional and
  each is refused where the renderer would otherwise assert on it at load.
  The two planes are resolved against the probe's own defaults before either
  is judged, so a document naming only a near plane past two hundred metres is
  refused here rather than at load: the far plane it did not name is still a
  far plane. Pure data to the simulation — nothing spawns and nothing is
  revealed — and
  a word a game has to put in its own vocabulary, so a game without probes
  reads the entity as unknown rather than growing a reflection it did not
  ask for.

## 0.4.1

* **Lightmaps.** `LightmapLayout` unwraps every visible brush face onto a
  planar atlas from the level alone, so the baker and the geometry agree
  without a table; `LightmapBaker` bakes the light the walls throw on each
  other by gathering — direct light with shadows through the level's own
  collision world, then bounces along cosine-weighted rays — seeded by the
  texel, so two bakes are the same bytes. `Lightmap` stores RGBM in RGBA8
  with a hash of the brushes, lights and materials, and
  `dart run flutter3d_sim:bake_lightmap` writes `<level>.lightmap.bin`.
  `BrushGeometry.build(lightmap:)` hands every vertex its second coordinate.
* **Jump links.** `NavGrid.bake(jumps:)` finds the gaps and ledges a
  `JumpReach` clears; a `FlowField` filters them by its own body's reach with
  the body's width added, relaxes them backwards at their distance plus two
  cells so a walk of equal length wins, and `jumpAt` says when the next step
  is a jump. `Navigation.jumpAhead` and `ActorSystem` take off through the
  controller's buffered request on the take-off cell.
* `Mind.heading`, for turning to face the way the field said.

## 0.4.0

* First release. It is `flutter3d_game`'s inside, moved out whole: the fixed
  step, the entity store, the level format and its validator, saves, demos and
  the rewind buffer, world logic, actors, navigation, the camera rig and the
  maths. Nothing changed behaviour; the imports moved and the package boundary
  is new.
* **Plain Dart, and that is the reason it exists.** A server that verifies a
  submitted run has to replay it through the same simulation the player ran,
  and a Flutter SDK in that container is a blocker rather than an
  inconvenience. `flutter3d_game` keeps the eight files that reached Flutter —
  the touch and keyboard widgets, the `MediaQuery` read, the diagnostics sink —
  and re-exports this package, so no existing program changes a line.
* The boundary is a check, not a comment: `the simulation names no Flutter` in
  `tool/structure.dart` scans `lib/`, `test/` and `bin/`.
* `StateDigest` and `DigestTrace` come with it — a 32-bit digest over the bits
  of a snapshot, computed the same way in a browser as in the VM, and a
  checkpoint trace that names the first step two runs disagree at.
* `dart run flutter3d_sim:bake_visibility` moves here from `flutter3d_game`,
  where it had never needed Flutter either.
