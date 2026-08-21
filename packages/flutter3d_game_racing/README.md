# flutter3d_game_racing

A car, a road that is a curve rather than a floor, and a lap that only counts
when it was driven all the way round.

## What is genuinely new here

The other two genres stand on geometry: a floor is a box in the collision world
and a body is swept against it. **A racing surface is not geometry.** A circuit
is a measured curve with a width, a camber and a shoulder, and where a car is on
the road is worked out from the curve rather than swept against it — see
`TrackSpline` and `TrackField`. Everything that is really an object — a barrier,
a wall, the scenery — stays in the collision world exactly as before.

That is what makes the road cheap enough to be a kilometre long, and it is what
makes a lap something the game knows about rather than something it infers.

## Nothing here draws

No `flutter3d`, no `flutter_gpu`, and the reason is not tidiness: **the things
that go wrong in a racing game go wrong invisibly.** A car that understeers
differently at a lower frame rate. A lap counted twice because the line was
crossed twice in one step. A driving line the AI cuts through a barrier. A
position table that disagrees with itself on a circuit that crosses over itself.
None of those appear in a screenshot and all of them are reachable from a plain
test.

## What is in it

| | |
|---|---|
| `TrackSpline`, `TrackField`, `TrackDocument` | The circuit: the curve, the surface under a car, and the file both come from. |
| `SphereVehicle`, `TireModel`, `VehicleInput` | A car as a sphere with a tyre model under it. The input is three doubles, so a keyboard, a trigger and a thumb all fit. |
| `RaceState`, `RacingSimulation` | Laps, checkpoints, positions, the lights, and the recovery that puts a car back when it has left the world. |
| `AiDriver` | Something to race. Aims up the road and brakes for what is coming, with a rubber band. |
| `ChaseCamera` | A camera that leans into corners and widens with speed — and answers reduce-motion, because this one moves more than the other two. |
| `GhostRecorder`, `GhostTape`, `GhostPlayer` | A lap recorded as places rather than as inputs, so it survives the car being tuned. |
| `SkyPreset` | The hour a circuit is raced at, and the haze that follows from it. |

## A note on the ghost

It was written, tested and called by nothing for as long as this package
existed. The application now records a lap, keeps it and draws it — and the
engine half of it (`Pose`, `Tape`, `Recorder`, `Playback`) has moved down to
`flutter3d_game`, because a place, a facing and an up have nothing to do with
racing. What stayed here is the vehicle it is read off and the shape of the file
it is written to: `lapTime` is a word the layer below is not allowed to say.
