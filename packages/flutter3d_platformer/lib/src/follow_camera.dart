import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// How the camera trails the runner.
final class FollowTuning {
  const FollowTuning({
    this.distance = 7.0,
    this.height = 2.6,
    this.aimHeight = 1.2,
    this.lag = 9.0,
    this.pitch = -0.22,
    this.minPitch = -1.2,
    this.maxPitch = 0.9,
    this.sensitivity = 0.0035,
    this.nearClearance = 0.35,
    this.minDistance = 1.2,
    this.impulseDecay = 9.0,
  });

  final double distance;
  final double height;

  /// How far up the runner the camera looks. Its middle, not its feet, or the
  /// horizon sits in the wrong place the whole game.
  final double aimHeight;

  /// How fast the camera catches up, in units a second of the remaining gap.
  ///
  /// Exponential rather than a fixed speed, so it is frame-rate independent and
  /// so it never overshoots — a camera that oscillates around the player is a
  /// camera that makes people ill.
  final double lag;

  final double pitch;
  final double minPitch;
  final double maxPitch;

  /// Radians of turn per unit of look delta.
  final double sensitivity;

  /// How far in front of a wall the camera stops.
  final double nearClearance;

  /// How close to the runner the camera may be pulled before giving up.
  final double minDistance;

  /// How fast a kick, a widening and a shake fade, per second.
  final double impulseDecay;
}

/// A third-person camera: behind the runner, above it, out of the walls.
///
/// What is left here is what makes it a *platformer's* camera: a yaw the player
/// turns with the mouse, a pitch they tilt, and the orbit those two describe
/// around the runner. Everything a chasing camera has in common with any other
/// — easing without overshoot, knocks and shakes that fade, staying out of the
/// walls, and the order those have to happen in — moved to [CameraRig] in the
/// engine when a second game wanted it. That is the same rule that produced
/// `flutter3d_bridge`, applied a second time.
///
/// Nothing here knows what a renderer is: it answers with two points and a
/// number, and the application copies them into whatever it is drawing with.
final class FollowCamera {
  FollowCamera({
    required this.world,
    this.tuning = const FollowTuning(),
    double yaw = 0.0,
  }) : rig = CameraRig(
          world: world,
          impulseDecay: tuning.impulseDecay,
          nearClearance: tuning.nearClearance,
          minDistance: tuning.minDistance,
        ) {
    _yaw = yaw;
    _pitch = tuning.pitch;
  }

  /// Where the walls are, for keeping the camera out of them.
  final CollisionWorld world;

  final FollowTuning tuning;

  /// The shared half: where the camera actually is, and everything that gets it
  /// there.
  final CameraRig rig;

  late double _yaw;
  late double _pitch;

  /// Which way the camera faces, in radians. The runner takes this as the
  /// direction "forward" means.
  double get yaw => _yaw;

  double get pitch => _pitch;

  /// Where the camera is. Valid after the first [follow].
  Vector3 get eye => rig.eye;

  /// What it is looking at.
  Vector3 get target => rig.target;

  /// How much of the shake the player asked for, nought to one.
  double get shakeScale => rig.shakeScale;
  set shakeScale(double value) => rig.shakeScale = value;

  /// Extra field of view, in radians, that decays away. Read by the
  /// application, which owns the projection.
  double get extraFov => rig.extraFov;

  /// Knocks the camera along [direction] by its length, in metres.
  ///
  /// For a landing: a dip the size of the impact, gone in a quarter of a
  /// second. Cinemachine calls the same idea an impulse.
  void kick(Vector3 direction) => rig.kick(direction);

  /// Shakes the camera for [seconds], [amount] metres wide.
  void shake(double amount, {double seconds = 0.35}) =>
      rig.shake(amount, seconds: seconds);

  /// Widens the view by [radians], which decays back. For speed and a dash.
  void widen(double radians) => rig.widen(radians);

  /// Turns the camera by a look delta from a mouse or a stick.
  void look(Vector2 delta) {
    _yaw -= delta.x * tuning.sensitivity;
    _pitch = (_pitch - delta.y * tuning.sensitivity)
        .clamp(tuning.minPitch, tuning.maxPitch);
  }

  /// Places the camera for a frame, given where the runner is.
  ///
  /// Called once a frame with the *interpolated* position rather than once a
  /// step with the simulated one: this is presentation, and a camera that
  /// steps at 60 Hz on a 120 Hz display judders even when the runner does not.
  void follow(Vector3 runner, double dt) {
    _wantedTarget
      ..setFrom(runner)
      ..y += tuning.aimHeight;

    final cosPitch = math.cos(_pitch);
    _wantedEye.setValues(
      _wantedTarget.x - math.sin(_yaw) * tuning.distance * cosPitch,
      _wantedTarget.y + tuning.height - math.sin(_pitch) * tuning.distance,
      _wantedTarget.z - math.cos(_yaw) * tuning.distance * cosPitch,
    );

    rig.place(
      desiredEye: _wantedEye,
      desiredTarget: _wantedTarget,
      lag: tuning.lag,
      dt: dt,
    );
  }

  /// Puts the camera behind the runner at once, without a chase.
  ///
  /// For a respawn: easing from where the player died to where they came back
  /// is a second of the level flying past for no reason.
  void cut() => rig.cut();

  final Vector3 _wantedEye = Vector3.zero();
  final Vector3 _wantedTarget = Vector3.zero();
}
