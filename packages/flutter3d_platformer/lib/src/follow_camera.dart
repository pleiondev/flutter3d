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
/// The game layer has no camera type and that is deliberate — its README says a
/// third-person camera is a caller reading `eye` and `aim` differently. This is
/// that caller, and it lives here rather than in the engine because a platformer
/// is the only thing in this repository that has one so far. It moves down when
/// a second game wants it, which is the same rule that produced
/// `flutter3d_bridge`.
///
/// Nothing here knows what a renderer is: it answers with two points and a
/// number, and the application copies them into whatever it is drawing with.
final class FollowCamera {
  FollowCamera({
    required this.world,
    this.tuning = const FollowTuning(),
    double yaw = 0.0,
  }) {
    _yaw = yaw;
    _pitch = tuning.pitch;
  }

  /// Where the walls are, for keeping the camera out of them.
  final CollisionWorld world;

  final FollowTuning tuning;

  late double _yaw;
  late double _pitch;

  /// Which way the camera faces, in radians. The runner takes this as the
  /// direction "forward" means.
  double get yaw => _yaw;

  double get pitch => _pitch;

  final Vector3 _eye = Vector3.zero();
  final Vector3 _target = Vector3.zero();
  bool _placed = false;

  /// Where the camera is. Valid after the first [follow].
  Vector3 get eye => _eye;

  /// What it is looking at.
  Vector3 get target => _target;

  /// A knock, in metres, that decays away. The camera's own recoil.
  final Vector3 _kick = Vector3.zero();

  /// How much shake is left, and how fast it wobbles.
  double _shake = 0.0;
  double _shakeTime = 0.0;

  /// How much of the shake the player asked for, nought to one.
  ///
  /// A setting rather than a constant because a shaking camera makes some
  /// people ill, and a game that cannot be turned down is a game they cannot
  /// play. Zero is not "broken", it is "off".
  double shakeScale = 1.0;

  /// Extra field of view, in radians, that decays away. Read by the
  /// application, which owns the projection.
  double get extraFov => _fov;
  double _fov = 0.0;

  /// Knocks the camera along [direction] by its length, in metres.
  ///
  /// For a landing: a dip the size of the impact, gone in a quarter of a
  /// second. Cinemachine calls the same idea an impulse.
  void kick(Vector3 direction) => _kick.add(direction);

  /// Shakes the camera for [seconds], [amount] metres wide.
  void shake(double amount, {double seconds = 0.35}) {
    _shake = math.max(_shake, amount * seconds);
    _shakeSeconds = math.max(_shakeSeconds, seconds);
  }

  double _shakeSeconds = 0.0;

  /// Widens the view by [radians], which decays back. For speed and a dash.
  void widen(double radians) => _fov = math.max(_fov, radians);

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
    _target
      ..setFrom(runner)
      ..y += tuning.aimHeight;

    final cosPitch = math.cos(_pitch);
    final wanted = Vector3(
      _target.x - math.sin(_yaw) * tuning.distance * cosPitch,
      _target.y + tuning.height - math.sin(_pitch) * tuning.distance,
      _target.z - math.cos(_yaw) * tuning.distance * cosPitch,
    );

    if (!_placed) {
      // The first frame is a cut, not a chase. Starting at the origin and
      // easing in means the level begins with the camera flying across it.
      _eye.setFrom(wanted);
      _placed = true;
    } else {
      // Exponential smoothing, written so that the fraction of the gap closed
      // in a second is the same whatever dt is.
      final t = 1.0 - math.exp(-tuning.lag * dt);
      _eye.addScaled(wanted - _eye, t);
    }

    // **The wall check runs on both sides of the impulse, and both are
    // needed.** Before, because the knock should be added to a camera that is
    // already where it belongs rather than to one halfway inside a wall.
    // After, because a knock is a displacement like any other and a camera
    // inside a brush is the one thing this class exists to prevent — a
    // property test with three hundred random impulses in a boxed room caught
    // it doing exactly that, half a metre into the wall behind the player.
    _keepOutOfWalls();

    _decay(dt);
    _eye.add(_kick);
    if (_shake > 0.0) {
      _eye
        ..x += math.sin(_shakeTime * 47.0) * _shake * shakeScale
        ..y += math.sin(_shakeTime * 39.0 + 1.7) * _shake * shakeScale
        ..z += math.sin(_shakeTime * 53.0 + 3.1) * _shake * shakeScale;
    }

    _keepOutOfWalls();
  }

  void _decay(double dt) {
    _shakeTime += dt;
    final gone = 1.0 - math.exp(-tuning.impulseDecay * dt);
    _kick.scale(1.0 - gone);
    _fov *= 1.0 - gone;
    if (_shakeSeconds > 0.0) {
      _shake = math.max(0.0, _shake - dt * _shake / _shakeSeconds - 1e-4);
    }
  }

  /// Pulls the camera in until the line from the runner to it is clear.
  ///
  /// A ray out from the target rather than a sweep of the camera's shape: the
  /// camera has no shape, and what matters is that the player can see their own
  /// runner. [FollowTuning.nearClearance] is what stops the near plane from
  /// clipping into the wall it stopped against.
  void _keepOutOfWalls() {
    final toEye = _eye - _target;
    final reach = toEye.length;
    if (reach <= 1e-4) return;
    toEye.scale(1.0 / reach);

    final hit = RayHit();
    if (!world.raycast(_target, toEye, reach, hit, mask: CollisionLayers.world)) {
      return;
    }

    final pulled = math.max(tuning.minDistance, hit.distance - tuning.nearClearance);
    _eye
      ..setFrom(_target)
      ..addScaled(toEye, pulled);
  }

  /// Puts the camera behind the runner at once, without a chase.
  ///
  /// For a respawn: easing from where the player died to where they came back
  /// is a second of the level flying past for no reason.
  void cut() {
    _placed = false;
    _kick.setZero();
    _shake = 0.0;
    _fov = 0.0;
  }
}
