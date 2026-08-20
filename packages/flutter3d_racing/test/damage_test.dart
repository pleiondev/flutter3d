/// What hitting things costs.
///
///     flutter test test/damage_test.dart
///
/// **The sweep used to throw the answer away.** Speed driven into a wall was
/// taken out of the car and nothing was told: scraping a track barrier threw
/// sparks, and hitting one of the pillars the circuit is measured against was
/// silent and free. A car could be driven into scenery at a hundred miles an
/// hour, all race, at no cost but the seconds — which made the wall the fastest
/// way through some corners.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class _Ground implements GroundField {
  _Ground({this.barrier = false, this.halfWidth = 0.0});

  final bool barrier;
  final double halfWidth;

  @override
  bool sample(Vector3 position, double nearHint, GroundSample out) {
    out
      ..s = position.z
      ..lateral = position.x
      ..onRoad = true
      ..barrier = barrier
      ..halfWidth = halfWidth
      ..surface = 'asphalt'
      ..height = 0.0;
    out.normal.setValues(0.0, 1.0, 0.0);
    return true;
  }
}

const double _step = 1 / 60;
const VehicleTuning _tuning = VehicleTuning();

({SphereVehicle car, CollisionWorld world}) _onRoad({
  bool barrier = false,
  double halfWidth = 0.0,
}) {
  final world = CollisionWorld();
  final car = SphereVehicle(
    world: world,
    ground: _Ground(barrier: barrier, halfWidth: halfWidth),
    position: Vector3(0.0, _tuning.rideHeight, 0.0),
  );
  return (car: car, world: world);
}

/// A wall across the road, [away] metres ahead.
void _wallAt(CollisionWorld world, double away) => world.add(Collider(
      shape: CollisionBox(Vector3(20.0, 4.0, 1.0)),
      position: Vector3(0.0, 2.0, away),
      kind: ColliderKind.static,
    ));

void _drive(SphereVehicle car, VehicleInput input, double seconds) {
  for (var step = 0; step < (seconds / _step).round(); step++) {
    car.step(_step, input);
  }
}

/// Brings a car up to [target] and drives it into whatever is ahead, stopping
/// on the step it arrives.
///
/// Returns the speed it arrived at.
///
/// **Two things the first version of this got wrong, both of which made the
/// test agree with anything.** It held the throttle down all the way to the
/// wall, so a car aimed at a wall a hundred metres away arrived at fifty
/// however slowly it set off — the two crashes it was comparing were the same
/// crash. And it then left the throttle down *against* the wall, so the car
/// went on hitting it sixty times a second and what got measured was a pile of
/// impacts rather than one. It coasts in now, and stops on the step it lands.
double _crashInto(SphereVehicle car, double target) {
  final throttle = VehicleInput()..throttle = 1.0;
  for (var step = 0; step < 60 * 30 && car.speed < target; step++) {
    car.step(_step, throttle);
  }
  final coast = VehicleInput();
  for (var step = 0; step < 60 * 30; step++) {
    car.step(_step, coast);
    if (car.struckThisStep > 0.0) return car.struckThisStep;
  }
  return 0.0;
}

void main() {
  test('a car that hits a wall is broken by it', () {
    final it = _onRoad();
    _wallAt(it.world, 120.0);

    final speed = _crashInto(it.car, 30.0);

    expect(speed, greaterThan(20.0), reason: 'it never reached the wall');
    expect(it.car.damage, greaterThan(0.15),
        reason: 'a shunt at ${speed}m/s cost ${it.car.damage}');
    expect(it.car.struckThisStep, greaterThan(0.0));

    // A step edge: it says what happened, not what is.
    it.car.step(_step, VehicleInput());
    expect(it.car.struckThisStep, 0.0,
        reason: 'the impact is still being reported a step later');
  });

  test('and the harder it hits the more it costs', () {
    final slow = _onRoad();
    _wallAt(slow.world, 40.0);
    final slowly = _crashInto(slow.car, 14.0);

    final fast = _onRoad();
    _wallAt(fast.world, 160.0);
    final quickly = _crashInto(fast.car, 34.0);

    expect(quickly, greaterThan(slowly * 2.0),
        reason: 'the two crashes were the same crash: $slowly and $quickly');
    expect(fast.car.damage, greaterThan(slow.car.damage * 2.0),
        reason: 'slow ${slow.car.damage}, fast ${fast.car.damage}');
  });

  test('and a nudge is free, because a racing line touches things', () {
    // A game that charged for a kerb would be a game about not racing.
    final car = SphereVehicle(
      world: CollisionWorld(),
      ground: _Ground(),
      position: Vector3(0.0, _tuning.rideHeight, 0.0),
    );

    car.hurt(_tuning.impactShrugged - 0.5);

    expect(car.damage, 0.0);
  });

  test('and no car is ever more than wrecked', () {
    final car = SphereVehicle(
      world: CollisionWorld(),
      ground: _Ground(),
      position: Vector3(0.0, _tuning.rideHeight, 0.0),
    );

    for (var crash = 0; crash < 50; crash++) {
      car.hurt(40.0);
    }

    expect(car.damage, 1.0);
  });

  test('a barrier breaks a car exactly as much as a pillar does', () {
    // **The two were different for no reason a driver could see.** The track's
    // own barrier — which is not geometry, it is a number in the document —
    // threw sparks and cost nothing, and a wall built out of brushes did the
    // same nothing. Arriving at either at forty is the same arrival.
    final it = _onRoad(barrier: true, halfWidth: 4.0);
    final into = VehicleInput()
      ..throttle = 1.0
      ..steer = 1.0;

    _drive(it.car, into, 6.0);

    expect(it.car.scrapedThisStep, greaterThan(0.0),
        reason: 'the car never reached the barrier');
    expect(it.car.damage, greaterThan(0.0));
  });

  group('a broken car', () {
    /// How far a car gets from a standstill in [seconds], full throttle.
    double reach(double damage, {double seconds = 8.0}) {
      final it = _onRoad();
      it.car.damage = damage;
      _drive(it.car, VehicleInput()..throttle = 1.0, seconds);
      return it.car.position.z;
    }

    test('gets going more slowly', () {
      // **Two seconds, because eight measures the wrong thing.** Given long
      // enough every car is at its top speed and what separates them is the
      // clamp; the engine only shows while the car is still finding it — which
      // is why the first version of this test passed with the power loss taken
      // out altogether.
      final fresh = reach(0.0, seconds: 2.0);
      final wrecked = reach(1.0, seconds: 2.0);

      expect(wrecked, lessThan(fresh * 0.9),
          reason: 'a wreck got ${wrecked}m in two seconds against ${fresh}m');
    });

    test('and has a lower top speed as well', () {
      // Measured as a speed after twenty seconds rather than as a distance:
      // distance is mostly the getting-going above, so a car that kept its top
      // speed and lost its engine passes a distance test and fails this one.
      double topSpeed(double damage) {
        final it = _onRoad();
        it.car.damage = damage;
        _drive(it.car, VehicleInput()..throttle = 1.0, 20.0);
        return it.car.speed;
      }

      final fresh = topSpeed(0.0);
      final wrecked = topSpeed(1.0);

      expect(wrecked, lessThan(fresh * 0.85),
          reason: 'a wreck tops out at $wrecked against a fresh car\'s $fresh');
    });

    test('and still corners and still stops', () {
      // Deliberate. Damage takes the engine, not the tyres: a car that stopped
      // being able to turn would be a car that cannot be driven back to the
      // pits, and the crash would end the race rather than cost it.
      final it = _onRoad();
      it.car.damage = 1.0;
      _drive(it.car, VehicleInput()..throttle = 1.0, 6.0);
      final speed = it.car.speed;

      // Timed rather than driven for a fixed while: below walking pace the
      // brake becomes reverse — see `_drive` in the vehicle — so a car left on
      // the pedal for three seconds is a car doing twelve backwards, which is
      // how the first version of this test failed.
      final brake = VehicleInput()..brake = 1.0;
      var steps = 0;
      for (; steps < 60 * 10 && it.car.speed > 1.0; steps++) {
        it.car.step(_step, brake);
      }

      expect(speed, greaterThan(20.0), reason: 'the wreck never got going');
      expect(steps / 60.0, lessThan(3.0),
          reason: 'a wrecked car takes ${steps / 60.0}s to stop');
    });
  });

  group('the pit stop', () {
    test('puts the car back together and the next tyres on it', () {
      final it = _onRoad();
      it.car.damage = 0.7;

      expect(it.car.pitStop(Tyres.after(it.car.tyres)), isTrue);

      expect(it.car.damage, 0.0);
      expect(it.car.tyres, isNot(Tyres.road));
    });

    test('and is refused while the car is moving', () {
      final it = _onRoad();
      it.car.damage = 0.7;
      _drive(it.car, VehicleInput()..throttle = 1.0, 2.0);

      expect(it.car.pitStop(Tyres.slicks), isFalse);
      expect(it.car.damage, 0.7, reason: 'it repaired itself at speed');
    });
  });

  test('and damage survives being saved and read back', () {
    // The shooter\'s own snapshot test caught exactly this about a recoil the
    // day it was added: a restored race that handed every wreck back its engine
    // would be a different race from the one that was saved.
    final it = _onRoad();
    it.car.damage = 0.42;
    it.car.fitTyres(Tyres.rally);

    final copy = _onRoad();
    copy.car.restore(it.car.save());

    expect(copy.car.damage, closeTo(0.42, 1e-9));
    expect(copy.car.tyres, Tyres.rally);
  });
}
