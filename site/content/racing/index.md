---
description: What flutter3d_game_racing adds — a track as a measured curve rather than geometry, a sphere-and-frame car, a Pacejka-shaped tire, lap counting that cannot be cheated, AI drivers and ghosts.
---

# What a racing game adds

The third genre, and the first one where the ground stops being geometry.

A shooter and a platformer both stand on brushes: axis-aligned boxes in a collision world, swept against. A track is not that. It is a measured curve with a width and a camber, and the surface under a car is worked out from the curve instead of found by a sweep. Everything that is really an object — barriers, kerbs, scenery — stays in the collision world as before.

| Taken from core, unchanged | Brought by this genre |
|---|---|
| The fixed step, `CollisionWorld`, `Dynamics` | `TrackSpline`: the road as a curve with width, bank and surface bands |
| `CatmullRom` in `flutter3d_game/src/math` | `SphereVehicle` and `TireModel`: how a car holds the road |
| Mechanisms, movers, the level format | `RaceState`: laps, checkpoints, positions, the lights |
| `CameraRig` | `ChaseCamera`, `AiDriver`, `GhostRecorder` |

Nothing in the package imports the renderer. `bridge.dart` turns a track into meshes and is the one file that does.

## The track is a curve, not a floor

```dart
final track = TrackSpline(
  centre: CatmullRom(points, closed: true),   // metres, measured
  widths: widthPerControlPoint,               // one per control point
  banks: bankPerControlPoint,                 // camber, in radians
  shoulder: 4.0,                              // how far the ground continues
  surfaces: <SurfaceBand>[...],               // tarmac, kerb, gravel, by arc length
  barriers: <BarrierBand>[...],               // which sides have a wall, and where
  checkpoints: <double>[...],                 // in order round the lap
  grid: const StartGrid(columns: 2, rowGap: 8.0, columnGap: 4.0),
);
```

Everything a car needs is a question asked at an arc length `s`:

| Call | Answer |
|---|---|
| `frameAt(s, out)` | Position, forward, right and up at that point, camber included |
| `widthAt(s)` | Full road width there, kerb to kerb |
| `bankAt(s)` | Camber in radians |
| `surfacePoint(s, lateral, out)` | A point on the road surface, `lateral` metres off the centre |
| `surfaceAt(s, lateral)` | Which surface that is — the name a grip table looks up |
| `barrierAt(s, left: true)` | Whether there is a wall on that side there |
| `startSlot(i, position, forward)` | Where car `i` starts on the grid |
| `length` | A lap, in metres |

The constructor validates rather than trusting: one width and one bank per control point, every width positive, and checkpoints in order round the lap. That last one matters because a lap counter walks them in turn.

## Ground comes from a field, not a sweep

```dart
abstract interface class GroundField {
  bool sample(Vector3 position, double nearHint, GroundSample out);
}
```

`TrackField` implements it over a `TrackSpline`, with a `CollisionWorld` behind it for everything the curve does not describe. Ask it where the ground is and it answers with a point, a normal, an arc length and a surface name — or falls back to a probe against the world when the car has left the road.

`nearHint` is the last known arc length. Without it, finding the nearest point on a closed kilometre-long spline is a global search every frame for every car.

## The car is a sphere with a frame drawn on it

`SphereVehicle` is a collider that rolls, plus a heading and a basis assembled for the renderer. Not a four-wheel rig: there is no suspension per corner and no wheel that can leave the ground on its own.

```dart
final car = SphereVehicle(
  world: collision,
  ground: field,
  tuning: const VehicleTuning(
    radius: 0.6,
    rideHeight: 0.35,
    maxSpeed: 62.0,
    maxReverse: 12.0,
    enginePush: 14.0,
    brakeStrength: 26.0,
    rollingDrag: 0.6,
    airDrag: 0.42,
    maxSteer: 0.62,      // radians at a standstill
    steerFalloff: 0.55,  // how much of it is left at speed
    wheelBase: 2.6,
    gravity: -22.0,
    gripLimit: 14.0,
    groundStick: 26.0,
    suspensionRate: 9.0,
    slideAlignment: 6.0,
    wheelInertia: 0.5,
  ),
  tires: const TireModel(...),
  grips: const GripTable(<String, double>{
    'tarmac': 1.0, 'kerb': 0.85, 'gravel': 0.45, 'grass': 0.35,
  }),
);

car.step(dt, input);
```

`VehicleController` is the interface the rest of the genre talks to, so a four-wheel model can replace this one without the simulation, the AI or the camera noticing:

```dart
Vector3 get position;      Vector3 get velocity;
double get headingYaw;     Matrix3 get visualBasis;
double get speed;          double get slipAngle;
double get slipRatio;      bool get grounded;
double get rpm;            double get trackDistance;
Collider get collider;
void step(double dt, VehicleInput input);
void placeAt(Vector3 position, double headingYaw, {double? trackDistance});
```

`VehicleInput` is a throttle, a brake, a steer and a handbrake — not a forward and a back. `GameAction` is a string for exactly this reason: a car's controls are not a walker's.

## The tire is a curve, not a friction coefficient

```dart
final tires = TireModel(peakSlipAngle: 0.14, peakSlipRatio: 0.12, ...);

tires.lateralAt(slipAngle);       // cornering force, normalised
tires.longitudinalAt(slipRatio);  // drive and brake force
TireModel.clampToCircle(force, limit);  // you cannot have all of both
```

A curve that rises to a peak and falls away past it is the whole of why a car can be driven over the limit and caught. A constant coefficient gives a car that grips until it does not, with nothing in between.

`clampToCircle` is the friction circle: lateral and longitudinal force share one budget, so braking into a corner costs cornering and there is no setting that makes both free.

`GripTable` scales the whole curve by what is under the wheels, which is where the track's surface bands arrive.

## Laps that cannot be cheated

```dart
final race = RaceState(
  mode: RaceMode.race,       // freeRoam · timeTrial · race
  track: track,
  racers: 4,
  laps: 3,
);
```

`RacerProgress` is derived once per step from where a car is, and none of it is stored on the car — a car does not know what a lap is, which is what makes `RaceMode.freeRoam` work at all.

| Field | |
|---|---|
| `s` | Distance round the lap, in metres. Wraps at the line |
| `lap` | Complete laps, counted only when every checkpoint was passed on the way round |
| `nextCheckpoint` | The one this car is driving towards |
| `wrongWay` | True while the car has been going backwards long enough to mean it |
| `offRoad` | True while the car is off the racing surface |
| `lateral` | Metres from the centre line |
| `lapTime`, `bestLap` | In simulated seconds |

<div class="why">
<p>Checkpoints exist for one reason. Without them a car can drive ten metres past the finish line, turn round and cross it forwards again, for a lap a second. The line only counts when every checkpoint has been passed since the last crossing, in order.</p>
</div>

`RacePhase` is `countdown`, `running` or `finished`. During the countdown a car may rev and may not move: the throttle reaches the wheels, and the velocity is zeroed after the step.

## The step order, for the third time

```dart
void step(double dt) {
  //  1. clear last step's flags, so nothing reads an event twice
  //  2. run the lights
  //  3. mechanisms move, reindex, dynamics
  //  4. every car steps, in a fixed order
  //  5. cars inside each other are pushed apart — after the driving, because
  //     it is the driving that put them there
  //  6. dynamics are shoved: intent, never leftover velocity
  //  7. progress is read: lap, checkpoints, wrong way, off road
  //  8. overlaps dispatch, kinematic deltas cleared
  //  9. mechanisms publish
  // 10. cars off the world, or too long off the road, are put back — and the
  //     broadphase is told, because it is still holding them where they went
}
```

The order is the platformer's with three insertions. The car list is a `List` and not a `Set` on purpose: cars are pushed apart in pairs, and a collection that iterated differently on another machine would separate them differently and take the replay with it.

`offRoadPatience` is how long a car may be off the surface before it is put back: long enough to run wide and recover, short enough that cutting the course is not a strategy.

## AI drivers

```dart
final ai = AiDriver(track: track, tuning: const AiTuning(skill: 0.9));

ai.drive(car, simulation.inputs[i], others: cars, playerGap: gap);
```

An AI driver fills a `VehicleInput`, the same one the player's keys fill. It cannot do anything the player cannot.

| Setting | What it decides |
|---|---|
| `lookAheadPerSpeed`, `minLookAhead` | How far up the road it aims |
| `steerGain` | How hard it corrects a heading error |
| `corneringGrip`, `brakeHorizon`, `brakeMargin` | When it lifts and when it brakes |
| `avoidRange`, `avoidWidth`, `avoidOffset` | How it moves over for a car alongside |
| `rubberBandClamp` | How much the pace may be scaled by the gap to the player |
| `skill` | One dial over the rest, for a grid that is not all the same driver |

It brakes for the sharpest bend within the horizon rather than the one it is in, because a driver that brakes for the corner it is already in has arrived too fast.

## Ghosts

```dart
final recorder = GhostRecorder(hz: 30.0);
recorder.tick(race.elapsed, car);
final tape = recorder.finish(lapTime);

final player = GhostPlayer(tape);
if (player.sampleAt(time, frame)) { /* place the ghost */ }
```

Recorded at 30 Hz and interpolated with Catmull-Rom on playback, so the tape is small and the ghost does not step. `GhostFrame` rounds to a millimetre on the way to JSON, which is what keeps a lap of tape a reasonable file.

## The chase camera

```dart
final camera = ChaseCamera(track: track, tuning: const ChaseTuning(
  distance: 7.5, height: 2.6, aimHeight: 1.0,
  lag: 9.0,
  headingBlend: 0.65,      // between where the car points and where it is going
  headingFrom: 6.0, headingTo: 26.0,
  lookAhead: 22.0, lookAheadWeight: 0.35,
  baseFov: 1.05, fovPerSpeed: 0.0045, maxFov: 1.35,
  nearClearance: 0.4, minDistance: 2.0,
));
camera.follow(car, dt);
```

`headingBlend` is what a chase camera in a racing game is actually about. Following the car's heading puts the camera behind a car that is sideways, and following the velocity puts it behind a car that is stationary and pointing nowhere. It blends between them, and the blend itself fades in with speed between `headingFrom` and `headingTo`.

The field of view opens with speed, and the camera looks ahead along the track rather than at the car's nose.

## What it does not do

- **No four-wheel model.** One sphere, one contact patch, no per-corner suspension and no wheel that can leave the ground alone.
- **No gearbox.** `rpm` is derived from wheel speed for the sound to read; there are no ratios and no shifts.
- **No tire wear, no fuel, no damage.**
- **No pit lane, no flags, no penalties.** `offRoad` is reported and the car is put back; nothing takes a time away.
- **No split screen.** `RenderView` supports it; nothing in this package assumes one camera, and nobody has written the other one.

## Next

- [Tutorial: build a racing game](/racing/tutorial/): the whole thing, step by step
- [Playable demo](/racing/demo/): the browser build, and what it costs
- [Simulation layer](/core/simulation/): the machinery all three genres share
