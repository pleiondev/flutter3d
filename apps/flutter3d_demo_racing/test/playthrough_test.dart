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

import 'package:flutter3d_demo_racing/src/circuits.dart';
import 'package:flutter3d_demo_racing/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

TrackDocument _shipped([String circuit = 'ring']) => TrackDocument.fromJson(
  jsonDecode(File('assets/tracks/$circuit.json').readAsStringSync())
      as Map<String, Object?>,
);

final class _Session {
  _Session({
    int cars = 1,
    RaceMode mode = RaceMode.timeTrial,
    String circuit = 'ring',
  }) {
    final document = _shipped(circuit);
    document.level?.addTo(world);

    // The shipped assembly. A harness that lines its own grid up is a harness
    // that agrees with any bug the game's has.
    final staged = stage(document, world, cars: cars, mode: mode, laps: 1);
    track = staged.track;
    race = staged.race;
    cars_.addAll(staged.cars);
    simulation = staged.sim;
    ai = staged.ai;
  }

  final CollisionWorld world = CollisionWorld();
  final List<SphereVehicle> cars_ = <SphereVehicle>[];
  late final TrackSpline track;
  late final RaceState race;
  late final RacingSimulation simulation;
  late final AiDriver ai;

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

    expect(
      it.player.lap,
      greaterThanOrEqualTo(1),
      reason: 'the shipped circuit must be driveable all the way round',
    );
    expect(
      respawns,
      0,
      reason: 'nothing on the racing line should need a reset',
    );

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
      reason:
          'a lap outside this range means the car or the circuit changed '
          'by a lot — which may well be right, and should be a deliberate '
          'edit to these numbers rather than a surprise',
    );
  });

  group('the second circuit', () {
    // **A circuit nothing drives is a circuit nobody has driven.** The gorge
    // came out of the same generator as the ring with nine numbers changed,
    // which is exactly the kind of change that produces a road with a corner
    // too tight to hold, a checkpoint in a wall, or a lap that cannot be
    // completed at all — and none of that shows in a file that parses.
    test('is a road, and a different one from the ring', () {
      final gorge = _shipped('gorge').track;
      final ring = _shipped().track;

      expect(gorge.length, greaterThan(500.0));
      expect(
        gorge.length,
        lessThan(ring.length),
        reason: 'the tighter circuit came out longer than the open one',
      );
      expect(gorge.checkpoints.length, greaterThan(ring.checkpoints.length));

      // Narrower, and still wide enough for the grid it starts.
      var narrowest = double.infinity;
      for (var s = 0.0; s < gorge.length; s += 5.0) {
        narrowest = math.min(narrowest, gorge.widthAt(s));
      }
      expect(narrowest, greaterThan(8.0));
      expect(narrowest, lessThan(11.0), reason: 'it is not the tighter one');
    });

    test('and can be driven all the way round', () {
      final it = _Session(circuit: 'gorge');
      var respawns = 0;
      var offRoadSteps = 0;

      it.driveFor(
        120.0,
        watch: () {
          if (it.player.respawnedThisStep) respawns += 1;
          if (it.player.offRoad) offRoadSteps += 1;
        },
      );

      expect(
        it.player.lap,
        greaterThanOrEqualTo(1),
        reason: 'the second circuit cannot be got round',
      );
      expect(respawns, 0);
      // The same tenth the ring is held to: this road is narrower and hillier,
      // and a driver that cannot stay on it is a road that cannot be raced.
      expect(offRoadSteps / (120.0 / _dt), lessThan(0.1));
    });
  });

  group('every circuit in the season', () {
    // **The gorge's tests, once each for the three that came after it** —
    // written over the season's own list rather than copied per circuit, so
    // a sixth circuit is covered the day it is added to `Season.circuits`
    // and not the day somebody remembers. What the gorge taught is that a
    // circuit is nine numbers away from being undriveable, and that none of
    // those nine is visible in a file that parses.
    for (final circuit in Season.circuits) {
      group(circuit.name, () {
        test('is a road a grid fits on, with its checkpoints in order', () {
          final track = _shipped(circuit.name).track;

          expect(track.length, greaterThan(500.0));
          for (var s = 0.0; s < track.length; s += 5.0) {
            expect(
              track.widthAt(s),
              greaterThan(8.0),
              reason: 'narrower than two cars at $s m',
            );
          }

          // Mutation: write the checkpoints as fractions of a lap the
          // generator got the wrong way round. `TrackSpline` refuses those;
          // what it cannot refuse is a checkpoint on the line itself, which
          // a lap counter walks past before the lap has begun.
          expect(track.checkpoints, isNotEmpty);
          expect(track.checkpoints.first, greaterThan(0.0));
          expect(track.checkpoints.last, lessThan(track.length));
          for (var i = 1; i < track.checkpoints.length; i++) {
            expect(track.checkpoints[i], greaterThan(track.checkpoints[i - 1]));
          }
        });

        test('can be driven all the way round, past every checkpoint', () {
          final it = _Session(circuit: circuit.name);
          var respawns = 0;
          var offRoadSteps = 0;
          var passed = 0;

          it.driveFor(
            120.0,
            watch: () {
              if (it.player.respawnedThisStep) respawns += 1;
              if (it.player.offRoad) offRoadSteps += 1;
              if (it.player.checkpointThisStep) passed += 1;
            },
          );

          expect(
            it.player.lap,
            greaterThanOrEqualTo(1),
            reason: '${circuit.name} cannot be got round',
          );
          expect(respawns, 0, reason: 'the racing line needed a reset');
          expect(offRoadSteps / (120.0 / _dt), lessThan(0.1));
          expect(passed, greaterThanOrEqualTo(it.track.checkpoints.length));

          // Not a number: a range set by the road. Nothing here can average
          // more than the car's sixty metres a second, and a lap of the
          // longest circuit slower than a minute is a circuit the reference
          // driver spent half of on the grass.
          final lap = it.player.bestLap!;
          expect(lap, greaterThan(it.track.length / 60.0));
          expect(
            lap,
            lessThan(60.0),
            reason: 'a lap of ${circuit.name} takes $lap s',
          );
        });

        test('and the rivals get round it too', () {
          // The driver above is the test's own. This is the one the game
          // ships: a field of `AiDriver`s, avoiding each other, on the
          // circuit as it is raced. A circuit the rivals cannot lap is a
          // race the player wins by standing still.
          final it = _Session(
            circuit: circuit.name,
            cars: kFieldSize,
            mode: RaceMode.race,
          );
          final respawns = List<int>.filled(kFieldSize, 0);
          final steps = (150.0 / _dt).round();

          for (var step = 0; step < steps; step++) {
            for (var i = 0; i < kFieldSize; i++) {
              it.ai.drive(
                it.cars_[i],
                it.simulation.inputs[i],
                others: it.cars_,
              );
            }
            it.simulation.step(_dt);
            for (var i = 0; i < kFieldSize; i++) {
              if (it.race.progress[i].respawnedThisStep) respawns[i] += 1;
            }
          }

          for (var i = 0; i < kFieldSize; i++) {
            expect(
              it.race.progress[i].lap,
              greaterThanOrEqualTo(1),
              reason: 'rival $i never finished a lap of ${circuit.name}',
            );
            expect(
              respawns[i],
              lessThan(3),
              reason: 'rival $i was put back ${respawns[i]} times',
            );
          }
        });
      });
    }
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

  group('the loop this game did not have', () {
    // **It drove `FixedStep` directly**, so it had no pause, no
    // `beginStep`/`endStep` around a step — `InputState.pressed` never worked
    // here at all — and no way to notice the simulated time the clock refused
    // to run.
    test('runs the race while nothing is in the way', () {
      var steps = 0;
      final input = InputState();
      final loop = GameLoop(input: input, onStep: (double _) => steps++);

      loop.paused = shouldPause(
        ready: true,
        menuOpen: false,
        pointerIsTheGate: false,
        pointerHeld: false,
        padConnected: false,
      );
      loop.advance(0.5);

      expect(steps, greaterThan(0));
    });

    test('and stands still while the player has stopped it', () {
      // Mutation: feed `menuOpen: false` regardless. Escape stops looking like
      // a pause and the race carries on behind the overlay — which is the bug
      // both other games shipped before the gate was written.
      var steps = 0;
      final input = InputState();
      final loop = GameLoop(input: input, onStep: (double _) => steps++);

      loop.paused = shouldPause(
        ready: true,
        menuOpen: true,
        pointerIsTheGate: false,
        pointerHeld: false,
        padConnected: false,
      );
      loop.advance(0.5);

      expect(steps, 0);
    });

    test('and does not accumulate time while the circuit is still loading', () {
      // The clause the dungeon's hand-written copy of this gate was missing.
      var steps = 0;
      final input = InputState();
      final loop = GameLoop(input: input, onStep: (double _) => steps++);

      loop.paused = shouldPause(
        ready: false,
        menuOpen: false,
        pointerIsTheGate: false,
        pointerHeld: false,
        padConnected: false,
      );
      loop.advance(5.0);

      expect(steps, 0);
    });

    test('and says so when the machine cannot keep up', () {
      // Silent slow motion: the loop refuses to run more than a few steps for
      // one frame and throws the rest away. This game showed nothing at all.
      final pace = Pace();
      final loop = GameLoop(input: InputState(), onStep: (double _) {});

      // A second of real time asked of a loop that will run a handful of steps.
      for (var i = 0; i < 8; i++) {
        loop.advance(1.0);
        pace.note(
          dropped: loop.clock.droppedSteps,
          dt: 1.0,
          stepSeconds: loop.clock.stepSeconds,
        );
      }

      expect(pace.behind, isTrue);
      expect(pace.lost, greaterThan(0.0));
    });
  });
}
