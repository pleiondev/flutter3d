# flame_flutter3d

A bridge to the [Flame](https://pub.dev/packages/flame) 2D game engine. Flame
draws its own layer and flutter3d draws its own. This package keeps the two in
agreement on transforms, lifecycle, physics contacts, input and the actor
system; neither engine drives the other's renderer.

```dart
final camera = CameraNode(name: 'eye');

Flutter3dFlameWidget(
  game: MyFlameGame(),
  camera: camera,
  buildScene: (device) => Scene()..add(camera),
)
```

## One clock, two layers

`Flutter3dFlameWidget` composites a flutter3d `SceneSurface` beneath Flame's
own `GameWidget` in one `Stack`. Flame is on top because it needs raw input,
the same way the HUD layer of `apps/flutter3d_demo_platformer` does. Neither
engine's renderer is reimplemented. A `BridgeClock` component, added once to
the hosted `FlameGame`, calls back every frame after Flame's own components
have updated. A physics step, an actor system step and a camera sync all
advance from that callback, so a bridged game has one clock, the one Flame
already owns.

## One plane, everywhere a point crosses

`BridgePlane` is the single place where a Flame `Vector2` and a flutter3d
`Vector3` are the same point. `BridgePlane.ground(height:)` is for a top-down
game, where Flame's `y` becomes flutter3d's `z`; `BridgePlane.backdrop(depth:)`
is for a side-scroller, where Flame's `y` becomes flutter3d's own `y`. Every
bridged component takes one, so a game does not reinvent its axis convention
per component.

## The bridges

- Transform: `Object3dComponent` keeps a Flame `PositionComponent` and a
  flutter3d `SceneNode` at the same place, on one `BridgePlane`, in the
  direction a `SyncDirection` names (`sceneToFlame` or `flameToScene`). The
  direction is chosen once, at construction, and never inferred from which
  side changed more recently.
- The actor system: `ActorComponent` extends `Object3dComponent` to carry the
  body position of a `flutter3d_sim` `Actor` across the bridge.
  `ActorSystemComponent` holds the single `ActorSystem.beginStep()`/`step()`
  pair that every `ActorComponent` in a game shares, so the system is stepped
  once a frame however many actors are bridged.
- Physics: `RigidBodyComponent` extends `Object3dComponent` to carry the
  position of a `flutter3d_physics` `RigidBody` the same way.
  `CollisionBridge` re-fires flutter3d's `CollisionListener` events as
  Flame's own `CollisionCallbacks`, projecting a 3D contact point through the
  bridge's `BridgePlane` into the `Set<Vector2>` that Flame's callback expects.
- Input: `FlameInputBridge` translates Flame's own keyboard and drag
  callbacks into calls on the `Bindings`/`InputState` of `flutter3d_game`.
  `DesktopInput`/`PadInput` already write into those same objects, so a
  bridged game and a native one share one input model, one rebinding UI and
  one saved binding file.
- Camera: `CameraSyncController` keeps a flutter3d `CameraNode` (typically
  orthographic) and Flame's own `Viewfinder` framed the same, reconciling
  position and zoom in whichever direction is authoritative.

The `flame` pages of `apps/flutter3d_showcase` show one mechanism per page,
each with a step-by-step guide.
