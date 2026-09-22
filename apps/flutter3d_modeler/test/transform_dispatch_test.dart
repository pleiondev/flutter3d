/// Which command a transform-panel field commit becomes.
///
///     flutter test test/transform_dispatch_test.dart
///
/// `ui-35n`'s own acceptance: typing 45 into the rotation-Y box gives a
/// quaternion of roughly sin(22.5°) on its own axis, and the pivot chip
/// changes what rotating two selected objects together actually does. Both
/// are arithmetic on a `TransformCommandFor` call and a `RotateBy.apply`, and
/// neither needs a `NumberField` in sight.
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/transform_dispatch.dart';
import 'package:flutter3d_modeler/src/transform_fields.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Fields at the identity, standing at [position].
TransformFields at(Vector3 position) => (
  position: position,
  rotationDegrees: Vector3.zero(),
  scale: Vector3.all(1),
);

/// Two objects with nothing but a place — a socket has no mesh, and neither
/// command under test reads one.
ModelProject twoObjects() {
  var project = const ModelProject();
  for (final double x in <double>[1, 3]) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'o$id',
        geometry: const SocketGeometry(),
        transform: Matrix4.translation(Vector3(x, 0, 0)),
      ),
    );
  }
  return project;
}

void main() {
  group("ui-35n's own acceptance", () {
    test('45 in the rotation-Y box is a turn of about 0.3827 in the '
        'quaternion', () {
      final decided = transformCommandFor(
        heldId: 1,
        from: at(Vector3.zero()),
        to: (
          position: Vector3.zero(),
          rotationDegrees: Vector3(0, 45, 0),
          scale: Vector3.all(1),
        ),
        pivot: TransformPivot.median,
        space: TransformSpace.global,
      );

      final RotateBy turn = decided.command! as RotateBy;
      final Quaternion asQuaternion = Quaternion.axisAngle(
        turn.axis,
        turn.radians,
      );

      // sin(45° / 2) ≈ 0.38268. Mutation: hand back the whole 45 degrees in
      // radians instead of the delta from a rotation that started at zero,
      // and this still passes by coincidence — the pole and the round-trip
      // groups below are what would catch that one, this one is the number
      // the row itself names.
      expect(asQuaternion.y.abs(), closeTo(0.3827, 1e-3));
    });

    test('the pivot changes what rotating two selected objects does', () {
      final project = twoObjects();
      const selection = ProjectSelection(objects: <int>[1, 2]);
      final ModelObject held = project[1]!;

      final decided = transformCommandFor(
        heldId: 1,
        from: transformFieldsOf(held.transform),
        to: (
          position: held.transform.getTranslation(),
          rotationDegrees: Vector3(0, 180, 0),
          scale: Vector3.all(1),
        ),
        pivot: TransformPivot.median,
        space: TransformSpace.global,
      );
      final RotateBy asMedian = decided.command! as RotateBy;
      expect(asMedian.pivot, TransformPivot.median);

      // Median: the two objects sit at 1 and 3, the middle is 2, and a half
      // turn about Y there swaps their places along X.
      final Outcome swung = asMedian.apply(project, selection);
      expect(swung.ok, isTrue);
      expect(swung.project![1]!.transform.getTranslation().x, closeTo(3, 1e-4));
      expect(swung.project![2]!.transform.getTranslation().x, closeTo(1, 1e-4));

      final decidedIndividual = transformCommandFor(
        heldId: 1,
        from: transformFieldsOf(held.transform),
        to: (
          position: held.transform.getTranslation(),
          rotationDegrees: Vector3(0, 180, 0),
          scale: Vector3.all(1),
        ),
        pivot: TransformPivot.individual,
        space: TransformSpace.global,
      );
      final RotateBy asIndividual = decidedIndividual.command! as RotateBy;

      // Individual: each object turns about its own origin, so both stay
      // exactly where they were.
      final Outcome spun = asIndividual.apply(project, selection);
      expect(spun.ok, isTrue);
      expect(spun.project![1]!.transform.getTranslation().x, closeTo(1, 1e-4));
      expect(spun.project![2]!.transform.getTranslation().x, closeTo(3, 1e-4));
    });
  });

  group('which command a commit becomes', () {
    test('a position-only edit becomes a move by the difference', () {
      final decided = transformCommandFor(
        heldId: 1,
        from: at(Vector3(1, 2, 3)),
        to: at(Vector3(1, 5, 3)),
        pivot: TransformPivot.median,
        space: TransformSpace.global,
      );

      final MoveBy moved = decided.command! as MoveBy;
      expect(moved.by, Vector3(0, 3, 0));
    });

    test('a scale-only edit sets the held object, pivot or no pivot', () {
      // `ScaleBy` takes one ratio for every axis and the grid edits one axis
      // at a time, so there is no ratio a pivot-aware command could carry for
      // "make this object twice as wide". The held object still gets exactly
      // what was typed.
      final TransformFields from = at(Vector3.zero());
      final TransformFields to = (
        position: Vector3.zero(),
        rotationDegrees: Vector3.zero(),
        scale: Vector3(2, 1, 1),
      );

      final decided = transformCommandFor(
        heldId: 5,
        from: from,
        to: to,
        pivot: TransformPivot.individual,
        space: TransformSpace.global,
      );

      final SetTransform set = decided.command! as SetTransform;
      expect(set.id, 5);
      expect(set.to.getColumn(0).x, closeTo(2, 1e-9));
    });

    test('the same fields twice is nothing changed, not a move by zero', () {
      final TransformFields fields = at(Vector3(4, 5, 6));

      final decided = transformCommandFor(
        heldId: 1,
        from: fields,
        to: fields,
        pivot: TransformPivot.median,
        space: TransformSpace.global,
      );

      // Mutation: hand back `MoveBy(Vector3.zero())` instead of null. A
      // person who tabs through the grid without changing anything would then
      // put a no-op step on the undo stack for every field they passed
      // through.
      expect(decided.command, isNull);
      expect(decided.refused, isNull);
    });

    test(
      'a refusal from the fields is passed on, and nothing is dispatched',
      () {
        final decided = transformCommandFor(
          heldId: 1,
          from: at(Vector3.zero()),
          to: (
            position: Vector3(0, double.infinity, 0),
            rotationDegrees: Vector3.zero(),
            scale: Vector3.all(1),
          ),
          pivot: TransformPivot.median,
          space: TransformSpace.global,
        );

        expect(decided.command, isNull);
        expect(decided.refused, 'Y of the position is not a number');
      },
    );

    test('the space chosen rides along on the rotation command', () {
      final decided = transformCommandFor(
        heldId: 1,
        from: at(Vector3.zero()),
        to: (
          position: Vector3.zero(),
          rotationDegrees: Vector3(0, 0, 30),
          scale: Vector3.all(1),
        ),
        pivot: TransformPivot.individual,
        space: TransformSpace.local,
      );

      final RotateBy turn = decided.command! as RotateBy;
      expect(turn.space, TransformSpace.local);
      expect(turn.pivot, TransformPivot.individual);
    });
  });
}
