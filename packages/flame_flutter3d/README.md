# flame_flutter3d

A bridge to the [Flame](https://pub.dev/packages/flame) 2D game engine. Flame
runs the game and draws its own layer; flutter3d draws the 3D one under it.
This package keeps the two in agreement on transforms, lifecycle, physics
contacts, input, the camera and the actor system, and neither engine drives
the other's renderer.

```dart
class MyGame extends FlameGame with HasFlutter3d {
  late final JetComponent jet;

  @override
  void onOpen3d() {
    scene.add(LightNode(name: 'sun'));
    jet = JetComponent(node: SceneNode(), scene: scene);
    add(jet);
    add(ChaseCameraComponent(ChaseCamera(
      camera: camera3d,
      target: jet,
      offset: Vector3(0, 10, 10),
      lookOffset: Vector3(0, 0, -8),
    )));
  }
}

// In the widget tree:
Flutter3dFlameWidget(game: myGame)
```

## One clock, two layers

`Flutter3dFlameWidget` puts a flutter3d `SceneSurface` under Flame's own
`GameWidget` in one `Stack`. Flame is on top because it needs raw input.
Neither renderer is reimplemented. A `BridgeClock`, added once to the game,
calls back every frame after Flame's components have updated, and the 3D
frame is drawn from there. A bridged game runs on Flame's clock and no
other.

A game with the `HasFlutter3d` mixin owns its 3D world. Its `scene`,
`device`, `camera3d`, `renderer` and `projector` are fields of the game; it
builds the world in `onOpen3d` and uses the renderer in `onRenderer3d`, each
once, after the game has loaded. The widget then needs only the game. A game
without the mixin passes a `camera` and a `buildScene` instead, as before.

## One plane, everywhere a point crosses

`BridgePlane` is the one place a Flame `Vector2` and a flutter3d `Vector3`
are the same point. `BridgePlane.ground(height:)` is for a top-down game,
where Flame's `y` becomes flutter3d's `z`; `BridgePlane.backdrop(depth:)` is
for a side-scroller, where it stays `y`. Every bridged component takes one.

## What crosses

`Object3dComponent` keeps a Flame `PositionComponent` and a scene node in
one place, in the direction a `SyncDirection` names. Flame's effects reach
the scene in the frame they happen, and a component nested under another
lands where Flame draws it. `elevation` lifts it off the plane; scale,
visibility, `opacity` and a `tint` cross as well, and a component under a
hidden parent is hidden in 3D too. A component that did not move writes
nothing, so it causes no shadow redraw. `visual` is a node under it that
the game turns and the bridge leaves alone.

For many small things of one shape, `InstancedObject3dComponent` takes a
slot in a shared `InstancedMeshNode`, so a hundred shots are one draw.

`ChaseCamera` follows a bridged component in perspective through
`flutter3d_sim`'s `CameraRig`, which can also shake it.
`CameraSyncController` keeps an orthographic camera and Flame's
`Viewfinder` framed the same.

`BridgeProjector` says where a scene point is drawn, for a score over a
target, and which point of the plane is under a touch. Under a perspective
camera Flame's own tap test misses what the player sees, so a component
with `Tap3dCallbacks` hears a tap on its drawing and `Taps3dComponent`
hands each tap to the nearest one. `debugHitboxes3d` draws every hitbox in
the scene, round its craft.

`FlameInputBridge` translates Flame's keys, drags, touch stick
(`followJoystick`) and buttons (`bindButton`) into `flutter3d_game`'s
`Bindings` and `InputState`, the objects a native game's input writes.

`RigidBodyComponent` and `ActorComponent` carry a body across.
`PhysicsStepComponent` and `ActorSystemComponent` step the shared world
once, in fixed steps, and a component handed its stepper is drawn between
two steps. `CollisionBridge` re-fires contacts as Flame's
`CollisionCallbacks`, and `ColliderRegistry` says which component a
collider belongs to.

`ChunkStreamer` builds the pieces of a world that come into view and lets
go of those that leave it. `Particles3dComponent` runs a
`flutter3d_particles` pool on Flame's clock, additive for fire and
darkening for smoke.

`BridgePriority` names the order all of this updates in, and the
components take it by default.

Sound is in [`flame_flutter3d_audio`](https://pub.dev/packages/flame_flutter3d_audio),
a package of its own so that a game without sound does not carry SoLoud.

`apps/flutter3d_demo_river` (River Sortie) uses most of this package;
`apps/flutter3d_demo_arcade` the physics side. The `flame` pages of
`apps/flutter3d_showcase` show one mechanism per page.
