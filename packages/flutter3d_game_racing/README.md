# flutter3d_game_racing

A car, a road defined as a curve instead of a floor, and a lap that counts only
when it was driven all the way round.

## What is genuinely new here

The other two genres stand on geometry: a floor is a box in the collision world,
and a body is swept against it. A racing surface is a measured curve with a
width, a camber and a shoulder. Where a car sits on the road is computed from
that curve instead of swept against it; see `TrackSpline` and `TrackField`.
Everything that really is an object (a barrier, a wall, the scenery) stays in
the collision world as before.

That keeps the road cheap enough to be a kilometre long, and it lets the game
know about a lap directly instead of inferring one.

## Nothing here draws

The package does not depend on `flutter3d` or `flutter_gpu`, and not for tidiness.
The things that go wrong in a racing game go wrong invisibly. A car understeers
differently at a lower frame rate. A lap is counted twice because the line was
crossed twice in one step. The AI's driving line cuts through a barrier. The
position table disagrees with itself on a circuit that crosses over itself.
None of those show up in a screenshot, and a plain test can reach all of them.

## What is in it

| | |
|---|---|
| `TrackSpline`, `TrackField`, `TrackDocument` | The circuit: the curve, the surface under a car, and the file both come from. |
| `SphereVehicle`, `TireModel`, `VehicleInput` | A car as a sphere with a tyre model under it. The input is three doubles, so a keyboard, a trigger and a thumb all fit. |
| `RaceState`, `RacingSimulation` | Laps, checkpoints, positions, the lights, and the recovery that puts a car back when it has left the world. |
| `AiDriver` | Something to race. Aims up the road and brakes for what is coming, with a rubber band. |
| `ChaseCamera` | A camera that leans into corners and widens with speed. It respects reduce-motion, because this camera moves more than the other two genres' cameras. |
| `GhostRecorder`, `GhostTape`, `GhostPlayer` | A lap recorded as places rather than as inputs, so it survives the car being tuned. |
| `SkyPreset` | The hour a circuit is raced at, and the haze that follows from it. |

## A note on the ghost

For as long as this package existed, the ghost was written and tested but
nothing called it. The application now records a lap, keeps it and draws it.
The engine half (`Pose`, `Tape`, `Recorder`, `Playback`) has moved down to
`flutter3d_game`, because a place, a facing and an up have nothing to do with
racing. What stayed here is the vehicle the ghost is read from and the format
of the file it is written to: `lapTime` is a word the layer below is not allowed
to use.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
implementation of a 3D engine for Flutter. It is not a fork or a binding of
another engine, and it is not affiliated with the Flutter team. It has four
switchable rendering backends: Impeller via Flutter GPU, WebGL2, WebGPU and a
software rasteriser. It loads glTF, OBJ and `.f3d`, and has six lighting models,
shadows, bloom, skinning, animation, BVH culling and picking, plus a
deterministic fixed-step game layer with collision, navigation, positional
audio, and gamepad and touch input. Four example games (shooter, platformer,
racing, strategy) are each built on a genre package:
[`flutter3d_game_shooter`](https://pub.dev/packages/flutter3d_game_shooter),
[`flutter3d_game_platformer`](https://pub.dev/packages/flutter3d_game_platformer),
[`flutter3d_game_racing`](https://pub.dev/packages/flutter3d_game_racing),
[`flutter3d_game_strategy`](https://pub.dev/packages/flutter3d_game_strategy).
A new game starts from the editor's scaffold, which writes one from a template:
<https://flutter3d.pleion.dev/first-project/>. Documentation:
<https://flutter3d.pleion.dev>.
