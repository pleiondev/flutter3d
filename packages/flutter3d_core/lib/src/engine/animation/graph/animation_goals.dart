import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../inverse_kinematics.dart';
import '../pose.dart';

/// Where a pose's joints are made to reach or to look, after its states and
/// layers have posed it — the IK nodes of N1.
///
/// A goal is laid on what the graph made of the frame, in the pose's own
/// space — the model's, the one [Pose.worldMatrices] is in — so a game
/// puts its targets there: the world point it cares about, times the
/// inverse of the model's world matrix. [weight] moves when [fadeTo] says,
/// on the graph's steps, so a monster turns its head to you and away again
/// rather than snapping.
sealed class AnimationGoal {
  AnimationGoal({double weight = 1.0})
    : _weight = weight.clamp(0.0, 1.0),
      _target = weight.clamp(0.0, 1.0);

  double _weight;
  double _target;
  double _rate = 0.0;

  /// How much of the goal is laid on, nought to one.
  double get weight => _weight;

  set weight(double value) {
    _weight = value.clamp(0.0, 1.0);
    _target = _weight;
    _rate = 0.0;
  }

  /// Moves [weight] to [target] over [seconds] of steps; at once for none.
  void fadeTo(double target, double seconds) {
    _target = target.clamp(0.0, 1.0);
    if (seconds <= 0.0) {
      weight = _target;
      return;
    }
    _rate = (_target - _weight).abs() / seconds;
  }

  /// Advances the fade by [dt]; the graph's, once a step.
  void step(double dt) {
    if (_rate == 0.0) return;
    final move = _rate * dt;
    if ((_target - _weight).abs() <= move) {
      _weight = _target;
      _rate = 0.0;
    } else {
      _weight += _target > _weight ? move : -move;
    }
  }

  /// Its weight and where that is fading to, for a graph's snapshot.
  Map<String, Object?> saveWeight() => <String, Object?>{
    'weight': _weight,
    'target': _target,
    'rate': _rate,
  };

  /// Back to what [saveWeight] wrote.
  void restoreWeight(Map<String, Object?> from) {
    _weight = (from['weight'] as num?)?.toDouble() ?? _weight;
    _target = (from['target'] as num?)?.toDouble() ?? _target;
    _rate = (from['rate'] as num?)?.toDouble() ?? 0.0;
  }

  /// Lays this goal on [pose] by [weight]; nothing at nought.
  void apply(Pose pose);
}

/// An arm or a leg bent to reach [target]: [root] → [mid] → [tip] by
/// `TwoBoneIk`, the middle joint on the side of [pole]. Below a weight of
/// one, the chain's joints are turned that share of the way from where the
/// graph had them.
final class ReachGoal extends AnimationGoal {
  ReachGoal({
    required this.root,
    required this.mid,
    required this.tip,
    Vector3? target,
    Vector3? pole,
    super.weight,
  }) : target = target ?? Vector3.zero(),
       pole = pole ?? Vector3(0.0, 0.0, 1.0);

  final int root, mid, tip;

  /// Where [tip] reaches, in the pose's space; moved by the game in place.
  final Vector3 target;

  /// Which side the middle joint bends to, in the pose's space.
  final Vector3 pole;

  @override
  void apply(Pose pose) {
    if (weight <= 0.0) return;
    final before = <Quaternion>[_rotation(pose, root), _rotation(pose, mid)];
    TwoBoneIk.solve(
      pose,
      root: root,
      mid: mid,
      tip: tip,
      target: target,
      pole: pole,
    );
    if (weight >= 1.0) return;
    for (final (i, joint) in <int>[root, mid].indexed) {
      _setRotation(
        pose,
        joint,
        _slerp(before[i], _rotation(pose, joint), weight),
      );
    }
  }
}

/// A joint turned to face [target]: a head that watches, by turning what
/// faced [forward] at rest towards it, at most [limit] radians — beyond
/// that it turns as far as it may and no further, which is a monster
/// glancing over its shoulder rather than wringing its neck.
final class LookGoal extends AnimationGoal {
  LookGoal({
    required this.joint,
    required Vector3 forward,
    this.limit = 1.0,
    Vector3? target,
    super.weight,
  }) : forward = forward.normalized(),
       target = target ?? Vector3.zero();

  final int joint;

  /// The direction [joint] faced at rest, in the pose's space.
  final Vector3 forward;

  /// The most it turns from where the graph had it, radians.
  double limit;

  /// What it looks at, in the pose's space; moved by the game in place.
  final Vector3 target;

  /// [forward] in [joint]'s own frame, from the pose's rest; taken once.
  Vector3? _facing;

  @override
  void apply(Pose pose) {
    if (weight <= 0.0) return;
    _facing ??= _turn(
      _rotationOf(pose.restCopy().worldMatrices()[joint]).conjugated(),
      forward,
    );
    final world = pose.worldMatrices();
    final at = world[joint].getTranslation();
    final turn = _rotationOf(world[joint]);
    final facing = _turn(turn, _facing!);
    final wanted = target - at;
    if (wanted.length2 < 1e-12) return;
    wanted.normalize();
    final axis = facing.cross(wanted);
    final sin = axis.length;
    final angle = math.atan2(sin, facing.dot(wanted));
    if (sin < 1e-9 || angle == 0.0) return;
    final by = math.min(angle, limit) * weight;
    final delta = Quaternion.axisAngle(axis..normalize(), by);
    final newWorld = (delta * turn)..normalize();
    final parent = pose.parents[joint];
    final local = parent < 0
        ? newWorld
        : (_rotationOf(world[parent]).conjugated() * newWorld
            ..normalize());
    _setRotation(pose, joint, local);
  }
}

/// One leg [FootPlantGoal] stands on the ground: [root] → [mid] → [tip],
/// hip, knee and ankle, bent by `TwoBoneIk` towards [pole].
///
/// [foot] is the bone the foot is skinned to when it is not under [tip]:
/// a rig exported with its feet as IK targets parented to the root — the
/// Quaternius characters', `Foot.L` on `Root` — has the clip put the foot
/// where the leg ends, and the plant moves it with the ankle.
final class FootLeg {
  FootLeg({
    required this.root,
    required this.mid,
    required this.tip,
    this.foot,
    this.poleJoint,
    Vector3? pole,
  }) : pole = pole ?? Vector3(0.0, 0.0, 1.0);

  final int root, mid, tip;
  final int? foot;

  /// A joint whose place is the knee's pole — `PoleTarget.L` — read each
  /// frame from the pose; [pole] when null.
  final int? poleJoint;

  /// Which side the knee bends to, in the pose's space, when [poleJoint]
  /// is null.
  final Vector3 pole;

  /// The height of the ground under this foot, in the pose's space, where
  /// the clip's own floor is nought; the game writes it before each step —
  /// a ray down from the foot, brought into the model's space. Nought is
  /// flat ground, which changes nothing.
  double ground = 0.0;
}

/// The feet put on the ground the game says is under them: a stair, a
/// slope, a rubble heap the clip was not made on.
///
/// Each foot moves up or down by its [FootLeg.ground], the leg bending to
/// reach it. A foot that must go down further than the leg can reach
/// lowers [hips] instead, by the most any foot must go down, so a
/// character on a stair stands with one knee bent rather than one leg
/// hanging in the air. Below a weight of one, every shift is that share.
final class FootPlantGoal extends AnimationGoal {
  FootPlantGoal({required this.hips, required this.legs, super.weight});

  /// The joint the legs hang from, lowered when a foot must go down.
  final int hips;
  final List<FootLeg> legs;

  @override
  void apply(Pose pose) {
    if (weight <= 0.0 || legs.isEmpty) return;
    final drop =
        legs.fold<double>(0.0, (d, l) => math.min(d, l.ground)) * weight;
    var world = pose.worldMatrices();
    // Where the clip had each ankle, before the hips move them.
    final ankles = <Vector3>[
      for (final leg in legs) world[leg.tip].getTranslation(),
    ];
    if (drop < 0.0) {
      _moveWorld(pose, world, hips, Vector3(0.0, drop, 0.0));
      world = pose.worldMatrices();
    }
    for (final (i, leg) in legs.indexed) {
      final target = ankles[i]..y += leg.ground * weight;
      final pole = switch (leg.poleJoint) {
        final int joint => world[joint].getTranslation(),
        null => world[leg.mid].getTranslation() + leg.pole,
      };
      TwoBoneIk.solve(
        pose,
        root: leg.root,
        mid: leg.mid,
        tip: leg.tip,
        target: target,
        pole: pole,
      );
      if (leg.foot case final int foot) {
        final moved = target - world[foot].getTranslation();
        _moveWorld(pose, world, foot, moved);
      }
      world = pose.worldMatrices();
    }
  }
}

/// Moves [joint] by [by] in the pose's space, through its parent's frame.
void _moveWorld(Pose pose, List<Matrix4> world, int joint, Vector3 by) {
  final parent = pose.parents[joint];
  final local = parent < 0
      ? by
      : (Matrix4.inverted(
          world[parent],
        )..setTranslationRaw(0.0, 0.0, 0.0)).transform3(by.clone());
  pose.translations[joint * 3] += local.x;
  pose.translations[joint * 3 + 1] += local.y;
  pose.translations[joint * 3 + 2] += local.z;
}

/// [v] turned by [q], as `asRotationMatrix` turns it — not
/// `Quaternion.rotated`, which turns by the inverse.
Vector3 _turn(Quaternion q, Vector3 v) =>
    q.asRotationMatrix().transform(v.clone());

Quaternion _rotationOf(Matrix4 world) {
  final rotation = Quaternion.identity();
  world.decompose(Vector3.zero(), rotation, Vector3.zero());
  return rotation..normalize();
}

Quaternion _rotation(Pose pose, int joint) => Quaternion(
  pose.rotations[joint * 4],
  pose.rotations[joint * 4 + 1],
  pose.rotations[joint * 4 + 2],
  pose.rotations[joint * 4 + 3],
);

void _setRotation(Pose pose, int joint, Quaternion q) {
  pose.rotations[joint * 4] = q.x;
  pose.rotations[joint * 4 + 1] = q.y;
  pose.rotations[joint * 4 + 2] = q.z;
  pose.rotations[joint * 4 + 3] = q.w;
}

Quaternion _slerp(Quaternion a, Quaternion b, double t) {
  var bx = b.x, by = b.y, bz = b.z, bw = b.w;
  if (a.x * bx + a.y * by + a.z * bz + a.w * bw < 0.0) {
    bx = -bx;
    by = -by;
    bz = -bz;
    bw = -bw;
  }
  return Quaternion(
    a.x + (bx - a.x) * t,
    a.y + (by - a.y) * t,
    a.z + (bz - a.z) * t,
    a.w + (bw - a.w) * t,
  )..normalize();
}
