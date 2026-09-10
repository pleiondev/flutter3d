/// A transform taken apart into fields and put back, without a window.
///
///     flutter test test/transform_fields_test.dart
///
/// The panel's rows are a widget's business; the conversion under them is
/// arithmetic with a right answer, and this is where the right answer is
/// written down. What is worth pinning is the unit the fields are in, the order
/// the turns are in, that the round trip does not lose anything or drift, and
/// what happens in the two places where the conversion is ambiguous — a mirror
/// and a pole.
library;

import 'package:flutter3d_modeler/src/transform_fields.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Both matrices, element by element.
///
/// A tolerance rather than equality because a `Matrix4` here is
/// single-precision storage: 1e-6 is a few ulps of a number of order one, and
/// nothing in these tests is of a larger order.
void expectSameMatrix(Matrix4 got, Matrix4 want, {double within = 1e-6}) {
  for (var i = 0; i < 16; i++) {
    expect(got.storage[i], closeTo(want.storage[i], within), reason: 'at $i');
  }
}

/// The matrix these fields make, or a failure naming the refusal.
Matrix4 built(TransformFields fields) {
  final made = transformFromFields(fields);
  expect(made.refused, isNull, reason: 'refused: ${made.refused}');
  return made.matrix!;
}

/// A handful of transforms that between them use every part of the conversion.
const List<(String, List<double>, List<double>, List<double>)> examples =
    <(String, List<double>, List<double>, List<double>)>[
      ('the identity', <double>[0, 0, 0], <double>[0, 0, 0], <double>[1, 1, 1]),
      (
        'a plain move',
        <double>[1.5, -2, 30],
        <double>[0, 0, 0],
        <double>[1, 1, 1],
      ),
      (
        'a turn about each axis at once',
        <double>[0, 0, 0],
        <double>[30, -20, 45],
        <double>[1, 1, 1],
      ),
      (
        'an uneven scale',
        <double>[0, 0, 0],
        <double>[0, 0, 0],
        <double>[2, 0.5, 3],
      ),
      (
        'all three together',
        <double>[-3, 4, 0.25],
        <double>[15, 80, -170],
        <double>[2, 1.25, 0.5],
      ),
      ('a mirror', <double>[1, 2, 3], <double>[10, 20, 30], <double>[1, -1, 1]),
    ];

TransformFields fieldsOf(
  List<double> position,
  List<double> rotation,
  List<double> scale,
) => (
  position: Vector3.array(position),
  rotationDegrees: Vector3.array(rotation),
  scale: Vector3.array(scale),
);

void main() {
  group('the unit', () {
    test('the fields are degrees', () {
      final fields = transformFieldsOf(
        built(
          fieldsOf(<double>[0, 0, 0], <double>[0, 45, 0], <double>[1, 1, 1]),
        ),
      );

      // Mutation: hand back the radians. The field then reads 0.785 where a
      // person typed 45, and every rotation in the panel becomes a number
      // nobody can check against anything. Dropping the `degrees()` on the way
      // out fails this at 0.785 against 45.
      expect(fields.rotationDegrees.y, closeTo(45, 1e-4));
    });

    test('45 in the field is an eighth of a turn in the matrix', () {
      final Matrix4 matrix = built(
        fieldsOf(<double>[0, 0, 0], <double>[0, 0, 90], <double>[1, 1, 1]),
      );

      // A quarter turn about Z takes X to Y. Mutation: drop the `radians()` on
      // the way in, and 90 becomes ninety radians — a turn of 117 degrees,
      // fourteen whole revolutions later. This fails at -0.448 where it wanted
      // 0, and the field still reads 90 the whole time.
      final Vector3 turned = matrix.transform3(Vector3(1, 0, 0));
      expect(turned.x, closeTo(0, 1e-6));
      expect(turned.y, closeTo(1, 1e-6));
    });
  });

  group('the order of the turns', () {
    test('X is applied after Z, not before it', () {
      final Matrix4 matrix = built(
        fieldsOf(<double>[0, 0, 0], <double>[90, 0, 90], <double>[1, 1, 1]),
      );

      // `Rx · Ry · Rz` turns a point about Z first: X goes to Y, and then the
      // quarter turn about X takes Y to Z. Mutation: multiply the three the
      // other way round. The same point stops at Y — 1 where this wants 0 —
      // so the panel and Blender disagree about what the same three numbers
      // mean, and a model authored in one is wrong in the other.
      final Vector3 turned = matrix.transform3(Vector3(1, 0, 0));
      expect(turned.x, closeTo(0, 1e-6));
      expect(turned.y, closeTo(0, 1e-6));
      expect(turned.z, closeTo(1, 1e-6));
    });

    test('the middle turn is Y', () {
      // Read back from a matrix built the other way about: only Y survives a
      // turn about Y, whatever else is going on, because it is the axis whose
      // sine is one entry on its own.
      final fields = transformFieldsOf(
        built(
          fieldsOf(<double>[0, 0, 0], <double>[0, -35, 0], <double>[1, 1, 1]),
        ),
      );

      expect(fields.rotationDegrees.x, closeTo(0, 1e-4));
      expect(fields.rotationDegrees.y, closeTo(-35, 1e-4));
      expect(fields.rotationDegrees.z, closeTo(0, 1e-4));
    });
  });

  group('the round trip', () {
    for (final (String what, position, rotation, scale) in examples) {
      test('$what comes back the same matrix', () {
        final Matrix4 first = built(fieldsOf(position, rotation, scale));

        final Matrix4 again = built(transformFieldsOf(first));

        // Taking a transform apart to show it and putting it back when one box
        // changed must not move the object by itself. Mutation: read the basis
        // by rows instead of columns — the transpose of a rotation is its
        // inverse, so it comes back turned the wrong way. Every example with a
        // turn in it fails; the first is -0.664 against 0.491.
        expectSameMatrix(again, first);
      });
    }

    test('doing it over and over settles instead of walking', () {
      final List<Matrix4> passes = <Matrix4>[
        built(
          fieldsOf(<double>[-3, 4, 0.25], <double>[15, 80, -170], <double>[
            2,
            1.25,
            0.5,
          ]),
        ),
      ];
      for (var again = 0; again < 20; again++) {
        passes.add(built(transformFieldsOf(passes.last)));
      }

      // What actually happens, measured rather than hoped for: the first few
      // passes each nudge an element by one ulp of single precision — 1.19e-7
      // on a value of 1.78 — and by the sixth the conversion has reached a
      // matrix it returns unchanged, bit for bit, from then on. Two hundred
      // passes were run while this was written and none moved after the sixth.
      // The whole walk is four ulps, which is the bound below.
      //
      // Mutation: keep the four ulps and give up the settling — round the
      // fields to three places on the way out, the way the panel shows them.
      // Every pass then finds a slightly different matrix and the exact check
      // fails by 2.4e-7, which is an object walking off while somebody opens
      // and closes the panel.
      expectSameMatrix(passes[20], passes[10], within: 0);
      expectSameMatrix(passes[20], passes[1], within: 1e-6);
    });
  });

  group('a mirror', () {
    test('a negative scale is kept, not clamped away', () {
      final fields = transformFieldsOf(
        built(
          fieldsOf(<double>[0, 0, 0], <double>[0, 0, 0], <double>[1, 1, -1]),
        ),
      );

      // Mutation: take the length of each axis and stop there. The mirror is
      // then thrown away silently — the product comes back 1 against -1, so
      // the panel reads 1, 1, 1 for an object that is inside out, and the next
      // thing typed into any box un-mirrors it.
      expect(
        fields.scale.x * fields.scale.y * fields.scale.z,
        closeTo(-1, 1e-6),
      );
    });

    test('the sign always comes back on X', () {
      final fields = transformFieldsOf(
        built(
          fieldsOf(<double>[0, 0, 0], <double>[0, 0, 0], <double>[1, 1, -1]),
        ),
      );

      // Flipping Z is the same matrix as flipping X and turning half a circle,
      // and nothing can tell which was meant. Choosing X to carry it is what
      // `Matrix4.decompose` does, so the panel and the scene graph agree; what
      // a person sees is the spelling move. Written down here because it is the
      // surprise: a mirror in Z reads back as a mirror in X and a half turn in
      // the other two boxes.
      expect(fields.scale.x, closeTo(-1, 1e-6));
      expect(fields.scale.y, closeTo(1, 1e-6));
      expect(fields.scale.z, closeTo(1, 1e-6));
      expect(fields.rotationDegrees.x.abs(), closeTo(180, 1e-4));
      expect(fields.rotationDegrees.y.abs(), closeTo(0, 1e-4));
      expect(fields.rotationDegrees.z.abs(), closeTo(180, 1e-4));
    });

    test('and the object is where it was', () {
      final Matrix4 first = built(
        fieldsOf(<double>[1, 2, 3], <double>[10, 20, 30], <double>[1, -1, 1]),
      );

      // The spelling moved and the matrix did not, which is the whole defence
      // of moving it. Mutation: negate the X scale without flipping the X
      // column of the basis to match. The round trip then comes back mirrored
      // in a different axis, -0.814 against 0.814: the same nine numbers, a
      // different object.
      expectSameMatrix(built(transformFieldsOf(first)), first);
      expect(first.determinant(), lessThan(0));
    });
  });

  group('a pole', () {
    test('at 90 in Y the whole turn goes to X', () {
      final fields = transformFieldsOf(
        built(
          fieldsOf(<double>[0, 0, 0], <double>[30, 90, 30], <double>[1, 1, 1]),
        ),
      );

      // X and Z are the same turn once Y is a quarter circle, so only their
      // sum is in the matrix. This gives all of it to X. Mutation: divide
      // through at the pole anyway. It fails at 30 against 60 — the division
      // digs 30 and 30 back out of what the rounding left of cos(Y), which
      // looks like the better answer until you notice it is the rounding's
      // answer: the matrix holds only the sum, so the split moves with the
      // last bit of the numbers that made it. Giving the whole sum to X is at
      // least the same answer every time.
      expect(fields.rotationDegrees.x, closeTo(60, 1e-3));
      expect(fields.rotationDegrees.y, closeTo(90, 1e-3));
      expect(fields.rotationDegrees.z, closeTo(0, 1e-3));
    });

    test('and it is still the same object', () {
      final Matrix4 first = built(
        fieldsOf(<double>[0, 1, 0], <double>[30, 90, 30], <double>[1, 2, 1]),
      );

      // The reading is ambiguous; the matrix is not. 60, 90, 0 draws exactly
      // what 30, 90, 30 draws.
      expectSameMatrix(built(transformFieldsOf(first)), first, within: 1e-5);
    });

    test('just short of the pole the split is still read', () {
      final fields = transformFieldsOf(
        built(
          fieldsOf(<double>[0, 0, 0], <double>[30, 89, 30], <double>[1, 1, 1]),
        ),
      );

      // A degree away from the pole there is still a real split to find, and
      // taking the pole too early would throw it away. Mutation: widen the
      // threshold to a plain 0.999, the sine of 87.4 degrees. The split within
      // three degrees of the pole is then given up for no reason and this
      // comes back as 59.996 against 30.
      expect(fields.rotationDegrees.x, closeTo(30, 1e-2));
      expect(fields.rotationDegrees.z, closeTo(30, 1e-2));
    });

    test('the reading jumps once on the way through, and the sum does not', () {
      // What a person dragging a turn up through the pole actually sees, since
      // the library comment promises it: 30 and 30 in the two boxes until Y
      // reaches 89.975, then 60 and 0 from there on. It is one jump and not a
      // flicker, and the sum is 60 on both sides of it, which is the part the
      // matrix really holds.
      final List<Vector3> readings = <double>[89.9, 89.975, 89.98, 90]
          .map(
            (double y) => transformFieldsOf(
              built(
                fieldsOf(<double>[0, 0, 0], <double>[30, y, 30], <double>[
                  1,
                  1,
                  1,
                ]),
              ),
            ).rotationDegrees,
          )
          .toList();

      expect(readings[0].x, closeTo(30, 1e-2));
      expect(readings[1].x, closeTo(30, 1e-2));
      expect(readings[2].x, closeTo(60, 1e-2));
      expect(readings[3].x, closeTo(60, 1e-2));
      for (final Vector3 reading in readings) {
        expect(reading.x + reading.z, closeTo(60, 1e-2));
      }
    });
  });

  group('what cannot become a matrix', () {
    test('an infinity is refused, and the sentence names the box', () {
      final made = transformFromFields(
        fieldsOf(<double>[0, double.infinity, 0], <double>[0, 0, 0], <double>[
          1,
          1,
          1,
        ]),
      );

      // Mutation: let it through. A matrix comes back where null was wanted,
      // and it is full of NaN: the object stops being drawn, and so does
      // everything computed from it afterwards — a bounding box, a selection
      // middle, the camera framing it — so the failure arrives a long way from
      // the box the infinity was typed into.
      expect(made.matrix, isNull);
      expect(made.refused, 'Y of the position is not a number');
    });

    test('a NaN in the turn is refused', () {
      final made = transformFromFields(
        fieldsOf(<double>[0, 0, 0], <double>[0, 0, double.nan], <double>[
          1,
          1,
          1,
        ]),
      );

      expect(made.matrix, isNull);
      expect(made.refused, 'Z of the rotation is not a number');
    });

    test('a scale of zero is refused in the same words as the command', () {
      final made = transformFromFields(
        fieldsOf(<double>[0, 0, 0], <double>[0, 0, 0], <double>[1, 0, 1]),
      );

      // The same sentence `ScaleBy` refuses with, because it is the same
      // mistake: a flattened object cannot be scaled back out, and the turn
      // about the flattened axis is gone with it. Mutation: drop the check and
      // a matrix comes back where null was wanted, so a person flattens an
      // object by typing one character and cannot undo it by typing another.
      expect(made.matrix, isNull);
      expect(made.refused, 'a scale of zero would flatten the object');
    });

    test('a refusal is a value, not a throw', () {
      // Every one of these is a thing a person can type into a box. A panel
      // row that has to catch to find out is a panel row that will not.
      for (final List<double> silly in <List<double>>[
        <double>[double.nan, 1, 1],
        <double>[1, double.negativeInfinity, 1],
        <double>[1, 1, 0],
      ]) {
        final made = transformFromFields(
          fieldsOf(<double>[0, 0, 0], <double>[0, 0, 0], silly),
        );
        expect(made.matrix, isNull);
        expect(made.refused, isNotNull);
      }
    });
  });

  group('a matrix that is already flattened', () {
    test('keeps the turn of the axes that are left', () {
      // Nothing in the modeller should make one — the scale command and the
      // fields both refuse a zero — but a file can hold one, and the panel has
      // to show the person something they can type over. A turn of 30 about Z
      // with the Z axis then squashed flat: X and Y still say which way the
      // object faces, and that is what the boxes have to show.
      final Matrix4 flattened = built(
        fieldsOf(<double>[4, 5, 6], <double>[0, 0, 30], <double>[1, 1, 1]),
      );
      for (var row = 0; row < 3; row++) {
        flattened.setEntry(row, 2, 0);
      }

      final fields = transformFieldsOf(flattened);

      // Mutation: divide by the length without checking it. The flat column
      // divides zero by zero and comes out NaN, and although `clamp` then
      // turns that NaN into a 1 rather than letting it through — which is why
      // the finiteness check below passes either way — a sine of 1 is the
      // pole, so the turn is read as 0, 90, 0 and this fails at 0 against 30.
      // The object is told it faces somewhere it does not.
      expect(fields.position, Vector3(4, 5, 6));
      expect(fields.scale.z, 0);
      expect(fields.rotationDegrees.z, closeTo(30, 1e-3));
      expect(fields.rotationDegrees.y, closeTo(0, 1e-3));
      for (final double number in <double>[
        ...fields.rotationDegrees.storage,
        ...fields.scale.storage,
      ]) {
        expect(number.isFinite, isTrue, reason: '$number');
      }
    });
  });

  test('the position is read straight off the matrix', () {
    final fields = transformFieldsOf(
      built(
        fieldsOf(<double>[1.5, -2, 30], <double>[10, 20, 30], <double>[
          2,
          2,
          2,
        ]),
      ),
    );

    // Mutation: read the translation from the scaled columns instead of the
    // fourth one. A scaled and turned object then reports 1.372 for the 1.5 it
    // is at, so typing anything into any other box teleports it.
    expect(fields.position.x, closeTo(1.5, 1e-5));
    expect(fields.position.y, closeTo(-2, 1e-5));
    expect(fields.position.z, closeTo(30, 1e-4));
  });
}
