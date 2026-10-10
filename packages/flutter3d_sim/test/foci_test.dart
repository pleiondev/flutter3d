/// Several things to chase, and one sweep to chase them by.
///
///     flutter test test/foci_test.dart
///
/// A co-op game has a player per controller, and every monster should go for
/// the one it can reach first. The field is swept from all of them at once and
/// records which one each cell's route ends at; the actor system reads that to
/// give each actor its own focus. The single-focus behaviour is held by the
/// rest of the suite, which passes a `focus:` exactly as before.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/src/actors/actor.dart';
import 'package:flutter3d_sim/src/actors/actor_system.dart';
import 'package:flutter3d_sim/src/actors/brain.dart';
import 'package:flutter3d_sim/src/level/level.dart';
import 'package:flutter3d_sim/src/nav/flow_field.dart';
import 'package:flutter3d_sim/src/nav/nav_grid.dart';
import 'package:flutter3d_sim/src/nav/navigation.dart';
import 'package:flutter3d_sim/src/save/game_random.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// Twenty metres square, its top face at y = 0.
Brush _floor() =>
    Brush(center: Vector3(0.0, -0.5, 0.0), size: Vector3(20.0, 1.0, 20.0));

/// A wall along x = 0 from the south edge to z = 8, leaving a gap at the
/// north end: the two halves of the room are two metres apart through it and
/// thirty round it.
Brush _wall() =>
    Brush(center: Vector3(0.0, 1.5, -1.0), size: Vector3(0.4, 3.0, 18.0));

/// Remembers which focus it was given, and walks to it.
final class _Chaser extends Brain {
  int attended = -1;
  final Vector3 seen = Vector3.zero();

  @override
  void think(Mind it) {
    attended = it.focusIndex;
    seen.setFrom(it.focus);
  }

  @override
  void act(Mind it) => it.steerTowardsFocus();
}

({ActorSystem system, List<Brush> brushes}) _room({bool wall = false}) {
  final brushes = <Brush>[_floor(), if (wall) _wall()];
  final world = CollisionWorld();
  for (final brush in brushes) {
    world.addBox(brush.center, brush.size);
  }
  world.update();
  return (
    system: ActorSystem(world: world, random: GameRandom(3)),
    brushes: brushes,
  );
}

Actor _chaserAt(ActorSystem system, double x, double z) => system.spawn(
  body: CharacterController(world: system.world, position: Vector3(x, 0.9, z)),
  brain: _Chaser(),
);

List<FocusPoint> _points(List<Vector3> at) => <FocusPoint>[
  for (final point in at) (at: point, body: null),
];

void main() {
  group('a field swept from two goals', () {
    late FlowField field;

    setUp(() {
      field = FlowField(
        NavGrid.bake(<Brush>[_floor()]),
      )..rebuildAll(<Vector3>[Vector3(-8.0, 0.0, 0.0), Vector3(8.0, 0.0, 0.0)]);
    });

    test('gives each cell to the goal nearer by walking', () {
      expect(field.sourceAt(Vector3(-5.0, 0.0, 3.0)), 0);
      expect(field.sourceAt(Vector3(-1.0, 0.0, -6.0)), 0);
      expect(field.sourceAt(Vector3(1.0, 0.0, -6.0)), 1);
      expect(field.sourceAt(Vector3(6.0, 0.0, 7.0)), 1);
    });

    test('and points each cell downhill to that goal', () {
      final out = Vector3.zero();

      expect(field.descend(Vector3(-3.0, 0.0, 0.0), out), isTrue);
      expect(out.x, lessThan(0.0), reason: 'west, to the western goal');
      expect(field.descend(Vector3(3.0, 0.0, 0.0), out), isTrue);
      expect(out.x, greaterThan(0.0), reason: 'east, to the eastern goal');
    });

    test('says nothing in either goal\'s own cell', () {
      final out = Vector3.zero();

      expect(field.descend(Vector3(-8.0, 0.0, 0.0), out), isFalse);
      expect(field.descend(Vector3(8.0, 0.0, 0.0), out), isFalse);
      expect(field.goalCells, hasLength(2));
      expect(field.goalCell, field.goalCells.first);
    });

    test('and off the grid there is no source', () {
      expect(field.sourceAt(Vector3(30.0, 0.0, 0.0)), -1);
    });
  });

  test('a wall makes the goal behind it the far one', () {
    // Two metres from the western chaser in a straight line, thirty by
    // walking; the other goal is fourteen either way. Straight-line nearest
    // would pick the wrong one, and a monster would press itself to the wall.
    final field = FlowField(NavGrid.bake(<Brush>[_floor(), _wall()]))
      ..rebuildAll(<Vector3>[Vector3(1.5, 0.0, -8.0), Vector3(-8.0, 0.0, 4.0)]);

    expect(field.sourceAt(Vector3(-1.5, 0.0, -8.0)), 1);
    expect(field.sourceAt(Vector3(2.5, 0.0, -8.0)), 0);
  });

  test('one goal is the same field it always was', () {
    final grid = NavGrid.bake(<Brush>[_floor()]);
    final one = FlowField(grid)..rebuild(Vector3(4.0, 0.0, -3.0));
    final list = FlowField(grid)
      ..rebuildAll(<Vector3>[Vector3(4.0, 0.0, -3.0)]);

    for (var cell = 0; cell < grid.cellCount; cell++) {
      expect(one.costAt(cell), list.costAt(cell));
    }
    expect(one.sourceAt(Vector3(-6.0, 0.0, 6.0)), 0);
  });

  test('re-sweeps only when a goal crosses into another cell', () {
    final field = FlowField(NavGrid.bake(<Brush>[_floor()]));
    final goals = <Vector3>[Vector3(-8.0, 0.0, 0.0), Vector3(8.0, 0.0, 0.0)];
    field.updateAll(goals);
    final before = field.costAt(0);

    // Inside the same half-metre cell: nothing to do.
    goals[1].x = 8.1;
    field.updateAll(goals);
    expect(field.costAt(0), before);

    // The western goal walks towards the corner cell 0 is: the field follows.
    goals[0].setValues(-9.0, 0.0, -9.0);
    field.updateAll(goals);
    expect(field.costAt(0), lessThan(before));
  });

  test('more goals than a byte holds is refused', () {
    final field = FlowField(NavGrid.bake(<Brush>[_floor()]));

    expect(
      () => field.updateAll(
        List<Vector3>.generate(FlowField.maxGoals + 1, (_) => Vector3.zero()),
      ),
      throwsArgumentError,
    );
  });

  group('an actor system with several foci', () {
    test('gives each actor the focus nearer by walking', () {
      final room = _room(wall: true);
      final system = room.system
        ..navigation = Navigation(NavGrid.bake(room.brushes));
      final west = _chaserAt(system, -1.5, -8.0);
      final east = _chaserAt(system, 2.5, -8.0);

      system
        ..beginStep()
        ..step(
          _dt,
          foci: _points(<Vector3>[
            Vector3(1.5, 0.9, -8.0),
            Vector3(-8.0, 0.9, 4.0),
          ]),
        );

      expect((west.brain! as _Chaser).attended, 1);
      expect((west.brain! as _Chaser).seen, Vector3(-8.0, 0.9, 4.0));
      expect((east.brain! as _Chaser).attended, 0);
      expect(system.focusIndex, 0, reason: 'outside a step, the first');
    });

    test('without navigation, the nearest in a straight line', () {
      final system = _room(wall: true).system;
      final west = _chaserAt(system, -1.5, -8.0);

      system
        ..beginStep()
        ..step(
          _dt,
          foci: _points(<Vector3>[
            Vector3(1.5, 0.9, -8.0),
            Vector3(-8.0, 0.9, 4.0),
          ]),
        );

      expect((west.brain! as _Chaser).attended, 0);
    });

    test('and the actors walk to different players', () {
      final room = _room();
      final system = room.system
        ..navigation = Navigation(NavGrid.bake(room.brushes));
      final a = _chaserAt(system, -3.0, 0.0);
      final b = _chaserAt(system, 3.0, 0.0);
      final foci = _points(<Vector3>[
        Vector3(-8.0, 0.9, 0.0),
        Vector3(8.0, 0.9, 0.0),
      ]);

      for (var i = 0; i < 120; i++) {
        system
          ..beginStep()
          ..step(_dt, foci: foci);
        system.world.update();
      }

      expect(a.position!.x, lessThan(-6.0));
      expect(b.position!.x, greaterThan(6.0));
    });

    test('counts damage against the focus whose body was hit', () {
      final system = _room().system;
      final first = Collider(shape: CollisionBox(Vector3.all(0.3)));
      final second = Collider(shape: CollisionBox(Vector3.all(0.3)));
      system
        ..beginStep()
        ..step(
          _dt,
          foci: <FocusPoint>[
            (at: Vector3(-5.0, 0.9, 0.0), body: first),
            (at: Vector3(5.0, 0.9, 0.0), body: second),
          ],
        );

      expect(system.hurtFocus(second, 7.0), isTrue);
      expect(system.hurtFocus(first, 2.0), isTrue);
      expect(
        system.hurtFocus(Collider(shape: CollisionBox(Vector3.all(1.0))), 9.0),
        isFalse,
      );
      expect(system.damageToFoci, <double>[2.0, 7.0]);
      expect(system.damageToFocusThisStep, 9.0);

      system.beginStep();
      expect(system.damageToFoci, <double>[0.0, 0.0]);
    });

    test(
      'measures each focus\'s speed, and none when their number changes',
      () {
        final system = _room().system;
        final a = Vector3(-5.0, 0.9, 0.0);
        final b = Vector3(5.0, 0.9, 0.0);
        final brain = _Velocity();
        _bodilessSpawn(system, brain);
        for (var i = 0; i < 2; i++) {
          a.x += 0.05;
          b.z -= 0.1;
          system
            ..beginStep()
            ..step(_dt, foci: _points(<Vector3>[a, b]));
        }

        expect(brain.velocities[0].x, closeTo(3.0, 1e-4));
        expect(brain.velocities[0].z, closeTo(0.0, 1e-9));
        expect(brain.velocities[1].z, closeTo(-6.0, 1e-4));
        expect(
          brain.velocity,
          brain.velocities[0],
          reason: 'a bodiless actor attends to the first',
        );

        a.x += 0.05;
        system
          ..beginStep()
          ..step(_dt, foci: _points(<Vector3>[a]));
        expect(
          brain.velocity.length,
          0.0,
          reason: 'one player left: the list is matched by index',
        );
      },
    );

    test('a save carries every focus to a system that loads it afresh', () {
      final a = Vector3(-5.0, 0.9, 0.0);
      final b = Vector3(5.0, 0.9, 0.0);
      final first = _room().system;
      first
        ..beginStep()
        ..step(_dt, foci: _points(<Vector3>[a, b]));
      final saved = first.save();

      final second = _room().system..restore(saved);
      final brain = _Velocity();
      _bodilessSpawn(second, brain);
      b.x += 0.1;
      second
        ..beginStep()
        ..step(_dt, foci: _points(<Vector3>[a, b]));

      expect(saved.containsKey('lastFoci'), isTrue);
      expect(saved.containsKey('lastFocus'), isFalse);
      expect(brain.velocities[1].x, closeTo(6.0, 1e-4));
    });

    test('one focus still saves under the key it always had', () {
      final system = _room().system
        ..beginStep()
        ..step(_dt, focus: Vector3(1.0, 2.0, 3.0));

      expect(system.save()['lastFocus'], <double>[1.0, 2.0, 3.0]);
      expect(system.save().containsKey('lastFoci'), isFalse);
    });

    test('takes a focus or foci, not both and not neither', () {
      final system = _room().system..beginStep();

      expect(() => system.step(_dt), throwsArgumentError);
      expect(
        () => system.step(
          _dt,
          focus: Vector3.zero(),
          foci: _points(<Vector3>[Vector3.zero()]),
        ),
        throwsArgumentError,
      );
      expect(
        () => system.step(_dt, foci: const <FocusPoint>[]),
        throwsArgumentError,
      );
    });
  });
}

/// Reads the attended focus's velocity, and every focus's, each step.
final class _Velocity extends Brain {
  final Vector3 velocity = Vector3.zero();
  final List<Vector3> velocities = <Vector3>[];

  @override
  void act(Mind it) {
    velocity.setFrom(it.system.focusVelocity);
    velocities.clear();
    // The attended one is the first here — a bodiless actor attends to the
    // first — so the rest are read by looking at each in turn.
    for (var i = 0; i < it.system.fociCount; i++) {
      velocities.add(it.system.focusVelocityOf(i).clone());
    }
  }
}

Actor _bodilessSpawn(ActorSystem system, Brain brain) =>
    system.spawn(brain: brain);
