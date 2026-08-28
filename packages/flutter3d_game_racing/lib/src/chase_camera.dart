import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'track.dart';
import 'vehicle/vehicle_controller.dart';

/// How the camera trails the car.
final class ChaseTuning extends RigTuning {
  const ChaseTuning({
    super.distance = 8.0,
    super.height = 3.0,
    super.aimHeight = 1.0,
    super.lag = 7.0,
    this.headingBlend = 0.75,
    this.headingFrom = 4.0,
    this.headingTo = 14.0,
    this.lookAhead = 26.0,
    this.lookAheadWeight = 0.35,
    this.baseFov = 1.05,
    this.fovPerSpeed = 0.006,
    this.maxFov = 1.45,
    super.nearClearance = 0.4,
    super.minDistance = 2.0,
  });

  /// How far the camera swings from behind the nose towards behind the
  /// direction of travel, from nought to one.
  ///
  /// The number that makes a drift look like one. Sat behind the nose, a car
  /// sliding sideways stays pointing straight up the screen and the slide is
  /// invisible; sat behind the direction of travel, the car swings across the
  /// frame and the angle is the picture. Not all the way to one, because a
  /// camera that ignores the nose entirely stops reporting which way the car is
  /// about to go.
  final double headingBlend;

  /// The speed the swing starts at, and the speed it is complete at.
  ///
  /// [headingFrom] is not only a threshold, it is the guard: below it the
  /// direction of travel is whatever a stationary car's rounding error says it
  /// is, and a camera reading that spins on the spot. The reach below is
  /// clamped at nought, so under this speed the swing contributes exactly
  /// nothing and the nose is followed — no separate early exit needed, and one
  /// that was there has been removed for saying the same thing twice.
  final double headingFrom;
  final double headingTo;

  /// How far up the track the camera looks, in metres.
  final double lookAhead;

  /// How much of the way to that point the aim actually moves.
  ///
  /// Not all of it: a camera that looks purely up the road loses the car out of
  /// the bottom of the frame in a hairpin. This opens the corner up while
  /// keeping the car the thing being watched.
  final double lookAheadWeight;

  /// The field of view standing still, in radians.
  final double baseFov;

  /// How much wider it gets per metre per second.
  ///
  /// The cheapest trick in the genre and the one that does the most: speed on a
  /// screen is not how fast the numbers change, it is how fast the edges of the
  /// frame move.
  final double fovPerSpeed;

  /// The widest it is allowed to get. Past about a fifth of a turn the picture
  /// reads as a fish-eye rather than as speed.
  final double maxFov;
}

/// A camera behind a car: behind where it is *going*, looking into the corner.
///
/// Everything a chasing camera has in common with any other — easing, knocks,
/// shakes, staying out of walls — is [CameraRig] in the engine. What is here is
/// the three things a racing camera does differently:
///
/// * it sits behind the direction of travel rather than behind the nose, which
///   is what makes a drift readable;
/// * it looks a little way up the track, which is what makes a corner arrive
///   before the car does;
/// * it widens with speed, which is most of what speed looks like on a screen.
///
/// Renderer-free, like the platformer's camera and for the same reason: it
/// answers with two points and a number, and the application copies them into
/// whatever it is drawing with.
final class ChaseCamera {
  ChaseCamera({
    required CollisionWorld world,
    this.track,
    this.tuning = const ChaseTuning(),
  }) : rig = CameraRig(
         world: world,
         nearClearance: tuning.nearClearance,
         minDistance: tuning.minDistance,
       );

  final CameraRig rig;

  /// The circuit, for looking up the road. Absent on a test plane, and then the
  /// camera looks along the car instead — which is the same thing on a straight.
  final TrackSpline? track;

  final ChaseTuning tuning;

  Vector3 get eye => rig.eye;
  Vector3 get target => rig.target;

  /// The field of view to draw with, in radians. Widened by speed, and by
  /// anything that asked for a kick of it.
  double get fov => _fov;
  double _fov = 0.0;

  /// Which way the camera is facing, in radians. What the last frame settled on.
  double get heading => _heading;
  double _heading = 0.0;

  /// How much of the camera's involuntary movement to keep — see
  /// [CameraRig.motion]. Was `shakeScale`, and covered only the shake.
  double get motion => rig.motion;
  set motion(double value) => rig.motion = value;

  void kick(Vector3 direction) => rig.kick(direction);

  void shake(double amount, {double seconds = 0.35}) =>
      rig.shake(amount, seconds: seconds);

  /// Widens the view, on top of whatever speed is already doing. For a boost.
  void widen(double radians) => rig.widen(radians);

  /// Puts the camera behind the car at once, without a chase. For a respawn or
  /// the start of a race.
  void cut() => rig.cut();

  /// Places the camera for a frame.
  ///
  /// Called once a frame with whatever the application is drawing the car at,
  /// rather than once a step: this is presentation, and a camera that moves at
  /// the simulation's rate judders on a faster display even when the car does
  /// not.
  void follow(VehicleController car, double dt) {
    _heading = _headingFor(car);

    _wantedTarget
      ..setFrom(car.position)
      ..y += tuning.aimHeight;

    final circuit = track;
    if (circuit != null) {
      // Towards the road ahead, part of the way. Blended rather than aimed at,
      // for the reason in [ChaseTuning.lookAheadWeight].
      circuit.centreAt(car.trackDistance + tuning.lookAhead, _ahead);
      _wantedTarget
        ..x += (_ahead.x - _wantedTarget.x) * tuning.lookAheadWeight
        ..z += (_ahead.z - _wantedTarget.z) * tuning.lookAheadWeight;
    }

    _wantedEye.setValues(
      car.position.x - math.sin(_heading) * tuning.distance,
      car.position.y + tuning.height,
      car.position.z - math.cos(_heading) * tuning.distance,
    );

    rig.place(
      desiredEye: _wantedEye,
      desiredTarget: _wantedTarget,
      lag: tuning.lag,
      dt: dt,
    );

    _fov =
        math.min(
          tuning.baseFov + car.speed * tuning.fovPerSpeed,
          tuning.maxFov,
        ) +
        rig.extraFov;
  }

  /// Somewhere between where the car points and where it is going.
  double _headingFor(VehicleController car) {
    final speed = car.speed;
    final travelling = math.atan2(car.velocity.x, car.velocity.z);
    final reach =
        ((speed - tuning.headingFrom) / (tuning.headingTo - tuning.headingFrom))
            .clamp(0.0, 1.0);

    return car.headingYaw +
        shortestAngle(car.headingYaw, travelling) * reach * tuning.headingBlend;
  }

  final Vector3 _wantedEye = Vector3.zero();
  final Vector3 _wantedTarget = Vector3.zero();
  final Vector3 _ahead = Vector3.zero();
}
