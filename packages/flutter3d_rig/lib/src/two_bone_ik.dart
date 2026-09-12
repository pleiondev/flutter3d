/// A minimal two-bone IK solve on plain positions and rotations —
/// `anim-17`'s own foot lock.
///
/// **Not a reuse of `packages/flutter3d`'s own `TwoBoneIk`.** That one
/// (`engine/animation/inverse_kinematics.dart`) solves against a runtime
/// `Pose`, which this package has no reason to depend on — pulling in the
/// renderer package just to bend a leg during an offline retarget pass
/// would be a much heavier and backwards-pointing dependency than this
/// row's own work justifies (`flutter3d_model_core`, which this package
/// already depends on, does not depend on the engine either). This is the
/// same three-step textbook algorithm — bend the middle joint by the law of
/// cosines, aim the root at the target, twist around the root-target axis
/// so the middle joint lands on the pole's own side — reimplemented in
/// terms of the three joints' own world positions and local rotations,
/// which is what a baked keyframe already has without a `Pose` in play.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The result of one [solveTwoBoneIk] call: the corrected *local* rotations
/// for `root` and `mid` — `tip` never rotates, the same convention its own
/// engine namesake uses.
class TwoBoneIkResult {
  const TwoBoneIkResult({
    required this.rootLocalRotation,
    required this.midLocalRotation,
    required this.reachError,
  });

  final Quaternion rootLocalRotation;
  final Quaternion midLocalRotation;

  /// Distance between where `tip` actually lands and the requested target —
  /// zero within floating-point error whenever the target was in reach.
  final double reachError;
}

double _triangleAngle(double opposite, double a, double b) {
  if (a <= 0.0 || b <= 0.0) return 0.0;
  final cos = ((a * a + b * b - opposite * opposite) / (2.0 * a * b)).clamp(
    -1.0,
    1.0,
  );
  return math.acos(cos);
}

Vector3 _arbitraryPerpendicular(Vector3 v) {
  final reference = v.x.abs() < 0.9
      ? Vector3(1.0, 0.0, 0.0)
      : Vector3(0.0, 1.0, 0.0);
  final axis = v.cross(reference);
  return axis.length2 > 1e-12 ? axis.normalized() : Vector3(0.0, 0.0, 1.0);
}

Vector3 _perpendicularComponent(Vector3 v, Vector3 axis) =>
    v - axis * v.dot(axis);

double _signedAngle(Vector3 a, Vector3 b, Vector3 axis) {
  final unsigned = math.acos(a.dot(b).clamp(-1.0, 1.0));
  final sign = a.cross(b).dot(axis) < 0.0 ? -1.0 : 1.0;
  return unsigned * sign;
}

/// Bends `root` → `mid` → `tip` so `tip` reaches [target] as closely as the
/// chain's own two bone lengths allow, and returns the *local* rotations
/// `root` and `mid` need for that — the caller's own job to write back into
/// whatever keyframe it came from.
///
/// [rootWorldPosition], [midWorldPosition] and [tipWorldPosition] are the
/// chain's current (pre-correction) world positions, from which the two
/// bone lengths are measured. [rootParentWorldRotation] is the world
/// rotation of `root`'s own parent (identity when `root` has none, the
/// ordinary case for a hip bone whose parent is the skeleton's own
/// translated-but-unrotated root) — needed to turn the solved *world*
/// rotations back into the *local* ones a track actually stores.
/// [rootWorldRotation] and [midWorldRotation] are `root`/`mid`'s own current
/// world rotations, read the same way [rootParentWorldRotation] is.
/// [target] is clamped to the chain's reach, never refused. [pole] decides
/// which of the two ways the chain bends by naming a point `mid` should
/// lean toward.
TwoBoneIkResult solveTwoBoneIk({
  required Vector3 rootWorldPosition,
  required Vector3 midWorldPosition,
  required Vector3 tipWorldPosition,
  required Quaternion rootParentWorldRotation,
  required Quaternion rootWorldRotation,
  required Quaternion midWorldRotation,
  required Vector3 target,
  required Vector3 pole,
}) {
  final rootPos = rootWorldPosition;
  final midPos0 = midWorldPosition;
  final tipPos0 = tipWorldPosition;

  final upperLength = (midPos0 - rootPos).length;
  final lowerLength = (tipPos0 - midPos0).length;
  const epsilon = 1e-6;
  final minReach = math.max((upperLength - lowerLength).abs(), epsilon);
  final maxReach = math.max(upperLength + lowerLength - epsilon, minReach);

  final rawDist = (target - rootPos).length;
  final targetDist = math.min(math.max(rawDist, minReach), maxReach);

  final currentTipDist = (tipPos0 - rootPos).length;
  final oldAngle = _triangleAngle(currentTipDist, upperLength, lowerLength);
  final newAngle = _triangleAngle(targetDist, upperLength, lowerLength);

  var bendAxis = (midPos0 - rootPos).cross(tipPos0 - midPos0);
  bendAxis = bendAxis.length2 > epsilon
      ? bendAxis.normalized()
      : _arbitraryPerpendicular(midPos0 - rootPos);

  // `mid`'s offset from `root`, and `tip`'s from `mid`, expressed in each
  // parent's own *local* frame — fixed quantities a bone length does not
  // change while root/mid rotate. Every position below is reconstructed as
  // "parent's *current absolute* world rotation, applied to this fixed
  // local offset" — never by rotating an already-world-space offset vector
  // a second time.
  final localMidOffset = rootWorldRotation.inverted().rotated(
    midPos0 - rootPos,
  );
  final localTipOffset = midWorldRotation.inverted().rotated(
    tipPos0 - midPos0,
  );

  // **Composition order.** This build of `vector_math` composes `A * B` as
  // "apply `A`'s rotation first, `B`'s second" — `(A * B).rotated(v) ==
  // B.rotated(A.rotated(v))` — the reverse of the usual "read right to
  // left" matrix convention. An additional rotation `delta` applied *on
  // top of* an existing world rotation `old` (i.e. `old` first, `delta`
  // after) is therefore `old * delta`, not `delta * old` — confirmed
  // against this library directly (`(rx90*ry90).rotated(v) !=
  // rx90.rotated(ry90.rotated(v))`, but the reverse product does), not
  // assumed from a doc comment, after an earlier draft's `delta * old`
  // convention sent this row's own foot-lock test *further* from the
  // target than before "correction".

  // Step 1: bend `mid` to the new interior angle. See the engine's own
  // `TwoBoneIk.solve` for why the swept angle is `oldAngle - newAngle`, not
  // the other sign — the same derivation applies unchanged here, but
  // *negated*: `Quaternion.axisAngle(axis, angle).rotated(v)` in this build
  // turns out to sweep `v` around `axis` by `-angle` under the usual
  // right-hand rule, confirmed directly (`axisAngle(Z, 90°).rotated((1,0,0))`
  // lands on `(0,-1,0)`, not `(0,1,0)`) rather than assumed.
  final bendDelta = Quaternion.axisAngle(bendAxis, -(oldAngle - newAngle));
  final midWorldRotAfterBend = (midWorldRotation * bendDelta)..normalize();
  final tipAfterBend = midPos0 + midWorldRotAfterBend.rotated(localTipOffset);

  // Step 2: aim `root` so the now-correctly-bent chain points at the
  // (clamped-distance, true-direction) target.
  final toTip = (tipAfterBend - rootPos).normalized();
  final toTarget = (target - rootPos).normalized();
  // Arguments swapped from the textbook "fromTwoVectors(from, to)" reading:
  // this build's own `.rotated()` applies a `fromTwoVectors(a, b)` quaternion
  // as *b → a*, confirmed directly against the library
  // (`fromTwoVectors(a, b).rotated(b)` lands on `a`, not the reverse) rather
  // than assumed from its doc comment, which reads the other way.
  final aimDelta = Quaternion.fromTwoVectors(toTarget, toTip);
  final rootWorldRotAfterAim = (rootWorldRotation * aimDelta)..normalize();

  final midPosAfterAim =
      rootPos + rootWorldRotAfterAim.rotated(localMidOffset);
  final midWorldRotAfterAim = (midWorldRotAfterBend * aimDelta)..normalize();

  // Step 3: twist `root` around the root→target axis so `mid` sits on
  // [pole]'s own side.
  final twistAxis = toTarget;
  final currentPoleDir = _perpendicularComponent(
    midPosAfterAim - rootPos,
    twistAxis,
  );
  final desiredPoleDir = _perpendicularComponent(pole - rootPos, twistAxis);

  var rootWorldRotFinal = rootWorldRotAfterAim;
  var midWorldRotFinal = midWorldRotAfterAim;
  if (currentPoleDir.length2 > epsilon && desiredPoleDir.length2 > epsilon) {
    final twistAngle = _signedAngle(
      currentPoleDir.normalized(),
      desiredPoleDir.normalized(),
      twistAxis,
    );
    final twistDelta = Quaternion.axisAngle(twistAxis, -twistAngle);
    rootWorldRotFinal = (rootWorldRotAfterAim * twistDelta)..normalize();
    midWorldRotFinal = (midWorldRotAfterAim * twistDelta)..normalize();
  }

  final midPosFinal = rootPos + rootWorldRotFinal.rotated(localMidOffset);
  final tipPosFinal =
      midPosFinal + midWorldRotFinal.rotated(localTipOffset);

  final rootLocalRotation =
      (rootParentWorldRotation.inverted() * rootWorldRotFinal)..normalize();
  final midLocalRotation = (rootWorldRotFinal.inverted() * midWorldRotFinal)
    ..normalize();

  return TwoBoneIkResult(
    rootLocalRotation: rootLocalRotation,
    midLocalRotation: midLocalRotation,
    reachError: (tipPosFinal - target).length,
  );
}
