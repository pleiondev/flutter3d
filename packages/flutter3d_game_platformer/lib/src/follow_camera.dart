import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// How the camera trails the runner.
final class FollowTuning extends RigTuning {
  const FollowTuning({
    super.distance = 7.0,
    super.height = 2.6,
    super.aimHeight = 1.2,
    super.lag = 9.0,
    this.pitch = -0.22,
    this.minPitch = -1.2,
    this.maxPitch = 0.9,
    this.sensitivity = 0.0035,
    super.nearClearance = 0.35,
    super.minDistance = 1.2,
    this.impulseDecay = 9.0,
    this.recentre = 1.6,
    this.recentreAbove = 3.0,
  });

  /// How fast the camera drifts back behind the runner, in radians a second.
  ///
  /// **Zero was the old behaviour and it is exhausting over a long level.** The
  /// yaw only ever changed when the mouse moved, so crossing 260 metres meant
  /// steering the camera by hand around every corner: the runner turns, the
  /// camera does not, and the player is soon watching their own back.
  ///
  /// Slow on purpose. A camera that snaps behind you takes the shot away from
  /// somebody who deliberately looked sideways; this is a drift a player can
  /// override simply by continuing to move the mouse.
  final double recentre;

  /// How fast the runner must be going before the camera drifts, in m/s.
  ///
  /// A standing runner is being looked *at*, and turning the camera round
  /// somebody who is not going anywhere is the camera deciding where the player
  /// should be looking. Above a walk, the direction of travel is the thing
  /// worth seeing.
  final double recentreAbove;

  final double pitch;
  final double minPitch;
  final double maxPitch;

  /// Radians of turn per unit of look delta.
  final double sensitivity;

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
  /// How much of the camera's involuntary movement to keep — see
  /// [CameraRig.motion]. Was `shakeScale`, and covered only the shake.
  double get motion => rig.motion;
  set motion(double value) => rig.motion = value;

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
    _pitch = (_pitch - delta.y * tuning.sensitivity).clamp(
      tuning.minPitch,
      tuning.maxPitch,
    );
  }

  /// Places the camera for a frame, given where the runner is.
  ///
  /// Called once a frame with the *interpolated* position rather than once a
  /// step with the simulated one: this is presentation, and a camera that
  /// steps at 60 Hz on a 120 Hz display judders even when the runner does not.
  void follow(Vector3 runner, double dt, {Vector3? travelling}) {
    _drift(travelling, dt);

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

  /// Eases the yaw round towards the way the runner is going.
  ///
  /// The shortest way round, which is the whole of the arithmetic worth
  /// commenting on: a runner heading a hair west of due north with the camera a
  /// hair east of it must not have the camera go the long way about.
  void _drift(Vector3? travelling, double dt) {
    if (travelling == null || tuning.recentre <= 0.0) return;
    final speed = math.sqrt(
      travelling.x * travelling.x + travelling.z * travelling.z,
    );
    if (speed < tuning.recentreAbove) return;

    final wanted = math.atan2(travelling.x, travelling.z);
    final away = shortestAngle(_yaw, wanted);

    // Scaled by how much faster than the threshold: a runner ambling barely
    // moves the camera, and one at a sprint gets it behind them promptly.
    final urgency = ((speed - tuning.recentreAbove) / 4.0).clamp(0.0, 1.0);
    _yaw += away * easeFactor(tuning.recentre * urgency, dt);
  }

  final Vector3 _wantedEye = Vector3.zero();
  final Vector3 _wantedTarget = Vector3.zero();
}
