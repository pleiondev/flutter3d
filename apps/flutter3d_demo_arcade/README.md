# Meteor Yard

A top-down ship over a 3D yard, built to exercise every bridge in
`packages/flutter3d_flame` at once — not a toy that imports the package and
does nothing with it.

```
flutter run -d macos
```

WASD or the arrow keys fly the ship. Three drones patrol the yard; three hits
end the run, and the elapsed survival time is the score. Clearing every drone
wins.

## Which bridge does what

- **Transform** — `ShipComponent` (a `RigidBodyComponent`) keeps the ship's
  flutter3d collider and its Flame position in step, on one `BridgePlane`.
- **ECS** — three drones are `flutter3d_sim` `Actor`s wrapped in
  `ActorComponent`, patrolling under a `PatrolBrain` genuinely stepped by an
  `ActorSystem` (via `ActorSystemComponent`), not animated by hand.
- **Physics** — the ship's `RigidBody` and every drone's `CharacterController`
  share one `CollisionWorld`; a `CollisionBridge` on the ship's collider
  relays a contact into Flame, which flashes the ship and clears the drone.
- **Input** — `FlameInputBridge` translates Flame's own keyboard events into
  the same `Bindings`/`InputState` pair `flutter3d_game`'s `DesktopInput`
  would write into.
- **Camera** — `CameraSyncController` keeps an orthographic flutter3d camera
  framed on wherever Flame's own `Viewfinder` follows the ship to.

See `lib/main.dart`'s own doc comment and `lib/src/arcade_game.dart`'s for the
non-obvious design calls — in particular, why a drone is an `ActorComponent`
and never a `RigidBodyComponent`.
