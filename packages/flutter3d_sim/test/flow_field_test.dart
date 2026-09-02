/// What the field says when it has nothing to say.
///
///     flutter test test/flow_field_test.dart
///
/// **Found by mutating `descend` and watching the suite pass.** The field
/// itself is exercised by `flutter3d_game_shooter/test/navigation_test.dart`,
/// which walks a monster round a corner — a good test of the sweep, and one
/// that never asks the four questions below, all of which are about a caller
/// that gets `false` and has to do something else.
///
/// That matters because `false` is not a failure here: a caller that gets it
/// walks straight at its target, which within one cell is the right answer.
/// Returning `true` with an unwritten `out` instead sends an agent along
/// whatever the last caller left in that vector.
library;

import 'package:flutter3d_sim/src/level/level.dart';
import 'package:flutter3d_sim/src/nav/flow_field.dart';
import 'package:flutter3d_sim/src/nav/nav_grid.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Twenty metres square, its top face at y = 0.
Brush _floor() =>
    Brush(centre: Vector3(0.0, -0.5, 0.0), size: Vector3(20.0, 1.0, 20.0));

void main() {
  test('before a sweep there is no direction anywhere', () {
    final field = FlowField(NavGrid.bake(<Brush>[_floor()]));
    final out = Vector3(9.0, 9.0, 9.0);

    expect(field.descend(Vector3(1.0, 0.0, 1.0), out), isFalse);
    expect(
      out,
      Vector3(9.0, 9.0, 9.0),
      reason: 'it wrote a direction it did not have',
    );
  });

  group('after a sweep', () {
    late FlowField field;

    setUp(() {
      field = FlowField(NavGrid.bake(<Brush>[_floor()]))
        ..rebuild(Vector3(8.0, 0.0, 8.0));
    });

    test('a cell with a route says which way', () {
      final out = Vector3.zero();

      expect(field.descend(Vector3(-8.0, 0.0, -8.0), out), isTrue);
      expect(out.length, closeTo(1.0, 1e-6), reason: 'not a unit vector');
      expect(out.y, 0.0, reason: 'the field steers on the ground');
      expect(out.x, greaterThan(0.0));
      expect(out.z, greaterThan(0.0));
    });

    test('and standing in the goal cell says nothing', () {
      // Deliberately, and the reason is in `descend`: steering by the field
      // inside the goal's own cell has an agent circling a cell centre half a
      // metre from the player.
      final out = Vector3(9.0, 9.0, 9.0);

      expect(field.descend(Vector3(8.0, 0.0, 8.0), out), isFalse);
      expect(out, Vector3(9.0, 9.0, 9.0));
    });

    test('and off the grid says nothing', () {
      final out = Vector3(9.0, 9.0, 9.0);

      expect(field.descend(Vector3(500.0, 0.0, 500.0), out), isFalse);
      expect(out, Vector3(9.0, 9.0, 9.0));
    });

    test('and a cell the sweep never reached says nothing', () {
      // A room the goal is walled out of. Nothing on this floor is unreachable,
      // so the field is asked about a goal it could not place at all.
      final walled = FlowField(
        NavGrid.bake(<Brush>[
          _floor(),
          Brush(centre: Vector3(0.0, 1.5, 0.0), size: Vector3(1.0, 3.0, 20.0)),
        ]),
      )..rebuild(Vector3(8.0, 0.0, 0.0));
      final out = Vector3(9.0, 9.0, 9.0);

      expect(
        walled.descend(Vector3(-8.0, 0.0, 0.0), out),
        isFalse,
        reason: 'it routed through a wall',
      );
      expect(out, Vector3(9.0, 9.0, 9.0));
    });
  });
}
