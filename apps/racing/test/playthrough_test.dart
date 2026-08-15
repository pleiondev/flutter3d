/// The circuit this game actually ships, driven without a renderer.
///
/// The package's own tests build their track in code, which proves the
/// machinery and nothing about the document. This one reads the file off disk
/// the way the application will, so a circuit generated into an undriveable
/// state — a corner narrower than the car, a checkpoint behind the one before
/// it, a barrier across the road — fails here rather than in front of somebody.
///
/// The lap time is pinned to a range rather than a number. A range is the only
/// honest form: the car's tuning is meant to be tuned, and a test that demanded
/// an exact time would be rewritten every time it was. What a range catches is
/// the thing nobody notices — a change that quietly makes the car half as fast,
/// or twice, which reads as "the handling feels a bit different" right up until
/// the day somebody compares a lap time with a recording.
///
/// The driver here is deliberately poor: it aims at a point up the road and
/// steers at it. Beating a lap time is not what this proves. Getting round at
/// all, without leaving the road and without being put back, is.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

TrackDocument _shipped() => TrackDocument.fromJson(
      jsonDecode(File('assets/tracks/ring.json').readAsStringSync())
          as Map<String, Object?>,
    );

final class _Session {
  _Session({int cars = 1, RaceMode mode = RaceMode.timeTrial}) {
    final document = _shipped();
    track = document.track;
    document.level?.addTo(world);

    final field = TrackField(track: track, world: world);
    race = RaceState(mode: mode, track: track, racers: cars, laps: 1);

    final position = Vector3.zero();
    final forward = Vector3.zero();
    for (var i = 0; i < cars; i++) {
      track.startSlot(i, position, forward);
      final car = SphereVehicle(
        world: world,
        ground: field,
        position: position.clone()..y += 0.6,
        headingYaw: math.atan2(forward.x, forward.z),
      );
      car.placeAt(
        car.position,
        car.headingYaw,
        trackDistance: track.centre.wrap(track.grid.s),
      );
      cars_.add(car);
    }

    simulation = RacingSimulation(
      collision: world,
      vehicles: cars_,
      race: race,
    );
  }

  final CollisionWorld world = CollisionWorld();
  final List<SphereVehicle> cars_ = <SphereVehicle>[];
  late final TrackSpline track;
  late final RaceState race;
  late final RacingSimulation simulation;

  RacerProgress get player => race.progress[0];

  /// Aims at a point up the road and steers at it, braking for what is coming.
  ///
  /// Look-ahead grows with speed, because a fixed one is either twitchy at
  /// speed or lazy in the slow corners.
  void driveFor(double seconds, {void Function()? watch}) {
    final aim = Vector3.zero();
    final toAim = Vector3.zero();
    final steps = (seconds / _dt).round();

    for (var step = 0; step < steps; step++) {
      for (var i = 0; i < cars_.length; i++) {
        final car = cars_[i];
        final lookAhead = math.max(12.0, car.speed * 0.6);
        track.centreAt(car.trackDistance + lookAhead, aim);

        toAim
          ..setFrom(aim)
          ..sub(car.position);
        var turn = math.atan2(toAim.x, toAim.z) - car.headingYaw;
        while (turn > math.pi) {
          turn -= 2 * math.pi;
        }
        while (turn < -math.pi) {
          turn += 2 * math.pi;
        }

        // Slow down for the corner ahead rather than for the one underneath:
        // the fastest a car holds a bend is the square root of its grip over
        // its curvature.
        final bend = track.centre.curvatureAt(car.trackDistance + lookAhead);
        final ceiling = bend.abs() < 1e-4
            ? 60.0
            : math.min(60.0, math.sqrt(14.0 / bend.abs()));

        simulation.inputs[i]
          // Negated: heading rises anticlockwise and the wheel is in the
          // driver's terms. See `SphereVehicle._steer`.
          ..steer = (-turn * 2.2).clamp(-1.0, 1.0)
          ..throttle = car.speed < ceiling ? 1.0 : 0.0
          ..brake = car.speed > ceiling * 1.15 ? 0.6 : 0.0
          ..handbrake = false;
      }
      simulation.step(_dt);
      watch?.call();
    }
  }
}

void main() {
  test('the circuit loads and says what it is', () {
    final track = _shipped().track;

    expect(track.length, greaterThan(500.0));
    expect(track.checkpoints, isNotEmpty);
    expect(track.checkpoints.first, greaterThan(0.0));
    expect(track.checkpoints.last, lessThan(track.length));

    // Every part of the road is wide enough for cars to be side by side on,
    // which is what a grid two wide assumes.
    for (var s = 0.0; s < track.length; s += 5.0) {
      expect(track.widthAt(s), greaterThan(8.0));
    }
  });

  test('the level around the circuit is there to land on', () {
    final document = _shipped();

    expect(document.level, isNotNull);
    expect(document.level!.brushes, isNotEmpty);
  });

  test('a lap can be driven, and takes about as long as it always has', () {
    final it = _Session();
    var respawns = 0;
    var offRoadSteps = 0;

    it.driveFor(
      120.0,
      watch: () {
        if (it.player.respawnedThisStep) respawns += 1;
        if (it.player.offRoad) offRoadSteps += 1;
      },
    );

    expect(it.player.lap, greaterThanOrEqualTo(1),
        reason: 'the shipped circuit must be driveable all the way round');
    expect(respawns, 0, reason: 'nothing on the racing line should need a reset');

    // A tenth of the drive off the road is the poor driver running wide; more
    // than that is a circuit with somewhere it cannot be kept on.
    expect(offRoadSteps / (120.0 / _dt), lessThan(0.1));

    final lap = it.player.bestLap!;
    // A kilometre of circuit, driven by the aim-and-steer driver above, comes
    // out at about twenty-four seconds. The range either side is wide enough
    // that tuning the car does not break the test and narrow enough to catch a
    // car that has quietly become half as fast or twice — which arrives as
    // "the handling feels a bit different" and is noticed the day somebody
    // compares a lap time against a recording.
    expect(
      lap,
      inInclusiveRange(17.0, 40.0),
      reason: 'a lap outside this range means the car or the circuit changed '
          'by a lot — which may well be right, and should be a deliberate '
          'edit to these numbers rather than a surprise',
    );
  });

  test('the checkpoints are all passed on the way round', () {
    // Mutation: generate the checkpoints in the wrong order, or put one off the
    // road. The lap would never count and the car would drive round forever
    // with nothing to show for it.
    final it = _Session();
    var passed = 0;

    it.driveFor(
      120.0,
      watch: () {
        if (it.player.checkpointThisStep) passed += 1;
      },
    );

    expect(passed, greaterThanOrEqualTo(it.track.checkpoints.length));
  });

  test('a grid of cars starts apart and stays apart', () {
    final it = _Session(cars: 4, mode: RaceMode.race);

    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        expect(
          it.cars_[i].position.distanceTo(it.cars_[j].position),
          greaterThan(1.5),
          reason: 'slot $i and slot $j overlap on the grid',
        );
      }
    }

    it.driveFor(30.0);

    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        expect(
          it.cars_[i].position.distanceTo(it.cars_[j].position),
          greaterThan(1.0),
        );
      }
    }
  });

  test('the same lap driven twice is the same lap', () {
    double lap() {
      final it = _Session();
      it.driveFor(120.0);
      return it.player.bestLap ?? -1.0;
    }

    expect(lap(), lap());
  });
}
