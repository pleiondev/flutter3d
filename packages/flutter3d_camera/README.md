# flutter3d_camera

Virtual cameras for flutter3d games. A game registers every camera it might
look through, says how much each one wants to be shown, and the view moves
between them by itself: cut, ease, or a curve the game writes.

A virtual camera draws nothing. It is a framing, which says where the camera
wants to be, carried out by the engine's `CameraRig`, which eases without
overshoot, carries knocks and shakes that fade, honours the player's motion
setting and keeps the camera out of the walls. The rig was already the shared
half of every camera the engine's games had, so a game's camera that moved
onto this kept its feel: same rig, same numbers.

| Type | What it is |
|---|---|
| `VirtualCamera` | A named framing on a rig, with a `priority`, an `enabled` switch and an optional `blendIn`. Its `shot` is what it shows |
| `CameraDirector` | Picks the live camera (highest priority, newest on a tie), blends to the next, keeps a blended shot out of the walls, and shakes the result. Its `shot` is what to draw |
| `CameraBlend` | `cut`, `ease(seconds)`, `linear(seconds)` or `custom(seconds, curve)`. Per pair with `blendBetween('map', 'battle', ...)`, `*` for any |
| `CameraShot` | Eye, target, field of view and roll. Blending turns the view rather than sliding the target |
| `FollowFraming` | A fixed offset from a subject, with a dead zone and per-axis damping |
| `LookAtFraming` | Stands still and turns to watch, with the same dead zone and damping |
| `GroupFraming` | Several weighted subjects kept in the picture at once, fitted to the narrower field of view |
| `ChaseFraming` | Behind where a subject is going, looking up the road, wider with speed |
| `OrbitFraming` | A third-person orbit the player turns, drifting back behind a moving subject and aiming up its path |
| `OverheadFraming` | A view over a map that pans, zooms and rides the ground's height |
| `FirstPersonFraming` | Out of a head: no smoothing, no walls |
| `CameraImpulse`, `ImpulseShake` | Decaying gradient noise, felt less with distance, seeded by the step |
| `ImpulseTable`, `CameraPlugin` | Which events shake the view, and the plugin that runs the director in the frame phase `camera` |

## Using it

```dart
final chase = ChaseFraming();
final finish = LookAtFraming(from: Vector3(0, 4, -20));
final director = CameraDirector(world: world)
  ..add(VirtualCamera('chase', chase, world: world))
  ..add(VirtualCamera('finish', finish, priority: 1)..enabled = false)
  ..blendBetween('chase', 'finish', const CameraBlend.ease(1.2));

final loop = EngineLoop(
  input: input,
  plugins: [
    genre,
    CameraPlugin(
      director,
      impulses: ImpulseTable()
        ..on<Exploded>((e) => CameraImpulse(amplitude: 0.4, at: e.at)),
    ),
  ],
);

// Every frame, before the loop's frame: hand the framings their subjects.
chase
  ..position.setFrom(car.position)
  ..velocity.setFrom(car.velocity)
  ..facing = car.headingYaw
  ..speed = car.speed;
finish.subject.setFrom(car.position);

// After it: draw from the director's shot.
node
  ..setPositionFrom(director.shot.eye)
  ..lookAt(director.shot.target);
```

Switching `finish` on cuts nothing by hand: it outranks the chase, the
director blends to it over the pair's ease, and switching it off blends back.

## Manifest

`CameraPlugin`:

- **id** `flutter3d_camera`, or the one passed in, when one engine has
  two directors (a split screen);
- **apiVersion** 1.0;
- **touches** `view`, so switching it is not written into a replay;
- **backends** all of them;
- **permissions** none;
- **dependsOn** nothing.

It has no `flutter3d_plugins:` marker: it is built around the game's own
director and cameras, so discovery has nothing to construct.

## Determinism

Cameras are the view's. No step reads one, and nothing in a replay depends on
where a camera was; the walls are read through the world's rays, a read of
the simulation and never a write. The one part that has to agree between a
run and its replay is the shake, and it does: an impulse's noise is chosen by
the director's seed, the step that published the event and its place among
that step's events, and played back against the time since it arrived. A
rollback shakes nothing twice: an event handed out again as resimulated is
skipped unless `shakeCorrections` is set. The hash is multiplied in 16-bit
halves, so the noise is the same in a browser as on a device.

## The genres' cameras

Each of the four genre packages keeps its camera class and builds it on a
preset here: racing's `ChaseCamera` on `ChaseFraming`, the platformer's
`FollowCamera` on `OrbitFraming`, strategy's `MapCamera` on `OverheadFraming`,
and the shooter's `FirstPersonCamera` on `FirstPersonFraming`. Each exposes
`virtualCamera` for a director, and `aim` to hand it a frame's subject
without placing it.
