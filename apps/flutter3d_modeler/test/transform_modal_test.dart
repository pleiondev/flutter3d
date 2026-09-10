/// A transform in progress, without a pointer or a window.
///
///     flutter test test/transform_modal_test.dart
///
/// This is the half of the basic operations that is arithmetic: which axes a
/// constraint lets through, what a half-typed number means, and where a snap
/// lands. What needs a window is the key arriving and the pointer moving.
library;

import 'dart:math' as math;

import 'package:flutter3d_modeler/src/transform_modal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A move that has been dragged by [by] and nothing else.
TransformModal dragged(Vector3 by, {TransformKind kind = TransformKind.move}) =>
    TransformModal(kind)..dragged = by;

void main() {
  group('a constraint', () {
    test('an axis lets one component through', () {
      final modal = dragged(Vector3(1, 2, 3))..axis = TransformAxis.x;

      // Mutation: zero the components the constraint *allows* instead of the
      // ones it does not — a sign slip that reads the same. The object then
      // moves in the two directions the person just said to leave alone.
      expect(modal.amount, Vector3(1, 0, 0));
    });

    test('a plane lets two through', () {
      final modal = dragged(Vector3(1, 2, 3))..axis = TransformAxis.yz;

      expect(modal.amount, Vector3(0, 2, 3));
    });

    test('the same key twice is the plane across it', () {
      // What two presses of `X` mean, and the reason there is a second press:
      // "along X" and "in the plane at right angles to X" are the two things a
      // person wants, and the second is otherwise a modifier nobody finds.
      expect(TransformAxis.free.pressed(TransformAxis.x), TransformAxis.x);
      expect(TransformAxis.x.pressed(TransformAxis.x), TransformAxis.yz);
      // Mutation: leave it at the plane. A third press then does nothing, so
      // the only way back to an unconstrained move is Escape — which throws
      // the whole transform away.
      expect(TransformAxis.yz.pressed(TransformAxis.x), TransformAxis.free);
    });

    test('a different key starts again on that axis', () {
      expect(TransformAxis.x.pressed(TransformAxis.y), TransformAxis.y);
      expect(TransformAxis.yz.pressed(TransformAxis.z), TransformAxis.z);
    });
  });

  group('typing a number', () {
    test('beats the pointer, along the axis that was named', () {
      final modal = dragged(Vector3(1, 2, 3))
        ..axis = TransformAxis.y
        ..type('5');

      // `G Y 5` is five along Y whatever the mouse did, which is the whole
      // reason for being able to type one. Mutation: add the typed number to
      // the drag instead of replacing it, and the answer depends on where the
      // pointer happened to be when the first digit was pressed.
      expect(modal.amount, Vector3(0, 5, 0));
    });

    test('with no axis it goes along X', () {
      final modal = dragged(Vector3(1, 2, 3))..type('4');

      // A number with no axis has to mean something, and the first axis is
      // what every modeller picks.
      expect(modal.amount, Vector3(4, 0, 0));
    });

    test('a half-typed number is shown and not applied', () {
      final modal = TransformModal(TransformKind.move);

      expect(modal.type('-'), isTrue);
      expect(modal.typedValue, isNull);
      expect(modal.typed, '-');

      expect(modal.type('2'), isTrue);
      expect(modal.type(','), isTrue);
      // `-2,` is a minus two waiting for a fraction. Mutation: parse the text
      // as it arrives and `-2,` is null, so a person mid-number sees the object
      // jump back to where it was between the comma and the next digit.
      expect(modal.typedValue, -2.0);
      expect(modal.type('5'), isTrue);
      expect(modal.typedValue, -2.5);
    });

    test('a second point and a late sign are refused', () {
      final modal = TransformModal(TransformKind.move)
        ..type('1')
        ..type('.');

      // Mutation: take them. `1.2.3` and `5-3` are shown as though they were
      // numbers and apply nothing when Enter is pressed, so the transform ends
      // by silently doing what the mouse said instead.
      expect(modal.type('.'), isFalse);
      expect(modal.type('-'), isFalse);
      expect(modal.typed, '1.');
    });

    test('backspace takes one off, and off the end is nothing', () {
      final modal = TransformModal(TransformKind.move)..type('1');

      expect(modal.type('backspace'), isTrue);
      expect(modal.typed, isNull);
      // Nothing left to delete: refused, so the caller can pass the key on
      // rather than swallowing it.
      expect(modal.type('backspace'), isFalse);
    });

    test('a letter is refused so the caller can use it', () {
      final modal = TransformModal(TransformKind.move);

      // `X` is a constraint while a number is being typed as much as before
      // one. Mutation: swallow every key, and `G 5 X` types nothing and
      // constrains nothing — the two features stop composing.
      expect(modal.type('x'), isFalse);
      expect(modal.typed, isNull);
    });
  });

  group('snapping', () {
    test('a move lands on tenths', () {
      final modal = dragged(Vector3(0.34, -0.06, 1.27))..snapping = true;

      // The tolerance is the width of a `Vector3`'s single-precision storage
      // rather than a hedge about the rounding: a tenth is not a float32.
      expect(modal.amount.x, closeTo(0.3, 1e-6));
      expect(modal.amount.y, closeTo(-0.1, 1e-6));
      expect(modal.amount.z, closeTo(1.3, 1e-6));
    });

    test('a turn lands on fifteen degrees', () {
      final modal = dragged(Vector3(0.30, 0, 0), kind: TransformKind.rotate)
        ..snapping = true;

      // Mutation: snap a turn to the same tenth a move uses. A tenth of a
      // radian is 5.7 degrees, which is not a step anybody thinks in — the
      // three steps are a tenth of a unit, fifteen degrees and a tenth of a
      // factor, and they are three numbers because they measure three things.
      expect(modal.amount.x, closeTo(math.pi / 12, 1e-6));
    });

    test('a typed number is not snapped', () {
      final modal = dragged(Vector3(1, 0, 0))
        ..snapping = true
        ..type('0')
        ..type('.')
        ..type('0')
        ..type('7');

      // Somebody who typed 0.07 asked for 0.07. Mutation: snap it anyway and
      // the number they typed is not the number they get, which is the one
      // thing typing a number is for.
      expect(modal.amount.x, closeTo(0.07, 1e-6));
    });
  });

  group('what the status line says', () {
    test('names the constraint and the amount', () {
      final modal = dragged(Vector3(1.5, 0, 0))..axis = TransformAxis.x;

      expect(modal.says, contains('along X'));
      expect(modal.says, contains('1.5'));
    });

    test('a turn is shown in degrees', () {
      final modal = dragged(
        Vector3(math.pi / 2, 0, 0),
        kind: TransformKind.rotate,
      );

      // Radians are what the arithmetic uses and degrees are what a person
      // reads. Mutation: show the radians and the status line says 1.571,
      // which nobody can check against anything.
      expect(modal.says, contains('90'));
    });

    test('shows the number as it is being typed', () {
      final modal = TransformModal(TransformKind.move)
        ..type('1')
        ..type('.');

      expect(modal.says, contains('1.'));
    });
  });
}
