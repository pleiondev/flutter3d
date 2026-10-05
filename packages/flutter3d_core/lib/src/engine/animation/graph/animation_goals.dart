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
