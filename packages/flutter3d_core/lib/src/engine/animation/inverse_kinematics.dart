import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'pose.dart';

/// Rotates [joint]'s local rotation in [pose] so its *world* rotation becomes
/// `delta * (its current world rotation)`, converting through [joint]'s
/// parent — shared by [TwoBoneIk] and [FabrikIk], since both work by rotating
/// one joint at a time toward a newly-computed world-space bone direction and
/// have to hand that back to [Pose] as a *local* rotation, the only kind it
/// stores.
///
/// Reads [Pose.worldMatrices] fresh on every call rather than being handed
/// one, deliberately: a chain of three or four joints calls this a handful of
/// times per solve, and the alternative — threading a stale world-matrix list
/// through every step and hoping nothing downstream forgot to refresh it — is
/// exactly the kind of bug an IK solver is hard to unit test into finding,
/// since a wrong-but-plausible pose still *looks* like a bent limb.
void _rotateJointWorld(Pose pose, int joint, Quaternion delta) {
  final world = pose.worldMatrices();
  final parent = pose.parents[joint];
  final currentWorld = Quaternion.fromRotation(world[joint].getRotation());
  final newWorld = (delta * currentWorld)..normalize();

  final Quaternion newLocal;
  if (parent < 0 || parent >= pose.nodeCount) {
    newLocal = newWorld;
  } else {
    final parentWorld = Quaternion.fromRotation(world[parent].getRotation());
    newLocal = (parentWorld.inverted() * newWorld)..normalize();
  }

  final at = joint * 4;
  pose.rotations[at] = newLocal.x;
  pose.rotations[at + 1] = newLocal.y;
  pose.rotations[at + 2] = newLocal.z;
  pose.rotations[at + 3] = newLocal.w;
}

/// The interior angle opposite a side of length [opposite] in a triangle
/// whose other two sides are [a] and [b] — the law of cosines solved for the
/// angle. Zero when either other side is degenerate, rather than `NaN`: a
/// bone of length zero has no meaningful bend to report.
double _triangleAngle(double opposite, double a, double b) {
  if (a <= 0.0 || b <= 0.0) return 0.0;
  final cos = ((a * a + b * b - opposite * opposite) / (2.0 * a * b)).clamp(
    -1.0,
    1.0,
  );
  return math.acos(cos);
}

/// Any unit vector perpendicular to [v] — used only when [v] is degenerate
/// for the purpose that wanted a bend axis, so which perpendicular hardly
/// matters.
Vector3 _arbitraryPerpendicular(Vector3 v) {
  final reference = v.x.abs() < 0.9
      ? Vector3(1.0, 0.0, 0.0)
      : Vector3(0.0, 1.0, 0.0);
  final axis = v.cross(reference);
  return axis.length2 > 1e-12 ? axis.normalized() : Vector3(0.0, 0.0, 1.0);
}

/// The component of [v] perpendicular to the unit vector [axis].
Vector3 _perpendicularComponent(Vector3 v, Vector3 axis) =>
    v - axis * v.dot(axis);

/// The signed angle from unit vector [a] to unit vector [b], both already
/// perpendicular to unit vector [axis] — positive when the shortest rotation
/// from [a] to [b] follows the right-hand rule around [axis].
double _signedAngle(Vector3 a, Vector3 b, Vector3 axis) {
  final unsigned = math.acos(a.dot(b).clamp(-1.0, 1.0));
  final sign = a.cross(b).dot(axis) < 0.0 ? -1.0 : 1.0;
  return unsigned * sign;
}

/// Two-bone inverse kinematics — an arm or a leg, bent to reach a point —
/// `anim-14`'s own row.
///
/// **The textbook three-step algorithm**, the same one behind every
/// off-the-shelf two-bone IK node (Unity's Animation Rigging package
/// documents the identical three steps under the same name): bend the middle
/// joint by the difference between its current and desired interior angle
/// (law of cosines) in whatever plane the chain is *already* bent in; aim the
/// root so the now-correctly-bent chain points at the target; twist the whole
/// chain around the root-target axis so the middle joint lands on the side
/// [pole] names. Working from the chain's *current* bend plane rather than
/// constructing one from [pole] up front is what lets this run on top of
/// whatever [Pose] already holds — a walk cycle, another IK pass — instead of
/// only from a bind pose.
abstract final class TwoBoneIk {
  /// Bends `root` → `mid` → `tip` in [pose] so `tip` reaches [target] as
  /// closely as the chain's own two bone lengths allow.
  ///
  /// [target] is clamped to the chain's reach when it is further away than
  /// the two bones can stretch, or closer than they can fold — a target
  /// inside that dead zone has no exact triangle, and stretching to the
  /// nearest one it does have is what every real two-bone IK does rather
  /// than refusing to solve.
  ///
  /// Returns the distance between where `tip` actually landed and [target] —
  /// zero within floating-point error whenever [target] was inside reach.
  static double solve(
    Pose pose, {
    required int root,
    required int mid,
    required int tip,
    required Vector3 target,
    required Vector3 pole,
  }) {
    var world = pose.worldMatrices();
    final rootPos = world[root].getTranslation();
    final midPos0 = world[mid].getTranslation();
    final tipPos0 = world[tip].getTranslation();

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

    // The plane the chain is already bent in, so a chain that starts mid-
    // animation bends further in the same sense rather than snapping into
    // whatever plane the pole alone would pick.
    var bendAxis = (midPos0 - rootPos).cross(tipPos0 - midPos0);
    bendAxis = bendAxis.length2 > epsilon
        ? bendAxis.normalized()
        : _arbitraryPerpendicular(midPos0 - rootPos);

    // Step 1: bend the middle joint to the desired interior angle.
    //
    // `oldAngle - newAngle`, not `newAngle - oldAngle`: for any two
    // non-parallel vectors `U = midPos0 - rootPos` and `L = tipPos0 -
    // midPos0`, rotating `U` by `+arccos(U·L)` about `bendAxis = U.cross(L)`
    // lands exactly on `L` — the right-hand rule that defines `bendAxis`
    // guarantees it. The interior angle this solves for is the angle
    // between `-U` and `L`, which is `180° - arccos(U·L)`, so rotating `-U`
    // to `L` about `bendAxis` sweeps `-(oldAngle)`, not `+oldAngle` — a
    // fixed, negative relationship to `bendAxis` that holds regardless of
    // how the chain is bent. Reaching a new interior angle of `newAngle`
    // by the same reasoning needs the swept angle to change from
    // `-oldAngle` to `-newAngle`, a delta of `oldAngle - newAngle` — and
    // only at the degenerate `oldAngle == 180°` boundary (`_twoBoneChain`'s
    // own straight rest pose, every existing test below) do `+` and `-`
    // that delta agree on magnitude, which is how the wrong sign passed
    // unnoticed until a bent starting pose (`anim-15`'s own project-level
    // reimplementation, checked against this function) exposed it.
    _rotateJointWorld(
      pose,
      mid,
      Quaternion.axisAngle(bendAxis, oldAngle - newAngle),
    );

    // Step 2: aim the root so the now-correctly-bent chain points at the
    // (clamped-distance, true-direction) target.
    world = pose.worldMatrices();
    final tipAfterBend = world[tip].getTranslation();
    final toTip = (tipAfterBend - rootPos).normalized();
    final toTarget = (target - rootPos).normalized();
    _rotateJointWorld(pose, root, Quaternion.fromTwoVectors(toTip, toTarget));

    // Step 3: twist the chain around the root-target axis so the middle
    // joint sits on the side the pole names — the only step [pole] enters
    // into, and the whole answer to "which of the two ways to bend".
    world = pose.worldMatrices();
    final midPosFinal = world[mid].getTranslation();
    final twistAxis = toTarget; // unchanged in direction by aiming the root
    final currentPoleDir = _perpendicularComponent(
      midPosFinal - rootPos,
      twistAxis,
    );
    final desiredPoleDir = _perpendicularComponent(pole - rootPos, twistAxis);
    if (currentPoleDir.length2 > epsilon && desiredPoleDir.length2 > epsilon) {
      final twistAngle = _signedAngle(
        currentPoleDir.normalized(),
        desiredPoleDir.normalized(),
        twistAxis,
      );
      _rotateJointWorld(
        pose,
        root,
        Quaternion.axisAngle(twistAxis, twistAngle),
      );
    }

    final finalTip = pose.worldMatrices()[tip].getTranslation();
    return (finalTip - target).length;
  }
}

/// FABRIK — Forward And Backward Reaching Inverse Kinematics — for a chain
/// of any length, `anim-14`'s other row.
///
/// Solves in *position* space (Aristidou & Lasenby's own algorithm: pin the
/// tip to the target and walk backward re-placing each joint at its fixed
/// distance from the next, then pin the root back where it started and walk
/// forward the same way, repeat), then turns the solved positions back into
/// *rotations* the one way [Pose] can hold them — one [Quaternion.fromTwoVectors]
/// per bone, from where it currently points to where the solve says it
/// should.
abstract final class FabrikIk {
  /// Bends the chain named by [joints] (root to tip, at least two entries)
  /// so its tip reaches [target] within [tolerance], stopping after
  /// [maxIterations] regardless — a target just out of reach never meets a
  /// tolerance, and this is what stops the solve from running forever
  /// chasing one.
  ///
  /// Returns how many iterations actually ran, `0` when the chain reached
  /// [target] before the loop needed to run, and up to [maxIterations] when
  /// it never met [tolerance].
  static int solve(
    Pose pose, {
    required List<int> joints,
    required Vector3 target,
    double tolerance = 1e-4,
    int maxIterations = 10,
  }) {
    if (joints.length < 2) {
      throw ArgumentError(
        'FABRIK needs at least two joints (one bone); got ${joints.length}.',
      );
    }

    final world = pose.worldMatrices();
    final rest = <Vector3>[for (final j in joints) world[j].getTranslation()];
    final lengths = <double>[
      for (var i = 0; i < joints.length - 1; i++)
        (rest[i + 1] - rest[i]).length,
    ];
    var totalLength = 0.0;
    for (final l in lengths) {
      totalLength += l;
    }
    final rootPos = rest.first;

    final positions = List<Vector3>.of(rest);
    var iterations = 0;

    if ((target - rootPos).length >= totalLength) {
      // Out of reach: the chain fully extends toward the target rather than
      // iterating toward a tolerance nothing this straight can meet.
      final direction = (target - rootPos).normalized();
      var at = rootPos;
      for (var i = 1; i < positions.length; i++) {
        at = at + direction * lengths[i - 1];
        positions[i] = at;
      }
    } else {
      for (; iterations < maxIterations; iterations++) {
        if ((positions.last - target).length <= tolerance) break;

        positions[positions.length - 1] = target;
        for (var i = positions.length - 2; i >= 0; i--) {
          final direction = (positions[i] - positions[i + 1]).normalized();
          positions[i] = positions[i + 1] + direction * lengths[i];
        }

        positions[0] = rootPos;
        for (var i = 1; i < positions.length; i++) {
          final direction = (positions[i] - positions[i - 1]).normalized();
          positions[i] = positions[i - 1] + direction * lengths[i - 1];
        }
      }
    }

    // Turned into rotations one bone at a time, root to tip, reading each
    // joint's *current* world direction fresh right before rotating it —
    // not the direction it had before the loop started, which its own
    // parent's rotation (set one step earlier, right here) has already
    // carried somewhere else.
    for (var i = 0; i < joints.length - 1; i++) {
      final fresh = pose.worldMatrices();
      final currentDir =
          (fresh[joints[i + 1]].getTranslation() -
                  fresh[joints[i]].getTranslation())
              .normalized();
      final newDir = (positions[i + 1] - positions[i]).normalized();
      if ((newDir - currentDir).length2 < 1e-12) continue;
      _rotateJointWorld(
        pose,
        joints[i],
        Quaternion.fromTwoVectors(currentDir, newDir),
      );
    }

    return iterations;
  }
}
