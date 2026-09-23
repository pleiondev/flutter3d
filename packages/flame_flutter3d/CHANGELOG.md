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
