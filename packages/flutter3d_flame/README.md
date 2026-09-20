# flutter3d_flame

A bridge to the [Flame](https://pub.dev/packages/flame) 2D game engine. Flame
draws its own layer, flutter3d draws its own, and this package keeps the two
reconciled — transforms, lifecycle, physics contacts, input and the actor
system — instead of one engine driving the other's renderer.

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
own `GameWidget` in one `Stack` — Flame on top, since it needs raw input the
same way `apps/flutter3d_demo_platformer`'s own HUD layer does. Neither
engine's renderer is reimplemented. A `BridgeClock` component, added to the
hosted `FlameGame` once, calls back every frame after Flame's own components
have updated — the one seam a physics step, an actor system step or a camera
sync advances from — so there is only ever one clock in a bridged game, the
one Flame already owns.

## One plane, everywhere a point crosses

`BridgePlane` is the one place a Flame `Vector2` and a flutter3d `Vector3` are
the same point: `BridgePlane.ground(height:)` for a top-down game, where
Flame's `y` becomes flutter3d's `z`; `BridgePlane.backdrop(depth:)` for a
side-scroller, where Flame's `y` becomes flutter3d's own `y`. Every bridged
component takes one, so a game does not reinvent its own axis convention per
component.

## The bridges

- **Transform** — `Object3dComponent` keeps a Flame `PositionComponent` and a
  flutter3d `SceneNode` at the same place, on one `BridgePlane`, in whichever
  direction a `SyncDirection` names (`sceneToFlame` or `flameToScene` —
  chosen once, at construction, never inferred from which side changed more
  recently).
- **The actor system** — `ActorComponent` extends `Object3dComponent` to
  carry a `flutter3d_sim` `Actor`'s body position across the bridge;
  `ActorSystemComponent` centralises the one `ActorSystem.beginStep()`/
  `step()` pair every `ActorComponent` in a game shares, so the system is
  stepped once a frame regardless of how many actors are bridged.
- **Physics** — `RigidBodyComponent` extends `Object3dComponent` to carry a
  `flutter3d_physics` `RigidBody`'s position the same way.
  `CollisionBridge` re-fires flutter3d's `CollisionListener` events as
  Flame's own `CollisionCallbacks`, projecting a 3D contact point through the
  bridge's `BridgePlane` into the `Set<Vector2>` Flame's callback expects.
- **Input** — `FlameInputBridge` translates Flame's own keyboard and drag
  callbacks into calls on `flutter3d_game`'s own `Bindings`/`InputState` —
  the same objects `DesktopInput`/`PadInput` already write into, so a
  bridged game and a native one share one rebinding UI and one saved binding
  file rather than two input models.
- **Camera** — `CameraSyncController` keeps a flutter3d `CameraNode` (typically
  orthographic) and Flame's own `Viewfinder` framed the same, reconciling
  position and zoom in whichever direction is authoritative.

See `apps/flutter3d_showcase`'s `flame` pages for one mechanism per page,
each with a step-by-step guide.
