import 'package:flutter3d_camera/flutter3d_camera.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'track.dart';
import 'vehicle/vehicle_controller.dart';

/// How the camera trails the car.
final class ChaseSettings extends RigSettings {
  const ChaseSettings({
    super.distance = 8.0,
    super.height = 3.0,
    super.aimHeight = 1.0,
    super.lag = 7.0,
    this.headingBlend = 0.75,
    this.headingFrom = 4.0,
    this.headingTo = 14.0,
    this.lookAhead = 26.0,
    this.lookAheadWeight = 0.35,
    this.baseFovY = 1.05,
    this.fovYPerSpeed = 0.006,
    this.maxFov = 1.45,
    super.nearClearance = 0.4,
    super.minDistance = 2.0,
  });

  /// A copy with the given fields replaced.
  @override
  ChaseSettings copyWith({
    double? distance,
    double? height,
    double? aimHeight,
    double? lag,
    double? nearClearance,
    double? minDistance,
    double? headingBlend,
    double? headingFrom,
    double? headingTo,
    double? lookAhead,
    double? lookAheadWeight,
    double? baseFovY,
    double? fovYPerSpeed,
    double? maxFov,
  }) => ChaseSettings(
    distance: distance ?? this.distance,
    height: height ?? this.height,
    aimHeight: aimHeight ?? this.aimHeight,
    lag: lag ?? this.lag,
    nearClearance: nearClearance ?? this.nearClearance,
    minDistance: minDistance ?? this.minDistance,
    headingBlend: headingBlend ?? this.headingBlend,
    headingFrom: headingFrom ?? this.headingFrom,
    headingTo: headingTo ?? this.headingTo,
    lookAhead: lookAhead ?? this.lookAhead,
    lookAheadWeight: lookAheadWeight ?? this.lookAheadWeight,
    baseFovY: baseFovY ?? this.baseFovY,
    fovYPerSpeed: fovYPerSpeed ?? this.fovYPerSpeed,
    maxFov: maxFov ?? this.maxFov,
  );

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
  /// Both in metres per second.
  final double headingFrom;

  /// The speed the swing is complete at, in metres per second.
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
  final double baseFovY;

  /// How much wider it gets per metre per second.
  ///
  /// The cheapest trick in the genre and the one that does the most: speed on a
  /// screen is not how fast the numbers change, it is how fast the edges of the
  /// frame move.
  final double fovYPerSpeed;

  /// The widest it is allowed to get. Past about a fifth of a turn the picture
  /// reads as a fish-eye rather than as speed.
  /// In radians.
  final double maxFov;
}

/// A camera behind a car: behind where it is *going*, looking into the corner.
///
/// **The racing preset of the virtual cameras.** What a racing camera does
/// differently from any other — sitting behind the direction of travel rather
/// than the nose, looking a little way up the track, widening with speed — is
/// `ChaseFraming` in `flutter3d_camera`, and the easing, knocks, shakes
/// and walls are the engine's [CameraRig] under it. What is left here is the
/// part only a racing game knows: reading a [VehicleController] and asking the
/// [TrackSpline] where the road goes. Hand [virtualCamera] to a
/// `CameraDirector` to blend from the chase to a replay shot and back.
///
/// Renderer-free, like the platformer's camera and for the same reason: it
/// answers with two points and a number, and the application copies them into
/// whatever it is drawing with.
final class ChaseCamera {
  ChaseCamera({
    required CollisionWorld world,
    this.track,
    this.tuning = const ChaseSettings(),
    String name = 'chase',
    CameraFraming Function(ChaseFraming preset)? reframe,
  }) : rig = CameraRig(
         world: world,
         nearClearance: tuning.nearClearance,
         minDistance: tuning.minDistance,
       ),
       framing = ChaseFraming(
         distance: tuning.distance,
         height: tuning.height,
         aimHeight: tuning.aimHeight,
         lag: tuning.lag,
         headingBlend: tuning.headingBlend,
         headingFrom: tuning.headingFrom,
         headingTo: tuning.headingTo,
         lookAheadWeight: tuning.lookAheadWeight,
         baseFovY: tuning.baseFovY,
         fovYPerSpeed: tuning.fovYPerSpeed,
         maxFov: tuning.maxFov,
       ) {
    virtualCamera = VirtualCamera(
      name,
      reframe?.call(framing) ?? framing,
      rig: rig,
    );
  }

  final CameraRig rig;

  /// Where the camera wants to be, worked out from what [follow] wrote into
  /// it: the preset this camera is.
  final ChaseFraming framing;

  /// This camera as one of a director's: the [framing] carried out by [rig].
  ///
  /// **Its framing can be replaced.** Pass `reframe` to the constructor and
  /// the camera takes its shots from what that returns, given the chase
  /// preset in [framing]: a framing of the game's own that wraps the preset
  /// and changes what it asks for, or one that ignores it. The preset is
  /// still the one the calls here feed, so a replacement that wraps it
  /// keeps the subject and the look it is given.
  late final VirtualCamera virtualCamera;

  /// The circuit, for looking up the road. Absent on a test plane, and then the
  /// camera looks along the car instead — which is the same thing on a straight.
  final TrackSpline? track;

  final ChaseSettings tuning;

  Vector3 get eye => rig.eye;
  Vector3 get target => rig.target;

  /// The field of view to draw with, in radians. Widened by speed, and by
  /// anything that asked for a kick of it.
  double get fovY => virtualCamera.shot.fovY;

  /// Which way the camera is facing, in radians. What the last frame settled on.
  double get heading => framing.heading;

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
  void cut() => virtualCamera.cut();

  /// Places the camera for a frame.
  ///
  /// Called once a frame with whatever the application is drawing the car at,
  /// rather than once a step: this is presentation, and a camera that moves at
  /// the simulation's rate judders on a faster display even when the car does
  /// not.
  ///
  /// With the camera in a `CameraDirector`, call [aim] instead and let the
  /// director place it.
  void follow(VehicleController car, double dt) {
    aim(car);
    virtualCamera.update(dt);
  }

  /// Hands the car to the framing without placing the camera: for a camera a
  /// `CameraDirector` places in the loop's `camera` phase.
  void aim(VehicleController car) {
    framing
      ..position.setFrom(car.position)
      ..velocity.setFrom(car.velocity)
      ..facing = car.headingYaw
      ..speed = car.speed;

    final circuit = track;
    if (circuit != null) {
      // Towards the road ahead, part of the way. Blended rather than aimed at,
      // for the reason in [ChaseSettings.lookAheadWeight].
      circuit.centerAt(car.trackDistance + tuning.lookAhead, _ahead);
      framing.ahead = _ahead;
    } else {
      framing.ahead = null;
    }
  }

  final Vector3 _ahead = Vector3.zero();
}
