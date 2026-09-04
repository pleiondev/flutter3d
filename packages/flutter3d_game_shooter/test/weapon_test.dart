import 'dart:math' as math;

import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show InputState;
import 'package:flutter3d_sim/src/physics/layers.dart';
import 'package:flutter3d_sim/src/save/game_random.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

void main() {
  group('damage falloff', () {
    test('is flat when the weapon has none', () {
      expect(Weapons.fists.damageAt(0.0), Weapons.fists.damage);
      expect(Weapons.fists.damageAt(100.0), Weapons.fists.damage);
    });

    test('is full up to the near threshold', () {
      expect(Weapons.pistol.damageAt(0.0), Weapons.pistol.damage);
      expect(Weapons.pistol.damageAt(25.0), Weapons.pistol.damage);
    });

    test('reaches the floor at the far threshold and stays there', () {
      final floor =
          Weapons.pistol.damage * Weapons.pistol.minimumDamageFraction;

      expect(Weapons.pistol.damageAt(70.0), closeTo(floor, 1e-9));
      expect(Weapons.pistol.damageAt(500.0), closeTo(floor, 1e-9));
    });

    test('is halfway down at the midpoint', () {
      final full = Weapons.pistol.damage;
      final floor = full * Weapons.pistol.minimumDamageFraction;

      expect(
        Weapons.pistol.damageAt(47.5),
        closeTo((full + floor) / 2.0, 1e-9),
      );
    });

    test('never increases with distance', () {
      var previous = double.infinity;
      for (var d = 0.0; d < 100.0; d += 0.5) {
        final damage = Weapons.shotgun.damageAt(d);
        expect(damage, lessThanOrEqualTo(previous + 1e-12));
        previous = damage;
      }
    });
  });

  group('the arsenal', () {
    test('starts with fists and a pistol', () {
      final arsenal = sampleArsenal();

      expect(arsenal.owns(Weapons.fists), isTrue);
      expect(arsenal.owns(Weapons.pistol), isTrue);
      expect(arsenal.owns(Weapons.shotgun), isFalse);
    });

    test('firing spends a round', () {
      final arsenal = sampleArsenal()..selectSlot(1);
      final before = arsenal.currentAmmo;

      expect(arsenal.fire(), isNotNull);
      expect(arsenal.currentAmmo, before - 1);
    });

    test('fists cost nothing and never run out', () {
      final arsenal = sampleArsenal();

      for (var i = 0; i < 50; i++) {
        expect(arsenal.fire(), isNotNull);
        arsenal.advanceTime(1.0);
      }
    });

    test('a second shot has to wait for the cooldown', () {
      final arsenal = sampleArsenal()..selectSlot(1);

      expect(arsenal.fire(), isNotNull);
      expect(arsenal.fire(), isNull);
    });

    test('the rate of fire does not depend on the frame rate', () {
      // The reason the cooldown counts seconds and not frames: a weapon that
      // fires once per N steps fires at a different rate on a faster machine.
      int shotsIn(double seconds, double step) {
        final arsenal = Arsenal(
          slots: Weapons.all,
          owned: <WeaponDef>[Weapons.pistol],
          ammo: <AmmoType, int>{AmmoType.bullets: 1000},
        );
        var fired = 0;
        for (var t = 0.0; t < seconds; t += step) {
          arsenal.advanceTime(step);
          if (arsenal.fire() != null) fired++;
        }
        return fired;
      }

      final atSixty = shotsIn(5.0, _dt);
      final atThirty = shotsIn(5.0, 1.0 / 30.0);
      final atOneFortyFour = shotsIn(5.0, 1.0 / 144.0);

      expect(atThirty, closeTo(atSixty, 1));
      expect(atOneFortyFour, closeTo(atSixty, 1));
      // Four shots a second for five seconds.
      expect(atSixty, closeTo(20, 1));
    });

    test('an empty weapon will not fire', () {
      final arsenal = Arsenal(
        slots: Weapons.all,
        owned: <WeaponDef>[Weapons.pistol],
        ammo: <AmmoType, int>{AmmoType.bullets: 0},
      );

      expect(arsenal.canFire, isFalse);
      expect(arsenal.fire(), isNull);
    });

    test('running dry falls back to something that works', () {
      final arsenal = Arsenal(
        slots: Weapons.all,
        owned: <WeaponDef>[Weapons.fists, Weapons.pistol],
        ammo: <AmmoType, int>{AmmoType.bullets: 1},
      )..selectSlot(1);

      arsenal.fire();
      arsenal.advanceTime(1.0);
      arsenal.fallBackIfEmpty();

      expect(arsenal.current.name, Weapons.fists.name);
    });

    test('the fallback leaves a working weapon alone', () {
      final arsenal = sampleArsenal()..selectSlot(1);

      arsenal.fallBackIfEmpty();

      expect(arsenal.current.name, Weapons.pistol.name);
    });

    test('switching does not reset the cooldown', () {
      // Otherwise tapping between two weapons fires faster than either allows,
      // which is the oldest exploit in the genre after diagonal running.
      final arsenal = Arsenal(
        slots: Weapons.all,
        owned: <WeaponDef>[Weapons.fists, Weapons.pistol],
        ammo: <AmmoType, int>{AmmoType.bullets: 50},
      )..selectSlot(1);

      arsenal.fire();
      arsenal.selectSlot(0);
      arsenal.selectSlot(1);

      expect(arsenal.fire(), isNull);
    });

    test('picking up a new weapon switches to it', () {
      final arsenal = sampleArsenal();

      expect(arsenal.pickUp(Weapons.shotgun), isTrue);
      expect(arsenal.current.name, Weapons.shotgun.name);
    });

    test('picking up one already owned changes nothing', () {
      final arsenal = sampleArsenal()..selectSlot(0);

      expect(arsenal.pickUp(Weapons.pistol), isFalse);
      expect(arsenal.current.name, Weapons.fists.name);
    });

    test('selecting a weapon that is not owned does nothing', () {
      final arsenal = sampleArsenal()..selectSlot(1);

      expect(arsenal.selectSlot(3), isFalse);
      expect(arsenal.current.name, Weapons.pistol.name);
    });

    test('ammo stops at the pouch limit', () {
      final arsenal = Arsenal(
        slots: Weapons.all,
        ammo: <AmmoType, int>{AmmoType.shells: 58},
      );

      expect(arsenal.addAmmo(AmmoType.shells, 10), 2);
      expect(arsenal.ammoOf(AmmoType.shells), 60);
      expect(arsenal.addAmmo(AmmoType.shells, 10), 0);
    });

    test(
      'an automatic weapon fires while held, a semi-automatic on the press',
      () {
        final auto = Arsenal(
          slots: Weapons.all,
          owned: <WeaponDef>[Weapons.fists],
        );
        final semi = Arsenal(
          slots: Weapons.all,
          owned: <WeaponDef>[Weapons.pistol],
          ammo: <AmmoType, int>{AmmoType.bullets: 10},
        );

        expect(auto.wantsToFire(held: true, pressed: false), isTrue);
        expect(semi.wantsToFire(held: true, pressed: false), isFalse);
        expect(semi.wantsToFire(held: true, pressed: true), isTrue);
      },
    );
  });

  group('hitscan', () {
    late CollisionWorld world;
    late Hitscan hitscan;

    setUp(() {
      world = CollisionWorld();
      hitscan = Hitscan(world: world, random: GameRandom(1));
    });

    test('a single ray reports what it hit and how far away', () {
      world.addBox(
        Vector3(0.0, 0.0, -10.0),
        Vector3(6.0, 6.0, 1.0),
        userData: 'wall',
      );

      final hits = hitscan.fire(
        Weapons.pistol,
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(hits, hasLength(1));
      expect(hits.single.collider?.userData, 'wall');
      expect(hits.single.distance, closeTo(9.5, 1e-6));
      expect(hits.single.damage, Weapons.pistol.damage);
    });

    test('a miss still reports where the ray ended', () {
      final hits = hitscan.fire(
        Weapons.pistol,
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(hits.single.struckSomething, isFalse);
      expect(hits.single.damage, 0.0);
      expect(hits.single.distance, Weapons.pistol.range);
      expect(hits.single.point.z, closeTo(-Weapons.pistol.range, 1e-6));
    });

    test('a wall in the way stops the shot before what is behind it', () {
      world.addBox(
        Vector3(0.0, 0.0, -5.0),
        Vector3(6.0, 6.0, 1.0),
        userData: 'wall',
      );
      world.add(
        Collider(
          shape: CollisionCapsule(radius: 0.4, halfHeight: 0.6),
          position: Vector3(0.0, 0.0, -12.0),
          kind: ColliderKind.kinematic,
          layer: CollisionLayers.actor,
          userData: 'monster',
        ),
      );
      world.update();

      final hits = hitscan.fire(
        Weapons.pistol,
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(hits.single.collider?.userData, 'wall');
    });

    test('the shooter does not shoot themselves', () {
      // The muzzle is inside the player's own collider, so without this every
      // shot hits at zero distance.
      final self = world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.5)),
          position: Vector3.zero(),
          kind: ColliderKind.kinematic,
          layer: CollisionLayers.player,
          userData: 'me',
        ),
      );
      world.addBox(
        Vector3(0.0, 0.0, -10.0),
        Vector3.all(2.0),
        userData: 'wall',
      );
      world.update();

      final hits = hitscan.fire(
        Weapons.pistol,
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
        ignore: self,
      );

      expect(hits.single.collider?.userData, 'wall');
    });

    test('damage falls off with the distance actually travelled', () {
      world.addBox(Vector3(0.0, 0.0, -60.0), Vector3(20.0, 20.0, 1.0));

      final hits = hitscan.fire(
        Weapons.pistol,
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(
        hits.single.damage,
        closeTo(Weapons.pistol.damageAt(hits.single.distance), 1e-9),
      );
      expect(hits.single.damage, lessThan(Weapons.pistol.damage));
    });

    group('the shotgun pattern', () {
      test('fires one ray per pellet', () {
        final hits = hitscan.fire(
          Weapons.shotgun,
          Vector3.zero(),
          Vector3(0.0, 0.0, -1.0),
        );

        expect(hits, hasLength(Weapons.shotgun.rayCount));
      });

      test('every pellet stays inside the stated cone', () {
        final forward = Vector3(0.0, 0.0, -1.0);
        // Sampled repeatedly, because the jitter is random and one shot proves
        // nothing about the bound.
        for (var shot = 0; shot < 200; shot++) {
          final hits = hitscan.fire(Weapons.shotgun, Vector3.zero(), forward);
          for (final hit in hits) {
            final direction = hit.point.normalized();
            final angle = math.acos(direction.dot(forward).clamp(-1.0, 1.0));
            // The ring sits at the spread angle and the jitter adds a quarter
            // of it, so this is the honest bound rather than a round number.
            expect(
              angle,
              lessThan(
                Weapons.shotgun.spread * (1.0 + Hitscan.jitterFraction) * 1.5,
              ),
            );
          }
        }
      });

      test('the middle pellet lands near the crosshair', () {
        // What makes the shotgun reliable up close: something always goes where
        // the player pointed.
        final forward = Vector3(0.0, 0.0, -1.0);
        for (var shot = 0; shot < 50; shot++) {
          final hits = hitscan.fire(Weapons.shotgun, Vector3.zero(), forward);
          final centre = hits.first.point.normalized();
          final angle = math.acos(centre.dot(forward).clamp(-1.0, 1.0));

          expect(angle, lessThan(Weapons.shotgun.spread * 0.5));
        }
      });

      test('the pattern spreads around the axis rather than along a line', () {
        // A basis built badly collapses the ring into a line, which still
        // passes a cone test and looks nothing like a shotgun.
        final hits = hitscan.fire(
          Weapons.shotgun,
          Vector3.zero(),
          Vector3(0.0, 0.0, -1.0),
        );

        var spanX = 0.0;
        var spanY = 0.0;
        for (final hit in hits) {
          final d = hit.point.normalized();
          spanX = math.max(spanX, d.x.abs());
          spanY = math.max(spanY, d.y.abs());
        }

        expect(spanX, greaterThan(Weapons.shotgun.spread * 0.5));
        expect(spanY, greaterThan(Weapons.shotgun.spread * 0.5));
      });

      test('spread survives shooting straight down', () {
        // Where the obvious "up is the second axis" basis degenerates.
        final forward = Vector3(0.0, -1.0, 0.0);
        final hits = hitscan.fire(Weapons.shotgun, Vector3.zero(), forward);

        var spanX = 0.0;
        var spanZ = 0.0;
        for (final hit in hits) {
          final d = hit.point.normalized();
          spanX = math.max(spanX, d.x.abs());
          spanZ = math.max(spanZ, d.z.abs());
        }

        expect(spanX, greaterThan(Weapons.shotgun.spread * 0.5));
        expect(spanZ, greaterThan(Weapons.shotgun.spread * 0.5));
      });

      test('pellets in one target add up to one wound', () {
        final monster = world.add(
          Collider(
            shape: CollisionBox(Vector3(3.0, 3.0, 0.5)),
            position: Vector3(0.0, 0.0, -4.0),
            kind: ColliderKind.kinematic,
            layer: CollisionLayers.actor,
            userData: 'monster',
          ),
        );
        world.update();

        final hits = hitscan.fire(
          Weapons.shotgun,
          Vector3.zero(),
          Vector3(0.0, 0.0, -1.0),
        );
        final totals = Hitscan.damageByTarget(hits);

        expect(totals, hasLength(1));
        expect(totals[monster], greaterThan(Weapons.shotgun.damage));
      });
    });

    test('a melee swing does not reach across the room', () {
      world.addBox(Vector3(0.0, 0.0, -5.0), Vector3.all(2.0), userData: 'wall');

      final hits = hitscan.fire(
        Weapons.fists,
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(hits.single.struckSomething, isFalse);
    });

    test('a melee swing connects up close', () {
      world.addBox(Vector3(0.0, 0.0, -2.0), Vector3.all(1.0), userData: 'wall');

      final hits = hitscan.fire(
        Weapons.fists,
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
      );

      expect(hits.single.collider?.userData, 'wall');
    });
  });

  group('an ammunition a game invents', () {
    // The four this template ships are constants, not cases, so a game can add
    // a fifth. As an enum it could not, and adding a value to let it broke
    // every switch in every game already published.
    const AmmoType cells = AmmoType('cells');

    test('is carried, spent, and named like any other', () {
      final arsenal = Arsenal(
        slots: <WeaponDef>[
          const WeaponDef(
            name: 'coil',
            behaviour: HitscanBehaviour(),
            ammo: cells,
            damage: 30.0,
            shotsPerSecond: 5.0,
          ),
        ],
        ammo: <AmmoType, int>{cells: 5},
      )..selectSlot(0);

      expect(arsenal.ammoOf(cells), 5);
      expect(arsenal.fire(), isNotNull);
      expect(arsenal.ammoOf(cells), 4);
      expect(arsenal.carrying, contains(cells));
    });

    test('and survives a round trip, which is what has no list to consult', () {
      // The restore reads the file's own keys. A loop over "every type there
      // is" would have dropped this one, and there is no such list any more.
      final saved = Arsenal(
        slots: <WeaponDef>[Weapons.pistol],
        ammo: <AmmoType, int>{cells: 7, AmmoType.bullets: 12},
      ).save();

      final loaded = Arsenal(slots: <WeaponDef>[Weapons.pistol])
        ..restore(saved);

      expect(loaded.ammoOf(cells), 7);
      expect(loaded.ammoOf(AmmoType.bullets), 12);
    });

    test('and two of the same name are the same ammunition', () {
      expect(const AmmoType('cells'), cells);
      expect(<AmmoType, int>{cells: 1}[const AmmoType('cells')], 1);
    });
  });

  group('a delivery a game invents', () {
    // Sealed said this package has the full list of ways a shot can arrive.
    // A beam that charges, a shot that arcs and a spell that seeks are all
    // ways a game delivers a weapon, and none of the three shipped here is
    // one. Nothing switches over the type, so opening it cost nothing.

    test('is handed the same shot the built-in ones are', () {
      final world = CollisionWorld()
        ..addBox(Vector3(0.0, 0.0, -4.0), Vector3(4.0, 4.0, 1.0))
        ..update();
      final random = GameRandom(3);
      final shot = WeaponShot(
        world: world,
        hitscan: Hitscan(world: world, random: random),
        projectiles: ProjectileSystem(world: world),
      );
      final behaviour = _TwiceOver();

      shot.begin(
        const WeaponDef(
          name: 'coil',
          behaviour: _TwiceOver(),
          ammo: AmmoType.bullets,
          damage: 10.0,
          shotsPerSecond: 2.0,
        ),
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
      );
      behaviour.deliver(shot);

      // Two rays down one line: what the built-in hitscan does once, done
      // twice by a class this package has never heard of.
      expect(shot.hits, hasLength(2));
      expect(behaviour.deliveries, 1);
    });
  });

  group('the other trigger', () {
    const alternate = WeaponDef(
      name: 'both barrels',
      behaviour: HitscanBehaviour(),
      ammo: AmmoType.shells,
      ammoPerShot: 2,
      damage: 40.0,
      shotsPerSecond: 1.0,
    );
    const twinned = WeaponDef(
      name: 'shotgun',
      behaviour: HitscanBehaviour(),
      ammo: AmmoType.shells,
      damage: 11.0,
      shotsPerSecond: 2.0,
      alternate: alternate,
    );

    Arsenal held({int shells = 10}) => Arsenal(
      slots: <WeaponDef>[twinned],
      ammo: <AmmoType, int>{AmmoType.shells: shells},
    )..selectSlot(0);

    test('spends its own cost and answers its own definition', () {
      final arsenal = held();

      final fired = arsenal.fire(alternate: true);

      expect(fired?.name, 'both barrels');
      expect(arsenal.ammoOf(AmmoType.shells), 8, reason: 'two shells, not one');
    });

    test('and shares the weapon cooldown, because it shares the weapon', () {
      final arsenal = held()..fire(alternate: true);

      expect(arsenal.canFire, isFalse);
      expect(arsenal.canFireAlternate, isFalse);
    });

    test('is refused on its own cost rather than on the main one', () {
      // One shell left: the main trigger fires, the alternate cannot.
      final arsenal = held(shells: 1);

      expect(arsenal.canFire, isTrue);
      expect(arsenal.canFireAlternate, isFalse);
      expect(arsenal.fire(alternate: true), isNull);
      expect(
        arsenal.ammoOf(AmmoType.shells),
        1,
        reason: 'a refused shot spent something',
      );
    });

    test('and a weapon with one trigger never has a second', () {
      final arsenal = sampleArsenal()..selectSlot(1);

      expect(arsenal.canFireAlternate, isFalse);
      expect(arsenal.fire(alternate: true), isNull);
      expect(
        arsenal.wantsToFireAlternate(held: true, pressed: true),
        isFalse,
        reason: 'a game may bind the action for every weapon',
      );
    });
  });

  group('a weapon with a magazine', () {
    const rifle = WeaponDef(
      name: 'rifle',
      behaviour: HitscanBehaviour(),
      ammo: AmmoType.bullets,
      damage: 12.0,
      shotsPerSecond: 8.0,
      magazine: 4,
      reloadSeconds: 1.0,
    );

    Arsenal held({int bullets = 20}) => Arsenal(
      slots: <WeaponDef>[rifle],
      ammo: <AmmoType, int>{AmmoType.bullets: bullets},
    )..selectSlot(0);

    test('starts full, so a weapon picked up mid-fight can be fired', () {
      // A pickup that hands over something that cannot be fired reads as a
      // broken pickup rather than as a rule.
      final arsenal = held();

      expect(arsenal.loaded, 4);
      expect(arsenal.canFire, isTrue);
    });

    test('fires out of the magazine, not out of what is carried', () {
      final arsenal = held();
      final carried = arsenal.ammoOf(AmmoType.bullets);

      arsenal.fire();

      expect(arsenal.loaded, 3);
      expect(arsenal.ammoOf(AmmoType.bullets), carried);
    });

    test(
      'and stops firing when the magazine is out, with rounds in the bag',
      () {
        final arsenal = held();
        for (var i = 0; i < 4; i++) {
          arsenal
            ..advanceTime(1.0)
            ..fire();
        }

        expect(arsenal.loaded, 0);
        expect(arsenal.canFire, isFalse);
        expect(arsenal.ammoOf(AmmoType.bullets), 20);
        expect(arsenal.canReload, isTrue);
      },
    );

    test('a reload takes its time and then fills from what is carried', () {
      final arsenal = held();
      for (var i = 0; i < 4; i++) {
        arsenal
          ..advanceTime(1.0)
          ..fire();
      }

      expect(arsenal.reload(), isTrue);
      expect(arsenal.canFire, isFalse, reason: 'it fired mid-reload');

      arsenal.advanceTime(0.5);
      expect(arsenal.loaded, 0, reason: 'the magazine filled early');

      arsenal.advanceTime(0.6);
      expect(arsenal.loaded, 4);
      expect(arsenal.ammoOf(AmmoType.bullets), 16);
      expect(arsenal.canFire, isTrue);
    });

    test('and a reload never conjures rounds nobody is carrying', () {
      final arsenal = held(bullets: 2);
      for (var i = 0; i < 4; i++) {
        arsenal
          ..advanceTime(1.0)
          ..fire();
      }
      arsenal
        ..reload()
        ..advanceTime(2.0);

      expect(arsenal.loaded, 2);
      expect(arsenal.ammoOf(AmmoType.bullets), 0);
      expect(arsenal.canReload, isFalse, reason: 'it reloaded from nothing');
    });

    test('two weapons keep their own magazines', () {
      // The first version kept one count for the whole arsenal: a player
      // would have found the rifle full because the pistol was, and emptied
      // one by firing the other.
      const pistol = WeaponDef(
        name: 'sidearm',
        behaviour: HitscanBehaviour(),
        ammo: AmmoType.bullets,
        damage: 8.0,
        shotsPerSecond: 4.0,
        magazine: 2,
      );
      final arsenal = Arsenal(
        slots: <WeaponDef>[rifle, pistol],
        ammo: <AmmoType, int>{AmmoType.bullets: 20},
      )..selectSlot(0);

      arsenal.fire();
      expect(arsenal.loaded, 3);

      arsenal.selectSlot(1);
      expect(
        arsenal.loaded,
        2,
        reason: 'the sidearm shared the rifle\'s count',
      );
    });

    test('and a weapon with no magazine is untouched by any of it', () {
      final arsenal = sampleArsenal()..selectSlot(1);

      expect(arsenal.current.magazine, isNull);
      expect(arsenal.canReload, isFalse);
      expect(arsenal.reload(), isFalse);
      expect(arsenal.canFire, isTrue);
    });
  });

  group('falling back from an empty weapon', () {
    // **Nothing covered this**, which is how a restructure of the firing block
    // silently skipped it: the fall-back sits after the shot, and an early
    // return added to that method walks straight past it.

    test('happens on a step nothing was fired on', () {
      final arsenal = Arsenal(
        slots: <WeaponDef>[Weapons.fists, Weapons.pistol],
        ammo: <AmmoType, int>{AmmoType.bullets: 0},
      )..selectSlot(1);
      expect(arsenal.canFire, isFalse, reason: 'the pistol is dry');

      arsenal.fallBackIfEmpty();

      expect(arsenal.current.name, Weapons.fists.name);
    });

    test('and through a step of a game with nothing to fire with', () {
      // **Driven through the simulation, because the arsenal's own method was
      // never the thing at risk.** What broke was the step walking past the
      // call, and only a step can catch that.
      //
      // Mutation: put `if (shot == null) return;` back at the top of
      // `_weapon`. The dry pistol stays in hand.
      final world = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0))
        ..update();
      final inventory = Inventory(
        arsenal: Arsenal(
          slots: <WeaponDef>[Weapons.fists, Weapons.pistol],
          ammo: <AmmoType, int>{AmmoType.bullets: 0},
        )..selectSlot(1),
      );
      final sim = GameSimulation(
        random: GameRandom(1),
        player: Player(
          body: CharacterController(
            world: world,
            position: Vector3(0.0, 0.9, 0.0),
          ),
          inventory: inventory,
        ),
        collision: world,
        input: InputState(),
      );

      sim.step(1.0 / 60.0);

      expect(inventory.arsenal.current.name, Weapons.fists.name);
    });
  });
}

/// A weapon behaviour written the way a game would write one.
///
/// Fires the ordinary hitscan twice, which is not something any of the three
/// built-in deliveries can be configured into.
final class _TwiceOver extends WeaponBehaviour {
  const _TwiceOver();

  static int deliveriesMade = 0;

  int get deliveries => deliveriesMade;

  @override
  void deliver(WeaponShot shot) {
    deliveriesMade += 1;
    for (var i = 0; i < 2; i++) {
      shot.hits.addAll(
        shot.hitscan.fire(
          shot.weapon,
          shot.origin,
          shot.aim,
          ignore: shot.shooter,
        ),
      );
    }
  }
}
