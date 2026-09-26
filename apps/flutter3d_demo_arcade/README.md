# Meteor Yard

A top-down ship over a 3D yard. It uses every bridge in
`packages/flame_flutter3d` at once, so the demo exercises the package rather
than importing it and doing nothing with it.

```
flutter run -d macos
```

WASD or the arrow keys fly the ship. Three drones patrol the yard; three hits
end the run, and the elapsed survival time is the score. Clearing every drone
wins.

## Which bridge does what

- Transform: `ShipComponent` (a `RigidBodyComponent`) keeps the ship's
  flutter3d collider and its Flame position in step, on one `BridgePlane`.
- ECS: three drones are `flutter3d_sim` `Actor`s wrapped in `ActorComponent`.
  They patrol under a `PatrolBrain` that an `ActorSystem` actually steps (via
  `ActorSystemComponent`); nothing animates them by hand.
- Physics: the ship's `RigidBody` and every drone's `CharacterController`
  share one `CollisionWorld`. A `CollisionBridge` on the ship's collider
  relays a contact into Flame, which flashes the ship and clears the drone.
- Input: `FlameInputBridge` translates Flame's keyboard events into the same
  `Bindings`/`InputState` pair that `flutter3d_game`'s `DesktopInput` would
  write into.
- Camera: `CameraSyncController` keeps an orthographic flutter3d camera
  framed on wherever Flame's `Viewfinder` follows the ship to.

The doc comments in `lib/main.dart` and `lib/src/arcade_game.dart` explain the
non-obvious design calls, in particular why a drone is an `ActorComponent` and
never a `RigidBodyComponent`.
