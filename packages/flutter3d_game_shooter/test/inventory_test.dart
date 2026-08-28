import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

void _run(MechanismWorld m, double seconds) {
  for (var i = 0; i < (seconds / _dt).round(); i++) {
    m.step(_dt);
    m.collisions.update();
    m.collisions.clearKinematicDeltas();
  }
}

({MechanismWorld mechanisms, CollisionWorld world}) _world() {
  final world = CollisionWorld();
  return (mechanisms: MechanismWorld(world), world: world);
}

Pickup _drop(
  ({MechanismWorld mechanisms, CollisionWorld world}) w,
  String gives, {
  double? amount,
  String? detail,
}) {
  final gift = sampleGifts[gives]!;
  return w.mechanisms.add(
    Pickup(
      gift: gift,
      amount: amount ?? gift.defaultAmount,
      detail: detail,
      collider: w.world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.3)),
          position: Vector3(0.0, 0.9, 0.0),
          kind: ColliderKind.trigger,
          layer: CollisionLayers.pickup,
          mask: CollisionLayers.player,
        ),
      ),
    ),
  );
}

/// A body that can walk about and carry things.
///
/// **A real `Player`.** It used to put the `Inventory` straight into
/// `userData`, which stopped being how the game arranges things the day a
/// collider started answering *who* it is. These tests kept passing while every
/// pickup in the running game silently did nothing — a harness that does not
/// build what the game builds is a harness that tests itself.
Collider _walkerOn(
  ({MechanismWorld mechanisms, CollisionWorld world}) w,
  Inventory carrying,
) => Player(
  body: CharacterController(world: w.world, position: Vector3(0.0, 0.9, 0.0)),
  inventory: carrying,
).body.collider;

void main() {
  group('an inventory', () {
    test('caps armour and says how much stuck', () {
      final carrying = Inventory(maxArmour: 100.0);
      expect(carrying.addArmour(60.0), closeTo(60.0, 1e-9));
      expect(carrying.addArmour(60.0), closeTo(40.0, 1e-9));
      expect(carrying.addArmour(10.0), 0.0);
      expect(carrying.health.armour, closeTo(100.0, 1e-9));
    });

    test('invulnerability stops damage, and wears off', () {
      final carrying = Inventory()..empower('invulnerability', 1.0);

      expect(carrying.damage(40.0), isFalse);
      expect(carrying.health.current, 100.0);

      _tick(carrying, 1.5);
      expect(carrying.isInvulnerable, isFalse);
      expect(carrying.expired, contains('invulnerability'));

      carrying.damage(40.0);
      expect(carrying.health.current, lessThan(100.0));
    });

    test('a second power-up refreshes rather than stacking', () {
      // Two medkits are twice the health; two invulnerabilities are not two
      // minutes of it.
      final carrying = Inventory()..empower('invulnerability', 10.0);
      _tick(carrying, 5.0);
      carrying.empower('invulnerability', 10.0);
      expect(carrying.remainingOf('invulnerability'), closeTo(10.0, 0.05));
    });

    test('and a weaker refresh does not cut a stronger one short', () {
      final carrying = Inventory()..empower('invulnerability', 30.0);
      carrying.empower('invulnerability', 5.0);
      expect(carrying.remainingOf('invulnerability'), closeTo(30.0, 1e-9));
    });
  });

  group('picking things up', () {
    test('a medkit heals and disappears', () {
      final w = _world();
      final carrying = Inventory();
      carrying.health.damage(50.0);
      final medkit = _drop(w, 'health', amount: 25.0);
      _walkerOn(w, carrying);

      _run(w.mechanisms, 0.1);

      expect(carrying.health.current, closeTo(75.0, 1e-6));
      expect(medkit.isTaken, isTrue);
    });

    test('but not at full health, and it stays on the floor', () {
      // The rule a player leaving a medkit for later depends on.
      final w = _world();
      final carrying = Inventory();
      final medkit = _drop(w, 'health', amount: 25.0);
      _walkerOn(w, carrying);

      _run(w.mechanisms, 0.5);

      expect(medkit.isTaken, isFalse);
      expect(carrying.health.current, 100.0);
    });

    test('and is collected the moment standing on it starts to matter', () {
      // Refused on entry, taken later without stepping off and back on.
      final w = _world();
      final carrying = Inventory();
      final medkit = _drop(w, 'health', amount: 25.0);
      _walkerOn(w, carrying);
      _run(w.mechanisms, 0.3);
      expect(medkit.isTaken, isFalse);

      carrying.health.damage(40.0);
      _run(w.mechanisms, 0.1);

      expect(medkit.isTaken, isTrue);
    });

    test('ammunition fills its own pouch', () {
      final w = _world();
      final carrying = Inventory();
      final before = carrying.arsenal.ammoOf(AmmoType.shells);
      _drop(w, 'shells', amount: 8.0);
      _walkerOn(w, carrying);

      _run(w.mechanisms, 0.1);

      expect(carrying.arsenal.ammoOf(AmmoType.shells), before + 8);
      expect(carrying.arsenal.ammoOf(AmmoType.rockets), 0);
    });

    test('a full pouch refuses, so the box waits', () {
      final w = _world();
      final carrying = Inventory();
      carrying.arsenal.addAmmo(AmmoType.rockets, 999);
      final box = _drop(w, 'rockets', amount: 4.0);
      _walkerOn(w, carrying);

      _run(w.mechanisms, 0.3);

      expect(box.isTaken, isFalse);
    });

    test('a power-up starts running', () {
      final w = _world();
      final carrying = Inventory();
      _drop(w, 'invulnerability', amount: 12.0);
      _walkerOn(w, carrying);

      _run(w.mechanisms, 0.1);

      expect(carrying.isInvulnerable, isTrue);
      expect(carrying.remainingOf('invulnerability'), greaterThan(11.0));
    });

    test('a body carrying nothing collects nothing', () {
      // A monster walking over a medkit does not drink it.
      final w = _world();
      final medkit = _drop(w, 'health');
      w.world.add(
        Collider(
          shape: CollisionCapsule(radius: 0.35, halfHeight: 0.55),
          position: Vector3(0.0, 0.9, 0.0),
          kind: ColliderKind.kinematic,
          layer: CollisionLayers.player,
        ),
      );

      _run(w.mechanisms, 0.3);
      expect(medkit.isTaken, isFalse);
    });

    test('every name the level format allows can be granted', () {
      // The validator accepts what the registry knows; this checks the registry
      // does not merely know a name but can act on it.
      for (final name in sampleGifts.names) {
        final gift = sampleGifts[name]!;
        final carrying = Inventory();
        carrying.health.damage(60.0);
        expect(
          gift.grantTo(carrying, gift.defaultAmount, 'blue'),
          isTrue,
          reason: '"$name" granted nothing to an empty inventory',
        );
      }
    });
  });
}

void _tick(Inventory carrying, double seconds) {
  for (var i = 0; i < (seconds / _dt).round(); i++) {
    carrying.step(_dt);
  }
}
