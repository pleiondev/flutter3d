/// A ragdoll in the core — N1: a capsule a bone, a joint where each bone
/// meets its parent, built from bones in world space and knowing nothing of
/// a scene.
///
/// ## Built at rest, put where the pose is
///
/// A joint's limits are taken from how its bodies stand when it is made: a
/// cone of half a radian about the axis they had then, a twist of ±0.4 from
/// the turn they had then. Made where an animation happened to leave a body
/// — a monster struck mid-stride, its knee bent — the limits would be
/// centred on that stride. So the bodies are made in the skeleton's rest
/// pose, joined there, and only then moved to where the animation has them,
/// with the velocities it gave them: the limits are a body's, the starting
/// pose and momentum the moment's.
///
/// A bone's frame and its capsule differ — a capsule lies along y from the
/// bone's head to its tail, the bone's own axes are whatever the rig chose —
/// so each bone keeps the offset between the two, taken at rest, and is read
/// back as its body times that offset.
library;

import 'package:vector_math/vector_math.dart';

import 'native_dynamics.dart';
import 'native_world.dart';

/// How a bone is held to its parent.
sealed class RagdollJoint {
  const RagdollJoint();
}

/// A ball: its swing within [cone] radians of the bone's direction at rest,
/// its twist about it within [twistLower]..[twistUpper]. A hip, a shoulder,
/// the spine, the neck.
final class RagdollBall extends RagdollJoint {
  const RagdollBall({
    required this.cone,
    required this.twistLower,
    required this.twistUpper,
  });

  final double cone, twistLower, twistUpper;
}

/// A hinge about [axis], in the bone's own frame, from [lower] to [upper]
/// radians from rest. A knee, an elbow.
final class RagdollHinge extends RagdollJoint {
  const RagdollHinge({
    required this.axis,
    required this.lower,
    required this.upper,
  });

  final Vector3 axis;
  final double lower, upper;
}

/// One bone, in world space: where it starts ([head], the joint with its
/// parent) and ends ([tail], where its capsule stops), its frame, how thick
/// and heavy it is, and how it is held. [parent] is an index into the list
/// the ragdoll is built from, earlier than this one, or -1 for the root.
final class RagdollBone {
  const RagdollBone({
    required this.name,
    required this.parent,
    required this.head,
    required this.tail,
    required this.orientation,
    required this.radius,
    required this.mass,
    this.joint,
  });

  final String name;
  final int parent;
  final Vector3 head, tail;
  final Quaternion orientation;
  final double radius, mass;

  /// How it is held to its parent; null for the root, which has none.
  final RagdollJoint? joint;
}

/// A bone's pose in world space: where its frame is and how it is turned.
typedef BonePose = ({Vector3 position, Quaternion orientation});

final class NativeRagdoll {
  /// Made in [world] from [rest], the bones at rest, then moved to [pose],
  /// one pose a bone, moving as [velocity] and [spin] say when they are
  /// given. Every joint resists turning with [friction] N m, or the ragdoll
  /// never comes to rest. When the world is a [NativeDynamics]', [dynamics]
  /// keeps these bodies through its restores.
  NativeRagdoll(
    this.world,
    List<RagdollBone> rest, {
    List<BonePose>? pose,
    List<Vector3>? velocity,
    List<Vector3>? spin,
    double friction = 2.0,
    NativeDynamics? dynamics,
  }) : bones = List<RagdollBone>.unmodifiable(rest),
       _dynamics = dynamics {
    for (var i = 0; i < rest.length; i++) {
      final bone = rest[i];
      if (bone.parent >= i) {
        throw ArgumentError.value(
          bone.parent,
          'rest[$i].parent',
          'not an earlier bone',
        );
      }
      final along = bone.tail - bone.head;
      final length = along.length;
      final turn = _alongY(along);
      final centre = (bone.head + bone.tail) * 0.5;
      final body = world.addBody(position: centre, mass: bone.mass);
      world
        ..setShape(
          body,
          NativeShape.capsule(
            bone.radius,
            (length * 0.5 - bone.radius).clamp(0.01, double.infinity),
          ),
        )
        ..setOrientation(body, turn);
      _bodies.add(body);
      // The bone's frame from the body's: inverse(body) · bone.
      final inverse = turn.conjugated();
      _offsetTurn.add(inverse * bone.orientation);
      _offsetAt.add(turnBy(inverse, bone.head - centre));
      dynamics?.keep(body);
    }
    for (var i = 0; i < rest.length; i++) {
      final bone = rest[i];
      if (bone.parent < 0) continue;
      final a = _bodies[bone.parent], b = _bodies[i];
      final direction = (bone.tail - bone.head).normalized();
      final NativeJoint joint;
      switch (bone.joint) {
        case RagdollHinge(:final axis, :final lower, :final upper):
          joint = world.createJoint(
            NativeJointType.revolute,
            a,
            b,
            anchor: bone.head,
            axis: turnBy(bone.orientation, axis),
          );
          world
            ..setJointLimits(joint, (lower: lower, upper: upper))
            ..setJointMotor(joint, (speed: 0.0, maxForce: friction));
        case RagdollBall(:final cone, :final twistLower, :final twistUpper):
          joint = world.createJoint(
            NativeJointType.spherical,
            a,
            b,
            anchor: bone.head,
            axis: direction,
          );
          world
            ..setJointCone(joint, cone)
            ..setJointLimits(joint, (lower: twistLower, upper: twistUpper))
            ..setJointFriction(joint, friction);
        case null:
          joint = world.createJoint(
            NativeJointType.fixed,
            a,
            b,
            anchor: bone.head,
          );
      }
      _joints.add(joint);
    }
    if (pose != null) place(pose, velocity: velocity, spin: spin);
  }

  final NativeWorld world;
  final List<RagdollBone> bones;
  final NativeDynamics? _dynamics;
  final List<NativeBody> _bodies = <NativeBody>[];
  final List<NativeJoint> _joints = <NativeJoint>[];
  final List<Quaternion> _offsetTurn = <Quaternion>[];
  final List<Vector3> _offsetAt = <Vector3>[];

  /// The core's body for bone [index]: to strike it, or to read its contacts.
  NativeBody bodyOf(int index) => _bodies[index];

  /// Puts every bone at [pose] — a pose a bone, in world space — moving at
  /// [velocity] and turning at [spin] where they are given, nought where not.
  void place(
    List<BonePose> pose, {
    List<Vector3>? velocity,
    List<Vector3>? spin,
  }) {
    for (var i = 0; i < _bodies.length; i++) {
      // body = bone · inverse(offset).
      final turn = pose[i].orientation * _offsetTurn[i].conjugated();
      final at = pose[i].position - turnBy(turn, _offsetAt[i]);
      world
        ..setOrientation(_bodies[i], turn)
        ..setPosition(_bodies[i], at)
        ..setVelocity(_bodies[i], velocity?[i] ?? Vector3.zero())
        ..setAngularVelocity(_bodies[i], spin?[i] ?? Vector3.zero());
    }
  }

  /// Where bone [index] is now, as its body has it.
  BonePose poseOf(int index) {
    final turn = world.orientationOf(_bodies[index]);
    return (
      position:
          world.positionOf(_bodies[index]) + turnBy(turn, _offsetAt[index]),
      orientation: turn * _offsetTurn[index],
    );
  }

  /// Whether every bone has come to rest.
  bool get isAsleep => _bodies.every(world.isAsleep);

  /// Takes the ragdoll out of the world.
  void dispose() {
    for (final joint in _joints) {
      world.removeJoint(joint);
    }
    for (final body in _bodies) {
      world.removeBody(body);
      _dynamics?.release(body);
    }
    _joints.clear();
    _bodies.clear();
  }
}

/// The turn that takes the y axis to [along].
Quaternion _alongY(Vector3 along) {
  final to = along.normalized();
  final up = Vector3(0.0, 1.0, 0.0);
  final dot = up.dot(to);
  if (dot > 1.0 - 1e-9) {
    return Quaternion.identity();
  }
  if (dot < -1.0 + 1e-9) {
    return Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), 3.141592653589793);
  }
  return Quaternion.fromTwoVectors(up, to);
}

/// [v] turned by [q], as the core turns a body by its orientation.
///
/// Not `Quaternion.rotated`, which in vector_math turns by the inverse —
/// the opposite of `asRotationMatrix`, which is what the core and
/// flutter3d_physics both mean by an orientation. A ragdoll placed with it
/// had every body turned one way and moved the other, and flew apart on
/// its first step.
Vector3 turnBy(Quaternion q, Vector3 v) =>
    q.asRotationMatrix().transform(v.clone());
