---
name: flutter3d-game-racing-track-and-car
description: Use when building a racing game on flutter3d — the circuit is a measured curve rather than collision geometry, and laps, positions and ghosts are known rather than inferred.
---

# A road that is a curve, not a floor

The other genres stand on geometry: a floor is a box and a body is swept against
it. **A racing surface is not geometry.** A circuit is a measured curve with a
width, a camber and a shoulder, and where a car is on the road comes out of the
curve rather than a sweep — `TrackSpline` and `TrackField`. Anything that is
really an object (a barrier, a wall, the scenery) stays in the collision world.

That is what makes a kilometre of road cheap, and what makes a lap something the
game knows rather than infers.

| | |
|---|---|
| `TrackSpline`, `TrackField`, `TrackDocument` | the curve, the surface under a car, the file both come from |
| `SphereVehicle`, `TireModel`, `VehicleInput` | a car as a sphere with a tyre model; the input is three doubles, so a keyboard, a trigger and a thumb all fit |
| `RaceState`, `RacingSimulation` | laps, checkpoints, positions, lights, and recovery when a car has left the world |
| `AiDriver` | aims up the road, brakes for what is coming, with a rubber band |
| `ChaseCamera` | leans into corners, widens with speed, answers reduce-motion |
| `GhostRecorder` | a lap recorded as places rather than inputs, over the engine's `Pose`, `Tape`, `Recorder` and `Playback` |

## Ask the track, not the collision world

`TrackField` answers with the distance along the curve, the offset across it and
what is underneath, which is what lap counting, position and the AI's line all
read. A lap counts when the checkpoints were passed in order, so crossing the
line twice in one step counts once and reversing over it gains nothing.

## Nothing here draws

No `flutter3d`, no `flutter_gpu` — because **the things that go wrong in a
racing game go wrong invisibly.** A car that understeers differently at a lower
frame rate. A lap counted twice because the line was crossed twice in one step.
A driving line the AI cuts through a barrier. A position table that disagrees
with itself on a circuit that crosses over itself. Every one is reachable from a
plain test and none appears in a screenshot.

## What a layer may say

A ghost is recorded as places rather than inputs, so it survives the car being
tuned. Its engine half — `Pose`, `Tape`, `Recorder`, `Playback` — is in
`flutter3d_game`, because a place, a facing and an up have nothing to do with
racing. What stays here is the vehicle it is read off and the shape of the file:
**`lapTime` is a word the layer below is not allowed to say**, and
`dart run tool/structure.dart` fails on a genre word appearing there.

Progression is not a `RunSession`: nobody resumes a race half a lap in, so its
two snapshot overrides would return nothing. Keep a season in the application.
