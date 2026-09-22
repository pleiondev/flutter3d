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

/// [v] turned [angle] radians about the unit vector [axis], right-hand rule.
///
/// **Through the rotation matrix, and never through `Quaternion.rotated`.**
/// `vector_math`'s own `Quaternion.rotate`/`rotated` turns a vector the
/// *opposite* way from the same quaternion's own `asRotationMatrix` —
/// `Quaternion.axisAngle(Vector3(0, 1, 0), pi / 2).rotated(Vector3(0, 0, 1))`
/// is `(-1, 0, 0)`, and `asRotationMatrix() * Vector3(0, 0, 1)` is
/// `(1, 0, 0)`. The matrix is the one that agrees with [worldTransformOf],
/// which composes through `Matrix4`, and with [_signedAngle], which reads
/// its sign out of a cross product. Mixing the two senses is a sign bug
/// that only shows up off-axis, which is exactly where nobody looks.
Vector3 _turnAbout(Vector3 axis, double angle, Vector3 v) =>
    Quaternion.axisAngle(axis, angle).asRotationMatrix().transformed(v);

/// The angle between two unit vectors, through `atan2` rather than `acos`.
///
/// **`acos` cannot measure a small angle.** Near a dot product of one its
/// slope is vertical, so `vector_math`'s `Float32List` storage — an epsilon
/// of about 6e-8 — comes back out as an angle of about 2.6e-4 radians for
/// two vectors that are the same vector. A look-at that hit its target
/// exactly would report a fifteenth of a degree of failure. The cross
/// product carries the same information conditioned the other way round,
/// and `atan2` of the two is accurate at both ends.
double _angleBetween(Vector3 a, Vector3 b) =>
    math.atan2(a.cross(b).length, a.dot(b));

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

/// [constraint] solved once: the joint's own new local rotation, and how
/// much of the turn its limits refused.
///
/// **[aimError] is the whole point of the limits being here.** A look-at
/// that silently stops short is a head that seems to be ignoring what it
/// was told to watch, and the caller has no way to tell that from a bug
/// in its own target. The angle between where the joint ends up facing
/// and where the target actually is says exactly how far the limits made
/// it fall short: zero when the target was inside them, and a number a
/// caller can act on — fade the gaze out, turn the chest as well — when it
/// was not.
///
/// The turn is the minimal rotation from the joint's own rest facing to
/// the clamped direction, so the joint gains no roll it did not already
/// have. A look-at that also twisted would need a second reference the
/// constraint does not carry, and a head that rolls while tracking looks
/// broken in a way a head that merely aims does not.
({Quaternion rotation, double aimError}) resolveLookAtConstraint({
  required ModelProject project,
  required LookAtConstraint constraint,
  ProjectClip? clip,
  double time = 0.0,
}) {
  final restLocal = _currentRotationOf(project, constraint.jointId, clip, time);
  final overrides = <int, Quaternion>{constraint.jointId: restLocal};

  final jointPos = worldTransformOf(
    project,
    constraint.jointId,
    rotationOverrides: overrides,
  ).getTranslation();

  // Every angle below is measured in the parent's space, which is what
  // makes the limits mean "away from rest" rather than "away from north".
  final parentId = project[constraint.jointId]?.parent;
  final parentRotation = parentId == null
      ? Matrix3.identity()
      : worldTransformOf(
          project,
          parentId,
          rotationOverrides: overrides,
        ).getRotation();

  final toTargetWorld = constraint.target - jointPos;
  if (toTargetWorld.length2 <= _epsilon) {
    // Nothing to aim at: a target sitting on the joint names no direction,
    // and turning to face it would be turning to face an arbitrary one.
    return (rotation: restLocal, aimError: 0.0);
  }
  // A rotation matrix's inverse is its transpose, which is the whole of
  // what "into the parent's frame" means here.
  final desired = parentRotation.transposed().transformed(
    toTargetWorld.normalized(),
  )..normalize();

  // The rest basis: where this joint faces, and which way is up, before
  // anything is asked of it.
  final rest = restLocal.asRotationMatrix();
  final restForward = rest.transformed(constraint.forward)..normalize();
  var restUp = _perpendicularComponent(
    rest.transformed(constraint.up),
    restForward,
  );
  restUp = restUp.length2 > _epsilon
      ? restUp.normalized()
      : _arbitraryPerpendicular(restForward);
  final restRight = restForward.cross(restUp)..normalize();

  // Yaw around up, pitch around right: the two angles a neck is specified
  // in, taken apart in that order and put back in the same one.
  final flat = _perpendicularComponent(desired, restUp);
  final yaw = flat.length2 > _epsilon
      ? _signedAngle(restForward, flat.normalized(), restUp)
      : 0.0;
  final pitch = math.asin(desired.dot(restUp).clamp(-1.0, 1.0));

  final clampedYaw = yaw.clamp(-constraint.maxYaw, constraint.maxYaw);
  final clampedPitch = pitch.clamp(-constraint.maxPitch, constraint.maxPitch);

  // Pitch first, then yaw about the rest up — the order the two angles are
  // quoted in, and the order that makes yaw mean "away from straight ahead"
  // rather than "away from wherever the pitch left it".
  final allowed = _turnAbout(
    restUp,
    clampedYaw,
    _turnAbout(restRight, clampedPitch, restForward),
  )..normalize();

  return (
    rotation: (Quaternion.fromTwoVectors(restForward, allowed) * restLocal)
      ..normalize(),
    aimError: _angleBetween(allowed, desired),
  );
}

/// [clip], with [constraint]'s own joint's rotation track replaced by
/// [resolveLookAtConstraint]'s own output, sampled every `1/[fps]` seconds
/// — the look-at's own [bakeIk], and for the same reason: nothing plays a
/// live [LookAtConstraint] back, so what leaves in a file has to be
/// ordinary keyframes.
ProjectClip bakeLookAt({
  required ModelProject project,
  required ProjectClip clip,
  required LookAtConstraint constraint,
  required double fps,
}) {
  if (fps <= 0) {
    throw ArgumentError.value(fps, 'fps', 'must be positive');
  }

  final table = KeyTable(componentCount: 4);
  for (var frame = 0; frame < _frameCount(clip, fps); frame++) {
    final time = frame / fps;
    final solved = resolveLookAtConstraint(
      project: project,
      constraint: constraint,
      clip: clip,
      time: time,
    );
    table.setKey(time, <double>[
      solved.rotation.x,
      solved.rotation.y,
      solved.rotation.z,
      solved.rotation.w,
    ]);
  }

  return ProjectClip(
    name: clip.name,
    tracks: <ProjectTrack>[
      for (final track in clip.tracks)
        if (track.objectId != constraint.jointId) track,
      ProjectTrack(
        objectId: constraint.jointId,
        track: table.toAnimationTrack(
          nodeIndex: 0,
          path: AnimationPath.rotation,
        ),
      ),
    ],
    extras: clip.extras,
  );
}

/// How many frames at [fps] cover [clip]'s own longest track, never fewer
/// than one — a clip with nothing in it still has a pose at time zero.
int _frameCount(ProjectClip clip, double fps) {
  var duration = 0.0;
  for (final track in clip.tracks) {
    final times = track.track.times;
    if (times.isNotEmpty) duration = math.max(duration, times.last);
  }
  return math.max(1, (duration * fps).round() + 1);
}

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

  final frameCount = _frameCount(clip, fps);

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
