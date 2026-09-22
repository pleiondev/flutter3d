/// Deciding what a transform-panel field commit means for the document.
///
/// **Pulled out of `main.dart` for the reason `transform_fields.dart` and
/// `properties_sections.dart` were.** `PropertiesPanel` is a wide widget to
/// pump for one arithmetic question, so this file answers it directly —
/// which command one field commit becomes, arithmetic on two
/// `TransformFields`, checkable without a `NumberField` in sight.
///
/// **Position and rotation are read back as a difference and handed to
/// `MoveBy`/`RotateBy`, which is what lets the pivot and the space chips mean
/// anything at all.** Those two commands already do exactly what the gizmo and
/// the keyboard do for a drag — turn or move everything selected about a
/// chosen point — and reusing them here rather than writing a third path is
/// the same argument `main.dart`'s own `_applyModal` makes for the gizmo: one
/// answer to what a turn is, not two that could disagree.
///
/// **A held object's own rotation comes out exactly as typed, whichever pivot
/// is chosen.** The delta between the old reading and the new one is computed
/// as a plain rotation matrix — old, then new, both built the same way
/// `transformFromFields` builds them — rather than assumed to be a turn about
/// whichever axis's box was edited. That difference matters once another axis
/// already holds a turn: editing Y after X is not a turn about the world's own
/// Y axis, and the matrix says which one it really is. The pivot only decides
/// *where* that turn is centred, not what it is, so the held object's own
/// orientation lands on the number typed into its box either way; only its
/// place can move, when the pivot puts the centre somewhere else.
///
/// **Scale keeps setting the held object alone.** `ScaleBy` takes one ratio
/// applied to every axis, for the reason its own doc argues at length, and the
/// grid this panel draws edits one axis at a time — so a scale edit is
/// anisotropic by construction and there is no ratio that reproduces it across
/// a selection. Broadcasting the exact matrix instead of a ratio would ignore
/// the pivot silently; refusing the edit would take away scaling with more than
/// one object selected. What is here is the honest middle: the held object gets
/// exactly what was typed, the rest of the selection is left alone, and the
/// pivot chip has no effect on a scale edit until a command exists that can
/// carry three ratios instead of one.
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

import 'transform_fields.dart';

/// How far apart two numbers have to be before they count as different — a
/// `NumberField` round trip settles within a handful of ulps
/// (`transform_fields_test.dart`'s own "doing it over and over settles instead
/// of walking"), and a pole's own reading can jump to a different spelling of
/// the identical matrix. Either would otherwise look like an edit and put a
/// no-op step on the undo stack.
const double _sameEnough = 1e-6;

/// What [from] becoming [to] means for the document: the command to run, or
/// the sentence to show instead when [to] does not describe a matrix at all.
///
/// Both null when nothing actually changed — the same number typed back, or a
/// pole read one way and typed back the other, which is the identical object
/// under a different spelling.
({ModelCommand? command, String? refused}) transformCommandFor({
  required int heldId,
  required TransformFields from,
  required TransformFields to,
  required TransformPivot pivot,
  required TransformSpace space,
}) {
  final built = transformFromFields(to);
  if (built.refused != null) return (command: null, refused: built.refused);

  final bool positionChanged = !_closeVector(from.position, to.position);
  final bool rotationChanged = !_closeVector(
    from.rotationDegrees,
    to.rotationDegrees,
  );
  final bool scaleChanged = !_closeVector(from.scale, to.scale);
  final int changed =
      (positionChanged ? 1 : 0) +
      (rotationChanged ? 1 : 0) +
      (scaleChanged ? 1 : 0);

  if (changed == 0) return (command: null, refused: null);

  if (changed == 1 && positionChanged) {
    return (command: MoveBy(to.position - from.position), refused: null);
  }

  if (changed == 1 && rotationChanged) {
    final (Vector3, double)? turn = _rotationDelta(
      from.rotationDegrees,
      to.rotationDegrees,
    );
    if (turn == null) return (command: null, refused: null);
    final (Vector3 axis, double radians) = turn;
    return (
      command: RotateBy(
        axis: axis,
        radians: radians,
        pivot: pivot,
        space: space,
      ),
      refused: null,
    );
  }

  // Scale on its own, or more than one of the three at once — the second is
  // not a shape `TransformRows` produces, but a field arriving from a file
  // reload or a future caller with no such guarantee still needs an answer
  // rather than a crash, and the exact matrix is always a correct one for the
  // object that owns it.
  return (command: SetTransform(id: heldId, to: built.matrix!), refused: null);
}

bool _closeVector(Vector3 a, Vector3 b) =>
    (a.x - b.x).abs() < _sameEnough &&
    (a.y - b.y).abs() < _sameEnough &&
    (a.z - b.z).abs() < _sameEnough;

/// The turn from [oldDegrees] to [newDegrees], as an axis and an angle in
/// radians a `RotateBy` can carry — or null when the two are the same turn,
/// within [_sameEnough].
(Vector3, double)? _rotationDelta(Vector3 oldDegrees, Vector3 newDegrees) {
  final Matrix3 was = _rotationOf(oldDegrees);
  final Matrix3 now = _rotationOf(newDegrees);
  // `now · was⁻¹`, and `was` is orthonormal so its transpose is its inverse:
  // the rotation that, applied after `was`, lands on `now`.
  final Matrix3 delta = now.clone()..multiply(was.transposed());
  final Quaternion turn = Quaternion.fromRotation(delta);
  if (turn.radians.abs() < _sameEnough) return null;
  return (turn.axis, turn.radians);
}

/// The same `Rx · Ry · Rz` composition `transformFromFields` builds, with no
/// translation or scale to read back out of.
Matrix3 _rotationOf(Vector3 degrees) => Matrix3.rotationX(radians(degrees.x))
  ..multiply(Matrix3.rotationY(radians(degrees.y)))
  ..multiply(Matrix3.rotationZ(radians(degrees.z)));
