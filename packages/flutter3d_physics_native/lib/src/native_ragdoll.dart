/// A ragdoll in the core — N1: a capsule a bone, a joint where each bone
/// meets its parent, built from bones in world space and knowing nothing of
/// a scene.
///
/// ## Built at rest, put where the pose is
///
/// A joint's limits are taken from how its bodies stand when it is made: a
/// cone about the axis they had then, a twist from the turn they had then,
/// and a [RagdollSwing]'s range from the anatomical position, read against
/// the skeleton's forward and up as they stand at rest. Made where an
/// animation happened to leave a body — a monster struck mid-stride, its
/// knee bent — the limits would be centred on that stride. So the bodies
/// are made in the skeleton's rest pose, joined there, and only then moved
/// to where the animation has them, with the velocities it gave them: the
/// limits are a body's, the starting pose and momentum the moment's.
///
/// ## Tissue, not friction
///
/// What brings a limp body to rest is its joints' tissue ([JointTissue]):
/// viscous damping, a torque in proportion to how fast a joint turns, and
/// soft limits, which give a little past the end of a joint's range rather
/// than stopping it dead. A fixed friction torque held a limb wherever it
/// was slow enough, and a body that came down on its arms stayed propped on
/// them.
///
/// A bone's frame and its capsule differ — a capsule lies along y from the
/// bone's head to its tail, the bone's own axes are whatever the rig chose —
/// so each bone keeps the offset between the two, taken at rest, and is read
/// back as its body times that offset.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_matter/flutter3d_matter.dart'
    show Confidence, ConstantLaw, InelasticProperties;
import 'package:vector_math/vector_math.dart';

import 'native_dynamics.dart';
import 'native_world.dart';

/// How a bone is held to its parent.
abstract final class RagdollJoint {
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

/// A ball held to a joint's range of motion: from the anatomical position,
/// the bone swings forward ([flexion]) and back ([extension]) along the
/// skeleton's forward, out from the body's midline ([lateral]) and in
/// towards it ([medial]), with an ellipse through the four between them, and
/// twists by at most [twist] either way from how it stood at rest. Radians,
/// each above nought and below 3: the core measures a swing short of a half
/// turn. The spine, the neck, a shoulder, a hip.
///
/// **Measured from the anatomical position, not the rest pose.** A bone that
/// [hangs] — an arm, a leg — swings from the skeleton's down; one that does
/// not — the spine, the neck — from its up. A rig bound in a T-pose has its
/// arms out at a right angle to that, a quarter of the way through their
/// abduction, and they are limited as an arm, not as a T. A bone on the
/// midline, the spine and the neck, bends the same way to either side, and
/// takes [lateral] for both.
///
/// Forward means the bone's far end moves ahead: a thigh lifted, an arm
/// raised in front, a spine bent over. A knee bends the other way, and is a
/// [RagdollBend].
final class RagdollSwing extends RagdollJoint {
  const RagdollSwing({
    required this.flexion,
    required this.extension,
    required this.lateral,
    double? medial,
    required this.twist,
    this.hangs = false,
  }) : medial = medial ?? lateral;

  final double flexion, extension, lateral, medial, twist;

  /// Whether the bone hangs from its joint in the anatomical position, as a
  /// limb does, rather than standing on it, as the spine does.
  final bool hangs;
}

/// What a ragdoll's joints are made of: what damps their turning and what
/// holds them at the end of their range — in place of a friction torque.
///
/// - [damping]: viscous, N·m·s/rad, the passive damping of a relaxed joint;
/// - [limitStiffness]: N·m/rad, how a joint gives past the end of its
///   range; nought for limits as hard as the core holds a joint;
/// - [inelastic]: the tissue's inelastic group, whose loss factor η makes
///   the damping ratio of that give, η/2.
final class JointTissue {
  const JointTissue({
    required this.damping,
    required this.limitStiffness,
    required this.inelastic,
  });

  /// N·m·s/rad.
  final double damping;

  /// N·m/rad.
  final double limitStiffness;

  /// Where [limitRatio] comes from.
  final InelasticProperties inelastic;

  /// The damping ratio of a joint's give past its range: half the tissue's
  /// loss factor, nought where it has none.
  double get limitRatio => (inelastic.lossFactor?.value ?? 0.0) * 0.5;

  /// A relaxed adult's joints.
  ///
  /// - **Damping 1.0 N·m·s/rad**: the passive damping of the knee in
  ///   flexion from pendulum drops, b ≈ 1.0 N·m·s/rad (Riener and Fuhr,
  ///   "Patient-driven control of FES-supported standing up: a simulation
  ///   study", IEEE Trans. Rehabil. Eng. 6, 1998, as quoted in US patent
  ///   8,108,190; not read in the paper). Every joint takes the knee's: an
  ///   estimate for the others.
  /// - **Limit stiffness 3000 N·m/rad**: an estimate, no source read.
  ///   Passive moments rise steeply at the end of a joint's range (Riener
  ///   and Edrich, J. Biomech. 32, 1999); this is chosen so the heaviest
  ///   load a ragdoll's joint carries, the trunk on the hip, some 90 N·m,
  ///   carries it three hundredths of a radian past its limit. At 300 the
  ///   hero's spine, struck, went 0.7 rad past.
  /// - **Loss factor 0.011**: tendon, which loses about 7 % of the work
  ///   done on it in a cycle (Ker, "Dynamic tensile properties of the
  ///   plantaris tendon of sheep", J. Exp. Biol. 93, 1981); η = ψ / 2π.
  ///   The catalog has no tissue to take it from.
  static const JointTissue human = JointTissue(
    damping: 1.0,
    limitStiffness: 3000.0,
    inelastic: InelasticProperties(
      lossFactor: ConstantLaw(
        0.011,
        confidence: Confidence.handbook,
        source:
            'Ker, Dynamic tensile properties of the plantaris tendon of '
            'sheep, J. Exp. Biol. 93 (1981): about 7 % of the work lost a '
            'cycle; eta = psi / (2 pi)',
      ),
      source: 'Ker (1981), tendon; no tissue in the catalog (flutter3d_matter)',
    ),
  );
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

/// A hinge whose axis the rest pose shows: a knee or an elbow a rig binds a
/// little bent, as most do for their IK, bends about the axis across its
/// bone and its parent's, the way it is already bent — from straight to
/// [most] radians of bend. Bound straighter than [least] radians, the rest
/// pose does not say which way, and it is held as [otherwise].
final class RagdollBend extends RagdollJoint {
  const RagdollBend({
    this.most = 2.4,
    this.least = 0.05,
    required this.otherwise,
  });

  final double most, least;
  final RagdollJoint otherwise;
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
  /// given. Every joint is made of [tissue]: it damps the joint's turning
  /// and softens its limits, or the ragdoll never comes to rest.
  ///
  /// [forward] and [up] are the skeleton's, in the world, as it stands at
  /// rest — which way its chest faces and which way its head is from its
  /// feet; a [RagdollSwing] is measured against them. Unless given, the
  /// figure faces +z and stands up +y, as glTF's do. When the world is a
  /// [NativeDynamics]', [dynamics] keeps these bodies through its restores.
  ///
  /// [layer] and [mask] are its bodies' collision filter. A ragdoll in the
  /// core a game's characters move and its rays are cast in is met by them
  /// as a body nobody's collider stands for, unless it is on a layer their
  /// masks leave out — or in a core of its own, as the dungeon's corpses
  /// are.
  NativeRagdoll(
    this.world,
    List<RagdollBone> rest, {
    List<BonePose>? pose,
    List<Vector3>? velocity,
    List<Vector3>? spin,
    JointTissue tissue = JointTissue.human,
    Vector3? forward,
    Vector3? up,
    NativeDynamics? dynamics,
    int layer = 1,
    int mask = 0xffffffff,
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
      final center = (bone.head + bone.tail) * 0.5;
      final body = world.addBody(position: center, mass: bone.mass);
      world
        ..setShape(
          body,
          NativeShape.capsule(
            bone.radius,
            (length * 0.5 - bone.radius).clamp(0.01, double.infinity),
          ),
        )
        ..setOrientation(body, turn)
        ..setCollisionFilter(body, layer: layer, mask: mask);
      _bodies.add(body);
      // The bone's frame from the body's: inverse(body) · bone.
      final inverse = turn.conjugated();
      _offsetTurn.add(inverse * bone.orientation);
      _offsetAt.add(turnBy(inverse, bone.head - center));
      dynamics?.keep(body);
    }
    final ahead = (forward ?? Vector3(0.0, 0.0, 1.0)).normalized();
    final above = (up ?? Vector3(0.0, 1.0, 0.0)).normalized();
    final softness = tissue.limitStiffness > 0.0
        ? (stiffness: tissue.limitStiffness, ratio: tissue.limitRatio)
        : null;
    for (var i = 0; i < rest.length; i++) {
      final bone = rest[i];
      if (bone.parent < 0) continue;
      final a = _bodies[bone.parent], b = _bodies[i];
      final direction = (bone.tail - bone.head).normalized();
      final NativeJoint joint;
      final held = _resolved(bone, rest[bone.parent]);
      _held[i] = held;
      switch (held) {
        case RagdollHinge(:final axis, :final lower, :final upper):
          joint = world.createJoint(
            NativeJointType.revolute,
            a,
            b,
            anchor: bone.head,
            axis: turnBy(bone.orientation, axis),
          );
          world.setJointLimits(joint, (lower: lower, upper: upper));
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
            ..setJointLimits(joint, (lower: twistLower, upper: twistUpper));
        case RagdollSwing():
          joint = world.createJoint(
            NativeJointType.spherical,
            a,
            b,
            anchor: bone.head,
            axis: direction,
          );
          world
            ..setJointSwing(
              joint,
              _swingOf(held, bone, rest.first, ahead, above),
            )
            ..setJointLimits(joint, (lower: -held.twist, upper: held.twist));
        case null:
          joint = world.createJoint(
            NativeJointType.fixed,
            a,
            b,
            anchor: bone.head,
          );
        case RagdollBend():
          throw StateError('a bend is resolved against the rest pose first');
        default:
          throw UnsupportedError('the native core has no joint for $held');
      }
      if (held != null) {
        world
          ..setJointDamping(joint, tissue.damping)
          ..setJointLimitSoftness(joint, softness);
      }
      _joints.add(joint);
      _jointOf[i] = joint;
    }
    if (pose != null) place(pose, velocity: velocity, spin: spin);
  }

  final NativeWorld world;
  final List<RagdollBone> bones;
  final NativeDynamics? _dynamics;
  final List<NativeBody> _bodies = <NativeBody>[];
  final List<NativeJoint> _joints = <NativeJoint>[];
  final Map<int, NativeJoint> _jointOf = <int, NativeJoint>{};
  final Map<int, RagdollJoint?> _held = <int, RagdollJoint?>{};
  final List<Quaternion> _offsetTurn = <Quaternion>[];
  final List<Vector3> _offsetAt = <Vector3>[];

  /// How bone [index] came to be held: a [RagdollBend] as the hinge or the
  /// fallback its rest pose made it; null for the root and a fixed joint.
  RagdollJoint? heldAs(int index) => _held[index];

  /// The joint holding bone [index] to its parent; null for the root. To
  /// read how far a knee has bent, or set a motor on it.
  NativeJoint? jointOf(int index) => _jointOf[index];

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
          world.localPositionOf(_bodies[index]) +
          turnBy(turn, _offsetAt[index]),
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

/// [bone]'s joint, a [RagdollBend] made the hinge or the fallback the rest
/// pose says.
RagdollJoint? _resolved(RagdollBone bone, RagdollBone parent) {
  final held = bone.joint;
  if (held is! RagdollBend) return held;
  final up = (parent.tail - parent.head).normalized();
  final down = (bone.tail - bone.head).normalized();
  final across = up.cross(down);
  final bent = Portable.atan2(across.length, up.dot(down));
  if (bent < held.least) return held.otherwise;
  // Turning the bone about up × down by a positive angle bends it further:
  // from straight (minus the rest bend) to the most it bends.
  return RagdollHinge(
    axis: turnBy(bone.orientation.conjugated(), across.normalized()),
    lower: -bent,
    upper: held.most - bent,
  );
}

/// [swing]'s limits for [bone] as the core takes them: measured from the
/// skeleton's up, or its down for a bone that hangs, with forward along
/// [ahead]. The core's side is neutral × ahead; for a bone off the midline —
/// its head further from [root]'s across the body than a tenth of its
/// length — that side is lateral where it points away from the midline and
/// medial where it points towards it.
JointSwing _swingOf(
  RagdollSwing swing,
  RagdollBone bone,
  RagdollBone root,
  Vector3 ahead,
  Vector3 up,
) {
  final neutral = swing.hangs ? -up : up.clone();
  final side = neutral.cross(ahead);
  final across = (bone.head - root.head).dot(ahead.cross(up));
  final midline = across.abs() <= 0.1 * bone.head.distanceTo(bone.tail);
  final outward = side.dot(ahead.cross(up)) * across > 0.0;
  return JointSwing(
    neutral: neutral,
    ahead: ahead,
    forward: swing.flexion,
    back: swing.extension,
    toSide: midline || outward ? swing.lateral : swing.medial,
    fromSide: midline || !outward ? swing.lateral : swing.medial,
  );
}

/// cos(π/2) of the double nearest π/2, as every correctly rounded libm gives
/// it: the w of the half turns below, so they keep the bits
/// `Quaternion.axisAngle` gave them.
const double _cosHalfPi = 6.123233995736766e-17;

/// The turn that takes the y axis to [along].
///
/// What `Quaternion.fromTwoVectors` makes, snapping within 0.0005 of
/// vertical and all, without its `math.acos`, `math.sin` and `math.cos`:
/// the platform's answers, which differ in the last bit between the VM and
/// a browser. The half angle's sine and cosine come from the angle's cosine
/// c instead, as √((1 − c)/2) and √((1 + c)/2): a square root is rounded
/// alike everywhere.
Quaternion _alongY(Vector3 along) {
  final to = along.normalized();
  final up = Vector3(0.0, 1.0, 0.0);
  final dot = up.dot(to);
  if (dot > 1.0 - 1e-9) {
    return Quaternion.identity();
  }
  if (dot < -1.0 + 1e-9) {
    // Half a turn about x.
    return Quaternion(1.0, 0.0, 0.0, _cosHalfPi);
  }
  final c = up.dot(to.normalized());
  if ((1.0 + c).abs() < 0.0005) {
    // Half a turn about up × x, as fromTwoVectors picks for a y axis.
    return Quaternion(0.0, 0.0, -1.0, _cosHalfPi);
  }
  if ((1.0 - c).abs() < 0.0005) return Quaternion.identity();
  final axis = up.cross(to.normalized()).normalized();
  final halfSin = math.sqrt((1.0 - c) * 0.5) / axis.length;
  return Quaternion(
    axis.x * halfSin,
    axis.y * halfSin,
    axis.z * halfSin,
    math.sqrt((1.0 + c) * 0.5),
  );
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
