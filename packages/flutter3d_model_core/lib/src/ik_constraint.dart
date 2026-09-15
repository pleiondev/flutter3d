/// Solving and baking [IkConstraint] — `anim-15`'s own row, the project-side
/// half of the two-bone solve `anim-14`'s `TwoBoneIk` already does live in
/// the engine.
///
/// **The same package boundary `anim-20`'s `ShapeDriver` already crossed.**
/// `TwoBoneIk.solve` (`packages/flutter3d/lib/src/engine/animation/
/// inverse_kinematics.dart`) works over a live `Pose`, a windowed-engine
/// type this plain Dart package cannot depend on. What is built here is the
/// same three-step law-of-cosines algorithm — bend the middle joint to the
/// desired interior angle, aim the root at the target, twist around the
/// root-target axis so the middle joint lands on [IkConstraint.pole]'s side
/// — reimplemented over [worldTransformOf] and a clip's own rotation
/// tracks instead of a `Pose`. A chain's own bone lengths never change with
/// rotation, so [worldTransformOf] without any override already gives the
/// right answer for those; only the *current bend* — which plane the
/// middle joint is already folded in, needed so a chain mid-animation keeps
/// bending the same way rather than snapping into whichever plane the pole
/// alone would pick — needs the animated rotations, supplied here through
/// [worldTransformOf]'s own `rotationOverrides`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:vector_math/vector_math.dart';

import 'key_table.dart';
import 'project.dart';
import 'project_animation.dart';
import 'world_transform.dart';

/// The rotation [clip] gives joint [jointId] at [time], or `null` when no
/// rotation track in [clip] names that joint — the same shape
/// `shape_driver.dart`'s own `_jointRotationAt` reads, duplicated rather
/// than shared across the two files: ten lines is cheaper than a coupling
/// between two otherwise-unrelated rows.
Quaternion? _animatedRotationAt(ProjectClip? clip, int jointId, double time) {
  if (clip == null) return null;
  for (final projectTrack in clip.tracks) {
    if (projectTrack.objectId != jointId) continue;
    final track = projectTrack.track;
    if (track.path != AnimationPath.rotation) continue;
    final out = Float32List(4);
    track.sample(time, out);
    return Quaternion(out[0], out[1], out[2], out[3]);
  }
  return null;
}

/// [jointId]'s own local rotation, straight out of [ModelObject.transform]
/// — what an untracked joint's rotation actually is, rather than identity:
/// a joint nothing animates keeps whatever orientation its own transform
/// already gives it, and reading that as identity would bend a chain from
/// the wrong starting shape.
Quaternion _restRotationOf(ModelProject project, int jointId) {
  final translation = Vector3.zero();
  final rotation = Quaternion.identity();
  final scale = Vector3.zero();
  project[jointId]?.transform.decompose(translation, rotation, scale);
  return rotation;
}

/// [jointId]'s own current local rotation: [clip] at [time] when it
/// animates this joint, [jointId]'s own rest rotation otherwise.
Quaternion _currentRotationOf(
  ModelProject project,
  int jointId,
  ProjectClip? clip,
  double time,
) =>
    _animatedRotationAt(clip, jointId, time) ??
    _restRotationOf(project, jointId);

Quaternion _worldRotation(
  ModelProject project,
  int id,
  Map<int, Quaternion> overrides,
) => Quaternion.fromRotation(
  worldTransformOf(project, id, rotationOverrides: overrides).getRotation(),
);

/// The local rotation [id] needs so its *world* rotation becomes
/// [newWorldRotation], given [id]'s own parent (whatever [overrides] says
/// for it, or [project]'s own rest rotation when [overrides] does not name
/// it) — the same conversion `inverse_kinematics.dart`'s own
/// `_rotateJointWorld` makes through `Pose.parents`, made here through
/// [ModelObject.parent] instead.
Quaternion _newLocalRotation(
  ModelProject project,
  int id,
  Map<int, Quaternion> overrides,
  Quaternion newWorldRotation,
) {
  final parentId = project[id]?.parent;
  final parentWorldRotation = parentId == null
      ? Quaternion.identity()
      : _worldRotation(project, parentId, overrides);
  return (parentWorldRotation.inverted() * newWorldRotation)..normalize();
}

/// The interior angle opposite a side of length [opposite] in a triangle
/// whose other two sides are [a] and [b] — the law of cosines solved for
/// the angle, zero rather than `NaN` when either other side is degenerate.
double _triangleAngle(double opposite, double a, double b) {
  if (a <= 0.0 || b <= 0.0) return 0.0;
  final cos = ((a * a + b * b - opposite * opposite) / (2.0 * a * b)).clamp(
    -1.0,
    1.0,
  );
  return math.acos(cos);
}

/// Any unit vector perpendicular to [v] — used only when [v] is degenerate
/// for the purpose that wanted a bend axis.
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
/// perpendicular to unit vector [axis] — positive when the shortest
/// rotation from [a] to [b] follows the right-hand rule around [axis].
double _signedAngle(Vector3 a, Vector3 b, Vector3 axis) {
  final unsigned = math.acos(a.dot(b).clamp(-1.0, 1.0));
  final sign = a.cross(b).dot(axis) < 0.0 ? -1.0 : 1.0;
  return unsigned * sign;
}

const double _epsilon = 1e-6;

/// [constraint] solved once, given [currentRoot] and [currentMid] as the
/// chain's own rotations before the solve — the corrected pair after it,
/// and how far the effector still sits from [IkConstraint.target] once
/// they are applied (zero within floating-point error whenever the target
/// was within the chain's own reach).
({Quaternion root, Quaternion mid, double reachError}) _solveTwoBoneIk({
  required ModelProject project,
  required IkConstraint constraint,
  required Quaternion currentRoot,
  required Quaternion currentMid,
}) {
  final overrides = <int, Quaternion>{
    constraint.rootJointId: currentRoot,
    constraint.midJointId: currentMid,
  };

  final rootPos = worldTransformOf(
    project,
    constraint.rootJointId,
    rotationOverrides: overrides,
  ).getTranslation();
  var midPos = worldTransformOf(
    project,
    constraint.midJointId,
    rotationOverrides: overrides,
  ).getTranslation();
  var tipPos = worldTransformOf(
    project,
    constraint.effectorJointId,
    rotationOverrides: overrides,
  ).getTranslation();

  final upperLength = (midPos - rootPos).length;
  final lowerLength = (tipPos - midPos).length;
  final minReach = math.max((upperLength - lowerLength).abs(), _epsilon);
  final maxReach = math.max(upperLength + lowerLength - _epsilon, minReach);

  final rawDist = (constraint.target - rootPos).length;
  final targetDist = math.min(math.max(rawDist, minReach), maxReach);

  final currentTipDist = (tipPos - rootPos).length;
  final oldAngle = _triangleAngle(currentTipDist, upperLength, lowerLength);
  final newAngle = _triangleAngle(targetDist, upperLength, lowerLength);

  // The plane the chain is already bent in, so a chain mid-animation bends
  // further the same way rather than snapping to whatever plane the pole
  // alone would pick.
  var bendAxis = (midPos - rootPos).cross(tipPos - midPos);
  bendAxis = bendAxis.length2 > _epsilon
      ? bendAxis.normalized()
      : _arbitraryPerpendicular(midPos - rootPos);

  // Step 1: bend the middle joint to the desired interior angle.
  //
  // `oldAngle - newAngle`, not `newAngle - oldAngle` — a real sign bug this
  // row found in `TwoBoneIk.solve` itself (`inverse_kinematics.dart`, fixed
  // alongside this), invisible there because every existing test started
  // from a perfectly straight chain, the one starting angle where the two
  // signs happen to agree. See that file's own comment on its matching line
  // for the derivation: rotating `midPos - rootPos` onto `tipPos - midPos`
  // about `bendAxis` always sweeps `+oldAngle`, never `-oldAngle`, so
  // reaching the *interior* angle (measured from the reversed first vector)
  // needs the swept angle to move from `-oldAngle` to `-newAngle`.
  final worldMidBefore = _worldRotation(
    project,
    constraint.midJointId,
    overrides,
  );
  final newWorldMid =
      (Quaternion.axisAngle(bendAxis, oldAngle - newAngle) * worldMidBefore)
        ..normalize();
  overrides[constraint.midJointId] = _newLocalRotation(
    project,
    constraint.midJointId,
    overrides,
    newWorldMid,
  );

  tipPos = worldTransformOf(
    project,
    constraint.effectorJointId,
    rotationOverrides: overrides,
  ).getTranslation();

  // Step 2: aim the root so the now-correctly-bent chain points at the
  // (clamped-distance, true-direction) target.
  final toTip = (tipPos - rootPos).normalized();
  final toTarget = (constraint.target - rootPos).normalized();
  final worldRootBefore = _worldRotation(
    project,
    constraint.rootJointId,
    overrides,
  );
  var newWorldRoot =
      (Quaternion.fromTwoVectors(toTip, toTarget) * worldRootBefore)
        ..normalize();
  overrides[constraint.rootJointId] = _newLocalRotation(
    project,
    constraint.rootJointId,
    overrides,
    newWorldRoot,
  );

  midPos = worldTransformOf(
    project,
    constraint.midJointId,
    rotationOverrides: overrides,
  ).getTranslation();

  // Step 3: twist the chain around the root-target axis so the middle
  // joint sits on the side the pole names.
  final twistAxis = toTarget;
  final currentPoleDir = _perpendicularComponent(midPos - rootPos, twistAxis);
  final desiredPoleDir = _perpendicularComponent(
    constraint.pole - rootPos,
    twistAxis,
  );
  if (currentPoleDir.length2 > _epsilon && desiredPoleDir.length2 > _epsilon) {
    final twistAngle = _signedAngle(
      currentPoleDir.normalized(),
      desiredPoleDir.normalized(),
      twistAxis,
    );
    newWorldRoot = (Quaternion.axisAngle(twistAxis, twistAngle) * newWorldRoot)
      ..normalize();
    overrides[constraint.rootJointId] = _newLocalRotation(
      project,
      constraint.rootJointId,
      overrides,
      newWorldRoot,
    );
  }

  final finalTip = worldTransformOf(
    project,
    constraint.effectorJointId,
    rotationOverrides: overrides,
  ).getTranslation();

  return (
    root: overrides[constraint.rootJointId]!,
    mid: overrides[constraint.midJointId]!,
    reachError: (finalTip - constraint.target).length,
  );
}

/// [constraint], solved against [project]'s own rest transforms and
/// whichever rotations [clip] gives its root and middle joints at [time] —
/// "applied after FK": the pre-solve rotations (from [clip] when it
/// animates them, [project]'s own rest pose otherwise) seed which way the
/// chain is already bent, exactly the reasoning `TwoBoneIk.solve`'s own doc
/// comment gives for reading a live `Pose` instead of constructing a bend
/// plane from the pole alone.
({Quaternion root, Quaternion mid, double reachError}) resolveIkConstraint({
  required ModelProject project,
  required IkConstraint constraint,
  ProjectClip? clip,
  double time = 0.0,
}) => _solveTwoBoneIk(
  project: project,
  constraint: constraint,
  currentRoot: _currentRotationOf(project, constraint.rootJointId, clip, time),
  currentMid: _currentRotationOf(project, constraint.midJointId, clip, time),
);

/// [clip], with [constraint]'s own root and middle joints' rotation tracks
/// replaced by [resolveIkConstraint]'s own output, sampled every `1/[fps]`
/// seconds from zero through [clip]'s own duration — `BakeIk(clip, fps)`'s
/// own row. "Export always bakes" because nothing plays a live
/// `IkConstraint` back: the two tracks this writes are ordinary rotation
/// keyframes, sampled and read exactly like any other joint's, needing no
/// [IkConstraint] or [worldTransformOf] call ever again.
ProjectClip bakeIk({
  required ModelProject project,
  required ProjectClip clip,
  required IkConstraint constraint,
  required double fps,
}) {
  if (fps <= 0) {
    throw ArgumentError.value(fps, 'fps', 'must be positive');
  }

  var duration = 0.0;
  for (final track in clip.tracks) {
    final times = track.track.times;
    if (times.isNotEmpty) duration = math.max(duration, times.last);
  }
  final frameCount = math.max(1, (duration * fps).round() + 1);

  final rootTable = KeyTable(componentCount: 4);
  final midTable = KeyTable(componentCount: 4);
  for (var frame = 0; frame < frameCount; frame++) {
    final time = frame / fps;
    final solved = resolveIkConstraint(
      project: project,
      constraint: constraint,
      clip: clip,
      time: time,
    );
    rootTable.setKey(time, <double>[
      solved.root.x,
      solved.root.y,
      solved.root.z,
      solved.root.w,
    ]);
    midTable.setKey(time, <double>[
      solved.mid.x,
      solved.mid.y,
      solved.mid.z,
      solved.mid.w,
    ]);
  }

  return ProjectClip(
    name: clip.name,
    tracks: <ProjectTrack>[
      for (final track in clip.tracks)
        if (track.objectId != constraint.rootJointId &&
            track.objectId != constraint.midJointId)
          track,
      ProjectTrack(
        objectId: constraint.rootJointId,
        track: rootTable.toAnimationTrack(
          nodeIndex: 0,
          path: AnimationPath.rotation,
        ),
      ),
      ProjectTrack(
        objectId: constraint.midJointId,
        track: midTable.toAnimationTrack(
          nodeIndex: 0,
          path: AnimationPath.rotation,
        ),
      ),
    ],
    extras: clip.extras,
  );
}
