import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A flat ring with four checkpoints, wide enough to drive round without trying
/// very hard.
TrackSpline ringTrack({double radius = 70.0, int points = 20}) {
  final positions = <Vector3>[
    for (var i = 0; i < points; i++)
      Vector3(
        radius * math.cos(2 * math.pi * i / points),
        0.0,
        radius * math.sin(2 * math.pi * i / points),
      ),
  ];
  final centre = CatmullRom(positions);
  return TrackSpline(
    centre: centre,
    widths: List<double>.filled(points, 18.0),
    banks: List<double>.filled(points, 0.0),
    surfaces: <SurfaceBand>[
      SurfaceBand(
        fromS: 0.0,
        toS: centre.length,
        centre: 'asphalt',
        shoulder: 'grass',
      ),
    ],
    checkpoints: <double>[for (var i = 1; i < 4; i++) centre.length * i / 4],
    grid: const StartGrid(s: -10.0, columns: 2),
  );
}

final class Race {
  Race({
    RaceMode mode = RaceMode.timeTrial,
    int cars = 1,
    int laps = 2,
    TrackSpline? track,
  }) : track = track ?? ringTrack() {
    final field = TrackField(track: this.track);
    race = RaceState(
      mode: mode,
      track: this.track,
      racers: cars,
      laps: laps,
      countdownSeconds: 3.0,
    );

    final position = Vector3.zero();
    final forward = Vector3.zero();
    for (var i = 0; i < cars; i++) {
      this.track.startSlot(i, position, forward);
      final car = SphereVehicle(
        world: world,
        ground: field,
        position: position.clone()..y += 0.55,
        headingYaw: math.atan2(forward.x, forward.z),
      );
      car.placeAt(
        car.position,
        car.headingYaw,
        trackDistance: this.track.centre.wrap(-10.0),
      );
      vehicles.add(car);
    }

    simulation = RacingSimulation(
      collision: world,
      vehicles: vehicles,
      race: race,
    );
  }

  final TrackSpline track;
  final CollisionWorld world = CollisionWorld();
  final List<SphereVehicle> vehicles = <SphereVehicle>[];
  late final RaceState race;
  late final RacingSimulation simulation;

  RacerProgress get player => race.progress[0];
}

const double _step = 1 / 60;

/// Drives every car round the track by aiming each at a point ahead of it on
/// the centre line.
///
/// A stand-in for a driver, and deliberately a poor one: the point of these
/// tests is what the race makes of a car going round, not how well it goes.
void driveRound(
  Race it, {
  required double seconds,
  double throttle = 0.6,
  bool backwards = false,
  void Function()? watch,
}) {
  final steps = (seconds / _step).round();
  final aim = Vector3.zero();
  final toAim = Vector3.zero();

  for (var step = 0; step < steps; step++) {
    for (var i = 0; i < it.vehicles.length; i++) {
      final car = it.vehicles[i];
      final ahead = backwards ? -14.0 : 14.0;
      it.track.centreAt(car.trackDistance + ahead, aim);

      toAim
        ..setFrom(aim)
        ..sub(car.position);
      final wanted = math.atan2(toAim.x, toAim.z);
      var turn = wanted - car.headingYaw;
      while (turn > math.pi) {
        turn -= 2 * math.pi;
      }
      while (turn < -math.pi) {
        turn += 2 * math.pi;
      }

      it.simulation.inputs[i]
        ..throttle = throttle
        ..brake = 0.0
        // Negated: heading rises anticlockwise, the wheel is in the driver's
        // terms. See `SphereVehicle._steer`.
        ..steer = (-turn * 2.5).clamp(-1.0, 1.0)
        ..handbrake = false;
    }
    it.simulation.step(_step);
    watch?.call();
  }
}

/// Spins a car on the spot to face back down the track.
///
/// Done outright rather than by steering: a car turning round at speed runs
/// wide off a track this width, gets put back facing forwards, and the test
/// ends up measuring the recovery instead of the offence.
void turnAround(Race it, [int car = 0]) {
  final vehicle = it.vehicles[car];
  vehicle.placeAt(
    vehicle.position,
    vehicle.headingYaw + math.pi,
    trackDistance: vehicle.trackDistance,
  );
}

void main() {
  group('going round', () {
    test('a lap driven the whole way round counts once', () {
      // Mutation: count the line and forget the checkpoints. See the test below
      // for what that costs.
      final it = Race();
      var laps = 0;

      driveRound(
        it,
        seconds: 40.0,
        watch: () {
          laps += it.simulation.events.drain().whereType<LapCompleted>().length;
        },
      );

      expect(laps, greaterThanOrEqualTo(1));
      expect(it.player.lap, laps);
      expect(it.player.bestLap, isNotNull);
      expect(it.player.bestLap, greaterThan(5.0));
    });

    test('crossing the line without going round counts nothing', () {
      // The reason checkpoints exist. Mutation: count a lap whenever the line is
      // crossed forwards. A car can then drive ten metres past the line, turn
      // round, and cross it forwards again for a lap a second — which is not a
      // theoretical exploit, it is what happens by accident on the first corner
      // of any track whose start line is near it.
      final it = Race();

      // Far enough forward to be over the line — the grid is ten metres behind
      // it — then back over it, then forward again, six times. A counter that
      // only watched the line would be reporting six laps in a quarter of a
      // minute on a four-hundred metre circuit.
      var crossings = 0;
      for (var i = 0; i < 6; i++) {
        driveRound(
          it,
          seconds: 2.5,
          throttle: 0.6,
          watch: () {
            if (it.player.s < 100.0) crossings += 1;
          },
        );
        turnAround(it);
        driveRound(it, seconds: 2.5, throttle: 0.6, backwards: true);
        turnAround(it);
      }

      expect(
        crossings,
        greaterThan(0),
        reason: 'the line must really be crossed',
      );
      expect(it.player.lap, 0);
    });

    test('checkpoints are passed in order and reported', () {
      final it = Race();
      var passed = 0;

      driveRound(
        it,
        seconds: 12.0,
        watch: () {
          passed += it.simulation.events
              .drain()
              .whereType<CheckpointPassed>()
              .length;
        },
      );

      expect(passed, greaterThan(0));
      expect(it.player.nextCheckpoint, passed);
    });

    test('the lap clock is simulated time, not wall-clock', () {
      final it = Race();

      driveRound(it, seconds: 5.0);

      expect(it.player.lapTime, closeTo(5.0, 0.05));
      expect(it.race.elapsed, closeTo(5.0, 0.05));
    });
  });

  group('going the wrong way', () {
    test('driving backwards is noticed, and briefly sliding is not', () {
      // Mutation: raise the flag the moment progress goes negative. A car
      // sliding through a corner spends single steps pointing anywhere at all,
      // and a warning that flashed on each of those would be noise.
      final it = Race();
      driveRound(it, seconds: 6.0);
      expect(it.player.wrongWay, isFalse);

      turnAround(it);
      it.simulation.events.clear();
      var announced = 0;
      driveRound(
        it,
        seconds: 6.0,
        backwards: true,
        watch: () {
          announced += it.simulation.events
              .drain()
              .whereType<WentWrongWay>()
              .length;
        },
      );

      expect(it.player.wrongWay, isTrue);
      // **Once, not once a step.** The flag this replaces could only say
      // "started this step" and a test could only ask about the last one;
      // counting is what actually says a warning does not flash.
      expect(
        announced,
        1,
        reason: 'it was announced on every step it kept going backwards',
      );
    });

    test('a moment going backwards is not going the wrong way', () {
      // Mutation: raise the flag the moment progress goes negative. A car
      // sliding through a corner spends single steps travelling backwards along
      // the track, and a warning that flashed on each of those is a warning a
      // player learns to ignore.
      final it = Race();
      driveRound(it, seconds: 6.0);

      turnAround(it);
      // A couple of metres back, well under the dozen it takes to mean it.
      driveRound(it, seconds: 0.6, throttle: 0.3, backwards: true);

      expect(it.player.wrongWay, isFalse);
    });

    test('turning round again clears it', () {
      final it = Race();
      driveRound(it, seconds: 4.0);
      turnAround(it);
      driveRound(it, seconds: 6.0, backwards: true);
      expect(it.player.wrongWay, isTrue);

      turnAround(it);
      driveRound(it, seconds: 8.0);

      expect(it.player.wrongWay, isFalse);
    });
  });

  group('leaving the track', () {
    test('a car that falls off the world is put back on the track', () {
      // Mutation: put the car back and leave the broadphase alone. It would be
      // holding the car where it fell, so the first sweep after the respawn
      // would find whatever was there — the classic "respawned inside a wall".
      final it = Race();
      driveRound(it, seconds: 6.0);
      final wasAt = it.player.s;

      it.vehicles[0].placeAt(
        Vector3(0.0, -200.0, 0.0),
        0.0,
        trackDistance: wasAt,
      );
      it.simulation.step(_step);

      expect(it.simulation.events.drain().whereType<Respawned>(), isNotEmpty);
      expect(it.vehicles[0].position.y, greaterThan(-10.0));
      expect(it.vehicles[0].speed, 0.0);
    });

    test('a car put back faces the way the track goes', () {
      final it = Race();
      driveRound(it, seconds: 10.0);

      it.vehicles[0].placeAt(
        Vector3(0.0, -200.0, 0.0),
        0.0,
        trackDistance: it.player.s,
      );
      it.simulation.step(_step);

      final tangent = Vector3.zero();
      it.track.centre.tangentAt(it.vehicles[0].trackDistance, tangent);
      final facing = Vector3(
        math.sin(it.vehicles[0].headingYaw),
        0.0,
        math.cos(it.vehicles[0].headingYaw),
      );

      expect(facing.dot(tangent), greaterThan(0.9));
    });

    test('running wide is not the same as leaving the road', () {
      final it = Race();
      driveRound(it, seconds: 6.0);

      expect(it.player.offRoad, isFalse);
      expect(it.player.lateral.abs(), lessThan(9.0));
    });
  });

  group('the lights', () {
    test('nobody moves until they go out', () {
      // Mutation: start the race running. Every car would be away before the
      // countdown had finished, which is a race with no start.
      final it = Race(mode: RaceMode.race, cars: 2);
      expect(it.race.phase, RacePhase.countdown);

      driveRound(it, seconds: 2.0, throttle: 1.0);

      expect(it.race.phase, RacePhase.countdown);
      for (final car in it.vehicles) {
        expect(car.speed, 0.0);
      }
      // The wheels have been turning, which is what the throttle is for on the
      // line.
      expect(it.vehicles[0].wheelSpeed, greaterThan(0.0));
    });

    test('on the grid the throttle is heard and nothing else is', () {
      // Mutation: pass the driver's whole input through during the countdown.
      //
      // Not tested through the steering, which would prove nothing: a car held
      // on the line has no speed, and steering turns a car in proportion to how
      // fast it is going, so the wheel is inert on the grid either way. The
      // brake is the one that tells them apart — a driver holding both pedals,
      // which is exactly what a driver does waiting for lights, would have the
      // brake win and sit there with the engine idling.
      final it = Race(mode: RaceMode.race, cars: 2);

      for (var i = 0; i < 90; i++) {
        it.simulation.inputs[0]
          ..throttle = 1.0
          ..brake = 1.0
          ..steer = 1.0;
        it.simulation.step(_step);
      }

      expect(it.race.phase, RacePhase.countdown);
      expect(it.vehicles[0].speed, 0.0);
      expect(it.vehicles[0].wheelSpeed, greaterThan(1.0));
    });

    test('the lights tick once a second and then let everyone go', () {
      final it = Race(mode: RaceMode.race, cars: 2);
      var ticks = 0;
      var starts = 0;

      driveRound(
        it,
        seconds: 5.0,
        throttle: 1.0,
        watch: () {
          for (final event in it.simulation.events.drain()) {
            if (event is CountdownTicked) ticks += 1;
            if (event is RaceStarted) starts += 1;
          }
        },
      );

      expect(ticks, 3);
      expect(starts, 1);
      expect(it.race.phase, RacePhase.running);
      expect(it.vehicles[0].speed, greaterThan(1.0));
    });

    test('the free roam has no lights at all', () {
      final it = Race(mode: RaceMode.freeRoam);

      expect(it.race.phase, RacePhase.running);
      driveRound(it, seconds: 2.0);
      expect(it.vehicles[0].speed, greaterThan(1.0));
    });
  });

  group('who is in front', () {
    test('the car further round is ahead', () {
      final it = Race(mode: RaceMode.race, cars: 2);
      driveRound(it, seconds: 8.0);

      final leader = it.race.progress[0].s > it.race.progress[1].s ? 0 : 1;

      expect(it.race.positionOf(leader), 1);
      expect(it.race.positionOf(1 - leader), 2);
    });

    test('a lap ahead beats being further round this lap', () {
      // Mutation: rank on `s` alone. A car that has just crossed the line to
      // start its third lap has an `s` of nearly nought, so the leader would be
      // shown last every time it completed a lap.
      final it = Race(mode: RaceMode.race, cars: 2, laps: 5);
      it.race.progress[0]
        ..lap = 2
        ..s = 5.0;
      it.race.progress[1]
        ..lap = 1
        ..s = it.track.length - 5.0;

      expect(it.race.positionOf(0), 1);
      expect(it.race.positionOf(1), 2);
    });

    test('a car that has finished stays ahead of one still going', () {
      // Mutation: rank everyone on distance. A winner slowing down after the
      // flag would be overtaken in the standings by somebody a lap down.
      final it = Race(mode: RaceMode.race, cars: 2, laps: 2);
      it.race.progress[0]
        ..lap = 2
        ..s = 1.0
        ..finishedAt = 90.0;
      it.race.progress[1]
        ..lap = 1
        ..s = it.track.length - 1.0;

      expect(it.race.positionOf(0), 1);
    });
  });

  group('cars meeting each other', () {
    test('two cars do not end up inside one another', () {
      // Mutation: let each car give way to the other by the full overlap. Two
      // cars would then swap places through each other rather than touch.
      final it = Race(mode: RaceMode.race, cars: 2);
      driveRound(it, seconds: 4.0, throttle: 1.0);

      // Put them on top of each other and let the step sort it out.
      final target = it.vehicles[0].position.clone();
      it.vehicles[1].placeAt(
        target,
        it.vehicles[1].headingYaw,
        trackDistance: it.vehicles[0].trackDistance,
      );

      it.simulation.step(_step);

      final apart = it.vehicles[0].position.distanceTo(it.vehicles[1].position);
      expect(apart, greaterThan(1.0));
    });

    test('separating them does not move the pair down the road', () {
      // Symmetry: the midpoint between two cars pushed apart is where it was.
      // A one-sided push would shuffle a car across the track every time it was
      // touched, which in a pack is a car being carried sideways into a wall.
      final it = Race(mode: RaceMode.race, cars: 2);
      driveRound(it, seconds: 4.0, throttle: 1.0);

      final target = it.vehicles[0].position.clone();
      it.vehicles[1].placeAt(
        target.clone()..x += 0.4,
        it.vehicles[1].headingYaw,
        trackDistance: it.vehicles[0].trackDistance,
      );
      final before = (it.vehicles[0].position + it.vehicles[1].position)
        ..scale(0.5);
      final axis = (it.vehicles[1].position - it.vehicles[0].position)
        ..normalize();

      it.simulation.step(_step);

      final after = (it.vehicles[0].position + it.vehicles[1].position)
        ..scale(0.5);
      // Measured along the axis the two were pushed apart on, and not as plain
      // distance: both cars are also driving, so the midpoint travels most of a
      // third of a metre down the road in a step whatever happens between them.
      // A one-sided push would move it half the overlap sideways — half a metre
      // for two cars this close.
      expect((after - before).dot(axis).abs(), lessThan(0.1));
    });
  });

  group('finishing', () {
    test('the race ends when everyone has done the laps', () {
      final it = Race(mode: RaceMode.race, cars: 1, laps: 1);

      driveRound(it, seconds: 60.0, throttle: 0.8);

      expect(it.player.finished, isTrue);
      expect(it.player.finishedAt, isNotNull);
      expect(it.race.phase, RacePhase.finished);
    });

    test('a finished race stops counting', () {
      final it = Race(mode: RaceMode.race, cars: 1, laps: 1);
      driveRound(it, seconds: 60.0, throttle: 0.8);
      final at = it.race.elapsed;

      driveRound(it, seconds: 2.0);

      expect(it.race.elapsed, at);
    });

    test('a time trial never ends on its own', () {
      final it = Race(cars: 1, laps: 1);

      driveRound(it, seconds: 60.0, throttle: 0.8);

      expect(it.player.lap, greaterThanOrEqualTo(1));
      expect(it.player.finished, isFalse);
      expect(it.race.phase, RacePhase.running);
    });
  });

  group('determinism', () {
    test('the same race twice is the same race to the bit', () {
      // Everything downstream rests on this: ghosts, replays, the playthrough
      // test, and two machines agreeing about a lap time.
      List<double> run() {
        final it = Race(mode: RaceMode.race, cars: 3);
        driveRound(it, seconds: 20.0, throttle: 0.9);
        return <double>[
          for (final car in it.vehicles) ...<double>[
            car.position.x,
            car.position.y,
            car.position.z,
            car.headingYaw,
          ],
        ];
      }

      final first = run();
      final second = run();

      expect(first.length, second.length);
      for (var i = 0; i < first.length; i++) {
        expect(first[i], second[i]);
      }
    });
  });

  group('the outcome every game shares', () {
    test('counts the countdown as playing', () {
      // The grid with the lights on is a moment inside a race, not an outcome.
      expect(RacePhase.countdown.outcome, RunOutcome.playing);
      expect(RacePhase.running.outcome, RunOutcome.playing);
    });

    test('and a race has no losing phase, which is the genre', () {
      // Everybody who starts crosses the line eventually, and coming last is a
      // position rather than a defeat. A time limit would grow one, and this
      // test is where somebody would notice they had.
      expect(RacePhase.finished.outcome, RunOutcome.won);
      expect(
        RacePhase.values.map((RacePhase p) => p.outcome),
        isNot(contains(RunOutcome.lost)),
      );
    });
  });

  group('what a step says happened', () {
    // The flags these events replace lived on one RacerProgress each, so a
    // caller found out *who* by knowing whose flag it had just read. That
    // works while you walk the grid in a loop and stops working the moment
    // anything wants the field's moments in the order they happened.

    test('a lap and the record it set arrive in that order', () {
      final it = Race(laps: 3);
      final order = <String>[];
      driveRound(
        it,
        seconds: 40.0,
        watch: () {
          for (final event in it.simulation.events.drain()) {
            if (event is LapCompleted) order.add('lap');
            if (event is BestLapSet) order.add('best');
          }
        },
      );

      expect(order, isNotEmpty, reason: 'nobody completed a lap');
      expect(order.first, 'lap');
      expect(order[1], 'best', reason: 'a first lap is always a best lap');
    });

    test('and every one of them names the car it happened to', () {
      final it = Race(cars: 2, laps: 2);
      final seen = <int>{};
      driveRound(
        it,
        seconds: 30.0,
        watch: () {
          for (final event in it.simulation.events.drain()) {
            if (event is! RacerEvent) continue;
            seen.add(event.racer.index);
            // The shorthand the base exists for, and the question a HUD asks
            // of every event it is handed.
            expect(event.isPlayer, event.racer.index == 0);
          }
        },
      );

      expect(seen, contains(0), reason: 'the player did nothing worth saying');
      expect(
        seen.length,
        greaterThan(1),
        reason: 'only one car was ever mentioned, on a grid of two',
      );
    });

    test('the countdown counts down, once per light', () {
      final it = Race(mode: RaceMode.race, laps: 1);
      final lights = <int>[];
      for (var i = 0; i < 300; i++) {
        it.simulation.step(_step);
        for (final event in it.simulation.events.drain()) {
          if (event is CountdownTicked) lights.add(event.remaining);
        }
      }

      expect(lights, <int>[2, 1, 0]);
    });
  });
}
