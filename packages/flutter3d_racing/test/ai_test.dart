import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A circuit with a long fast section and one genuinely slow corner, so that a
/// driver that brakes for nothing and one that brakes properly come out
/// visibly different.
TrackSpline circuit() {
  const points = 28;
  final positions = <Vector3>[
    for (var i = 0; i < points; i++)
      () {
        final angle = 2 * math.pi * i / points;
        final radius = 130.0 + 45.0 * math.cos(2 * angle);
        return Vector3(
          radius * math.cos(angle),
          0.0,
          radius * math.sin(angle),
        );
      }(),
  ];
  final centre = CatmullRom(positions);
  return TrackSpline(
    centre: centre,
    widths: List<double>.filled(points, 16.0),
    banks: List<double>.filled(points, 0.0),
    surfaces: <SurfaceBand>[
      SurfaceBand(
        fromS: 0.0,
        toS: centre.length,
        centre: 'asphalt',
        shoulder: 'grass',
      ),
    ],
    checkpoints: <double>[
      for (var i = 1; i < 4; i++) centre.length * i / 4,
    ],
  );
}

final class Field {
  Field({int cars = 1, AiTuning tuning = const AiTuning()})
      : track = circuit(),
        driver = AiDriver(track: circuit(), tuning: tuning) {
    final field = TrackField(track: track);
    race = RaceState(mode: RaceMode.race, track: track, racers: cars, laps: 3);

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
      car.placeAt(car.position, car.headingYaw,
          trackDistance: track.centre.wrap(track.grid.s));
      cars_.add(car);
    }

    simulation = RacingSimulation(
      collision: world,
      vehicles: cars_,
      race: race,
    );
    race.phase = RacePhase.running;
  }

  final TrackSpline track;
  final AiDriver driver;
  final CollisionWorld world = CollisionWorld();
  final List<SphereVehicle> cars_ = <SphereVehicle>[];
  late final RaceState race;
  late final RacingSimulation simulation;

  /// Lets the drivers drive. [gaps] is the player distance handed to each car,
  /// which is what the rubber band reads.
  void run(double seconds, {List<double> gaps = const <double>[]}) {
    final steps = (seconds * 60).round();
    for (var step = 0; step < steps; step++) {
      for (var i = 0; i < cars_.length; i++) {
        driver.drive(
          cars_[i],
          simulation.inputs[i],
          others: cars_,
          playerGap: i < gaps.length ? gaps[i] : 0.0,
        );
      }
      simulation.step(1 / 60);
    }
  }
}

void main() {
  group('getting round', () {
    test('a driver completes laps without being put back', () {
      final it = Field();
      var respawns = 0;
      var laps = 0;

      final steps = (150 * 60).round();
      for (var step = 0; step < steps; step++) {
        it.driver.drive(it.cars_[0], it.simulation.inputs[0]);
        it.simulation.step(1 / 60);
        if (it.race.progress[0].respawnedThisStep) respawns += 1;
        if (it.race.progress[0].lapCompletedThisStep) laps += 1;
      }

      expect(laps, greaterThanOrEqualTo(1));
      expect(respawns, 0);
    });

    test('a driver stays on the road', () {
      final it = Field();
      var offRoad = 0;
      const steps = 90 * 60;

      for (var step = 0; step < steps; step++) {
        it.driver.drive(it.cars_[0], it.simulation.inputs[0]);
        it.simulation.step(1 / 60);
        if (it.race.progress[0].offRoad) offRoad += 1;
      }

      expect(offRoad / steps, lessThan(0.05));
    });
  });

  group('aiming up the road', () {
    test('the wheel is not sawed back and forth', () {
      // Mutation: aim at the point on the line nearest the car instead of one
      // up it. The car is then always almost exactly on its target, so the
      // sliver of error left over swings the wheel from lock to lock — it hunts
      // for a line it is already on.
      //
      // Measured directly rather than left to the lap counter. Taken far
      // enough the hunting does end the lap, but the first thing to go is the
      // steering, and a driver that merely looks like a learner is a driver
      // nothing else here would report.
      final it = Field();
      var flips = 0;
      var previous = 0.0;

      for (var step = 0; step < 60 * 60; step++) {
        it.driver.drive(it.cars_[0], it.simulation.inputs[0]);
        final steer = it.simulation.inputs[0].steer;
        if (step > 120 && steer.sign != previous.sign && steer.abs() > 0.02) {
          flips += 1;
        }
        previous = steer;
        it.simulation.step(1 / 60);
      }

      // A minute of driving. Aiming up the road turns the wheel one way for a
      // corner and the other for the next; hunting for the nearest point
      // reverses it many times a second.
      expect(flips, lessThan(60));
    });
  });

  group('braking for what is coming', () {
    test('the braking is done before the corner, not in it', () {
      // Mutation: work the corner speed out from the curvature underneath the
      // car rather than up the road. Braking would then begin at the apex,
      // which is the definition of arriving too fast — and measuring only the
      // minimum speed would not notice, because a car that arrives too fast
      // still ends up slow, just later and wider.
      final it = Field();
      final speeds = <double>[];
      final bends = <double>[];

      for (var step = 0; step < 90 * 60; step++) {
        it.driver.drive(it.cars_[0], it.simulation.inputs[0]);
        it.simulation.step(1 / 60);
        speeds.add(it.cars_[0].speed);
        bends.add(it.track.centre.curvatureAt(it.cars_[0].trackDistance).abs());
      }

      // The sharpest place the car went through, once it was up to speed.
      var apex = 600;
      for (var i = 600; i < bends.length; i++) {
        if (bends[i] > bends[apex]) apex = i;
      }

      const approach = 50; // most of a second before it
      expect(apex - approach, greaterThan(0));

      expect(
        speeds[apex],
        lessThan(speeds[apex - approach]),
        reason: 'the car should already be slowing on the way in',
      );
      expect(
        bends[apex - approach],
        lessThan(bends[apex] * 0.8),
        reason: 'and it should still have been on the easy bit when it started',
      );

      var fastest = 0.0;
      for (var i = 600; i < speeds.length; i++) {
        fastest = math.max(fastest, speeds[i]);
      }
      expect(speeds[apex], lessThan(fastest * 0.9));
      expect(speeds[apex], greaterThan(5.0),
          reason: 'braking for a corner is not stopping at it');
    });

    test('a driver that believes it has more grip goes faster', () {
      double lapDistance(double grip) {
        final it = Field(tuning: AiTuning(corneringGrip: grip));
        it.run(40.0);
        return it.race.progress[0].progressAlong(it.track.length);
      }

      expect(lapDistance(20.0), greaterThan(lapDistance(8.0)));
    });
  });

  group('the rubber band', () {
    test('a driver behind the player goes faster than one ahead of it', () {
      // Positive gap is the player up the road, so the car is behind and gets
      // the nudge.
      double distance(double gap) {
        final it = Field();
        it.run(45.0, gaps: <double>[gap]);
        return it.race.progress[0].progressAlong(it.track.length);
      }

      expect(distance(300.0), greaterThan(distance(-300.0)));
    });

    test('the band is capped, however far behind the driver falls', () {
      // Mutation: drop the clamp. A driver a lap down would be given whatever
      // pace it took to get back, which a player feels within two laps as a
      // race that is not really being run.
      final near = Field();
      final far = Field();
      near.run(45.0, gaps: <double>[400.0]);
      far.run(45.0, gaps: <double>[40000.0]);

      final nearAt = near.race.progress[0].progressAlong(near.track.length);
      final farAt = far.race.progress[0].progressAlong(far.track.length);

      // Four hundred metres behind is already past the clamp, so being a
      // hundred times further behind buys nothing.
      expect(farAt, closeTo(nearAt, nearAt * 0.02));
    });

    test('with no gap given, the band does nothing at all', () {
      // What a time trial and every test above rely on.
      final quiet = Field();
      final zero = Field();
      quiet.run(30.0);
      zero.run(30.0, gaps: <double>[0.0]);

      expect(
        zero.race.progress[0].progressAlong(zero.track.length),
        quiet.race.progress[0].progressAlong(quiet.track.length),
      );
    });
  });

  group('traffic', () {
    test('a driver moves over for a car right in front of it', () {
      // Mutation: ignore the others entirely. The car behind drives into the
      // back of the one in front and stays there, which in a field of eight is
      // a queue.
      final it = Field(cars: 2);

      // Put the second car directly in front of the first, on the line.
      final ahead = it.cars_[0].trackDistance + 10.0;
      final at = Vector3.zero();
      it.track.centreAt(ahead, at);
      it.cars_[1].placeAt(at..y += 0.6, it.cars_[1].headingYaw,
          trackDistance: ahead);

      final input = VehicleInput();
      it.driver.drive(it.cars_[0], input, others: it.cars_);
      final avoiding = input.steer;

      it.driver.drive(it.cars_[0], input);
      final alone = input.steer;

      expect(avoiding, isNot(closeTo(alone, 1e-6)));
    });

    test('a car far up the road is not something to swerve for', () {
      final it = Field(cars: 2);
      final ahead = it.cars_[0].trackDistance + 200.0;
      final at = Vector3.zero();
      it.track.centreAt(ahead, at);
      it.cars_[1].placeAt(at..y += 0.6, 0.0, trackDistance: ahead);

      final input = VehicleInput();
      it.driver.drive(it.cars_[0], input, others: it.cars_);
      final withTraffic = input.steer;
      it.driver.drive(it.cars_[0], input);

      expect(withTraffic, closeTo(input.steer, 1e-9));
    });

    test('a field of four gets round without piling up', () {
      final it = Field(cars: 4);

      it.run(60.0);

      for (var i = 0; i < 4; i++) {
        expect(it.race.progress[i].lap + it.race.progress[i].s / it.track.length,
            greaterThan(0.3),
            reason: 'car $i barely moved');
        for (var j = i + 1; j < 4; j++) {
          expect(
            it.cars_[i].position.distanceTo(it.cars_[j].position),
            greaterThan(1.0),
          );
        }
      }
    });
  });

  group('determinism', () {
    test('the same field twice runs the same race', () {
      List<double> run() {
        final it = Field(cars: 3);
        it.run(30.0, gaps: <double>[100.0, 0.0, -100.0]);
        return <double>[
          for (final car in it.cars_) ...<double>[
            car.position.x,
            car.position.z,
            car.headingYaw,
          ],
        ];
      }

      final first = run();
      final second = run();
      for (var i = 0; i < first.length; i++) {
        expect(first[i], second[i]);
      }
    });
  });
}
