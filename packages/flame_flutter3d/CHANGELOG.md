## 0.8.2

**A Flame turn on a ground plane is no longer drawn mirrored.**
`BridgePlane.rotationFor` took its sign from `Quaternion.rotated`, which
computes `q̄·v·q` and turns a vector by `-θ`, while a node is drawn through
its matrix, which turns by `+θ`. On `BridgePlane.ground` a Flame angle of
+0.5, clockwise on screen, was drawn anticlockwise; on a backdrop the two
sign flips cancelled and it came out right. `rotationFor` and `angleFor` now
both work through the matrix a node is drawn with, and a test checks where
the node is drawn on every plane, where the old ones only checked that an
angle survived the round trip, which it did either way. An
`Object3dComponent` syncing rotation `flameToScene` on the ground plane turns
the other way than it did, which is the way Flame means.

**Flame is updated once a frame, not twice.** The bridge redrew the 3D layer
with a `setState` on the whole `Stack`, which rebuilt `GameWidget` every
frame, and `GameWidget` calls `game.update(0)` from its layout whenever it is
rebuilt: every frame the game updated twice and `onTick` saw a second call
with a `dt` of zero. Now only the 3D layer is rebuilt, and the `GameWidget`
is made once per game, so a rebuild from above (a HUD beside it) does not
reach Flame either.

## 0.8.1

**An example to start from.** `example/` is the smallest hybrid game: a Flame
HUD over a 3D yard, a cube whose Flame position drives its scene node, and a
crate that falls under `flutter3d_physics` onto a trigger pad and reports the
landing through Flame's own `onCollisionStart`. It runs the physics step as a
Flame component, so the order within a frame is the component tree's.

The README is rewritten around what the bridge does. Nothing in `lib/`
changed.

It asks for `flutter3d` and `flutter3d_physics` `^0.8.1`, which bring the
contact-shadow and folded-cloth fixes; the rest of its `flutter3d_*`
dependencies stay at `^0.8.0`.

## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

**A bridge to the Flame 2D game engine.** Flame draws its own layer, flutter3d
draws its own, and `Flutter3dFlameWidget` composites the two in one `Stack`,
Flame's `GameWidget` above flutter3d's `SceneSurface` — the same ordering
`apps/flutter3d_demo_platformer` already uses for a HUD over a bare
`SceneSurface`, and for the same reason: on the web the 3D surface is a
platform view that swallows pointer events, so whatever needs raw input has
to sit above it. A single `BridgeClock` component rides Flame's own game
loop rather than starting a second ticker, so the two engines' frames never
drift apart.

`BridgePlane` is the one place a Flame `Vector2` and a flutter3d `Vector3`
are the same point — a ground plane or a vertical backdrop, chosen once and
shared by every bridged component rather than reinvented per caller.
`Object3dComponent` keeps a Flame `PositionComponent` and a flutter3d
`SceneNode` at the same place on one `BridgePlane`, in whichever direction a
`SyncDirection` names; `ActorComponent` and `RigidBodyComponent` extend it to
carry a `flutter3d_sim` actor's or a `flutter3d_physics` rigid body's own
position across the same seam, and `ActorSystemComponent` centralises the
one `ActorSystem.step` every `ActorComponent` in a game shares.
`CollisionBridge` re-fires flutter3d's collision events as Flame's own,
projecting a 3D contact onto the bridge's plane. `FlameInputBridge` reuses
`flutter3d_game`'s own `Bindings`/`InputState` — a bridged game and a native
one share one rebinding UI and one saved binding file, not two input models.
`CameraSyncController` keeps an orthographic flutter3d camera and Flame's own
2D viewfinder framed the same.
