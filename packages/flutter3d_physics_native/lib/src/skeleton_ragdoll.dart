/// A skinned character gone limp — N1: the joints of a scene's [Skeleton]
/// made into a [NativeRagdoll] by a profile of names, and the ragdoll's
/// bodies written back into the joints, all the way or blended with the
/// animation's pose.
///
/// ## Which joints are bodies
///
/// A rig has more joints than a ragdoll wants bodies: fingers, ears, the
/// helpers a modelling package adds. A [RagdollProfile] names the ones that
/// become bodies; every other joint rides along with whatever it hangs from,
/// keeping its animated local pose, and the profile's followers — a foot an
/// IK rig hangs from the root, not from the shin — are carried rigidly by
/// the body they name. Each body's parent is its nearest ancestor that is a
/// body, so the profile names bodies and not the hierarchy.
///
/// ## Sizes from the figure
///
/// A rig's units are whatever its author's were — the Quaternius figures are
/// two centimetres tall under a node that scales them up a hundredfold — so
/// a part's thickness is a share of the figure's height and its mass a share
/// of the whole, both measured in the world, after every scale.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart' show SceneNode, Skeleton;
import 'package:flutter3d_physics/flutter3d_physics.dart' show Portable;
import 'package:vector_math/vector_math.dart';

import 'native_dynamics.dart';
import 'native_ragdoll.dart';
import 'native_world.dart';

/// One body of a [RagdollProfile].
final class RagdollPart {
  const RagdollPart({
    this.tailAt = const <String>[],
    this.tailLength,
    required this.radius,
    required this.share,
    this.joint,
  });

  /// Where the body ends: the first of these joints the rig has.
  final List<String> tailAt;

  /// Else, along the joint's own y, this many times the length of an earlier
  /// part.
  final ({String of, double times})? tailLength;

  /// How thick, as a share of the figure's height.
  final double radius;

  /// How heavy, as a share of the whole.
  final double share;

  /// How it is held to its parent body; ignored for the root.
  final RagdollJoint? joint;
}

/// Which joints of a rig become bodies, and which ride rigidly on one.
final class RagdollProfile {
  const RagdollProfile({required this.parts, this.followers = const {}});

  final Map<String, RagdollPart> parts;

  /// Joints carried rigidly by a body, by name: follower to body.
  final Map<String, String> followers;

  /// The Quaternius character rig — the dungeon's monsters, the hero, the
  /// robot: `Body` at the pelvis, `Torso`, `Head`, upper and lower arms and
  /// legs, and the feet, which hang from `Root` for their IK, carried by the
  /// shins. Knees are hinges, their axis from the bend the rig is bound
  /// with; elbows too where the bend says enough. A forearm reaches to the tip of the middle finger where the rig
  /// has fingers, so the hand lies inside it: ended at the knuckles, the
  /// runner's fingers went eight centimetres into the floor. Elbows and knees
  /// are balls with a wide cone and little twist:
  /// which way a hinge on this rig would bend depends on axes the rig does
  /// not promise, and a knee bent backwards is worse than one a little too
  /// free.
  static const RagdollProfile quaternius = RagdollProfile(
    parts: <String, RagdollPart>{
      'Body': RagdollPart(
        tailAt: <String>['Torso'],
        radius: 0.075,
        share: 0.17,
      ),
      'Torso': RagdollPart(
        tailAt: <String>['Neck', 'Head'],
        radius: 0.085,
        share: 0.27,
        joint: RagdollBall(cone: 0.5, twistLower: -0.4, twistUpper: 0.4),
      ),
      'Head': RagdollPart(
        tailLength: (of: 'Torso', times: 0.9),
        radius: 0.07,
        share: 0.08,
        joint: RagdollBall(cone: 0.6, twistLower: -0.7, twistUpper: 0.7),
      ),
      'UpperArm.L': _upperArm,
      'UpperArm.R': _upperArm,
      'LowerArm.L': _lowerArmL,
      'LowerArm.R': _lowerArmR,
      'UpperLeg.L': _upperLeg,
      'UpperLeg.R': _upperLeg,
      'LowerLeg.L': _lowerLeg,
      'LowerLeg.R': _lowerLeg,
    },
    followers: <String, String>{'Foot.L': 'LowerLeg.L', 'Foot.R': 'LowerLeg.R'},
  );

  static const RagdollPart _upperArm = RagdollPart(
    tailAt: <String>['LowerArm.L', 'LowerArm.R'],
    radius: 0.035,
    share: 0.03,
    joint: RagdollBall(cone: 1.5, twistLower: -1.0, twistUpper: 1.0),
  );
  static const RagdollPart _lowerArmL = RagdollPart(
    tailAt: <String>['Fist.L', 'Middle3.L', 'Middle1.L'],
    tailLength: (of: 'UpperArm.L', times: 0.9),
    radius: 0.03,
    share: 0.02,
    joint: _elbow,
  );
  static const RagdollPart _lowerArmR = RagdollPart(
    tailAt: <String>['Fist.R', 'Middle3.R', 'Middle1.R'],
    tailLength: (of: 'UpperArm.R', times: 0.9),
    radius: 0.03,
    share: 0.02,
    joint: _elbow,
  );
  static const RagdollPart _upperLeg = RagdollPart(
    tailAt: <String>['LowerLeg.L', 'LowerLeg.R'],
    radius: 0.05,
    share: 0.1,
    joint: RagdollBall(cone: 1.2, twistLower: -0.5, twistUpper: 0.5),
  );
  static const RagdollPart _lowerLeg = RagdollPart(
    tailLength: (of: 'UpperLeg.L', times: 1.2),
    radius: 0.04,
    share: 0.05,
    joint: _knee,
  );

  /// A knee is a hinge: the rig binds it bent a little, which says the
  /// axis and the way it bends.
  static const RagdollJoint _knee = RagdollBend(otherwise: _limb);

  /// An elbow, bound in a T-pose all but straight, would read its axis from
  /// a few hundredths of a radian of noise; asked for a tenth and a half of
  /// bend, the Quaternius arms fall back to a ball.
  static const RagdollJoint _elbow = RagdollBend(least: 0.15, otherwise: _limb);

  static const RagdollJoint _limb = RagdollBall(
    cone: 2.2,
    twistLower: -0.15,
    twistUpper: 0.15,
  );
}

final class SkeletonRagdoll {
  /// [skeleton] gone limp in [world] from the pose it holds now, [mass]
  /// kilograms in all. [meshWorld] is the skinned mesh's world matrix, which
  /// the skeleton's bind pose is in. With [previous] — every joint's world
  /// matrix [dt] seconds ago — the bodies keep the motion the animation had.
  SkeletonRagdoll({
    required this.skeleton,
    required Matrix4 meshWorld,
    required NativeWorld world,
    this.profile = RagdollProfile.quaternius,
    double mass = 70.0,
    List<Matrix4>? previous,
    double dt = 1.0 / 60.0,
    double friction = 2.0,
    NativeDynamics? dynamics,
  }) {
    final joints = skeleton.joints;
    final byName = <String, int>{
      for (var i = 0; i < joints.length; i++) ?joints[i].name: i,
    };
    final bind = <Matrix4>[
      for (var i = 0; i < joints.length; i++)
        meshWorld * skeleton.bindPoseOf(i) as Matrix4,
    ];
    final height = _extent(bind);
    final total = profile.parts.entries
        .where((e) => byName.containsKey(e.key))
        .fold<double>(0.0, (sum, e) => sum + e.value.share);

    // The bodies, in the skeleton's order, which puts every parent first.
    final lengths = <String, double>{};
    final rest = <RagdollBone>[];
    final bodyOfJoint = <int, int>{};
    for (var i = 0; i < joints.length; i++) {
      final name = joints[i].name;
      final part = name == null ? null : profile.parts[name];
      if (part == null) continue;
      final head = bind[i].getTranslation();
      final turn = _turnOf(bind[i]);
      final tail = _tailOf(part, bind, byName, head, turn, lengths);
      lengths[name!] = tail.distanceTo(head);
      final parent = _bodyAbove(joints[i], joints, bodyOfJoint);
      bodyOfJoint[i] = rest.length;
      _jointOfBody.add(i);
      rest.add(
        RagdollBone(
          name: name,
          parent: parent,
          head: head,
          tail: tail,
          orientation: turn,
          radius: part.radius * height,
          mass: mass * part.share / total,
          joint: parent < 0 ? null : part.joint,
        ),
      );
    }
    if (rest.isEmpty) {
      throw ArgumentError('the skeleton has no joint the profile names');
    }
    _bodyOfJoint.addAll(bodyOfJoint);

    // Followers: carried by their body as they stood at bind.
    for (final MapEntry(key: follower, value: carrier)
        in profile.followers.entries) {
      final f = byName[follower], c = byName[carrier];
      if (f == null || c == null || !bodyOfJoint.containsKey(c)) continue;
      _followers[f] = (
        body: bodyOfJoint[c]!,
        offset: Matrix4.inverted(_unscaled(bind[c])) * bind[f] as Matrix4,
      );
    }

    // The first body — the pelvis — at bind, and which way the character
    // faced and stood up there: what [lying] reads the body against.
    _pelvisAtBind = rest.first.orientation.clone();
    final facing = _turnOf(meshWorld);
    _forwardAtBind = turnBy(facing, Vector3(0.0, 0.0, 1.0));
    _upAtBind = turnBy(facing, Vector3(0.0, 1.0, 0.0));

    final now = <BonePose>[
      for (final j in _jointOfBody)
        (
          position: joints[j].worldMatrix.getTranslation(),
          orientation: _turnOf(joints[j].worldMatrix),
        ),
    ];
    List<Vector3>? velocity, spin;
    if (previous != null) {
      velocity = <Vector3>[
        for (var k = 0; k < _jointOfBody.length; k++)
          (now[k].position - previous[_jointOfBody[k]].getTranslation()) / dt,
      ];
      spin = <Vector3>[
        for (var k = 0; k < _jointOfBody.length; k++)
          _spinBetween(
            _turnOf(previous[_jointOfBody[k]]),
            now[k].orientation,
            dt,
          ),
      ];
    }
    ragdoll = NativeRagdoll(
      world,
      rest,
      pose: now,
      velocity: velocity,
      spin: spin,
      friction: friction,
      dynamics: dynamics,
    );
  }

  final Skeleton skeleton;
  final RagdollProfile profile;

  /// The bodies, to strike one or ask whether they sleep.
  late final NativeRagdoll ragdoll;

  /// For each body, its joint in the skeleton; and back.
  final List<int> _jointOfBody = <int>[];
  final Map<int, int> _bodyOfJoint = <int, int>{};
  final Map<int, ({int body, Matrix4 offset})> _followers =
      <int, ({int body, Matrix4 offset})>{};

  late final Quaternion _pelvisAtBind;
  late final Vector3 _forwardAtBind, _upAtBind;

  /// How the body lies now, read off its pelvis: whether the chest faces
  /// up, where the pelvis is, and which way along the floor the head lies
  /// from it — what a game picks a get-up clip by and places the character
  /// it gets up as.
  RagdollLying lying() {
    final pelvis = ragdoll.poseOf(0);
    // As matrices, which turn the way `turnBy` does whatever order the
    // quaternion product composes in: now, after undoing bind.
    final turn = pelvis.orientation.asRotationMatrix()
      ..multiply(_pelvisAtBind.asRotationMatrix()..transpose());
    final forward = turn.transformed(_forwardAtBind);
    final up = turn.transformed(_upAtBind);
    final headward = Vector3(up.x, 0.0, up.z);
    return RagdollLying(
      faceUp: forward.y >= 0.0,
      pelvis: pelvis.position.clone(),
      headward: headward.length2 < 1e-12
          ? Vector3(0.0, 0.0, 1.0)
          : headward.normalized(),
    );
  }

  /// The body standing for the joint called [name]; null for one that is
  /// not a body.
  int? bodyNamed(String name) {
    final joints = skeleton.joints;
    for (final MapEntry(key: joint, value: body) in _bodyOfJoint.entries) {
      if (joints[joint].name == name) return body;
    }
    return null;
  }

  /// The ragdoll's pose into the joints: all of it at [weight] one, none at
  /// nought, between them a blend with what the joints hold now — which is
  /// the animation's pose when its player was updated this frame first. A
  /// character getting up is this with [weight] falling to nought.
  void apply({double weight = 1.0}) {
    final joints = skeleton.joints;
    final w = weight.clamp(0.0, 1.0);
    if (w == 0.0) return;
    for (var i = 0; i < joints.length; i++) {
      final body = _bodyOfJoint[i];
      final follower = _followers[i];
      if (body == null && follower == null) continue;
      final node = joints[i];
      final scale = _scaleOf(node.worldMatrix);
      final Matrix4 target;
      if (body != null) {
        final pose = ragdoll.poseOf(body);
        target = Matrix4.compose(pose.position, pose.orientation, scale);
      } else {
        final carrier = ragdoll.poseOf(follower!.body);
        target =
            Matrix4.compose(
                      carrier.position,
                      carrier.orientation,
                      Vector3.all(1.0),
                    ) *
                    follower.offset
                as Matrix4;
      }
      final parent = node.parent;
      final local = parent == null
          ? target
          : Matrix4.inverted(parent.worldMatrix) * target as Matrix4;
      if (w < 1.0) _blendInto(local, node.localMatrix, w);
      node.setLocalMatrix(local);
    }
  }

  /// Takes the bodies out of the world. The joints keep the last pose
  /// written to them.
  void dispose() => ragdoll.dispose();
}

/// [into] made the blend of [from] (weight 1 − [w]) and itself (weight [w]).
void _blendInto(Matrix4 into, Matrix4 from, double w) {
  final ta = Vector3.zero(), sa = Vector3.zero(), tb = Vector3.zero();
  final sb = Vector3.zero();
  final ra = Quaternion.identity(), rb = Quaternion.identity();
  from.decompose(ta, ra, sa);
  into.decompose(tb, rb, sb);
  final dot = ra.x * rb.x + ra.y * rb.y + ra.z * rb.z + ra.w * rb.w;
  if (dot < 0.0) rb.setValues(-rb.x, -rb.y, -rb.z, -rb.w);
  final r = Quaternion(
    ra.x + (rb.x - ra.x) * w,
    ra.y + (rb.y - ra.y) * w,
    ra.z + (rb.z - ra.z) * w,
    ra.w + (rb.w - ra.w) * w,
  )..normalize();
  into.setFromTranslationRotationScale(
    ta + (tb - ta) * w,
    r,
    sa + (sb - sa) * w,
  );
}

/// The turn in [m], its scale taken out.
Quaternion _turnOf(Matrix4 m) {
  final t = Vector3.zero(), s = Vector3.zero();
  final r = Quaternion.identity();
  m.decompose(t, r, s);
  return r..normalize();
}

Vector3 _scaleOf(Matrix4 m) {
  final t = Vector3.zero(), s = Vector3.zero();
  final r = Quaternion.identity();
  m.decompose(t, r, s);
  return s;
}

/// [m] with its scale taken out.
Matrix4 _unscaled(Matrix4 m) =>
    Matrix4.compose(m.getTranslation(), _turnOf(m), Vector3.all(1.0));

/// How far the joints spread along the widest axis: the figure's height,
/// standing at bind.
double _extent(List<Matrix4> worlds) {
  final lo = Vector3.all(double.infinity), hi = Vector3.all(-double.infinity);
  for (final m in worlds) {
    final p = m.getTranslation();
    Vector3.min(lo, p, lo);
    Vector3.max(hi, p, hi);
  }
  final d = hi - lo;
  return math.max(d.x, math.max(d.y, d.z));
}

Vector3 _tailOf(
  RagdollPart part,
  List<Matrix4> bind,
  Map<String, int> byName,
  Vector3 head,
  Quaternion turn,
  Map<String, double> lengths,
) {
  for (final name in part.tailAt) {
    final j = byName[name];
    if (j != null) return bind[j].getTranslation();
  }
  final along = part.tailLength;
  final length = along == null ? null : lengths[along.of];
  if (along == null || length == null) {
    throw ArgumentError('no tail for a ragdoll part: none of ${part.tailAt}');
  }
  return head + turnBy(turn, Vector3(0.0, length * along.times, 0.0));
}

/// The body of [node]'s nearest ancestor that is one, or -1.
int _bodyAbove(SceneNode node, List<SceneNode> joints, Map<int, int> bodies) {
  for (var up = node.parent; up != null; up = up.parent) {
    final index = joints.indexOf(up);
    if (index >= 0 && bodies.containsKey(index)) return bodies[index]!;
  }
  return -1;
}

/// The spin that turns [from] into [to] in [dt].
Vector3 _spinBetween(Quaternion from, Quaternion to, double dt) {
  var d = to * from.conjugated();
  if (d.w < 0.0) d = Quaternion(-d.x, -d.y, -d.z, -d.w);
  final s = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
  if (s < 1e-9) return Vector3.zero();
  final angle = 2.0 * Portable.atan2(s, d.w);
  return Vector3(d.x, d.y, d.z) * (angle / (s * dt));
}

/// How a fallen body lies — see [SkeletonRagdoll.lying].
final class RagdollLying {
  const RagdollLying({
    required this.faceUp,
    required this.pelvis,
    required this.headward,
  });

  /// Whether the chest faces up: a get-up from the back, else from the
  /// front.
  final bool faceUp;

  /// Where the pelvis is.
  final Vector3 pelvis;

  /// Which way along the floor the head lies from the pelvis, unit length;
  /// straight up reads as +z.
  final Vector3 headward;

  /// The yaw an actor faces [headward] by — yaw nought looking along -z, as
  /// `Facing` has it: a character getting up from its front rises facing
  /// where its head was.
  double get headingYaw => Portable.atan2(-headward.x, -headward.z);
}

/// A fallen body getting up — N1: the animation poses the joints each
/// frame, a get-up clip from the [RagdollLying] it fell into, and this lays
/// the ragdoll over that pose, all of it at first and none of it after
/// [seconds], then takes the bodies out of the world.
///
/// The game places the character first — its model where
/// [RagdollLying.pelvis] is and turned by [RagdollLying.headingYaw] — so
/// the clip's first frame lies about where the body does, and what the
/// fade hides is the difference.
final class RagdollGetUp {
  RagdollGetUp(this.ragdoll, {this.seconds = 0.4});

  final SkeletonRagdoll ragdoll;
  final double seconds;
  double _elapsed = 0.0;
  bool _done = false;

  /// How much of the ragdoll is still laid on, one to nought.
  double get weight =>
      seconds <= 0.0 ? 0.0 : (1.0 - _elapsed / seconds).clamp(0.0, 1.0);

  /// Whether the animation has the body to itself.
  bool get isDone => _done;

  /// Advances by [dt] — after the animation has posed the joints this
  /// frame — and lays the ragdoll on by what is left of it.
  void step(double dt) {
    if (_done) return;
    ragdoll.apply(weight: weight);
    _elapsed += dt;
    if (weight <= 0.0) {
      _done = true;
      ragdoll.dispose();
    }
  }
}
