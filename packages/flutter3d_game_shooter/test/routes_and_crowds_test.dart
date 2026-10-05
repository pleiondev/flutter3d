/// Monsters on the navigation mesh the game stages, and round each other.
///
/// Written as A/B pairs, like `navigation_test.dart`: the same room, the
/// same monsters, the same number of steps, once with what `stage` now sets
/// on the actor system and once without. A guard whose next post is on the
/// far side of a wall gets there over the mesh and walks into the wall
/// without it; two guards walking the same corridor towards each other pass
/// with avoidance and meet without it.
library;

import 'dart:math' as math;

import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Brush _box(double cx, double cy, double cz, double sx, double sy, double sz) =>
    Brush(centre: Vector3(cx, cy, cz), size: Vector3(sx, sy, sz));

/// Twenty metres square, its top face at y = 0.
Brush _floor() => _box(0.0, -0.5, 0.0, 20.0, 1.0, 20.0);

/// The room split by a wall that stops short of the south side, so the way
/// from one half to the other is round its end.
List<Brush> _uRoom() => <Brush>[_floor(), _box(0.0, 1.5, -4.0, 1.0, 3.0, 12.0)];

/// The actor system and bestiary of a room of [brushes], with the meshes
/// and avoidance the game stages — [stageRoutes] — when [staged].
({ActorSystem system, Bestiary bestiary}) _room(
  List<Brush> brushes, {
  required bool staged,
}) {
  final world = CollisionWorld();
  for (final brush in brushes) {
    world.addBox(brush.centre, brush.size);
  }
  world.update();
  final random = GameRandom(1);
  final system = ActorSystem(world: world, random: random);
  if (staged) stageRoutes(system, Level(name: 'room', brushes: brushes));
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

/// A runner at [from] on a beat whose first post is [to] and whose second is
/// back where it started.
Actor _guard(Bestiary bestiary, Vector3 from, Vector3 to) {
  final guard = bestiary.spawn(Monsters.runner, from);
  guard.brain = PatrolBrain(
    def: Monsters.runner,
    shot: WeaponShot(
      world: bestiary.actors.world,
      hitscan: Hitscan(
        world: bestiary.actors.world,
        random: bestiary.actors.random,
      ),
      projectiles: ProjectileSystem(world: bestiary.actors.world),
    ),
    route: <Vector3>[to, from],
  );
  return guard;
}

/// The player, far enough away to be nobody's business.
final Vector3 _away = Vector3(0.0, 0.7, 80.0);

void _step(ActorSystem system) {
  system.world.reindex();
  system
    ..beginStep()
    ..step(_dt, focus: _away);
  system.world.update();
}

void main() {
  group('a guard whose next post is behind a wall', () {
    int legAfter({required bool staged}) {
      final room = _room(_uRoom(), staged: staged);
      final guard = _guard(
        room.bestiary,
        Vector3(-6.0, 0.9, -8.0),
        Vector3(6.0, 0.9, -8.0),
      );
      final brain = guard.brain! as PatrolBrain;
      for (var i = 0; i < 900 && brain.leg == 0; i++) {
        _step(room.system);
      }
      return brain.leg;
    }

    test('walks round the wall to it over the staged mesh', () {
      expect(legAfter(staged: true), 1);
    });

    test('and walks into the wall without it', () {
      expect(legAfter(staged: false), 0);
    });
  });

  group('two guards walking a corridor towards each other', () {
    /// How near they came, centre to centre, and the step each first
    /// reached its post at, or null.
    ({double closest, int? a, int? b}) walk({required bool staged}) {
      final room = _room(<Brush>[_floor()], staged: staged);
      final a = _guard(
        room.bestiary,
        Vector3(-6.0, 0.9, 0.0),
        Vector3(6.0, 0.9, 0.0),
      );
      // A hundredth of a metre off the line, as two bodies never quite are
      // on one.
      final b = _guard(
        room.bestiary,
        Vector3(6.0, 0.9, 0.01),
        Vector3(-6.0, 0.9, 0.01),
      );
      var closest = double.infinity;
      int? arrivedA;
      int? arrivedB;
      for (var i = 0; i < 300; i++) {
        _step(room.system);
        final pa = a.position!;
        final pb = b.position!;
        final dx = pa.x - pb.x;
        final dz = pa.z - pb.z;
        closest = math.min(closest, math.sqrt(dx * dx + dz * dz));
        if ((a.brain! as PatrolBrain).leg == 1) arrivedA ??= i;
        if ((b.brain! as PatrolBrain).leg == 1) arrivedB ??= i;
      }
      return (closest: closest, a: arrivedA, b: arrivedB);
    }

    test('pass each other with the staged avoidance', () {
      final it = walk(staged: true);
      // Twelve metres at a runner's 5.4 a second is 133 steps; they arrive
      // in 137, having stepped round each other without touching — their
      // capsules are 0.35 in radius.
      expect(it.a, isNotNull);
      expect(it.b, isNotNull);
      expect(it.a!, lessThan(150));
      expect(it.closest, greaterThan(2 * Monsters.runner.radius));
    });

    test('and meet without it', () {
      // Capsule against capsule, a hundredth of a metre off true, each
      // pushing at the other: neither gets anywhere.
      final it = walk(staged: false);
      expect(it.a, isNull);
      expect(it.b, isNull);
    });
  });
}
