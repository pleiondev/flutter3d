## 0.7.1

**A level without fog comes back without fog.** `Level.toJson` wrote
`fogColor` even when the document never named one, and wrote the default back
through float32, so a hand-written level failed a round trip on that key.

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
