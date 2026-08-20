/// What a step of the race looks like.
///
///     flutter test test/reactions_test.dart
///
/// **This game showed nothing at all.** A car could lock its wheels, slide
/// across a kerb and scrape down a barrier at a hundred miles an hour, and the
/// only thing that changed on screen was a number in the corner — there were no
/// particles anywhere in the application. The other two games have had this
/// split since they were written: deciding is a pure function of the simulation
/// and testable without a device, bursting is what the widget does with the
/// answer.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing/src/effects.dart';
import 'package:racing/src/reactions.dart';
import 'package:vector_math/vector_math.dart';

/// A car that reports exactly what a test wants it to report.
final class _Car implements VehicleController {
  _Car({
    this.speed = 40.0,
    this.slipRatio = 0.0,
    this.slipAngle = 0.0,
    this.grounded = true,
    this.impactThisStep = 0.0,
    Vector3? at,
  }) : collider = Collider(
          shape: CollisionSphere(0.7),
          position: at ?? Vector3(0.0, 1.0, 0.0),
        );

  @override
  final Collider collider;

  @override
  Vector3 get position => collider.position;

  @override
  final Vector3 velocity = Vector3.zero();

  @override
  double headingYaw = 0.0;

  @override
  Matrix3 get visualBasis => _basis;
  final Matrix3 _basis = Matrix3.identity();

  @override
  double speed;

  @override
  double slipAngle;

  @override
  double slipRatio;

  @override
  bool grounded;

  @override
  double impactThisStep;

  @override
  double rpm = 0.0;

  @override
  double trackDistance = 0.0;

  @override
  void step(double dt, VehicleInput input) {}

  @override
  void placeAt(Vector3 at, double yaw, {double? trackDistance}) {}

  @override
  Map<String, Object?> save() => const <String, Object?>{};

  @override
  void restore(Map<String, Object?> from) {}
}

/// A race with [cars] racers, all of them on the road until told otherwise.
RaceState _race(TrackSpline track, int cars) =>
    RaceState(mode: RaceMode.race, track: track, racers: cars, laps: 3);

TrackSpline _ring() => TrackSpline(
      centre: CatmullRom(<Vector3>[
        Vector3(40.0, 0.0, 0.0),
        Vector3(0.0, 0.0, 40.0),
        Vector3(-40.0, 0.0, 0.0),
        Vector3(0.0, 0.0, -40.0),
      ]),
      widths: List<double>.filled(4, 16.0),
      banks: List<double>.filled(4, 0.0),
      surfaces: const <SurfaceBand>[],
      checkpoints: const <double>[],
      grid: const StartGrid(s: 0.0, columns: 2),
    );

void main() {
  final track = _ring();

  test('a clean lap shows nothing', () {
    // The half that matters most: smoke at every touch of the throttle is a
    // car that appears to be permanently on fire.
    final reaction = Reactions().listen(_race(track, 1), <VehicleController>[
      _Car(slipRatio: 0.1, slipAngle: 0.05),
    ]);

    expect(reaction.bursts, isEmpty);
  });

  test('and locked wheels smoke', () {
    final reaction = Reactions().listen(_race(track, 1), <VehicleController>[
      _Car(slipRatio: -0.9),
    ]);

    expect(reaction.bursts.single.effect, same(Effects.smoke));
  });

  test('and so does a car going sideways', () {
    final reaction = Reactions().listen(_race(track, 1), <VehicleController>[
      _Car(slipAngle: 0.6),
    ]);

    expect(reaction.bursts.single.effect, same(Effects.smoke));
  });

  test('and a car off the road throws earth rather than rubber', () {
    // The same slide, and what comes off it is what it is sliding on.
    final race = _race(track, 1)..progress[0].offRoad = true;
    final reaction = Reactions().listen(race, <VehicleController>[
      _Car(slipAngle: 0.6, slipRatio: -0.9),
    ]);

    expect(reaction.bursts.single.effect, same(Effects.dirt));
  });

  test('and a car standing still shows nothing, whatever its wheels say', () {
    // A stationary car with a spinning wheel would otherwise smoke for ever,
    // which is what a car left on the grid does.
    final reaction = Reactions().listen(_race(track, 1), <VehicleController>[
      _Car(speed: 0.5, slipRatio: -1.0, slipAngle: 1.0),
    ]);

    expect(reaction.bursts, isEmpty);
  });

  test('and a car in the air shows nothing', () {
    final reaction = Reactions().listen(_race(track, 1), <VehicleController>[
      _Car(slipRatio: -1.0, grounded: false),
    ]);

    expect(reaction.bursts, isEmpty);
  });

  test('and every car is watched, not just the player', () {
    // A rival locking up in front is exactly as worth seeing as the player
    // doing it, and it is what makes a pack read as a race.
    final reaction = Reactions().listen(_race(track, 3), <VehicleController>[
      _Car(),
      _Car(slipRatio: -0.9, at: Vector3(4.0, 1.0, 0.0)),
      _Car(slipAngle: 0.7, at: Vector3(8.0, 1.0, 0.0)),
    ]);

    expect(reaction.bursts.length, 2);
  });

  test('and a car that hits a wall throws sparks', () {
    // Either wall. The track's barrier is a number in the document and a pillar
    // is geometry; only the first of the two used to be reported at all, so a
    // car bouncing off the scenery at ninety was the quietest thing on the
    // circuit — and a fake car could not be given a crash to report, which is
    // why there was no test here.
    final reaction = Reactions().listen(_race(track, 1), <VehicleController>[
      _Car(impactThisStep: 8.0),
    ]);

    expect(reaction.bursts.single.effect, same(Effects.sparks));
  });

  test('and leaning on one does not', () {
    // A car merely resting against a barrier through a corner is not a crash,
    // and a shower of sparks down every long right-hander would be.
    final reaction = Reactions().listen(_race(track, 1), <VehicleController>[
      _Car(impactThisStep: 0.4),
    ]);

    expect(reaction.bursts, isEmpty);
  });

  test('and the smoke comes off the tyres, not the roof', () {
    // A car is simulated as a sphere whose centre floats above the road, so
    // particles emitted at `position` come out of the roof.
    final car = _Car(slipRatio: -0.9, at: Vector3(0.0, 1.0, 0.0));
    final reaction =
        Reactions().listen(_race(track, 1), <VehicleController>[car]);

    expect(reaction.bursts.single.at.y, lessThan(car.position.y));
  });
}
