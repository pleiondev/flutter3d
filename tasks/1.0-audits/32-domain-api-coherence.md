# 32. The domain packages read as one engine? (2026-10-15)

Branch `1.0.0` at `da3b09a6e`, read-only. The subject is the public
libraries of 29 domain packages, through their barrels and committed
snapshots: `flutter3d` (facade), `flutter3d_app`, `_sim`, `_physics`,
`_game_physics`, `_matter`, `_fields`, `_particles`, `_effects`, `_post`,
`_camera`, `_elements`, `_game`, `_game_kit`, the five genre kits,
`_audio` and `_audio_core`, `_net`, `_voxel`, `_mesh`, `_model_core`,
`_level_scene`, `_stereo`, `_education` and `flame_flutter3d`. That is
22,597 snapshot lines in 67 libraries. Where a subject signature hands the
user a type from elsewhere, that type was read too:
`flutter3d_physics_native` (through elements and effects), core's
`LightNode`, `RenderSettings` and `PhysicalCamera` (through the facade),
plugin_api's `EventRegistry`, and `flame_flutter3d_audio`.

Audits 25–28 checked the structure: modifiers, records, sealed sets,
naming rules and the HAL. Decisions 63–126 and wave 4.3 answer them. This
audit does not argue those again. It cites them where a domain finding is
one more instance of a decided item:

- 63, records in public signatures;
- 69, `release` to `dispose`;
- 70, `==` on settings;
- 75, the facade's `vector_math` and `Matrix4`;
- 76, `onCreated` everywhere;
- 77, the time vocabulary and its rule;
- 81, open sets.

It also does not repeat audit 29's file and wire findings (saves'
`requires`, replay checks).

No code was changed and no suite was run. Snapshot lines are cited as
`<pkg>.api:N`, short for `packages/<pkg>/api/<pkg>.api` with the
`flutter3d_` prefix dropped (`physics.api:896`, `pn.api` for
physics_native). Source lines are cited by path. Counts come from `rg`
over the snapshots. A count that matches on shape rather than meaning
says "heuristic".

Severity:
- **BLOCKER**: only a major can fix it after 1.0. That is the case where the
  meaning of an existing member is undecided or wrong against CONTRACTS, so
  any later fix changes behaviour silently.
- **BEFORE RC.1**: a rename or a shape change. It is cheap now with a
  `dart fix` migration. After the tag it needs a deprecation and a second
  name until 2.0.
- **ADDITIVE 1.x**: a minor can add it.
- **DOCS ONLY**: the API is fine; CONTRACTS or a doc comment must say it.

## Verdict

**At the level of types, the packages read as one engine. At the level
of a task, they read as three or four.** The type-level picture is
uniform:

- every options type is `…Settings`, and there is no `Options`, `Config`
  or `Params` type;
- constructors take named parameters, and builders are almost absent;
- `Registration` is the one unsubscribe;
- exceptions hang from the root, with `ArgumentError` and `StateError`
  for programmer errors;
- colours are `LinearColor`, and there are no degrees anywhere;
- matter's units table is complete;
- fields carry `Unit` and `WorldPosition`.

A user following a task meets parallel dialects instead:

- **The physics dialects.** The Dart reference speaks methods on a body,
  with live vectors and `orientation`. The native core and elements speak
  `world.verbOf(body)`, with copies, `WorldPosition`, `turn` and `spin`.
- **The scene and app side**, which has its own origin, callback and
  field-of-view words.
- **The genre kits**, which wrap both and alias their names (the racing
  kit's `GhostTape = Tape`).

**The units contract mostly holds**. Five places leave it:

- **Exposure.** `RenderSettings.exposure` is a linear multiplier, while
  CONTRACTS says exposure is EV100.
- **Elements' sun and glow.** They take light in the renderer's internal
  scale, neither lux nor nits.
- **Units in names.** A heat-release rate is in kW, a value named `rpm` is
  a 0–1 fraction, and a spin rate is in turns per second.
- **Gravity defaults.** About a dozen world-living types take gravity as a
  number that defaults to `standardGravity`. A game's 24 m/s² world never
  reaches them.
- **`step`.** It is a step number in 88 places and seconds in 14.

**Two blockers**, both of them decisions that the code cannot defer:

1. Whether a returned vector is live or a copy. Today both happen, inside
   one class.
2. What `exposure` means against CONTRACTS.

Below them come 18 BEFORE RC.1 findings: renames, shapes and units. Most
are an hour each with a migration. Six 1.x or docs items follow. There
are 15 questions at the end.

## 1. Vocabulary

One row per concept: the spellings found, then where. Counts are over the
29 subject snapshots.

| Concept | Spellings found | Where (file:line) |
|---|---|---|
| Put a body in a world | `add(RigidBody)`; `add(Collider)`, `addBox(center, size)`; `addBody({position})`; `addBody(Solid, {at})` returning `NativeBody` or `TrackedBody`; `register(Collider, component)` | physics.api:405, 309-310; pn.api:796; elements.api:211; effects.api:58; flame_flutter3d.api:173 |
| Take it out | `remove` (void); `removeLater`; `removeBody` (bool); `remove(Object thing)`; `unregister`; ECS `despawn` | physics.api:422, 338-339; pn.api:838; elements.api:227; effects.api:79; flame_flutter3d.api:174; sim.api:785 |
| A body handle | `RigidBody`, `Collider`, `NativeBody`, `ElementBody` (an extension type over an int), `TrackedBody`, `Follower`; the ECS components `Body` (a character controller) and `Physical` (a rigid body) | physics.api:875, 141; elements.api:18, 372; effects.api:46; sim.api:386, 2185 |
| Push it | `applyImpulse(i)`, `applyImpulseAt(i, worldPoint)`, no `applyForce`; a force only through `BodyForce.addForce(ctx)` and `ctx.add(fx, fy, fz)`; `world.addForce(body, f)`, `applyImpulse(body, i, {Vector3? at})`; `fields.addForce`, `applyImpulse(…, {WorldPosition? at})` | physics.api:896-898, 8, 25; pn.api:880, 885; elements.api:89, 94 |
| Read its motion | `body.velocity` (a live field) and `position` (a live getter); `world.velocityOf(body)` (a copy) and `positionOf` → `WorldPosition`, `localPositionOf` → `Vector3`; `fields.velocityOf`, `positionOf` → `WorldPosition` | physics.api:890; pn.api:823-827; elements.api:78-80 |
| Rotation | `rotation` (app, model_core, sim `BodyPose`, stereo: 8); `orientation` (physics, `RigidPose`: 3); `turn` (elements, effects, game_physics, and `LiquidBody.place(Matrix3 turn)`: 5) | sim.api:391; physics.api:895, 641; elements.api:211 |
| Angular velocity | `angularVelocity` (physics); `spin` (elements, effects, `NativeRagdoll`) | physics.api:887; elements.api:211; pn.api:675 |
| A box's size | `size`, full (`CuboidShape`, `CollisionWorld.addBox`, `CollisionWedge.size`); `halfExtents` (`CollisionBox`, `NativeShape.box`, `BoxEmitter`); `half` (`Solid.box`) | core.api:911; physics.api:310, 174, 288; pn.api:717; particles.api:8 |
| A capsule's length | `height`, the straight part (`CapsuleShape`); `halfHeight` (`CollisionCapsule`); `halfLength` (`NativeShape.capsule`, `Solid.capsule`) | core.api:672; physics.api:189; pn.api:718 |
| Cast a ray | `raycast(…, RayHit out)` → bool; `rayCast` → `NativeHit?` and `rayCastAll`, beside `NativeWorldRays.raycast` in the same package; `VoxelRays.raycast` → `VoxelHit?`; the distance is `distance`, `at` (`NativeHit.at`) or `fraction` | physics.api:322, 836, 981; pn.api:800, 791, 959, 497; voxel.api |
| Move the floating origin | `shiftOrigin(WorldPosition to)` (Scene, EngineLoop); `shiftOrigin(dx, dy, dz)`, a delta (ParticleSystem); `moveOriginTo(WorldPosition)` (CollisionWorld, NativeWorld); `followOrigin(scene)` → Registration; `shiftsPhysics(world)`; `shiftsWithOrigin(Vector3)` | core.api:4529; sim.api:860; particles.api:361, 339; physics.api:334, 340; pn.api:893; sim.api:816; app.api:126 |
| A world position in | `burstInWorld(…, WorldPosition, scene:)`; `placeAt(WorldPosition, origin:)`; `WorldPosition` given directly (`bodiesIn`, `positionOf`); `Vector3` of unstated space (`AudioScene.play(at)`, `addBody(at:)`, `waterAt`, `heatFluxAt`) | particles.api:257, 345; audio_core.api:53, 68, 85; elements.api:76, 203, 211, 218 |
| Advance time (decision 77) | `step(dt)`; `update(dt)`; `advance(dt)` as a frame with fixed sub-steps (particles, `FluidWorld`, `ImpulseShake`, `Mixer`); `advance()` as one step (net); `tick` (`Recorder`, `GhostRecorder`, `LoopbackParty`); `Elements.update` plus `draw` | particles.api:354, 362; physics.api:494; camera.api:182; net.api:12, 36, 137; sim.api:2377; racing.api:147; effects.api:83 |
| `step` as a name | `int step` (the step number): 88; `double step`: 14, of which seconds in `BodyForceContext.step` and `FluidWorld.step`, a fractional step in `SequenceView.cameraAt(double step)`, and `fixedUpdate(double step)` | physics.api:12, 24, 493; camera.api:285; flame_flutter3d.api:146 |
| Field of view | `fovY` (framings, stereo); `fieldOfView`, `minFieldOfView`, `maxFieldOfView` (`PhotoCamera`); `maxFov` (`ChaseFraming`, `ChaseSettings`); `extraFovY` | camera.api:253, 123; racing.api:113; stereo.api:103 |
| Hear an event | `Registration on*/listen*` (10); a single listener slot (`Collider.listener`, `Elements.listener`, `ElementsSimulation.listener`); constructor callback bundles without `on` (`ElementsListener`'s nine, `SimulationObserver`'s `replay/readings/restore/show`, `findParty(left:)`); bus `onStep/onFrame<T>`; `Stream` (2); `ValueListenable` (9) | physics.api:158; effects.api:69; elements.api:204, 184-192; net.api:235-238; sim.api:983-985 |
| A widget's frame callback | `onBeforeFrame: void Function(EngineFrame)` (`Flutter3dView`, `Scene3D`) and `onBeforeFrame: VoidCallback` (`SceneSurface`, `StereoSurface`); `onTick: void Function(double dt)` (Flame) and `onTick: VoidCallback` (stereo); `onRendererReady` beside `onCreated` | app.api:157, 550, 590; stereo.api:110, 62; flame_flutter3d.api:270-271 |
| Record and replay | ghost poses: `Recorder`/`Tape`/`Playback`, re-aliased `GhostRecorder`, `GhostTape = Tape`, `GhostPlayer = Playback`; deterministic: `InputTapeRecorder`/`InputTape`/`InputTapePlayback`, `Demo`, `DemoRecording`, `SideRecording`; `PoseRecorder`/`PoseRecord`; `OrderTapeRecorder`/`OrderTape`/`OrderTapePlayback`; `RewindBuffer` | sim.api:2371, 2962, 2194, 1439, 1410, 1432, 625, 2229, 2458; racing.api:140-149; game.api:386; game_physics.api:179; strategy.api:218-233 |
| Attach to a loop | `attach(loop)` void plus `detach()` (`DemoRecording`); `attach(loop)` → Registration (`RewindBuffer`); `install`/`uninstall` (plugins) | game.api:400-401; sim.api:2460 |
| Teardown | `void dispose()` 35; `Future<void> dispose()` 11 (audio backends and `Speakers`, `SimulationHandle`s, `XrDriver`, `DesktopInput`, `PartySession`); `close()` as a Future (`PeerWire`) and as void (`ObserverFeed`, `SimulationObserver`); `leave()`; `close3d`, `closeWith(release)` and `dispose` on one Flame mixin | audio.api:13, 28; sim.api:1463, 1852; net.api:39, 54, 240; flame_flutter3d.api:338-350 |
| Open | async `open` (CONTRACTS) beside synchronous `ElementsSimulation.open()`, `open3d(device)`, `openStrategyLevel`, `openRegistryFor`; `connect(Uri)` | elements.api:221; flame_flutter3d.api:345; strategy.api:461; game.api:1067; net.api:256 |
| A refusal | sealed answers (`SaveRead`, `SaveUpgrade`, `ServiceAnswer<T>`, `ScrubAnswer`, `TapeBisection`); `String? refusal` / `refusalOn` (3); `Future<bool>` plus `IssueSink` (12 `Future<bool>` in game); null | sim.api:2581, 2615, 627; strategy.api:170; net.api:264; game.api:862-865 |
| Gravity in | about 60 parameters and fields spelled `gravity` (`Vector3` or `double`) or `g`, defaults `= standardGravity` (heuristic), against `WorldProperties` taken by 12 packages | physics.api:113, 479; particles.api:350; education.api:213, 221; platformer.api:475 |
| A settings parameter's name | `settings` 25; aspect names (`loop`, `view`, `wind`…); `config` 21; `tuning` 15; `options` 5 (heuristic) | physics.api:29; racing.api:48, 393; sim (`NavMeshSettings config`); model_core (`ImportSettings options`) |
| A plugin class | `*Plugin` 16; `*Addon` 23 (post, and core's `RenderStepAddon`, `LightingModelAddon`, both `extends Flutter3dPlugin`) | post.api:7-; core.api:2412, 4256 |
| A registry's verb | `add` 64; `register` 8 (`SubsystemRegistry`, `LightingModels`, `LightTypes`, `DataSections`, `MaterialCompilerRegistry`); `declare` 3 (fields, events, element switches) | fields.api:179, 72 |

## 2. Journeys

### (a) Spawn a physics body, apply a force, read its velocity

**Dart reference.** The user writes
`RigidBody(world: collision, shape: CollisionBox(half), position: p, mass: 2)`,
then `dynamics.add(body)` (physics.api:875, 405). The body is built with
the world and then added to the dynamics: two steps, two receivers.

A force has no method. `RigidBody` has `applyImpulse`, `applyImpulseAt`
and `applyTorqueImpulse` (physics.api:896-898). A steady push means
subclassing `BodyForce`, adding it to `dynamics.forces` and calling
`context.add(fx, fy, fz)` with three doubles (physics.api:8, 25). That
context's `step` is the step's length in seconds (`body_force.dart`: "The
step being taken, in seconds"). Everywhere else `step` is the step
number.

Velocity is `body.velocity`, a live `final Vector3` (physics.api:890,
`rigid_body.dart:100`). Writing into it sets the body's velocity.

**Native core, reached through elements.**
`NativeWorld.addBody({position})`, then
`world.addForce(body, Vector3)`, `world.applyImpulse(body, i, {at})`,
`world.velocityOf(body)` (a copy) and `world.setVelocity`
(pn.api:796-949). There are three more second vocabularies:
`positionOf` returns a `WorldPosition` while `addBody` takes a `Vector3`;
rotation is `turn:` and angular velocity `spin:` (elements.api:211); and
the impulse point is a `Vector3` here and a `WorldPosition` in
`ElementFields.applyImpulse` (elements.api:94).

**The ECS.** The component that holds the rigid body is `Physical`. The
one called `Body` is a character controller (sim.api:386, 2185).

**Second vocabularies met: 7.** Body versus world receiver, impulse
without force, scalar triples, `step` meaning seconds, live versus copy,
`orientation` versus `turn`, and `Body` meaning a character.

### (b) Add a light with a physical intensity, and see it

`Light3D.sun()` is 15,000 lux and `Light3D.lamp()` is an 800 lm bulb
(app.api:265-272). Both match CONTRACTS. A light from a datasheet in
lumens has `LightNode.lumens` (core.api:2323) and `Photometric.fromLumens`
(core.api:3687), but no `Light3D.lumens` widget constructor.

Then the user exposes the frame. CONTRACTS:273 says "Exposure is in
EV100". The value that changes the picture is `RenderSettings.exposure`,
whose doc says "Linear multiplier applied before tone mapping … with
light intensity at a unitless 1.0" (`render_settings.dart:1669-1676`,
the pre-1.0 unit). The same applies to `RenderViewSettings.exposure` ("A
linear multiplier", `render_view.dart:307-310`). EV100 exists only on
`PhysicalCamera` (`ev100`, `atEv100`, `exposure`, `exposureScale`,
core.api:3690-3720), and nothing hands that camera to the settings.

A user who adds water through `Elements` then meets
`sun({along, light: LinearColor})`, "its colour times its intensity", in
the scene's light scale (`effects/lib/src/elements.dart:406-408`). That is
the third unit for the same sun.

**Second vocabularies met: 3.** Lumens only below the widget layer,
exposure as a multiplier against an EV100 contract, and sun light in
internal units.

### (c) Play a sound at a body

`AudioScene.play(sound, Vector3 at, {follow: PoseSource})` or
`attach(sound, PoseSource pose)` (audio_core.api:84-85): two ways to do
one thing.

`PoseSource` is `Matrix4 Function()` (audio_core.api:237). That puts the
`Matrix4` trap (decision 75) into the audio API. A physics body has no
`Matrix4`: `RigidBody` gives a `Vector3` and a `Quaternion`, and
`NativeWorld` gives a `WorldPosition`. Elements' own follower takes
`RigidPose Function()` (elements.api:205), a second pose-function type.

`at` is "in metres" with no space (`audio_scene.dart:282`). The emitter's
`placeAt` takes `WorldPosition` and an explicit `origin:`
(audio_core.api:53), which is a different world entry point from
particles' `burstInWorld(…, scene:)`. The Flame bridge's
`play(sound, {Vector3? at})` makes `at` optional and named
(`flame_flutter3d_audio.api:8`).

**Second vocabularies met: 4.** Two calls for one thing, a pose as a
matrix versus a `RigidPose`, an unstated space, and the position named
and positional.

### (d) Record a run and replay it

A user looking for "record" in `flutter3d_sim` finds `Recorder`, `Tape`
and `Playback` first (sim.api:2371, 2962, 2194). Those are ghost-pose
recorders: `Recorder.tick(time, position:, yaw:)` and
`Tape(poses, seconds)` with both `seconds` and a `duration` getter. The
racing kit renames them by typedef (`GhostTape = Tape`,
`GhostPlayer = Playback`, racing.api:140-149) and adds a `GhostRecorder`
with the same members.

The deterministic replay is `InputTapeRecorder`, `InputTape` and
`InputTapePlayback` (sim.api:1439, 1410, 1432), wrapped by `Demo`, which
`DemoRecording` in `flutter3d_game` builds (game.api:386).

`flutter3d_app` re-exports `InputTapeRecorder` but neither `InputTape`
nor `InputTapePlayback` (app.api:1126 show list). The quickstart's two
imports can record and cannot play.

`DemoRecording.attach(loop)` returns void and has `detach()`
(game.api:400-401). `RewindBuffer.attach(loop)` returns a `Registration`
(sim.api:2460). The strategy kit has a third
recorder/tape/playback triple (`OrderTape*`, strategy.api:218-233). It is
consistent with the input one, which is good. `SideRecording`
(game_physics.api:179) is a fourth recorder.

**Second vocabularies met: 4.** Generic names on the ghost tools, a
typedef layer, a half export, and two attach shapes.

### (e) Hear that two bodies collided

There are five ways, in five shapes:

1. `Collider.listener`, a single slot holding a `CollisionListener` with
   `onCollisionStart/onCollision/onCollisionEnd` (physics.api:158, 239).
2. `ContactEvent` (`'physics.contact'`) on the bus through
   `events.onStep<ContactEvent>(label, handler)`, carrying `int bodyA,
   bodyB` that must go back through `Dynamics.bodyOfId` (sim.api:551-569).
3. `Dynamics.contacts`, a list read after the step.
4. `NativeWorld.readContacts()` and `readEvents()` (pn.api:788-789).
5. On elements, `ElementsListener`'s nine callback fields without `on`,
   set into a single `listener` slot (elements.api:184-204). Its
   `ElementsListener.toBus` factory is the bridge to the bus.

**Second vocabularies met: 3.** A slot versus a Registration, ids versus
bodies, and callbacks with and without `on`.

## 3. Findings

### BLOCKER

**1. Whether a returned vector is live or a copy is undecided, and both
happen inside one class.** The subject snapshots have 216 public `final`
fields of type `Vector2/3/4`, `Quaternion`, `Matrix3/4` or `Aabb3`, and
100 getters of those types (heuristic: a getter's body is not in the
snapshot). Sampled getters:

- `PhotoCamera.eye => _eye` hands out private state, so writing into it
  moves the camera past its collision. `PhotoCamera.target` returns a new
  vector (`camera/lib/src/photo_camera.dart:100, 123`). Neither doc says
  which.
- `RigidBody.position => collider.position` is live
  (`rigid_body.dart:98`). `NativeWorld.positionOf` and `velocityOf` are
  copies. `WorldProperties.gravity` and `wind` clone
  (`matter/lib/src/world_properties.dart:93, 126`).
- `CameraRig.eye`, `target`, `OverheadFraming.focus` and
  `ParticleGlow.center` return private fields.

CONTRACTS and the API docs say nothing (`rg` for "live" or "copy" in
`docs/` finds nothing). After 1.0, each getter's current behaviour is
what someone depends on, so making them consistent either way is a
silent break.

*Fix:* decide the rule and write it in CONTRACTS ("Space"):

- a public `final` vector field is the owner's live state;
- a getter and an `…Of(x)` query return a copy the caller owns;
- a parameter vector is read and never kept.

Then make the private-state getters `clone()`, or rename them as fields.
The heuristic count of `get x => _x` over vector types in subject `lib/`
is the list to work through. A rule locks it (§4).

**2. `exposure` contradicts the units contract.** CONTRACTS:273 says
"Exposure is in EV100". `RenderSettings.exposure` (default 1.6),
`RenderViewSettings.exposure` (default 1.0), `FrameResult.exposure` and
`PhotoCaptureReport.exposure` are linear factors in the renderer's scale.
`RenderSettings`' doc still describes the pre-1.0 "unitless 1.0" light
(`render_settings.dart:1669-1676`). A user lighting in lux who reads the
contract writes `exposure: 12` (an overcast EV100) and gets a white
frame. Changing the unit of the field after 1.0 silently changes every
picture.

*Fix, one of two, decided now:*
- (a) Amend CONTRACTS: "exposure is a linear factor; a photographic
  exposure is `PhysicalCamera` (EV100), and `PhysicalCamera.exposure` is
  the factor it gives". Rewrite the doc, and add
  `RenderSettings.copyWith(exposure: camera.exposure)` to the light
  guide.
- (b) Make the field EV100, with a migration that converts the literals.

(a) is docs only.

### BEFORE RC.1

**3. One body, three dialects (journey a).**
- `RigidBody` has no `applyForce`. Steady forces go through `BodyForce`
  and `BodyForceContext.add(fx, fy, fz)` (physics.api:8, 25).
- The impulse point is `applyImpulseAt(i, worldPoint)` (physics.api:897),
  `applyImpulse(body, i, {Vector3? at})` (pn.api:885), and
  `applyImpulse(body, i, {WorldPosition? at})` (elements.api:94).
- `BodyForceContext.moveTo(time, x, y, z, vx, vy, vz)` takes seven
  positional doubles (physics.api:26).

*Fix:*
- Add `RigidBody.applyForce(Vector3)` and `applyTorque(Vector3)`,
  accumulated until the next step (additive).
- Fold `applyImpulseAt` into `applyImpulse(i, {Vector3? at})` with a
  migration, so the Dart and C cores read alike.
- Give `BodyForceContext` `Vector3` views beside the scalars (additive).

The native shape is the one 1.0 should call the engine's for worlds. See
question 3.

**4. The ECS names a character `Body` and a rigid body `Physical`**
(sim.api:386, 2185). A reader of `world.get<Body>(e)` expects a rigid
body.

*Fix:* rename them (question 4) with migrations.

**5. `step` is a count in 88 places and seconds in 14.** Seconds:

- `BodyForceContext.step` (physics.api:12, 24);
- `FluidWorld.step` (physics.api:479, 493);
- `Ballistics.aim(step: 1/60)` (elements.api:8);
- `fixedUpdate(double step)` (flame_flutter3d.api:146, 199, 295, 309,
  391).

A fractional step: `SequenceView.cameraAt(double step)` and `fadeAt`
(camera.api:285-286).

*Fix:* `dt` for seconds, which is decision 77's own exception, and
`atStep` for the fractional one. The decision 77 rule should also say
"`step` is an `int`".

**6. Rotation and angular velocity have two spellings each.**
`orientation` is used by physics and `RigidPose`, `turn` by elements,
effects and game_physics (`addBody(turn:)` is a named parameter),
`rotation` by the scene graph and widgets. Angular velocity is
`angularVelocity` in physics and `spin` in elements and effects.

*Fix:* `orientation` for a simulated body, `rotation` for a scene node
(the split already holds in core), `angularVelocity` everywhere, with
migrations for the named parameters.

**7. Gravity is a number with a default where CONTRACTS says it is read
from the world.** World-living types that take their own gravity:

- `ClothSettings.gravity` is a `double = standardGravity`
  (physics.api:113, 122), while `ClothSettings.inWorld(world)` exists
  beside it.
- `FluidWorld(gravity: required Vector3)` (physics.api:479), and every
  liquid's `step(gravity:)`.
- `ParticleSystem.gravity` is a `double` setter (particles.api:350),
  while `ParticleGravity.world()` reads the world.
- `Runner(gravity: double?)` (platformer.api:475).
- `PendulumSimulation(gravity: standardGravity)` and
  `PendulumLabRun(gravity: …)` (education.api:213, 221).

The structure rule "a world's gravity, air and sea are read from the
world" checks literals, so `= standardGravity` passes. A platformer at 24
m/s² gets cloth and pendulums at 9.81 unless the author finds each
default. Changing a default after 1.0 is a behaviour change. Pure
formulas (`fallTime(g:)`, `jurinHeight(…, g)`, `pipeFlow(g:)`) are right
to take `g`.

*Fix:* world-living types read `WorldProperties` (from their
`CollisionWorld`, or as a required parameter), and the scalar versions
lose their default. Extend the rule (§4).

**8. Light outside the light types is in the renderer's scale.**
- `Elements.sun({along, light})` and `LiquidLook.sun` take "colour times
  intensity" (`elements.dart:406-408`, `liquid_look.dart:139-141`).
- `LiquidLook.glow` is "linear, in the scene's light"
  (`liquid_look.dart:154-157`).
- The public extension type `LiquidParameters` exposes `sunColor`,
  `glow`, `zenith` and `horizon` as `Vector3` (effects.api:203-215).

None is lux, nits or a `LinearColor` colour. CONTRACTS lists what is in
lux and nits, and these are missing from it.

*Fix:* `sun({required Vector3 along, LinearColor color, required double
illuminance})` in lux, and `glow` in nits, converted inside through
`FrameContext.nitsPerHdrUnit`. `LiquidParameters` moves to `internal.dart`
or answers `LinearColor`. See question 10.

**9. Names carry units outside the contract, and the rule cannot see
them.**
- `SmokePlume.centerlineSpeed(double kw, …)`, `depth`, `halfWidth`,
  `virtualOrigin` (elements.api:346-352) and `FireView.plumeDepth(double
  kw, …)` (effects.api:132) are in kilowatts.
- `VehicleController.rpm` is "the engine's speed, from nought to one"
  (racing.api:403, 513; `vehicle_controller.dart:136`). It is named after
  a unit it is not in.
- `ParticleSpin(turnsPerSecond)` is turns, not radians.
- `PendulumSimulation(lengthMeters:)` sits beside
  `PendulumLabRun(startLength:)`.
- SI unit words used as parameter names: `kelvin` (7), `joules` (4),
  `kilograms` (3) in elements and effects. CONTRACTS ("Names") says a
  contract unit is not in a name.

The kW one is a semantic choice. A positional parameter's name is free to
change, but the number's unit is not.

*Fix:* heat release in watts. `rpm` becomes `engineSpeed`, a fraction.
`ParticleSpin(rate)` in rad/s, with a migration that multiplies by 2π.
`length` replaces `lengthMeters`. Parameter names say what, not the unit
(`temperature`, `heat`, `mass`). Extend `unitSuffix` (§4).

**10. The ghost recorder owns the generic names, and the app exports
half of replay (journey d).**

*Fix:*
- In sim, rename `Recorder`, `Tape` and `Playback` to `GhostRecorder`,
  `GhostTape` and `GhostPlayback`. Drop racing's typedefs and
  `GhostRecorder` duplicate, and give `GhostTape` one length,
  `seconds`.
- `DemoRecording.attach` returns `Registration`, as `RewindBuffer`'s
  does, and `detach` goes.
- `flutter3d_app` shows `InputTape` and `InputTapePlayback` beside the
  recorder.

Audit 29 #26 (the playback taking a `Demo`) lands in the same class.

**11. Five ways to hear a contact, and the event style decision 6 set is
not the one users meet (journey e).** E.9 and decision 6 allow
`Registration on*/listen*` and `Stream`. The subject packages add:

- single listener slots: `Collider.listener`, `Elements.listener` and
  `ElementsSimulation.listener` (physics.api:158; effects.api:69;
  elements.api:204);
- callback bundles without `on`: `ElementsListener` (9 fields) and
  `SimulationObserver(replay:, readings:, restore:, show:)` (net.api:235-238).

A slot holds one subscriber and silently replaces the last one. Turning a
setter into a `Registration` after 1.0 is a break.

*Fix:*
- `Collider.onContact(listener) → Registration` (or a list of listeners);
- `ElementsSimulation.listen(ElementsListener) → Registration`, with the
  slot removed;
- event callbacks spelled `on…` (`onCaught`, `onReadings`), strategy
  hooks left as they are (`applyInput`, `restore`);
- `ContactEvent` keeps ids for the wire and gains
  `bodyIn(RigidDynamics)`.

**12. One callback name, two signatures, and decision 76 stops at
`Scene3D`.**
- `onBeforeFrame` is `void Function(EngineFrame)` on `Flutter3dView` and
  `Scene3D` (app.api:157, 550), and `VoidCallback` on `SceneSurface` and
  `StereoSurface` (app.api:590; stereo.api:110).
- `onTick` is `void Function(double dt)` on Flame (flame_flutter3d.api:271)
  and `VoidCallback` on `LessonStereoView` (stereo.api:62).
- `Flutter3dFlameWidget.onRendererReady` (flame_flutter3d.api:270) is the
  `onCreated` of decision 76 under another name.

Widget props otherwise agree. `position`, `rotation`, `scale`, `visible`,
`children` and `name` come through `Spatial3D`. `ReflectionProbe3D` has
`near/far` where views say `depthNear`.

*Fix:*
- the surfaces' callback becomes `onBeforeDraw` (it fires before a draw,
  not an engine frame);
- stereo's `onTick` becomes `onFrame`;
- Flame's `onRendererReady` becomes `onCreated`;
- the probe takes `depthNear`/`depthFar`.

Rule in §4.

**13. A save that cannot be read answers null, against CONTRACTS.**
CONTRACTS:345-346: "A newer file is refused with a sentence … a reader
never answers null for it." `SaveFile.read()` and `readRecord()` are the
same call twice. Both answer `Future<SaveRecord?>`, null for "nothing,
newer, or broken", and the reason goes to `onIssue` (game.api:862-863;
`save_file.dart:105-117`). The sealed `SaveRead` (`SaveFound`/`SaveNotRead`,
sim.api:2569-2591) already says this properly, one layer down. Writes
answer `Future<bool>` (12 in game.api).

*Fix:* `SaveFile.read() → Future<SaveRead>`, with `readRecord` dropped.
`SettingsFile.read` falls back to defaults rather than null
(game.api:935), which is a sound answer for settings and can stay. Writes
may stay `bool`, with a doc that says what false means. The null-as-error rule misses this
(§4).

**14. The floating origin has five verbs (vocabulary row 11).** One of
them is a delta of three doubles where the others take an absolute
`WorldPosition`.

*Fix:*
- `shiftOrigin(WorldPosition to)` on everything that holds scene-space
  state, so `CollisionWorld.moveOriginTo` and `NativeWorld.moveOriginTo`
  are renamed;
- `ParticleSystem` takes `shiftOrigin(to)`, keeping its origin, and its
  delta form becomes private;
- `followOrigin(scene) → Registration` is the subscription, and
  `EngineLoop.shiftsPhysics` and `CollisionWorld.shiftsWithOrigin` are
  renamed to it.

**15. A synchronous `open`, and allowlist reasons that promise a rename.**
CONTRACTS ("Names"): "a device or a session is opened (open,
asynchronous)". `ElementsSimulation.open()` is a synchronous factory
(elements.api:221), and its twin `Elements.open` is async
(effects.api:74). `openStrategyLevel` and `openRegistryFor` sit in
`verbAllowed` with reasons that say "becomes a `create`" and "its name
says neither" (`tool/structure/repository.dart:3839-3841`), the same
trap audit 25 found in `_recordResultsPending`. `open3d` is not seen at
all.

*Fix:* the unnamed constructor `ElementsSimulation()`,
`createStrategyLevel`, `registryFor`, and `open3d` kept with a Flame
lifecycle reason. Rule in §4.

**16. Field of view has four spellings.** `PhotoCamera.fieldOfView`,
`minFieldOfView` and `maxFieldOfView` (camera.api:253, 259-261),
`ChaseFraming.maxFov` and `ChaseSettings.maxFov` (camera.api:123;
racing.api:113), and `fovY` everywhere else.

*Fix:* `fovY`, `minFovY` and `maxFovY`, with migrations. Audit 03's 3.3
(`yfov`) goes with them.

**17. Shape sizes are half or full by package, and a capsule's height
means three things** (vocabulary rows 8 and 9). `NativeShape.capsule` and
`Solid.capsule` take `halfLength` positionally, so renaming it to
`halfHeight` is free.

*Fix:* rename the positional names. Add one sentence to CONTRACTS
("Space"): "a size is the whole extent; `half…` is half of it; a
capsule's height is its straight part".

**18. `rayCast` beside `raycast`, and a hit distance named `at`.**
`NativeWorld.rayCast` and `rayCastAll` (pn.api:791, 800) sit beside
`NativeWorldRays.raycast` (pn.api:959) and the Dart core's `raycast`.
`NativeHit.at` is the distance (pn.api:497). That is the package reached
through elements.

*Fix:* `raycast` and `raycastAll`, and `NativeHit.distance`.

**19. `Future<void> dispose()` on 11 types beside 35 synchronous ones,
and `close()` both ways.**
- Audio's `SoLoudBackend`, `Speakers` and `AudioBackend` (audio.api:13,
  28; audio_core.api:16); `SimulationHandle`, `IsolateSimulation` and
  `LocalSimulation` (sim.api:1463, 1852, 2784); `XrDriver` (app.api:822);
  `DesktopInput` (game.api:413); `PartySession` and `RoomSession`
  (game_physics.api:112, 239).
- `PeerWire.close()` is a Future, while `ObserverFeed.close()` and
  `SimulationObserver.close()` are void.

A caller who writes `x.dispose();` without `await` in a widget's
`dispose` gets an unawaited future and no lint. CONTRACTS ("Names") gives
`dispose` and `close` meanings but no sync/async rule. See question 12.

### ADDITIVE 1.x

**20. Discoverability from the facades.**
- `flutter3d_app` re-exports `CollisionWorld` but not `RigidBody`,
  `Dynamics` or `Collider` (app.api:1114).
- `flutter3d` exports `flutter3d_matter` (`WorldProperties`) but not
  physics.
- `Light3D` has no `lumens` constructor, while `LightNode.lumens` has one.
- A user of the quickstart's two imports can declare a world and cannot
  put a body in it without a third import.

*Fix:* add `Light3D.lumens`. Either widen the app's physics `show` list
to the types its shown members name (rule in §4), or say in the
quickstart that physics is `flutter3d_physics`.

**21. World entry points come in three patterns** (vocabulary row 12).
Particles take `*InWorld(WorldPosition, scene:)`, audio takes
`placeAt(WorldPosition, origin:)`, and elements and the native core take
a `WorldPosition` directly on queries but a `Vector3` of unstated space
on `addBody(at:)`, `waterAt` and `heatFluxAt`.

*Fix:* add `AudioScene.playInWorld`, `ElementsSimulation.addBodyInWorld`
and similar, through `Scene.toScene`. Each `Vector3 at` doc names its
space, as CONTRACTS "Three spaces" asks. The docs part can go before
rc.1.

**22. Physical quantities are typed in one call and bare in its
neighbour.** `HostField.quantityAt → Quantity` but `sample → double`
(fields.api:127, 131). `ElementFields.quantityOf → Quantity` but
`temperatureOf → double` (elements.api:77, 86). Both are fine. The doc of
the bare one should name the typed one, and the reverse. Docs only.

**23. Records in domain parameters.**
- `addBody(collides: ({int layer, int mask})?)` (elements.api:211;
  effects.api:58);
- `waterAt → ({WaterBody water, NativeShallowSample sample})?`
  (elements.api:203);
- `FireView.wanted → List<(String, int, int)>` (effects.api:119);
- `ChunkKey` and `VoxelBox` typedefs (voxel.api:7-9).

These are covered by decision 63, which forbids records in public
signatures. They are listed here so that 4.3A's inventory includes the
parameter side.

**24. Instances of decision 77 that its rule must catch.**
- `ParticleSystem` has both `advance(dt)` (a frame, cut into fixed
  sub-steps) and `step(dt)` (one step) (particles.api:354, 362). Under 77
  the frame one is `update`.
- `FluidWorld.advance(elapsed) → int`, `ImpulseShake.advance` and
  `Mixer.advance(seconds)` are `update` too.
- `EngineRollback.advance()` and `RollbackSession.advance()` are one step,
  so they become `step()`.
- `Recorder.tick`, `GhostRecorder.tick`, `LoopbackParty.tick` and
  `LoopbackWire.tick` go.
- The subjects have about 66 bare time doubles (`time` 26, `elapsed` 13,
  `clock` 5, `duration` 2…) against 21 `*Seconds` (heuristic: `length`
  is sometimes spatial).

No new decision is needed. This is input for 4.3B.

**25. Smaller vocabulary drift.** See question 13.
- Registries `add` (64) or `register` (8).
- Settings parameters named `config` (21), `tuning` (15) and
  `options` (5) rather than `settings` or an aspect name (heuristic).
- `*Addon` (23) beside `*Plugin` (16) for the same base class.
- Event-table query verbs differ: `ImpulseTable.impulsesFor`,
  `ReactionTable.react` and `CueSheet.listen`. `listen` elsewhere returns
  a `Registration`.

## 4. What the structure rules claim and cannot see

| Rule (`tool/structure/rules.dart`) | What it misses | Rule that would lock the fix |
|---|---|---|
| "no public name carries a unit the engine does not use" (`naming.dart:380`, `unitSuffix`) | Reads only angle and time suffixes. `kw`, `rpm`, `turnsPerSecond`, `lengthMeters` and unit words as parameter names (`kelvin`, `joules`, `kilograms`) pass (finding 9) | Extend `unitSuffix` with non-SI multiples and miscounts (`Kw`, `kw`, `Kilowatt`, `Kmh`, `Mph`, `Rpm`/`rpm`, `Turns`, `Celsius`, `Fahrenheit`, `Grams`, `Cm`, `Mm`, `Meters`, `Percent`). Add a second detector for a parameter named exactly a contract unit word. Allowlist with reasons (`cutoffHz`, `…Decibels`) |
| "a world's gravity, air and sea are read from the world" | Literals only. `= standardGravity`, `standardAirDensity` and `standardAtmosphere` defaults on world-living constructors pass (finding 7) | Flag a public constructor or settings default equal to a `standard*` world constant outside `flutter3d_matter`. Allowlist top-level formulas (`fallTime`, `jurinHeight`, `pipeFlow`) |
| "a light's intensity is lux or candela, not the pre-1.0 unit" | Watches `intensity` literals. `sun(light:)`, `glow`, `LiquidParameters` and the exposure doc are invisible (findings 2, 8) | A public parameter or field named `sun*`, `light`, `glow`, `exposure`, `illuminance` or `luminance` outside core's light and camera types must be in an allowlist naming its unit. Also a doc rule: an `exposure` doc says "linear" or "EV100" |
| "a type has one teardown verb, and creation has its own verbs" (`naming.dart:275`) | `verbAllowed` reasons promise "becomes a `create`" (`repository.dart:3839-3841`). A synchronous `factory X.open()` is not read. `open3d` is not seen. `Future<void> dispose()` passes (findings 15, 19) | (a) A reason may not say "becomes", as decided for records in 63. (b) The detector reads factories and `open\w*`. (c) `dispose` returns `void` unless listed (question 12) |
| "a reader throws where it fails, and answers null only for absent" (`nullAsErrorIn`) | `Future<SaveRecord?> read()` with "never throws" passes (finding 13) | Include `Future<T?>` results of `read*`/`load*`. A `nullAsErrorAllowed` reason for a file reader must name the sealed result it chose not to use |
| decision 76's rule (to be written in 4.3A) | Covers `onSceneCreated` only. Not `onRendererReady`, and not one name with two types (finding 12) | **New**: "a callback name has one type": collect `final <T> onX` across every snapshot and fail when a name has two `T`s. Plus a synonym table for creation callbacks (`onRendererReady`, `onReady`, `onSceneCreated` → `onCreated`) |
| decision 77's rule (to be written in 4.3B) | As decided, it cannot see `double step` (finding 5) | Add: "a member or parameter named `step` is an `int`" |
| decision 6 / E.9, two event styles | No rule. Listener slots and `on`-less callback bundles pass (finding 11) | **New**: "no public setter or mutable field holds a listener": fail on `set \w*[Ll]istener(`, on mutable fields typed `…Listener`, and on `final void Function(<X>Event)` fields not named `on…`. Strategy hooks are listed |
| none | Synonyms across packages (findings 6, 14, 16, 18) | **New**: "one concept, one spelling": a table in `naming.dart` of preferred and refused spellings (`orientation`/`turn` for bodies; `angularVelocity`/`spin`; `raycast`/`rayCast`; `fovY`/`fieldOfView`/`fov`; `shiftOrigin`/`moveOriginTo`; `halfExtents`/`half`), failing on a refused spelling in any snapshot, with an allowlist |
| none | Live versus copy (finding 1) | **New**, over `lib/` source (the snapshot cannot see bodies): a public getter of a `vector_math` type whose body is a bare private field fails unless its doc says "live". An `…Of(` query returning one must not return a field |
| "a facade names what it leaves out of the library under it" | Checks that a `show` list is decided, not that it is whole. `InputTapeRecorder` is shown without the `InputTape` its `tape` getter returns (finding 10, 20) | **New**: "a facade shows every type its shown members name": the type closure of a `show` list's signatures is in the list, or the type is in the facade's own exports, or it is listed |
| none | `Future<bool>`/`IssueSink` versus sealed answers (finding 13) | Fold into the null-as-error rule above. The `Future<bool>` write shape stays, and is listed with its doc |

## 5. What is good and should stay

- **One options word.** 25 `*Settings` types in the subjects, and not one
  `Options`, `Config`, `Params` or `Tuning` type. `Descriptor` only in
  the HAL, `Spec` only for registry declarations.
- **Constructors with named parameters, almost no builders.** The one
  builder, `ReactionBuilder`, exists to collect output while rules run,
  not to configure.
- **Event tables agree on `on<T>(rule)`.** `ImpulseTable`,
  `ReactionTable` and `CueSheet` all register typed rules the same way,
  and the bus's `onStep<T>`/`onFrame<T>` match them.
- **Ownership is written down.** Elements' `open`, `adopt` and `over`
  say who steps and who disposes (`elements/lib/src/simulation.dart:945-951`,
  `effects/lib/src/elements.dart:211-266`). Plugins pair `install` and
  `uninstall`. Every registration returns a `Registration`.
- **Errors split cleanly.** Of the `throw`s sampled in physics,
  elements, audio, camera, particles, net and the genres, programmer
  errors are `ArgumentError` and `StateError`, and domain refusals are
  typed exceptions under the root (`EffectFormatException` 45,
  `LevelFormatException`, `UnsupportedCapabilityException`). Only
  effects has one `UnsupportedError`.
- **Colour.** `LinearColor` in every domain signature except effects'
  `LiquidParameters` (finding 8). Flutter `Color` stays in widgets and
  game screens.
- **Angles.** No degrees in a signature. `halfAngle`, `maxSteer`, `tilt`
  and `widen` are radians and their docs say so.
- **Matter is a model of the units contract.** `WorldProperties` with
  `==`, cloning getters, and a `Patch`. `FieldQuantity` and `Unit` carry
  dimensions. Constants carry their SI names (`standardAtmosphere`,
  `stefanBoltzmann`).
- **Event names live under areas** (`physics.contact`,
  `elements.caught`, `racing.*`), all listed in `reservedAreas`
  (`plugin_api/lib/src/manifest.dart:378-380`).
- **The strategy kit's `OrderTapeRecorder`/`OrderTape`/`OrderTapePlayback`**
  mirrors the input tape exactly. That is the shape finding 10 asks of the
  ghosts.

## Questions for Dmitrii

1. **Is a returned vector live or a copy?** *Recommended:* a public `final`
   vector field is the owner's live state; a getter and an `…Of` query
   return a copy; a vector parameter is never kept. Write it in CONTRACTS
   ("Space"), make the getters that hand out private state clone, and lock
   it with the source rule in §4. *Alternative:* everything may be live,
   documented once in CONTRACTS ("clone what you keep"), and each getter's
   doc says so. This is cheaper now and costs allocation-free reads
   nothing, but it freezes `PhotoCamera.eye`'s write-through as API.
2. **Exposure: amend the contract or the field?** *Recommended:* amend
   CONTRACTS. `exposure` is a linear factor, EV100 is `PhysicalCamera`'s,
   and the light guide shows `copyWith(exposure: camera.exposure)`.
   Rewrite `RenderSettings.exposure`'s doc. *Alternative:* make
   `RenderSettings.exposure` EV100 now, with a migration that converts
   literals (`ev100ForExposure`) and `PhysicalCamera` as its default.
3. **Which body dialect is the engine's?** *Recommended:* the world-verb
   shape (`world.addForce(body, f)`, `velocityOf`) for the native core
   and elements. `RigidBody` keeps methods, because it is the reference
   and the body owns its state, but gains `applyForce`/`applyTorque` and
   `applyImpulse(i, {at})`. `orientation` and `angularVelocity`
   everywhere, so `turn:` and `spin:` are renamed with migrations.
   *Alternative:* keep three dialects, each documented in its package's
   README as "the X core speaks Y".
4. **Rename the ECS `Body` and `Physical`?** *Recommended:* `CharacterBody`
   and `RigidBodyComponent`, with migrations. *Alternative:* keep the
   names and say in their docs which body each holds.
5. **The ghost tools: rename and drop the typedefs?** *Recommended:*
   `GhostRecorder`, `GhostTape` and `GhostPlayback` in sim. Racing's
   typedefs and second recorder go. `DemoRecording.attach` returns a
   `Registration`. The app exports the whole input-tape triple.
   *Alternative:* keep `Recorder`/`Tape`/`Playback`, and have their docs
   open with "a ghost, not a replay: see `InputTapeRecorder`".
6. **Listener slots and `on`-less callbacks: break now?** *Recommended:*
   yes. `Collider.onContact` and `ElementsSimulation.listen` return a
   `Registration`, the slots go, event callbacks are spelled `on…`, and
   the §4 rule holds it. *Alternative:* amend E.9 to allow a third style,
   "a single listener slot, replaced on set", documented on each slot.
7. **One type per callback name?** *Recommended:* yes. The surfaces' hook
   becomes `onBeforeDraw`, stereo's `onTick` becomes `onFrame`, and
   Flame's `onRendererReady` becomes `onCreated` under decision 76's
   rule, extended. *Alternative:* keep the names and document the two
   signatures. Then no rule can say "one name, one meaning".
8. **Units outside the contract: convert or allow?** *Recommended:*
   convert. Heat release in W, `rpm` becomes `engineSpeed`, spin in
   rad/s, and unit words leave parameter names (`kelvin` becomes
   `temperature`). Extend `unitSuffix`. *Alternative:* allow a published
   correlation's own unit (Heskestad's kW) when the name carries it
   (`heatReleaseKw`) and the entry is in an allowlist, and rename only
   `rpm`.
9. **Gravity defaults on world-living types?** *Recommended:* those types
   read `WorldProperties` (or take it as required), scalar `gravity`
   parameters lose their `standardGravity` default, and the rule catches
   `= standard*` defaults. *Alternative:* keep the defaults and document
   on each that it ignores the world unless set. The platformer and
   racing kits then have to remember every one.
10. **Elements' sun and glow: lux and nits, or the scene's light?**
    *Recommended:* `sun({along, color, illuminance})` in lux and `glow`
    in nits, converted inside, with `LiquidParameters` moved to
    `internal.dart`. *Alternative:* drop `Elements.sun` and `sky`, and
    have the water read the scene's directional light and sky preset
    each frame. That gives one source of truth, but it costs a scene
    lookup per draw.
11. **`SaveFile.read` returns `SaveRead`?** *Recommended:* yes, with
    `readRecord` dropped. `SettingsFile.read` keeps its fall-back to
    defaults. `onIssue` stays for logging. *Alternative:* keep `null` and amend CONTRACTS for
    saves and settings only: "a save that cannot be read is a fresh start,
    not a refusal".
12. **Asynchronous teardown: `dispose` or `close`?** *Recommended:*
    `dispose()` is synchronous everywhere, as Flutter's is. An end that
    must await is `close()` returning `Future<void>`. The 11
    `Future<void> dispose()` become `close()`, and `ObserverFeed` and
    `SimulationObserver.close` become `Future`s or `dispose`.
    *Alternative:* allow `Future<void> dispose()` and say in CONTRACTS
    that a caller awaits it, with `unawaited_futures` on in the template's
    lints.
13. **The small vocabulary batch: do it now?** *Recommended:* yes for
    `register` → `add` on the 8 registries and for `config`, `tuning` and
    `options` → `settings` or an aspect name on 41 parameters. Keep
    `*Addon`, documented as "a plugin that adds render steps" in
    CONTRACTS ("Plugins"). *Alternative:* none of it; add one paragraph
    to CONTRACTS ("Names") listing the accepted synonyms.
14. **The floating origin's verbs?** *Recommended:* `shiftOrigin(WorldPosition
    to)` on every holder of scene-space state (the two `moveOriginTo`
    renamed, and `ParticleSystem` keeping its origin), and `followOrigin`
    → `Registration` as the one subscription (`shiftsPhysics` and
    `shiftsWithOrigin` renamed). *Alternative:* keep them and add a table
    to CONTRACTS "Space" that maps each verb to its holder.
15. **Synchronous `open` and `verbAllowed`'s promises?** *Recommended:* do
    the renames the allowlist promises now (`ElementsSimulation()`,
    `createStrategyLevel`, `registryFor`). Keep `open3d` with a Flame
    lifecycle reason. Forbid "becomes" in an allowlist reason.
    *Alternative:* amend CONTRACTS so that `open` may be synchronous for
    an in-memory session, and rewrite the reasons to say why each stays.
