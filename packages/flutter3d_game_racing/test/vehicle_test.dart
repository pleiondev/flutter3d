import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// An infinite flat floor of one named surface.
///
/// Most of what a car does has nothing to do with the shape of a track, and a
/// test about braking distance should not also be a test about a circuit. This
/// is the reason [GroundField] is an interface.
final class FlatGround implements GroundField {
  FlatGround({this.height = 0.0, this.surface, this.extent = double.infinity});

  final double height;
  final String? surface;

  /// How far the floor reaches from the origin, so that a test can drive off
  /// the end of the world.
  final double extent;

  @override
  bool sample(Vector3 position, double nearHint, GroundSample out) {
    out
      ..s = position.z
      ..lateral = position.x
      ..onRoad = true
      ..barrier = false
      ..halfWidth = 0.0
      ..surface = surface;
    out.normal.setValues(0.0, 1.0, 0.0);
    if (position.x.abs() > extent || position.z.abs() > extent) return false;
    out.height = height;
    return true;
  }
}

/// A car on a flat floor, at rest at the origin, pointing along +z.
({SphereVehicle car, CollisionWorld world}) onFlat({
  String? surface,
  GripTable? grips,
  Tyres? tyres,
  VehicleTuning tuning = const VehicleTuning(),
  double extent = double.infinity,
}) {
  final world = CollisionWorld();
  final car = SphereVehicle(
    world: world,
    ground: FlatGround(surface: surface, extent: extent),
    position: Vector3(0.0, tuning.rideHeight, 0.0),
    tuning: tuning,
    // A table on its own still reads as "what the surfaces are worth", which is
    // what most of this file is about; the tyres it belongs to are the road
    // ones unless a test says otherwise.
    tyres:
        tyres ??
        (grips == null ? Tyres.road : Tyres(name: 'test', grips: grips)),
  );
  return (car: car, world: world);
}

const double _step = 1 / 60;

/// Drives for [seconds] with one unchanging input.
void drive(
  SphereVehicle car, {
  double seconds = 1.0,
  double throttle = 0.0,
  double brake = 0.0,
  double steer = 0.0,
  bool handbrake = false,
  void Function(SphereVehicle car, double time)? watch,
}) {
  final input = VehicleInput()
    ..throttle = throttle
    ..brake = brake
    ..steer = steer
    ..handbrake = handbrake;

  final steps = (seconds / _step).round();
  for (var i = 0; i < steps; i++) {
    car.step(_step, input);
    watch?.call(car, (i + 1) * _step);
  }
}

/// Brings a car up to [target] metres per second, however long that takes.
///
/// Needed wherever two surfaces are compared: a car on ice takes far longer to
/// reach a speed than one on asphalt, and comparing them after the same
/// *duration* compares two different speeds and calls the difference grip.
void driveUpTo(SphereVehicle car, double target, {double limit = 25.0}) {
  final input = VehicleInput()..throttle = 1.0;
  final steps = (limit / _step).round();
  for (var i = 0; i < steps && car.speed < target; i++) {
    car.step(_step, input);
  }
}

void main() {
  test('the suspension settles the same at any frame rate', () {
    // **Written because an extraction found the hole.** The ride height eases
    // towards the road by `1 - exp(-rate * dt)`, which was retyped at six call
    // sites across four packages before it became `easeFactor`. Replacing it
    // with a plain `rate * dt` — the mistake it exists to prevent — left every
    // test in this package passing, and a car whose suspension is stiffer on a
    // slow machine is a car that handles differently on two computers running
    // the same replay.
    double settleFrom(double dt, int steps) {
      final it = onFlat();
      // Dropped a quarter of a metre, then left to settle for a fixed sixth of
      // a second of *simulated* time at two different step sizes.
      it.car.collider.position.y += 0.25;
      for (var i = 0; i < steps; i++) {
        it.car.step(dt, VehicleInput());
      }
      return it.car.collider.position.y;
    }

    final slow = settleFrom(1 / 30.0, 5);
    final fast = settleFrom(1 / 240.0, 40);

    expect(
      fast,
      closeTo(slow, 1e-3),
      reason:
          'the same sixth of a second settled to $slow at 30 Hz and '
          '$fast at 240',
    );
  });

  group('going in a straight line', () {
    test('the throttle gathers speed and the drag ends it', () {
      // Mutation: leave the air drag out. Top speed would then be whatever
      // `maxSpeed` says the wheels do, reached instantly and held exactly,
      // which is a car with no character at all — and a straight where the
      // slipstream and the exit of the last corner stop mattering.
      final it = onFlat(surface: 'asphalt');
      final speeds = <double>[];

      drive(
        it.car,
        seconds: 20.0,
        throttle: 1.0,
        watch: (car, time) => speeds.add(car.speed),
      );

      expect(speeds.first, lessThan(2.0));
      expect(it.car.speed, greaterThan(30.0));
      expect(it.car.speed, lessThan(it.car.tuning.maxSpeed));

      // Monotone: a car that gains speed in fits is a car whose tyre curve is
      // being crossed the wrong way.
      for (var i = 1; i < speeds.length; i++) {
        expect(speeds[i], greaterThanOrEqualTo(speeds[i - 1] - 1e-9));
      }
    });

    test('it goes where it is pointing', () {
      final it = onFlat(surface: 'asphalt');

      drive(it.car, seconds: 5.0, throttle: 1.0);

      expect(it.car.position.z, greaterThan(10.0));
      expect(it.car.position.x.abs(), lessThan(0.01));
      expect(it.car.slipAngle.abs(), lessThan(0.01));
    });

    test('the brakes stop it, and ice takes far longer', () {
      // Mutation: read the grip table but never multiply it in. Every surface
      // would stop the car in the same distance, and the ice would be paint.
      double stoppingDistance(String surface) {
        final it = onFlat(surface: surface);
        drive(it.car, seconds: 6.0, throttle: 1.0);
        final from = it.car.position.z;
        drive(it.car, seconds: 8.0, brake: 1.0);
        return it.car.position.z - from;
      }

      final asphalt = stoppingDistance('asphalt');
      final ice = stoppingDistance('ice');

      expect(asphalt, greaterThan(5.0));
      expect(ice, greaterThan(asphalt * 2.5));
    });

    test('the wheels are not the car', () {
      // Mutation: drive the car straight from the throttle and report the slip
      // as nought. Everything below stops existing at once — wheelspin, lock-up
      // and, because the handbrake works by locking the wheels, drift.
      //
      // Under power the wheels always lead the road a little; how much depends
      // on what the road will take. On tarmac it is a few percent, which is
      // what a real car does. On ice the road takes almost nothing and the
      // surplus goes into wheels spinning on the spot.
      final asphalt = onFlat(surface: 'asphalt');
      final ice = onFlat(surface: 'ice');

      drive(asphalt.car, seconds: 3.0, throttle: 1.0);
      drive(ice.car, seconds: 3.0, throttle: 1.0);

      expect(asphalt.car.wheelSpeed, greaterThan(asphalt.car.speed));
      expect(asphalt.car.slipRatio, greaterThan(0.005));
      expect(asphalt.car.slipRatio, lessThan(0.15));

      expect(ice.car.slipRatio, greaterThan(0.5));
      expect(ice.car.wheelSpeed, greaterThan(ice.car.speed * 2));
    });
  });

  group('cornering', () {
    test('more lock is a tighter corner', () {
      double radius(double steer) {
        final it = onFlat(surface: 'asphalt');
        drive(it.car, seconds: 4.0, throttle: 1.0);
        final before = it.car.headingYaw;
        final from = it.car.position.clone();
        drive(it.car, seconds: 1.0, throttle: 0.4, steer: steer);
        final turned = (it.car.headingYaw - before).abs();
        return it.car.position.distanceTo(from) / math.max(turned, 1e-6);
      }

      expect(radius(1.0), lessThan(radius(0.35)));
    });

    test('positive steering is the driver\'s right, not the maths one', () {
      // Mutation: drop the negation in `_steer`. Everything downstream stays
      // self-consistent — the car drives, the AI gets round, every other test
      // here passes — and the wheel steers the other way, which is the first
      // thing anybody notices and the last thing the suite would have caught.
      //
      // Stated in the driver's terms rather than in world axes, because world
      // axes are exactly what is easy to get backwards: right is `forward × up`,
      // which for a car facing +z is −x.
      final leftward = onFlat(surface: 'asphalt');
      final rightward = onFlat(surface: 'asphalt');

      drive(leftward.car, seconds: 3.0, throttle: 1.0);
      drive(rightward.car, seconds: 3.0, throttle: 1.0);

      final forward = Vector3(
        math.sin(rightward.car.headingYaw),
        0.0,
        math.cos(rightward.car.headingYaw),
      );
      final right = forward.cross(Vector3(0.0, 1.0, 0.0))..normalize();
      final from = rightward.car.position.clone();

      drive(leftward.car, seconds: 2.0, throttle: 0.5, steer: -1.0);
      drive(rightward.car, seconds: 2.0, throttle: 0.5, steer: 1.0);

      expect(
        (rightward.car.position - from).dot(right),
        greaterThan(1.0),
        reason: 'a positive wheel should take the car to the driver\'s right',
      );
      expect(
        (leftward.car.position - from).dot(right),
        lessThan(-1.0),
        reason: 'and a negative one the other way',
      );
    });

    test('a corner taken flat out runs wider than one taken at a sensible '
        'speed', () {
      // The limit has to be findable, which means going faster has to stop
      // working at some point. Without a peak in the tyre curve it never does.
      double sidewaysTravel(double throttleFirst) {
        final it = onFlat(surface: 'asphalt');
        drive(it.car, seconds: 6.0, throttle: throttleFirst);
        final from = it.car.position.clone();
        final heading = it.car.headingYaw;
        drive(it.car, seconds: 2.0, throttle: throttleFirst, steer: 1.0);
        // How far the car actually went round, per unit of nose rotation.
        return (it.car.headingYaw - heading).abs() /
            math.max(it.car.position.distanceTo(from), 1e-6);
      }

      // Turned-per-metre is higher at the lower speed: the fast car is running
      // wide.
      expect(sidewaysTravel(0.35), greaterThan(sidewaysTravel(1.0)));
    });
  });

  group('losing grip', () {
    test('the handbrake breaks traction, and lifting off restores it', () {
      // Mutation: give the handbrake its own lateral grip multiplier, making it
      // a drift button. It would pass this test and fail the design: a drift
      // that is a mode is a drift that cannot be provoked any other way, cannot
      // be caught, and cannot be scored by anything except the button.
      //
      // Nothing here reaches for a drift setting. The handbrake locks the
      // wheels; the tyres spend their whole budget stopping them; there is
      // nothing left holding the car sideways, and the steering keeps turning
      // the nose. The slide is what falls out.
      final sliding = onFlat(surface: 'asphalt');
      drive(sliding.car, seconds: 6.0, throttle: 1.0);
      drive(sliding.car, seconds: 1.2, steer: 1.0, handbrake: true);

      final gripping = onFlat(surface: 'asphalt');
      drive(gripping.car, seconds: 6.0, throttle: 1.0);
      drive(gripping.car, seconds: 1.2, throttle: 1.0, steer: 1.0);

      expect(
        sliding.car.slipAngle.abs(),
        greaterThan(sliding.car.tires.peakSlipAngle),
        reason: 'the handbrake should push the tyres past their peak',
      );
      expect(
        gripping.car.slipAngle.abs(),
        lessThan(sliding.car.slipAngle.abs()),
        reason: 'the same steering without it should not',
      );
    });

    test('a slide is held, not survived for one step', () {
      // A drift worth scoring is one that lasts. If the tyre curve had no fall
      // past its peak, grip would rise with slip forever and every slide would
      // snap straight back.
      final it = onFlat(surface: 'asphalt');
      drive(it.car, seconds: 6.0, throttle: 1.0);

      var slidingFor = 0.0;
      drive(
        it.car,
        seconds: 2.0,
        steer: 1.0,
        handbrake: true,
        watch: (car, time) {
          if (car.slipAngle.abs() > car.tires.peakSlipAngle) {
            slidingFor += 1 / 60;
          }
        },
      );

      expect(slidingFor, greaterThan(0.5));
    });

    test('ice slides where asphalt grips, at the same speed', () {
      final ice = onFlat(surface: 'ice');
      final asphalt = onFlat(surface: 'asphalt');

      // Matched on speed rather than on time on the throttle. Ice takes several
      // times as long to reach twenty metres a second, and a comparison after
      // equal seconds would be comparing a slow car with a fast one.
      for (final car in <SphereVehicle>[ice.car, asphalt.car]) {
        driveUpTo(car, 20.0);
        drive(car, seconds: 1.5, throttle: 0.4, steer: 1.0);
      }

      expect(ice.car.slipAngle.abs(), greaterThan(asphalt.car.slipAngle.abs()));
    });

    test('braking in a corner costs cornering', () {
      // The friction circle, which is the one line that makes a driver choose.
      //
      // Measured as sideways speed gained over a short burst at a matched
      // starting speed, and not as how far round the car got. Braking slows the
      // car, a slower car turns its nose more slowly whatever the tyres are
      // doing, and a test that watched the heading would be reporting that and
      // calling it grip.
      double sidewaysGained({required double brake}) {
        final it = onFlat(surface: 'asphalt');
        driveUpTo(it.car, 30.0);

        final forward = Vector3(
          math.sin(it.car.headingYaw),
          0.0,
          math.cos(it.car.headingYaw),
        );
        final right = Vector3(forward.z, 0.0, -forward.x);
        final before = it.car.velocity.dot(right);

        drive(it.car, seconds: 0.25, steer: 1.0, brake: brake);
        return (it.car.velocity.dot(right) - before).abs();
      }

      final free = sidewaysGained(brake: 0.0);
      final braking = sidewaysGained(brake: 1.0);

      expect(braking, lessThan(free * 0.9));
    });
  });

  group('the world around the car', () {
    test('a wall at speed stops the car instead of being passed through', () {
      // Mutation: move the car by adding the velocity to the position. At fifty
      // metres a second a step covers most of a metre, so a car meets a wall by
      // arriving on the far side of it.
      final it = onFlat(surface: 'asphalt');
      it.world.add(
        Collider(
          shape: CollisionBox(Vector3(20.0, 4.0, 0.5)),
          position: Vector3(0.0, 2.0, 60.0),
        ),
      );

      drive(it.car, seconds: 12.0, throttle: 1.0);

      expect(it.car.position.z, lessThan(60.0));
      expect(it.car.position.z, greaterThan(50.0));
    });

    test('a car slides along a wall it meets at an angle', () {
      // Aimed at the wall rather than steered into it: holding the wheel over
      // would drive the car round in a circle, and what is being tested is the
      // contact, not the circle.
      final world = CollisionWorld();
      final car = SphereVehicle(
        world: world,
        ground: FlatGround(surface: 'asphalt'),
        position: Vector3(0.0, 0.55, 0.0),
        headingYaw: 0.35,
      );
      world.add(
        Collider(
          shape: CollisionBox(Vector3(0.5, 4.0, 120.0)),
          position: Vector3(6.0, 2.0, 100.0),
        ),
      );

      drive(car, seconds: 3.0, throttle: 1.0);
      final from = car.position.z;
      drive(car, seconds: 4.0, throttle: 1.0);

      expect(car.position.x, lessThan(6.0));
      expect(
        car.position.z,
        greaterThan(from + 5.0),
        reason: 'a car scraping a barrier should keep going, not stop dead',
      );
    });

    test('over nothing, the car falls', () {
      final it = onFlat(surface: 'asphalt', extent: 30.0);

      // Two seconds, not six: at full throttle six would have carried the car
      // off the far edge before the test had checked it was ever on it.
      drive(it.car, seconds: 2.0, throttle: 1.0);
      expect(it.car.grounded, isTrue);
      expect(it.car.position.z, lessThan(30.0));

      drive(it.car, seconds: 4.0, throttle: 1.0);

      expect(it.car.position.z, greaterThan(30.0));
      expect(it.car.grounded, isFalse);
      expect(it.car.position.y, lessThan(-5.0));
    });

    test('a banked corner leans the car with it', () {
      final track = TrackSpline(
        centre: CatmullRom(<Vector3>[
          for (var i = 0; i < 16; i++)
            Vector3(
              60 * math.cos(2 * math.pi * i / 16),
              0.0,
              60 * math.sin(2 * math.pi * i / 16),
            ),
        ]),
        widths: List<double>.filled(16, 14.0),
        banks: List<double>.filled(16, 0.25),
      );
      final world = CollisionWorld();
      final start = Vector3.zero();
      final forward = Vector3.zero();
      track.startSlot(0, start, forward);

      final car = SphereVehicle(
        world: world,
        ground: TrackField(track: track),
        position: start..y += 1.0,
        headingYaw: math.atan2(forward.x, forward.z),
      );

      drive(car, seconds: 2.0, throttle: 0.6);

      // The body's own up follows the road rather than the world.
      expect(car.grounded, isTrue);
      expect(car.visualBasis.getColumn(1).y, lessThan(0.995));
    });
  });

  group('what the ground probe may stand on', () {
    /// A ring with a floor beside it, which is what a real circuit has.
    ({
      SphereVehicle car,
      TrackSpline track,
      RaceState race,
      RacingSimulation sim,
    })
    onCircuit() {
      const points = 20;
      final centre = CatmullRom(<Vector3>[
        for (var i = 0; i < points; i++)
          Vector3(
            90 * math.cos(2 * math.pi * i / points),
            0.0,
            90 * math.sin(2 * math.pi * i / points),
          ),
      ]);
      final track = TrackSpline(
        centre: centre,
        widths: List<double>.filled(points, 12.0),
        banks: List<double>.filled(points, 0.12),
        shoulder: 4.0,
      );

      final world = CollisionWorld()
        ..add(
          Collider(
            // Wide enough that a car running wide off a ninety-metre circuit
            // is still over it after ten seconds at full throttle.
            shape: CollisionBox(Vector3(1200.0, 2.0, 1200.0)),
            position: Vector3(0.0, -7.0, 0.0),
          ),
        );

      final start = Vector3.zero();
      final forward = Vector3.zero();
      track.startSlot(0, start, forward);
      final car = SphereVehicle(
        world: world,
        ground: TrackField(track: track, world: world),
        position: start.clone()..y += 0.6,
        headingYaw: math.atan2(forward.x, forward.z),
      );
      car.placeAt(
        car.position,
        car.headingYaw,
        trackDistance: track.centre.wrap(track.grid.s),
      );

      final race = RaceState(
        mode: RaceMode.race,
        track: track,
        racers: 1,
        laps: 3,
      )..phase = RacePhase.running;

      return (
        car: car,
        track: track,
        race: race,
        sim: RacingSimulation(
          collision: world,
          vehicles: <SphereVehicle>[car],
          race: race,
        ),
      );
    }

    test('a car does not stand on itself', () {
      // Mutation: let the downward probe hit everything. The ray starts above
      // the car and points down, so the first thing in its way is the car's own
      // body — it reads the top of its own collider as the ground, settles up
      // towards it, and reads higher again next step. The car then climbs at
      // about twenty metres a second, in a straight line, on a flat road, while
      // reporting that it is on the ground. It is the sort of fault that looks
      // like a physics mystery and is one line of mask.
      final it = onCircuit();
      final startedAt = it.car.position.y;

      // Straight ahead on a circuit that curves: the car runs wide and off,
      // which is exactly where the probe stops finding road and starts asking
      // the world.
      for (var i = 0; i < 60 * 12; i++) {
        it.sim.inputs[0]
          ..throttle = 1.0
          ..steer = 0.0;
        it.sim.step(1 / 60);

        expect(
          it.car.position.y,
          lessThan(startedAt + 3.0),
          reason: 'the car gained height nothing gave it, at step $i',
        );
      }
    });

    test('off the road, the car lands on the ground beside it', () {
      // And is then put back, which is why this watches the whole run rather
      // than reading the end of it: a car driving straight off a circuit that
      // curves leaves, lands, drives out across the grass, gets returned to the
      // last checkpoint, and does it again. Any single moment is somewhere in
      // that cycle.
      final it = onCircuit();
      var landedOnGrass = 0;
      var returned = 0;
      var highest = -1e9;

      for (var i = 0; i < 60 * 10; i++) {
        it.sim.inputs[0]
          ..throttle = 1.0
          ..steer = 0.0;
        it.sim.step(1 / 60);

        highest = math.max(highest, it.car.position.y);
        returned += it.sim.events.drain().whereType<Respawned>().length;
        // The floor's top is at -5, and the car rides half a metre above it.
        if (it.car.grounded &&
            (it.car.position.y - (-5.0 + 0.55)).abs() < 0.2) {
          landedOnGrass += 1;
        }
      }

      expect(
        landedOnGrass,
        greaterThan(60),
        reason: 'the car should spend real time down on the grass',
      );
      expect(
        returned,
        greaterThan(0),
        reason: 'and should be put back on the track when it stays off',
      );
      expect(highest, lessThan(4.0));
    });
  });

  group('being put somewhere', () {
    test('a car put back on the track arrives stopped and straight', () {
      // Mutation: set the position and leave the rest. A car returning from a
      // spin would arrive still spinning, still sideways, and still carrying the
      // speed that put it off in the first place.
      final it = onFlat(surface: 'asphalt');
      drive(it.car, seconds: 6.0, throttle: 1.0);
      drive(it.car, seconds: 1.0, steer: 1.0, handbrake: true);

      it.car.placeAt(Vector3(0.0, 0.55, 0.0), 0.0);

      expect(it.car.speed, 0.0);
      expect(it.car.slipAngle, 0.0);
      expect(it.car.headingYaw, 0.0);
      expect(it.car.wheelSpeed, 0.0);
    });
  });

  group('determinism', () {
    test('the same drive twice is the same drive to the bit', () {
      // The simulation is replayed from recorded input: ghosts, playthrough
      // tests, and anything that has to agree between two machines.
      Vector3 finish() {
        final it = onFlat(surface: 'asphalt');
        drive(it.car, seconds: 4.0, throttle: 1.0);
        drive(it.car, seconds: 2.0, throttle: 0.7, steer: 0.8);
        drive(it.car, seconds: 1.0, brake: 1.0, steer: -0.4);
        return it.car.position.clone();
      }

      final first = finish();
      final second = finish();

      expect(first.x, second.x);
      expect(first.y, second.y);
      expect(first.z, second.z);
    });
  });

  group('the slipstream', () {
    // Named in this file's own comments as the thing that was missing: the
    // exit of the last corner stops mattering when a tow can hand the place
    // back on the straight.

    test('a sheltered car keeps more of its speed than a bare one', () {
      double coastFrom(double shelter) {
        final it = onFlat();
        final input = VehicleInput()..shelter = shelter;
        it.car.placeAt(it.car.position, 0.0, trackDistance: 0.0);
        it.car.velocity.setValues(0.0, 0.0, -60.0);
        for (var i = 0; i < 120; i++) {
          it.car.step(1 / 60, input);
        }
        return it.car.speed;
      }

      final bare = coastFrom(0.0);
      final towed = coastFrom(1.0);

      expect(towed, greaterThan(bare));
      // And by the amount the tuning says, not by an arbitrary one: a third of
      // the drag is escaped at a perfect tow.
      expect(towed - bare, greaterThan(0.05));
    });

    test('and a car with nothing in front of it is not sheltered', () {
      final input = VehicleInput();
      expect(input.shelter, 0.0);

      input.shelter = 0.5;
      input.reset();
      expect(input.shelter, 0.0, reason: 'a stale tow survived the reset');
    });
  });
}
