/// A transform taken apart into the nine numbers a person edits, and put back
/// together again.
///
/// **The document holds a `Matrix4` and the panel holds nine boxes**, and
/// something has to be the translator. Sixteen numbers is what a scene graph
/// wants and three-plus-three-plus-three is what a person can type, so the
/// conversion lives here rather than in the panel: it is arithmetic with a
/// right answer, and arithmetic with a right answer should be testable without
/// a window.
///
/// **Degrees in the fields and radians in the matrix.** A person types 45 and
/// not 0.785, and the alternative — showing radians because that is what the
/// maths uses — makes every rotation in the panel a number nobody can check
/// against anything.
///
/// **The turn is read and written as X then Y then Z**, meaning the rotation
/// part is `Rx · Ry · Rz`, so a point is turned about Z first and about X last.
/// That is the default order in Blender and in three.js, and it is worth
/// matching because a person who reads 30, 0, 45 here and types the same three
/// numbers there has to get the same object. There is no field for the order
/// and no plan for one: an order picker is a control that six people understand
/// and everybody else changes by accident.
///
/// **A negative scale is kept, and it always comes back on X.** Mirroring is a
/// real edit, so a negative number is not clamped away. But a mirror has no
/// axis of its own: flipping Z is the very same matrix as flipping X and
/// turning half a circle about Y, and no decomposition can tell which of the
/// two somebody meant. This one puts the sign on X, the way `Matrix4.decompose`
/// and every engine that follows three.js does, so the panel and the scene
/// graph agree about which axis carries the mirror. What a person sees is that
/// typing -1 into Z and looking again shows a scale of -1, 1, 1 and a turn of
/// 180, 0, 180 — a half turn that puts back the two axes the sign moved. The
/// object is right; the spelling moved.
///
/// **At ±90 degrees of Y the turn cannot be split**, because the X and the Z
/// turns become the same turn. Only their sum survives in the matrix, so this
/// gives the whole of it to X and reports Z as zero: 30, 90, 30 is read back as
/// 60, 90, 0, which is the same object.
///
/// The seam that leaves is worth being plain about, because it is a thing a
/// person will see. Somebody dragging a turn up through the pole watches X and
/// Z read 30 and 30 until Y reaches 89.975 and then jump to 60 and 0 in one
/// frame, their sum unchanged. Nothing better is available — the matrix at the
/// pole holds the sum and nothing else — and the alternative of easing across
/// would mean the panel showing numbers that are not what the object is doing.
/// What the panel must not do is re-read a box somebody is typing in, and it
/// already does not: that is `NumberField`'s rule.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// What the panel edits: a place, a turn in degrees, and a size along each
/// axis.
typedef TransformFields = ({
  Vector3 position,
  Vector3 rotationDegrees,
  Vector3 scale,
});

/// Where the Y turn stops being splittable into an X and a Z one.
///
/// A sine of this is 89.974 degrees, so the last twenty-six thousandths of a
/// degree before the pole are treated as the pole. The cosine there is about
/// 4.5e-4, and both of the numbers the split divides are that small: in the
/// single-precision storage a `Matrix4` keeps they have about three digits
/// left, and below this they have fewer than that. Taking the pole early is
/// giving up a split that was already noise.
const double _turnedFlatAbove = 0.9999999;

/// Takes [matrix] apart into the numbers the panel shows.
///
/// Total, on purpose: whatever the document holds, this answers with nine
/// numbers. A matrix with shear in it loses the shear, and a matrix flattened
/// along an axis reports a scale of zero there and no turn about it, because
/// the turn went with it. Neither is recoverable, and the alternative — a
/// refusal — would be a panel that shows nothing at all for an object a person
/// can see on the screen and wants to fix.
TransformFields transformFieldsOf(Matrix4 matrix) {
  final Vector3 alongX = Vector3(
    matrix.entry(0, 0),
    matrix.entry(1, 0),
    matrix.entry(2, 0),
  );
  final Vector3 alongY = Vector3(
    matrix.entry(0, 1),
    matrix.entry(1, 1),
    matrix.entry(2, 1),
  );
  final Vector3 alongZ = Vector3(
    matrix.entry(0, 2),
    matrix.entry(1, 2),
    matrix.entry(2, 2),
  );

  // The length of each axis is its scale, and a matrix that turns a
  // right-handed set of axes into a left-handed one is mirrored somewhere. The
  // sign goes on X for the reason in the library comment.
  final Vector3 scale = Vector3(
    matrix.determinant() < 0 ? -alongX.length : alongX.length,
    alongY.length,
    alongZ.length,
  );

  final Matrix3 basis = Matrix3.columns(
    _unit(alongX, scale.x, Vector3(1, 0, 0)),
    _unit(alongY, scale.y, Vector3(0, 1, 0)),
    _unit(alongZ, scale.z, Vector3(0, 0, 1)),
  );

  // Read off `Rx · Ry · Rz`: the top-right entry is sin(Y) on its own, and the
  // rest of the top row and the right column carry X and Z divided by cos(Y).
  // Clamped because a basis assembled from a flattened matrix need not be
  // orthonormal, and asin of 1.0000001 is a NaN that would spread through
  // every field.
  final double sinY = basis.entry(0, 2).clamp(-1.0, 1.0);
  final (double x, double z) = sinY.abs() < _turnedFlatAbove
      ? (
          math.atan2(-basis.entry(1, 2), basis.entry(2, 2)),
          math.atan2(-basis.entry(0, 1), basis.entry(0, 0)),
        )
      : (math.atan2(basis.entry(2, 1), basis.entry(1, 1)), 0.0);

  return (
    position: matrix.getTranslation(),
    rotationDegrees: Vector3(degrees(x), degrees(math.asin(sinY)), degrees(z)),
    scale: scale,
  );
}

/// The direction of [column], or [ifFlattened] when there is nothing left of
/// it.
///
/// Dividing by a negative length flips the column, which is what carries the
/// mirror out of the basis and into the scale: what is left is a rotation.
Vector3 _unit(Vector3 column, double length, Vector3 ifFlattened) =>
    length == 0 ? ifFlattened : column / length;

/// Puts the fields back into a matrix, or refuses with a sentence.
///
/// A record rather than a throw, because a refusal here is an ordinary answer
/// from a panel row and the caller shows it in the status line, the way a
/// refused command is shown.
({Matrix4? matrix, String? refused}) transformFromFields(
  TransformFields fields,
) {
  // Infinity and NaN both parse out of a text field, and a transform holding
  // either draws nothing while every number computed from it afterwards is a
  // NaN as well — so the failure arrives a long way from the box it was typed
  // into. `NumberField` already refuses them; this refuses them again, because
  // the fields also arrive from a gizmo drag and from a file.
  final String? notANumber =
      _notANumber(fields.position, 'position') ??
      _notANumber(fields.rotationDegrees, 'rotation') ??
      _notANumber(fields.scale, 'scale');
  if (notANumber != null) return (matrix: null, refused: notANumber);

  // The same sentence `ScaleBy` refuses with, and refused for the same reason:
  // a zero flattens the object into a plane no later scale multiplies back out
  // of, and it takes the turn about that axis with it. Saying it identically
  // whether a person typed 0 in the box or pressed `S 0` is the point.
  if (fields.scale.x == 0 || fields.scale.y == 0 || fields.scale.z == 0) {
    return (matrix: null, refused: 'a scale of zero would flatten the object');
  }

  final Matrix3 turn = Matrix3.rotationX(radians(fields.rotationDegrees.x))
    ..multiply(Matrix3.rotationY(radians(fields.rotationDegrees.y)))
    ..multiply(Matrix3.rotationZ(radians(fields.rotationDegrees.z)));

  return (
    matrix: Matrix4.identity()
      // Scaling the columns rather than multiplying by a diagonal matrix: the
      // two are the same arithmetic and this one is three multiplications
      // instead of twenty-seven, but the reason it is written this way is that
      // it says which order the scale is in — inside the turn, so an object
      // stretched along X stays stretched along its own X when it is turned.
      ..setRotation(
        Matrix3.columns(
          turn.getColumn(0) * fields.scale.x,
          turn.getColumn(1) * fields.scale.y,
          turn.getColumn(2) * fields.scale.z,
        ),
      )
      ..setTranslation(fields.position),
    refused: null,
  );
}

/// Which component of [value] is not a number, said as a sentence.
String? _notANumber(Vector3 value, String what) {
  for (final (String axis, double along) in <(String, double)>[
    ('X', value.x),
    ('Y', value.y),
    ('Z', value.z),
  ]) {
    if (!along.isFinite) return '$axis of the $what is not a number';
  }
  return null;
}
