/// `anim-31n`'s other half: a look-at with angle constraints, and the bake.
///
///     dart test test/look_at_constraint_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelObject _joint(
  int id, {
  int? parent,
  required Vector3 localOffset,
  Quaternion? rotation,
}) => ModelObject(
  id: id,
  name: 'joint$id',
  geometry: const SocketGeometry(),
  transform: rotation == null
      ? Matrix4.translation(localOffset)
      : (Matrix4.compose(localOffset, rotation, Vector3.all(1.0))),
  parent: parent,
);

/// A chest at the origin with a head one unit above it, both facing +Z.
ModelProject _chestAndHead({Quaternion? chestRotation}) => ModelProject(
  objects: <ModelObject>[
    _joint(1, localOffset: Vector3.zero(), rotation: chestRotation),
    _joint(2, parent: 1, localOffset: Vector3(0, 1, 0)),
  ],
);

/// Where joint 2's own face points in world space, given [rotation] as its
/// local rotation.
Vector3 _facing(ModelProject project, Quaternion rotation) => worldTransformOf(
  project,
  2,
  rotationOverrides: <int, Quaternion>{2: rotation},
).getRotation().transformed(Vector3(0, 0, 1))..normalize();

/// The angle between two directions, in degrees — through `atan2`, for the
/// reason `ik_constraint.dart`'s own `_angleBetween` gives: `acos` of two
/// `Float32List` vectors that are the same vector reports a fiftieth of a
/// degree, and a check for "faces it exactly" written on `acos` would be a
/// check for "faces it to within the arithmetic's own noise floor".
double _degreesBetween(Vector3 a, Vector3 b) {
  final x = a.normalized();
  final y = b.normalized();
  return degrees(math.atan2(x.cross(y).length, x.dot(y)));
}

LookAtConstraint _lookAt(
  Vector3 target, {
  double maxYaw = math.pi,
  double maxPitch = math.pi,
}) => LookAtConstraint(
  jointId: 2,
  target: target,
  forward: Vector3(0, 0, 1),
  up: Vector3(0, 1, 0),
  maxYaw: maxYaw,
  maxPitch: maxPitch,
);

void main() {
  group('resolveLookAtConstraint', () {
    test('with no limits, the joint faces the target exactly', () {
      final project = _chestAndHead();
      final solved = resolveLookAtConstraint(
        project: project,
        constraint: _lookAt(Vector3(3, 1, 3)),
      );

      expect(solved.aimError, lessThan(1e-5));
      expect(
        _degreesBetween(
          _facing(project, solved.rotation),
          Vector3(3, 0, 3), // the head sits at y = 1, so the target is level
        ),
        lessThan(0.01),
      );
    });

    test('a target behind the joint is refused by a sixty-degree limit', () {
      final project = _chestAndHead();
      final solved = resolveLookAtConstraint(
        project: project,
        constraint: _lookAt(Vector3(0, 1, -5), maxYaw: radians(60)),
      );

      // Sixty degrees is as far as it goes, and the remaining hundred and
      // twenty are reported rather than swallowed.
      expect(
        _degreesBetween(_facing(project, solved.rotation), Vector3(0, 0, 1)),
        closeTo(60, 0.01),
      );
      expect(degrees(solved.aimError), closeTo(120, 0.01));
    });

    test('yaw and pitch are limited separately', () {
      final project = _chestAndHead();
      // A target forty-five degrees off in each: a direction at that yaw
      // and that pitch is `(cos45·sin45, sin45, cos45·cos45)`, which is
      // `(0.5, 0.707, 0.5)` — not `(1, 1, 1)`, whose pitch is 35.26°.
      // Against a limit of thirty on yaw and none on pitch, the yaw is cut
      // and the pitch is not.
      final solved = resolveLookAtConstraint(
        project: project,
        constraint: _lookAt(Vector3(1, 1 + math.sqrt2, 1), maxYaw: radians(30)),
      );

      final facing = _facing(project, solved.rotation);
      final flat = Vector3(facing.x, 0, facing.z).normalized();
      expect(
        _degreesBetween(flat, Vector3(0, 0, 1)),
        closeTo(30, 0.01),
        reason: 'the yaw limit should bite',
      );
      expect(
        degrees(math.asin(facing.y.clamp(-1.0, 1.0))),
        closeTo(45, 0.01),
        reason: 'and the pitch should not, since nothing limited it',
      );
    });

    test('the limits are measured from rest, so they turn with the parent', () {
      // The same target, twice: once with the chest facing +Z, once with
      // the chest turned ninety degrees to face +X. A limit measured
      // against the world would refuse one and allow the other; a limit
      // measured against rest treats them identically.
      final facingZ = _chestAndHead();
      final turned = _chestAndHead(
        chestRotation: Quaternion.axisAngle(Vector3(0, 1, 0), radians(90)),
      );

      final straight = resolveLookAtConstraint(
        project: facingZ,
        constraint: _lookAt(Vector3(1, 1, 1), maxYaw: radians(30)),
      );
      // (1, 1, 1) is forty-five degrees off +Z; (1, 1, -1) is forty-five
      // degrees off +X the same way round.
      final rotated = resolveLookAtConstraint(
        project: turned,
        constraint: _lookAt(Vector3(1, 1, -1), maxYaw: radians(30)),
      );

      expect(
        degrees(rotated.aimError),
        closeTo(degrees(straight.aimError), 0.01),
      );
      expect(degrees(straight.aimError), closeTo(15, 0.01));
    });

    test('a target sitting on the joint leaves it where it was', () {
      final project = _chestAndHead();
      final solved = resolveLookAtConstraint(
        project: project,
        constraint: _lookAt(Vector3(0, 1, 0)),
      );

      expect(solved.aimError, 0.0);
      expect(
        _degreesBetween(_facing(project, solved.rotation), Vector3(0, 0, 1)),
        lessThan(0.01),
      );
    });

    test('the turn adds no roll of its own', () {
      final project = _chestAndHead();
      final solved = resolveLookAtConstraint(
        project: project,
        constraint: _lookAt(Vector3(5, 1, 0)),
      );

      // Aiming ninety degrees to the right around the up axis should leave
      // the top of the head where it was. A solve that twisted would tip it.
      final world = worldTransformOf(
        project,
        2,
        rotationOverrides: <int, Quaternion>{2: solved.rotation},
      ).getRotation();
      expect(
        _degreesBetween(world.transformed(Vector3(0, 1, 0)), Vector3(0, 1, 0)),
        lessThan(0.01),
      );
    });

    test('a swept target moves the gaze continuously', () {
      // The same "doesn't jitter" check `ik_constraint_test.dart` makes of
      // the two-bone solve, across the angle where a limit starts biting:
      // the clamp must round the corner rather than jump at it.
      final project = _chestAndHead();
      Vector3? previous;
      var largestStep = 0.0;
      for (var degree = 0; degree <= 120; degree += 2) {
        final angle = radians(degree.toDouble());
        final solved = resolveLookAtConstraint(
          project: project,
          // Level with the head and five units out, so only the yaw moves.
          constraint: _lookAt(
            Vector3(5 * math.sin(angle), 1, 5 * math.cos(angle)),
            maxYaw: radians(60),
          ),
        );
        final facing = _facing(project, solved.rotation);
        if (previous != null) {
          largestStep = math.max(
            largestStep,
            _degreesBetween(previous, facing),
          );
        }
        previous = facing;
      }
      // Two degrees of target per step, so two degrees of gaze at most —
      // and zero once the limit bites. A clamp that jumped at the boundary
      // would show up here as a step the size of the overshoot.
      expect(largestStep, lessThan(2.5));
    });
  });

  group('bakeLookAt', () {
    ProjectClip clipOfLength(double seconds) {
      final table = KeyTable(componentCount: 4);
      table.setKey(0.0, <double>[0, 0, 0, 1]);
      table.setKey(seconds, <double>[0, 0, 0, 1]);
      return ProjectClip(
        name: 'idle',
        tracks: <ProjectTrack>[
          ProjectTrack(
            objectId: 2,
            track: table.toAnimationTrack(
              nodeIndex: 0,
              path: AnimationPath.rotation,
            ),
          ),
        ],
      );
    }

    test('replaces the joint\'s own rotation track with keyed frames', () {
      final project = _chestAndHead();
      final baked = bakeLookAt(
        project: project,
        clip: clipOfLength(1.0),
        constraint: _lookAt(Vector3(5, 1, 0)),
        fps: 10,
      );

      expect(baked.tracks, hasLength(1));
      final track = baked.tracks.single;
      expect(track.objectId, 2);
      expect(track.track.path, AnimationPath.rotation);
      expect(track.track.times, hasLength(11));
    });

    test('an fps of zero is refused rather than looping forever', () {
      expect(
        () => bakeLookAt(
          project: _chestAndHead(),
          clip: clipOfLength(1.0),
          constraint: _lookAt(Vector3(5, 1, 0)),
          fps: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
