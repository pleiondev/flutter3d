import 'dart:math' as math;

import 'package:flutter3d_sim/flutter3d_sim.dart' show easeFactor;
import 'package:vector_math/vector_math.dart';

import 'shot.dart';

/// Where a virtual camera wants to be this frame.
///
/// **Only the wanting.** A framing works out the shot it would take with
/// nothing in the way and nothing shaking it; the camera that holds it eases
/// towards that, keeps it out of the walls and adds the knocks (`CameraRig`,
/// through `VirtualCamera`). Splitting it there is what lets one framing be
/// written in a few lines: the hard parts of a camera were already solved
/// once, and a framing that re-solved them would be the fourth copy.
///
/// A game's inputs — where the subject is, which way it is going — are fields
/// the game writes before the camera is updated. That keeps the framings free
/// of any game's types: a car, a runner and a cursor over a map all arrive as
/// points and directions.
abstract base class CameraFraming {
  /// A framing.
  CameraFraming();

  /// How much of the remaining gap the camera closes in a second. Higher is
  /// tighter; infinity is no smoothing at all.
  double get lag;

  /// Writes the shot this framing wants into [wanted], [dt] seconds after the
  /// last.
  ///
  /// [wanted] arrives holding the last frame's wish, which a framing that
  /// changes only some of it may keep.
  void frame(CameraShot wanted, double dt);

  /// Forgets any smoothing of its own, for a cut: a respawn or a new shot.
  /// The camera's own easing is reset by the camera.
  void cut() {}
}

/// A camera that keeps a fixed offset from a subject: follow and look at it.
///
/// **The dead zone and the damping are the two numbers a following camera is
/// tuned by.** A subject moving inside the [deadZone] moves on screen and the
/// camera stays put, which is what stops a camera from twitching with every
/// step of a walk; once it leaves the zone the camera's anchor is dragged
/// with it, eased per axis by [damping] — a camera usually wants to keep up
/// with a fall far faster than with a stroll.
final class FollowFraming extends CameraFraming {
  /// Follows [subject] from [offset], looking at it raised by [aim].
  FollowFraming({
    Vector3? offset,
    Vector3? aim,
    Vector3? deadZone,
    Vector3? damping,
    this.lag = 9.0,
    this.fovY = 1.0,
  }) : offset = offset ?? Vector3(0.0, 3.0, 8.0),
       aim = aim ?? Vector3(0.0, 1.0, 0.0),
       deadZone = deadZone ?? Vector3.zero(),
       damping = damping ?? Vector3.zero();

  /// Where the subject is. Written by the game before every update.
  final Vector3 subject = Vector3.zero();

  /// Where the camera sits relative to what it follows, in the world's axes.
  final Vector3 offset;

  /// Where it looks relative to what it follows: its middle rather than its
  /// feet.
  final Vector3 aim;

  /// How far, per axis and either way, the subject may move before the camera
  /// follows. Nought follows every movement.
  final Vector3 deadZone;

  /// How fast the anchor catches up, per axis, as a rate per second. Nought
  /// catches up at once.
  final Vector3 damping;

  /// How fast the camera closes the gap, as a rate per second.
  @override
  final double lag;

  /// The field of view it asks for, in radians.
  double fovY;

  /// The point that is followed: the subject, held back by the dead zone and
  /// the damping. Exposed because a test asking whether the dead zone holds
  /// asks about this.
  Vector3 get anchor => _anchor;
  final Vector3 _anchor = Vector3.zero();
  bool _anchored = false;

  @override
  void frame(CameraShot wanted, double dt) {
    if (!_anchored) {
      _anchor.setFrom(subject);
      _anchored = true;
    } else {
      _anchor
        ..x = _follow(_anchor.x, subject.x, deadZone.x, damping.x, dt)
        ..y = _follow(_anchor.y, subject.y, deadZone.y, damping.y, dt)
        ..z = _follow(_anchor.z, subject.z, deadZone.z, damping.z, dt);
    }
    wanted.eye
      ..setFrom(_anchor)
      ..add(offset);
    wanted.target
      ..setFrom(_anchor)
      ..add(aim);
    wanted.fovY = fovY;
  }

  @override
  void cut() => _anchored = false;
}

/// A camera that stays where it is put and turns to watch a subject.
///
/// A security camera, a turret's view, the establishing shot of a room.
/// [deadZone] and [damping] mean what they mean on [FollowFraming], applied
/// to the point being looked at instead of the place being stood at.
final class LookAtFraming extends CameraFraming {
  /// Stands at [from] and watches a subject raised by [aim].
  LookAtFraming({
    required Vector3 from,
    Vector3? aim,
    Vector3? deadZone,
    Vector3? damping,
    this.lag = double.infinity,
    this.fovY = 1.0,
  }) : from = from.clone(),
       aim = aim ?? Vector3(0.0, 1.0, 0.0),
       deadZone = deadZone ?? Vector3.zero(),
       damping = damping ?? Vector3.zero();

  /// Where the camera stands. Moving it moves the camera.
  final Vector3 from;

  /// Where the subject is. Written by the game before every update.
  final Vector3 subject = Vector3.zero();

  /// The offset from the subject that is looked at.
  final Vector3 aim;

  /// How far the subject may wander before the view turns after it.
  final Vector3 deadZone;

  /// How fast the view catches up, per axis, per second. Nought is at once.
  final Vector3 damping;

  /// How fast the camera closes the gap, as a rate per second.
  @override
  final double lag;

  /// The field of view it asks for, in radians.
  double fovY;

  final Vector3 _watched = Vector3.zero();
  bool _watching = false;

  @override
  void frame(CameraShot wanted, double dt) {
    final x = subject.x + aim.x;
    final y = subject.y + aim.y;
    final z = subject.z + aim.z;
    if (!_watching) {
      _watched.setValues(x, y, z);
      _watching = true;
    } else {
      _watched
        ..x = _follow(_watched.x, x, deadZone.x, damping.x, dt)
        ..y = _follow(_watched.y, y, deadZone.y, damping.y, dt)
        ..z = _follow(_watched.z, z, deadZone.z, damping.z, dt);
    }
    wanted.eye.setFrom(from);
    wanted.target.setFrom(_watched);
    wanted.fovY = fovY;
  }

  @override
  void cut() => _watching = false;
}

/// One subject of a [GroupFraming]: where it is, how big, and how much it
/// counts.
final class FramedTarget {
  /// A subject at [position], [radius] metres round, counted [weight] times.
  FramedTarget({Vector3? position, this.radius = 1.0, this.weight = 1.0})
    : position = position ?? Vector3.zero();

  /// Where it is. Written by the game before every update.
  final Vector3 position;

  /// How much room it needs around it, in metres.
  double radius;

  /// How strongly it pulls the middle of the shot towards itself. Nought
  /// keeps it in frame without moving the middle; a negative weight counts as
  /// nought.
  double weight;
}

/// A camera that keeps several subjects in the picture at once.
///
/// It looks at their weighted middle from a fixed direction ([yaw] and
/// [pitch]) and stands back as far as the whole group needs: the smallest
/// sphere about the middle that holds every subject's own, fitted into the
/// narrower of the two fields of view, times [padding]. Two players on one
/// screen, a party in a fight, a ball and the goal.
final class GroupFraming extends CameraFraming {
  /// Frames [targets] from [yaw] and [pitch].
  GroupFraming({
    List<FramedTarget>? targets,
    this.yaw = 0.0,
    this.pitch = 0.6,
    this.padding = 1.15,
    this.minDistance = 4.0,
    this.maxDistance = 120.0,
    this.aspect = 16.0 / 9.0,
    this.lag = 6.0,
    this.fovY = 1.0,
  }) : targets = targets ?? <FramedTarget>[];

  /// What has to be in the picture.
  final List<FramedTarget> targets;

  /// The direction the camera looks from: turned about the vertical, and
  /// tilted down from the horizon, in radians. At nought yaw it looks along
  /// minus Z.
  double yaw;

  /// How far below the horizon the camera looks down at the group, in
  /// radians.
  double pitch;

  /// How much room to leave round the group, as a factor of what it needs.
  double padding;

  /// The nearest the camera may stand to the group's middle, in metres.
  double minDistance;

  /// The furthest the camera may stand from the group's middle, in metres.
  double maxDistance;

  /// The picture's width over its height, so the group fits sideways too: a
  /// ratio, with no unit.
  double aspect;

  /// How fast the camera closes the gap, as a rate per second.
  @override
  final double lag;

  /// The vertical field of view it asks for, in radians.
  double fovY;

  /// How far it stood back on the last frame, in metres.
  double get distance => _distance;
  double _distance = 0.0;

  @override
  void frame(CameraShot wanted, double dt) {
    if (targets.isEmpty) return;
    final middle = Vector3.zero();
    var total = 0.0;
    for (final target in targets) {
      final weight = math.max(0.0, target.weight);
      middle.addScaled(target.position, weight);
      total += weight;
    }
    if (total > 0.0) {
      middle.scale(1.0 / total);
    } else {
      for (final target in targets) {
        middle.add(target.position);
      }
      middle.scale(1.0 / targets.length);
    }

    var reach = 0.0;
    for (final target in targets) {
      reach = math.max(
        reach,
        target.position.distanceTo(middle) + target.radius,
      );
    }

    // The narrower half-angle decides: a wide group on a tall screen has to
    // fit its width, and a tall one on a wide screen its height.
    final halfV = fovY / 2.0;
    final halfH = math.atan(math.tan(halfV) * aspect);
    final half = math.min(halfV, halfH);
    _distance = (reach * padding / math.sin(half)).clamp(
      minDistance,
      maxDistance,
    );

    final back = math.cos(pitch) * _distance;
    wanted.target.setFrom(middle);
    wanted.eye.setValues(
      middle.x + math.sin(yaw) * back,
      middle.y + math.sin(pitch) * _distance,
      middle.z + math.cos(yaw) * back,
    );
    wanted.fovY = fovY;
  }
}

/// One axis of a followed point: held inside the dead zone, then eased.
double _follow(
  double current,
  double wanted,
  double zone,
  double rate,
  double dt,
) {
  final away = wanted - current;
  final past = away.abs() - zone;
  if (past <= 0.0) return current;
  final goal = current + (away.isNegative ? -past : past);
  if (rate <= 0.0) return goal;
  return current + (goal - current) * easeFactor(rate, dt);
}
