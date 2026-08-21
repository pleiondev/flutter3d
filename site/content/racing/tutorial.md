---
description: Twelve steps from an empty project to a racing game — a track as a curve, a car that slides, laps that cannot be cheated, AI drivers, a chase camera and a ghost.
---

# Tutorial: build a racing game

Twelve steps. The engine underneath is the one the [shooter](/shooter/tutorial/) and the [platformer](/platformer/tutorial/) use, unchanged. What is new is that the ground is a curve.

<div class="goal">
<ul>
<li>A track authored as a measured centre line with width, camber and surface bands</li>
<li>A car that understeers, oversteers and can be caught, on a tire curve rather than a friction constant</li>
<li>Laps counted through checkpoints, positions, a countdown and a finish</li>
<li>Three AI drivers that brake for the corner ahead and move over for each other</li>
<li>A chase camera that follows where the car is going, not only where it points</li>
</ul>
</div>

## Set the project up {.step}

```yaml
dependencies:
  flutter: { sdk: flutter }

  flutter3d_impeller: { path: ../flutter3d/packages/flutter3d_impeller }
  flutter3d:          { path: ../flutter3d/packages/flutter3d }
  flutter3d_game:     { path: ../flutter3d/packages/flutter3d_game }
  flutter3d_racing:   { path: ../flutter3d/packages/flutter3d_racing }
  flutter3d_bridge:   { path: ../flutter3d/packages/flutter3d_bridge }
  flutter3d_audio:    { path: ../flutter3d/packages/flutter3d_audio }
  vector_math: ^2.2.0
```

No `flutter3d_game_shooter` and no `flutter3d_game_platformer`. A genre is a package, and this one inherits nothing from either.

## Decide what a driver may ask for {.step}

A car has a throttle and a brake, not a forward and a back. `GameAction` is a string rather than an enum for exactly this: a genre declares its own verbs without editing the engine.

```dart
abstract final class Drive {
  static const GameAction throttle = GameAction('throttle');
  static const GameAction brake = GameAction('brake');
  static const GameAction left = GameAction('steerLeft');
  static const GameAction right = GameAction('steerRight');
  static const GameAction handbrake = GameAction('handbrake');
}

final bindings = Bindings(<InputSource, GameAction>{});
void bind(LogicalKeyboardKey key, GameAction action) =>
    bindings.bind(InputSource.key(key.keyId), action);

bind(LogicalKeyboardKey.keyW, Drive.throttle);
bind(LogicalKeyboardKey.arrowUp, Drive.throttle);
bind(LogicalKeyboardKey.keyS, Drive.brake);
bind(LogicalKeyboardKey.arrowDown, Drive.brake);
bind(LogicalKeyboardKey.keyA, Drive.left);
bind(LogicalKeyboardKey.arrowLeft, Drive.left);
bind(LogicalKeyboardKey.keyD, Drive.right);
bind(LogicalKeyboardKey.arrowRight, Drive.right);
bind(LogicalKeyboardKey.space, Drive.handbrake);
```

## Author a track {.step}

A track document holds two halves: the spline this genre reads, and an ordinary level the engine has read since the first game. One script writes both.

```json
{
  "version": 1,
  "name": "Ring",
  "level": "assets/tracks/ring_level.json",
  "track": {
    "closed": true,
    "points": [[0, 0, 0], [120, 0, 40], [180, 0, 150], [60, 2, 210]],
    "widths": [14.0, 14.0, 11.0, 12.0],
    "banks":  [0.0, 0.05, 0.12, 0.0],
    "shoulder": 4.0,
    "surfaces": [
      {"fromS": 0.0,   "toS": 240.0, "centre": "tarmac", "shoulder": "kerb"},
      {"fromS": 240.0, "toS": 380.0, "centre": "tarmac", "shoulder": "gravel"}
    ],
    "barriers": [{"fromS": 180.0, "toS": 320.0, "left": false, "right": true}],
    "checkpoints": [250.0, 520.0, 780.0],
    "grid": {"s": 12.0, "columns": 2, "rowGap": 8.0, "columnGap": 4.0}
  }
}
```

<div class="note">
<p>One width and one bank per control point, every width positive, and checkpoints in ascending order. <code>TrackSpline</code>'s constructor throws on each of these rather than producing a track that behaves oddly a lap later.</p>
</div>

Read it with `TrackDocument`, which hands back the spline and the level path:

```dart
final text = await rootBundle.loadString('assets/tracks/ring.json');
final document = TrackDocument.fromJson(
  jsonDecode(text) as Map<String, Object?>,
);
final track = document.track;
```

## Load the scenery through the engine {.step}

```dart
final loaded = await const LevelLoader().load(
  'assets/tracks/ring_level.json',
  device: device,
  // This circuit places no entities — the scenery is brushes — so the registry
  // is empty rather than absent: the loader validates against it, and an empty
  // one is the statement that nothing is expected.
  registry: EntityRegistry(const <EntityKind>[]),
);
```

Then turn the curve into meshes. That is `bridge.dart`, the one file in the genre that knows what a mesh is:

```dart
addTrackTo(loaded.scene, track, device: device);
```

`RoadMeshSettings` controls the cut. The subdivision rule is stated as an error, not a step count: `sagitta` is how far the middle of a straight edge may sit from the curve it stands in for, so a hairpin gets short segments and a straight gets long ones without anybody choosing a number per corner.

```dart
addTrackTo(scene, track, device: device, settings: const RoadMeshSettings(
  sagitta: 0.04,        // four centimetres, well under a kerb
  minStep: 1.5,
  maxStep: 8.0,         // not about accuracy: about per-vertex lighting and fog
  metresPerTile: 9.0,
  barrierHeight: 1.1,
));
```

## Give the cars a ground to find {.step}

```dart
final field = TrackField(track: track, world: loaded.collision);
```

`GroundField` is one method. It answers with a point, a normal, an arc length and a surface name, and falls back to a probe against the collision world where the curve stops describing the ground.

```dart
abstract interface class GroundField {
  bool sample(Vector3 position, double nearHint, GroundSample out);
}
```

<div class="why">
<p><code>nearHint</code> is the car's last known arc length, and it is the reason this is affordable. Finding the nearest point on a closed kilometre-long spline from nothing is a global search; from a hint it is a window of a few metres. <code>CatmullRom</code> offers both — <code>closestS(point, nearS:, window:)</code> and <code>closestSGlobal</code> — and only the first belongs in a step.</p>
</div>

## Build the grid {.step}

```dart
final race = RaceState(mode: RaceMode.race, track: track, racers: 4, laps: 3);

final position = Vector3.zero();
final forward = Vector3.zero();
final cars = <SphereVehicle>[];

for (var i = 0; i < 4; i++) {
  track.startSlot(i, position, forward);
  final car = SphereVehicle(
    world: loaded.collision,
    ground: field,
    position: position.clone()..y += 0.6,
    headingYaw: math.atan2(forward.x, forward.z),
  );
  // Told where it is on the lap, so the first `sample` has a hint and the
  // first progress read is not a global search from the wrong end.
  car.placeAt(car.position, car.headingYaw,
      trackDistance: track.centre.wrap(track.grid.s));
  cars.add(car);
}
```

## Tune the car, and then the tire {.step}

These are the numbers the game is. Change one and re-run the tests before changing a second.

```dart
const tuning = VehicleTuning(
  radius: 0.6,
  rideHeight: 0.35,
  maxSpeed: 62.0,        // about 220 km/h
  maxReverse: 12.0,
  enginePush: 14.0,
  brakeStrength: 26.0,   // brakes beat the engine, or nothing stops
  rollingDrag: 0.6,
  airDrag: 0.42,
  maxSteer: 0.62,        // radians at a standstill
  steerFalloff: 0.55,    // how much of it is left at speed
  wheelBase: 2.6,
  gravity: -22.0,
  gripLimit: 14.0,       // metres per second squared the tires can spend
  groundStick: 26.0,     // how hard the car is held onto a crest
  suspensionRate: 9.0,
  slideAlignment: 6.0,   // how quickly a slide straightens itself out
  wheelInertia: 0.5,     // what makes a wheelspin a wheelspin
);
```

The tire is where the feel lives:

```dart
const tires = TireModel(peakSlipAngle: 0.14, peakSlipRatio: 0.12);

const grips = GripTable(<String, double>{
  'tarmac': 1.00,
  'kerb':   0.85,
  'gravel': 0.45,
  'grass':  0.35,
}, fallback: 0.5);
```

<div class="why">
<p>A curve that rises to a peak and falls away past it is the whole reason a car can be driven over the limit and caught. A constant coefficient gives a car that grips until it does not, with nothing in between, and no amount of tuning elsewhere puts that back.</p>
<p><code>TireModel.clampToCircle</code> is the friction circle: lateral and longitudinal force share one budget. That is what makes braking into a corner cost cornering, and it is why there is no setting that gives you both.</p>
</div>

## Wire the simulation {.step}

```dart
final simulation = RacingSimulation(
  collision: loaded.collision,
  vehicles: cars,          // a List: index nought is the player
  race: race,
  offRoadPatience: 4.0,    // long enough to run wide, short enough not to cut
  contactRestitution: 0.35,
  killPlane: -50.0,
);
```

<div class="warn">
<p>The car list is a <code>List</code> and not a <code>Set</code>, and the order is part of the answer. Cars are pushed apart in pairs, so a collection that iterated differently on another machine would separate them differently and take the replay with it.</p>
</div>

## Fill in what each driver wants {.step}

Every car is driven the same way: something fills a `VehicleInput` before the step. For car nought that is the keyboard.

```dart
void readDriver(RacingSimulation simulation) {
  simulation.inputs[0]
    ..throttle = input.held(Drive.throttle) ? 1.0 : 0.0
    ..brake = input.held(Drive.brake) ? 1.0 : 0.0
    ..handbrake = input.held(Drive.handbrake)
    ..steer = (input.held(Drive.right) ? 1.0 : 0.0) -
              (input.held(Drive.left) ? 1.0 : 0.0);
}
```

For the rest it is an `AiDriver`, which cannot do anything the player cannot:

```dart
final ai = AiDriver(track: track, tuning: const AiTuning(skill: 0.9));

void driveTheRest(RacingSimulation simulation, RaceState race) {
  final player = race.progress[0];
  for (var i = 1; i < cars.length; i++) {
    // How far the player is up the road from this car, wrapped. This is what
    // the rubber band reads, and zero turns it off.
    var gap = player.progressAlong(track.length) -
              race.progress[i].progressAlong(track.length);
    if (gap.abs() > track.length / 2) gap -= gap.sign * track.length;

    ai.drive(cars[i], simulation.inputs[i], others: cars, playerGap: gap);
  }
}
```

## Run the loop {.step}

```dart
void _onTick(Duration now) {
  final dt = _lastTick == Duration.zero
      ? 1 / 60
      : (now - _lastTick).inMicroseconds / 1e6;
  _lastTick = now;

  final steps = _step.advance(dt.clamp(0.0, 0.25));
  for (var i = 0; i < steps; i++) {
    readDriver(simulation);
    driveTheRest(simulation, race);
    simulation.step(_step.stepSeconds);
  }

  _placeCamera(dt);
  _listen(race);
  setState(() {});
}
```

Inputs are filled **inside** the step loop rather than once a frame. A frame that runs three steps and reads the keys once gives the first step three steps' worth of intent.

## Place the chase camera {.step}

```dart
final chase = ChaseCamera(world: loaded.collision, track: track);

chase.follow(cars[0], dt);
_camera
  ..setPositionFrom(chase.eye)
  ..lookAt(chase.target)
  ..projection = _lens.copyWith(fovYRadians: chase.fov);
```

<div class="why">
<p><code>headingBlend</code> is what a chase camera in a racing game is about. Following the car's heading puts the camera behind a car that is sideways, so a slide is invisible. Following the velocity puts it behind a car that is stationary and pointing nowhere. It blends, and the blend fades in with speed between <code>headingFrom</code> and <code>headingTo</code>, because at walking pace the velocity means nothing.</p>
</div>

## Record a ghost {.step}

```dart
final recorder = GhostRecorder(hz: 30.0);

// each frame
recorder.tick(race.elapsed, cars[0]);

// on a completed lap
final tape = recorder.finish(player.lapTime);
await file.writeAsString(jsonEncode(tape.toJson()));
```

```dart
final ghost = GhostPlayer(GhostTape.fromJson(jsonDecode(text)));
if (ghost.sampleAt(time, frame)) {
  ghostNode
    ..setPosition(frame.position.x, frame.position.y, frame.position.z)
    ..setRotationYawPitchRoll(frame.yaw, 0.0, 0.0);
}
```

Thirty samples a second, interpolated with Catmull-Rom on the way out, and rounded to a millimetre on the way to JSON. A lap of tape stays a small file and the ghost does not step.

## Test it without a device {.step}

The racing package has 140 tests and none of them draws anything. The ones worth copying:

```dart
test('a lap does not count without its checkpoints', () {
  final game = ring();
  // Nose over the line, reverse, cross it forwards again.
  driveTo(game, game.track.length - 5.0);
  driveTo(game, 5.0);
  driveTo(game, game.track.length - 5.0);
  driveTo(game, 5.0);
  expect(game.race.progress[0].lap, 0);
});

test('the tire falls away past its peak', () {
  const tires = TireModel(peakSlipAngle: 0.14, peakSlipRatio: 0.12);
  expect(tires.lateralAt(0.14), greaterThan(tires.lateralAt(0.30)));
});

test('two runs of one input agree', () {
  expect(play(recorded).save(), play(recorded).save());
});
```

<div class="note">
<p>The things that go wrong in a racing game go wrong invisibly: a car that understeers differently at a lower frame rate, a lap that counts twice because the line was crossed twice in one step, a driving line an AI cuts through a barrier, a position table that disagrees with itself on a track that crosses over itself. None of those appear in a screenshot.</p>
</div>

## Next

- [What a racing game adds](/racing/): the reference for every type used here
- [Playable demo](/racing/demo/): the browser build, and why it is not playable yet
- [Simulation layer](/core/simulation/): the machinery all three genres share
