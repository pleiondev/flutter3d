/// Where a shot lands on a body, and what that is worth.
///
///     flutter test test/hit_zones_test.dart
///
/// **Every hit was worth the same.** A shotgun in the face and a pistol in the
/// shin came to the same arithmetic, so aiming was a question of whether the
/// ray connected and nothing else — which is the difference between a weapon
/// having a feel and a weapon having a number.
///
/// Two halves, in two packages. The engine measures: `Actor.fractionUp`, nought
/// at the feet and one at the crown, which is geometry and no more. The genre
/// says what the fractions mean, because "head" is a word about a fiction and a
/// platformer has no use for it.
library;


import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

({ActorSystem system, Bestiary bestiary}) _room() {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))
    ..update();
  final random = GameRandom(3);
  final system = ActorSystem(world: world, random: random);
  return (
    system: system,
    bestiary: Bestiary(
      actors: system,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world, random: random),
        projectiles: ProjectileSystem(world: world),
      ),
      catalog: Monsters.byName,
    ),
  );
}

void main() {
  group('the measurement, which is the engine\'s', () {
    test('is nought at the feet and one at the crown', () {
      final it = _room();
      final monster = it.bestiary.spawn(Monsters.runner, Vector3.zero());
      final at = monster.position!;
      final half = monster.body!.halfExtents.y;

      expect(monster.fractionUp(Vector3(at.x, at.y - half, at.z)),
          closeTo(0.0, 1e-6));
      expect(monster.fractionUp(at), closeTo(0.5, 1e-6));
      expect(monster.fractionUp(Vector3(at.x, at.y + half, at.z)),
          closeTo(1.0, 1e-6));
    });

    test('and a shot past either end still answers something usable', () {
      // Clamped rather than open: a graze off the top of a head and a scuff of
      // the floor under the feet both have to index a table.
      final it = _room();
      final monster = it.bestiary.spawn(Monsters.runner, Vector3.zero());
      final at = monster.position!;

      expect(monster.fractionUp(Vector3(at.x, at.y + 99.0, at.z)), 1.0);
      expect(monster.fractionUp(Vector3(at.x, at.y - 99.0, at.z)), 0.0);
    });

    test('and nothing at all for something with no body', () {
      // A brain with no body is a perfectly good thing to be, and null is what
      // makes a caller decide rather than aim at the middle of nowhere.
      final it = _room();
      final bodyless = it.system.spawn(health: Health(10.0));

      expect(bodyless.fractionUp(Vector3.zero()), isNull);
    });
  });

  group('what the fractions mean, which is this game\'s', () {
    const zones = HitZones();

    test('rewards the head and discounts the legs', () {
      expect(zones.multiplierFor(0.95), greaterThan(1.0));
      expect(zones.multiplierFor(0.5), 1.0);
      expect(zones.multiplierFor(0.1), lessThan(1.0));
    });

    test('and an even table makes every hit the same again', () {
      // For a boss that is one solid mass, and for a game that does not want
      // headshots at all.
      const even = HitZones.even();
      for (final fraction in <double>[0.0, 0.2, 0.5, 0.9, 1.0]) {
        expect(even.multiplierFor(fraction), 1.0);
      }
    });

    test('and anything without a body is worth exactly what it says', () {
      // A barrel, a door, a lamp post: hit anywhere, worth the same.
      expect(zones.forHitOn(null, Vector3.zero()), 1.0);
      expect(zones.forHitOn('a crate, say', Vector3.zero()), 1.0);
    });
  });

  test('a shotgun is summed after the zones, not before', () {
    // **The reason the scaling is inside `damageByTarget`.** Eight pellets in
    // one monster arrive at the game as a single number, and by then where each
    // of them landed is gone — so two pellets in the head and six in the shins
    // would come to the same total as the other way round.
    final it = _room();
    final monster = it.bestiary.spawn(Monsters.runner, Vector3.zero());
    final at = monster.position!;
    final half = monster.body!.halfExtents.y;
    final collider = monster.body!.collider;

    ShotHit pelletAt(double y) => ShotHit(
          collider: collider,
          point: Vector3(at.x, y, at.z),
          normal: Vector3(0.0, 0.0, 1.0),
          distance: 4.0,
          damage: 10.0,
        );

    const zones = HitZones();
    double scale(ShotHit hit) => zones.forHitOn(collider.userData, hit.point);

    final head = Hitscan.damageByTarget(
      <ShotHit>[pelletAt(at.y + half * 0.9), pelletAt(at.y + half * 0.9)],
      scale: scale,
    ).values.single;
    final shins = Hitscan.damageByTarget(
      <ShotHit>[pelletAt(at.y - half * 0.9), pelletAt(at.y - half * 0.9)],
      scale: scale,
    ).values.single;

    expect(head, greaterThan(shins * 2.0),
        reason: 'the pellets were summed before anybody asked where they went');
  });
}
