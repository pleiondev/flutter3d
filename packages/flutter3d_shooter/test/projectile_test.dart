import 'package:flutter3d_game/src/physics/layers.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_shooter/flutter3d_shooter.dart';
import 'package:flutter3d_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

const Blast _blast = Blast(radius: 4.0, damage: 90.0, minimumFraction: 0.1);

Collider _target(CollisionWorld world, Vector3 at, {Object? name}) => world.add(
      Collider(
        shape: CollisionCapsule(radius: 0.4, halfHeight: 0.7),
        position: at,
        kind: ColliderKind.kinematic,
        layer: CollisionLayers.actor,
        userData: name,
      ),
    );

void main() {
  group('blast falloff', () {
    test('is full at the centre and nothing past the edge', () {
      expect(_blast.damageAt(0.0), 90.0);
      expect(_blast.damageAt(4.0), 0.0);
      expect(_blast.damageAt(10.0), 0.0);
    });

    test('drops to the stated fraction just inside the edge', () {
      expect(_blast.damageAt(3.999), closeTo(9.0, 0.1));
    });

    test('never increases with distance', () {
      var previous = double.infinity;
      for (var d = 0.0; d < 5.0; d += 0.05) {
        final damage = _blast.damageAt(d);
        expect(damage, lessThanOrEqualTo(previous + 1e-12));
        previous = damage;
      }
    });
  });

  group('a blast in the open', () {
    late CollisionWorld world;
    late BlastResolver resolver;

    setUp(() {
      world = CollisionWorld();
      resolver = BlastResolver(world);
    });

    test('hurts everything within reach, less the further away', () {
      final near = _target(world, Vector3(1.0, 0.0, 0.0), name: 'near');
      final far = _target(world, Vector3(3.0, 0.0, 0.0), name: 'far');
      world.update();

      final damage = <Collider, double>{};
      resolver.resolve(_blast, Vector3.zero(), damage);

      expect(damage[near], greaterThan(damage[far]!));
      expect(damage[far], greaterThan(0.0));
    });

    test('spares anything outside the radius', () {
      _target(world, Vector3(6.0, 0.0, 0.0));
      world.update();

      final damage = <Collider, double>{};
      resolver.resolve(_blast, Vector3.zero(), damage);

      expect(damage, isEmpty);
    });

    test('hurts the one who fired it, standing in their own blast', () {
      // Rocket jumping, and the price of the launcher being the best weapon in
      // the game at close range.
      final shooter = world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.4)),
          position: Vector3(0.5, 0.0, 0.0),
          kind: ColliderKind.kinematic,
          layer: CollisionLayers.player,
        ),
      );
      world.update();

      final damage = <Collider, double>{};
      resolver.resolve(_blast, Vector3.zero(), damage);

      expect(damage[shooter], greaterThan(0.0));
    });

    test('leaves level geometry alone', () {
      world.addBox(Vector3(1.0, 0.0, 0.0), Vector3.all(1.0));
      world.update();

      final damage = <Collider, double>{};
      resolver.resolve(_blast, Vector3.zero(), damage);

      expect(damage, isEmpty);
    });
  });

  group('a blast round a corner', () {
    test('does not reach through a wall', () {
      // The failure this exists for: without the sight check, a rocket kills
      // whatever is in the next room and the player has no way to understand
      // why they died.
      final world = CollisionWorld();
      world.addBox(Vector3(1.0, 0.0, 0.0), Vector3(0.4, 6.0, 8.0));
      final sheltered = _target(world, Vector3(2.5, 0.0, 0.0));
      world.update();

      final damage = <Collider, double>{};
      BlastResolver(world).resolve(_blast, Vector3.zero(), damage);

      expect(damage[sheltered], isNull);
    });

    test('still reaches what is standing against the same wall', () {
      // The check must not be so eager that touching a surface counts as being
      // behind it — a monster with its back to a wall is exactly what a rocket
      // is aimed at.
      final world = CollisionWorld();
      world.addBox(Vector3(0.0, 0.0, -3.0), Vector3(8.0, 6.0, 0.4));
      final exposed = _target(world, Vector3(0.0, 0.0, -2.6));
      world.update();

      final damage = <Collider, double>{};
      BlastResolver(world).resolve(_blast, Vector3.zero(), damage);

      expect(damage[exposed], greaterThan(0.0));
    });
  });

  group('a rocket in flight', () {
    late CollisionWorld world;
    late ProjectileSystem system;

    setUp(() {
      world = CollisionWorld();
      system = ProjectileSystem(world: world);
    });

    test('travels at the speed it was given', () {
      system.spawn(
        position: Vector3.zero(),
        direction: Vector3(0.0, 0.0, -1.0),
        speed: 30.0,
        blast: _blast,
      );

      for (var i = 0; i < 30; i++) {
        system.step(_dt);
      }

      expect(system.activeCount, 1);
      expect(system.detonations, isEmpty);
    });

    test('cannot pass through a thin wall', () {
      // A rocket at this speed covers more than half a metre per step, which is
      // further than the wall is thick. Moving by addition and then testing the
      // position would put it cleanly on the other side.
      world.addBox(Vector3(0.0, 0.0, -10.0), Vector3(8.0, 8.0, 0.2));

      system.spawn(
        position: Vector3.zero(),
        direction: Vector3(0.0, 0.0, -1.0),
        speed: 50.0,
        blast: _blast,
      );

      for (var i = 0; i < 60; i++) {
        system.step(_dt);
        if (system.detonations.isNotEmpty) break;
      }

      expect(system.detonations, hasLength(1));
      expect(system.detonations.single.position.z, closeTo(-9.9, 0.2));
    });

    test('explodes outside the wall it struck, not inside it', () {
      // Inside, and the wall stands between the blast and everything it should
      // have hurt — the explosion would do nothing at all.
      world.addBox(Vector3(0.0, 0.0, -10.0), Vector3(8.0, 8.0, 2.0));
      final victim = _target(world, Vector3(1.5, 0.0, -8.6));
      world.update();

      system.spawn(
        position: Vector3.zero(),
        direction: Vector3(0.0, 0.0, -1.0),
        speed: 40.0,
        blast: _blast,
      );
      for (var i = 0; i < 60 && system.detonations.isEmpty; i++) {
        system.step(_dt);
      }

      expect(system.detonations, hasLength(1));
      expect(system.detonations.single.damage[victim], greaterThan(0.0));
    });

    test('does not detonate on the body that fired it', () {
      final shooter = world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.5)),
          position: Vector3.zero(),
          kind: ColliderKind.kinematic,
          layer: CollisionLayers.player,
        ),
      );
      world.update();

      system.spawn(
        position: Vector3.zero(),
        direction: Vector3(0.0, 0.0, -1.0),
        speed: 30.0,
        blast: _blast,
        owner: shooter,
      );
      system.step(_dt);

      expect(system.detonations, isEmpty);
      expect(system.activeCount, 1);
    });

    test('gives up after its lifetime and explodes where it is', () {
      system.spawn(
        position: Vector3.zero(),
        direction: Vector3(0.0, 0.0, -1.0),
        speed: 10.0,
        blast: _blast,
        life: 0.1,
      );

      var steps = 0;
      for (; steps < 12 && system.detonations.isEmpty; steps++) {
        system.step(_dt);
      }

      expect(system.detonations, hasLength(1));
      expect(system.activeCount, 0);
      // A tenth of a second is six steps at sixty hertz.
      expect(steps, closeTo(6, 1));
    });

    test('reports its explosions for one step only', () {
      world.addBox(Vector3(0.0, 0.0, -3.0), Vector3(8.0, 8.0, 1.0));
      system.spawn(
        position: Vector3.zero(),
        direction: Vector3(0.0, 0.0, -1.0),
        speed: 40.0,
        blast: _blast,
      );

      for (var i = 0; i < 30 && system.detonations.isEmpty; i++) {
        system.step(_dt);
      }
      expect(system.detonations, hasLength(1));

      system.step(_dt);
      expect(system.detonations, isEmpty);
    });

    test('a slot is reused once its rocket is gone', () {
      final small = ProjectileSystem(world: world, capacity: 1);

      expect(
        small.spawn(
          position: Vector3.zero(),
          direction: Vector3(0.0, 0.0, -1.0),
          speed: 10.0,
          blast: _blast,
          life: 0.05,
        ),
        isTrue,
      );
      for (var i = 0; i < 5; i++) {
        small.step(_dt);
      }

      expect(
        small.spawn(
          position: Vector3.zero(),
          direction: Vector3(0.0, 0.0, -1.0),
          speed: 10.0,
          blast: _blast,
        ),
        isTrue,
      );
    });

    test('a full pool drops the shot and counts it, rather than growing', () {
      final small = ProjectileSystem(world: world, capacity: 2);
      for (var i = 0; i < 5; i++) {
        small.spawn(
          position: Vector3.zero(),
          direction: Vector3(0.0, 0.0, -1.0),
          speed: 10.0,
          blast: _blast,
        );
      }

      expect(small.activeCount, 2);
      expect(small.dropped, 3);
    });
  });

  group('firing the launcher', () {
    test('spends a rocket, produces no immediate hits, and launches one', () {
      final world = CollisionWorld();
      final system = ProjectileSystem(world: world);
      final shot = WeaponShot(
        world: world,
        hitscan: Hitscan(world: world),
        projectiles: system,
      );

      final arsenal = Arsenal(
        slots: Weapons.all,
        owned: <WeaponDef>[Weapons.rocketLauncher],
        ammo: <AmmoType, int>{AmmoType.rockets: 5},
      );

      final weapon = arsenal.fire()!;
      shot.begin(weapon, Vector3.zero(), Vector3(0.0, 0.0, -1.0));
      weapon.behaviour.deliver(shot);

      expect(arsenal.ammoOf(AmmoType.rockets), 4);
      // The damage arrives later, from wherever the rocket ends up.
      expect(shot.hits, isEmpty);
      expect(system.activeCount, 1);
    });

    test('a world with no projectile system simply launches nothing', () {
      // The firing rules are testable without one, which is the reason the
      // field is nullable.
      final world = CollisionWorld();
      final shot = WeaponShot(world: world, hitscan: Hitscan(world: world));

      shot.begin(
        Weapons.rocketLauncher,
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(
        () => Weapons.rocketLauncher.behaviour.deliver(shot),
        returnsNormally,
      );
    });
  });
}
