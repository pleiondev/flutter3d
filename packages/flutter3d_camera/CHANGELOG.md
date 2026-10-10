## 1.0.0-rc.1

- **Breaking: `CameraRig`, `PhotoCamera` and `RigSettings` are this
  package's**, moved from `flutter3d_sim`, which no longer exports them: a
  camera places a view and no step reads it, so the rig sits beside the
  virtual cameras that turn it. Import `package:flutter3d_camera/flutter3d_camera.dart`;
  `dart run flutter3d_build:migrate` adds the dependency and the import.
- **Breaking: the package is `flutter3d_camera`**, renamed from
  `flutter3d_addon_camera` before it was ever published, and its library is
  `package:flutter3d_camera/flutter3d_camera.dart`. `dart run
  flutter3d_build:migrate` moves the dependency and the imports. The
  plugin's id stays `flutter3d_addon_camera`, so an ordering constraint that
  names it still holds.
- **Breaking: a field of view is `fovY`**, in radians: `CameraShot.fov` and
  every framing's `fov` are `fovY`, and `baseFov` and `fovPerSpeed` are
  `baseFovY` and `fovYPerSpeed` (docs/CONTRACTS.md).
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `recentre` is `recenter`, `recentreAbove` is `recenterAbove`,
  `travelling` is `traveling`. Only the Dart names changed: a file keeps
  the keys it was written with, and `dart fix` carries the renames.
- **One camera system, many cameras.** `VirtualCamera` is a framing carried
  out by the engine's `CameraRig`, with a priority and an on switch.
  `CameraDirector` makes the highest enabled one live, a tie going to the one
  switched on last, and blends to the next by `CameraBlend`: a cut, an ease, a
  straight line, or a curve of the game's own, chosen per pair of cameras, per
  camera, or by default. A blend interrupted halfway goes on from the shot on
  screen rather than jumping back.

- **Framing by targets.** `FollowFraming` and `LookAtFraming` with dead zones
  and per-axis damping, and `GroupFraming`, which keeps several weighted
  subjects in the picture by fitting them to the narrower field of view.

- **The genres' cameras, as presets.** `ChaseFraming`, `OrbitFraming`,
  `OverheadFraming` and `FirstPersonFraming` are the racing, platformer,
  strategy and shooter cameras with their numbers and arithmetic unchanged;
  the four genre packages now build their cameras on them.

- **Clear of the walls, blended too.** Each camera's rig keeps itself out of
  the walls; the director does the same for a blended shot, which can pass
  through a wall neither camera is in.

- **Impulse shake seeded by the step.** `ImpulseShake` adds decaying gradient
  noise, nought at the moment of the blow, felt less with distance and scaled
  by the player's motion setting. Its noise is chosen by the step and the
  event's place in it, so a replay shakes the way the run did.

- **A plugin in the frame phase `camera`.** `CameraPlugin` places the
  director once a displayed frame and shakes it from events on the bus's
  frame channel through an `ImpulseTable`, as a view plugin on plugin API
  1.0.

- **`OrbitFraming`'s `pitch` and `yaw` are ordinary parameters**, copied
  into private fields, not private parameters (`this._pitch`), which put a
  private name in the API and needed the newest language version to call.
  Callers pass them as before.

