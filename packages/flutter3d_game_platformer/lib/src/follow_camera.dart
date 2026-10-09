import 'package:flutter3d_camera/flutter3d_camera.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

/// How the camera trails the runner.
final class FollowSettings extends RigSettings {
  const FollowSettings({
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
    this.lookAhead = 0.34,
    this.lookAheadLimit = 4.0,
    this.recenter = 1.6,
    this.recenterAbove = 3.0,
  });

  /// A copy with the given fields replaced.
  @override
  FollowSettings copyWith({
    double? distance,
    double? height,
    double? aimHeight,
    double? lag,
    double? nearClearance,
    double? minDistance,
    double? pitch,
    double? minPitch,
    double? maxPitch,
    double? sensitivity,
    double? impulseDecay,
    double? lookAhead,
    double? lookAheadLimit,
    double? recenter,
    double? recenterAbove,
  }) => FollowSettings(
    distance: distance ?? this.distance,
    height: height ?? this.height,
    aimHeight: aimHeight ?? this.aimHeight,
    lag: lag ?? this.lag,
    nearClearance: nearClearance ?? this.nearClearance,
    minDistance: minDistance ?? this.minDistance,
    pitch: pitch ?? this.pitch,
    minPitch: minPitch ?? this.minPitch,
    maxPitch: maxPitch ?? this.maxPitch,
    sensitivity: sensitivity ?? this.sensitivity,
    impulseDecay: impulseDecay ?? this.impulseDecay,
    lookAhead: lookAhead ?? this.lookAhead,
    lookAheadLimit: lookAheadLimit ?? this.lookAheadLimit,
    recenter: recenter ?? this.recenter,
    recenterAbove: recenterAbove ?? this.recenterAbove,
  );

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
  final double recenter;

  /// How fast the runner must be going before the camera drifts, in m/s.
  ///
  /// A standing runner is being looked *at*, and turning the camera round
  /// somebody who is not going anywhere is the camera deciding where the player
  /// should be looking. Above a walk, the direction of travel is the thing
  /// worth seeing.
  final double recenterAbove;

  /// The starting tilt and the range it may tilt through, in radians; negative
  /// looks down.
  final double pitch;

  /// The lowest tilt, in radians.
  final double minPitch;

  /// The highest tilt, in radians.
  final double maxPitch;

  /// Radians of turn per unit of look delta.
  final double sensitivity;

  /// How fast a kick, a widening and a shake fade, per second.
  final double impulseDecay;

  /// How far ahead of the runner the camera aims, in seconds of travel.
  ///
  /// **The camera watched where the runner was.** It followed a point on the
  /// body, so a player sprinting right saw the same amount of level ahead of
  /// them as behind — and a platformer is about what is coming. Aiming a
  /// fraction of a second up the road puts the landing on screen before the
  /// jump has to be committed to.
  ///
  /// In seconds rather than metres, so it widens by itself as the runner
  /// speeds up: a walk needs almost none of this and a sprint needs all of it,
  /// and a fixed distance is wrong at one end or the other.
  ///
  /// A third of a second is about two metres at a sprint. Zero is the old
  /// behaviour exactly.
  final double lookAhead;

  /// How far ahead it may ever aim, in metres.
  ///
  /// The limit that stops a spring or a long fall — where the runner is moving
  /// far faster than it ever runs — from throwing the camera off the level
  /// entirely.
  final double lookAheadLimit;
}

/// A third-person camera: behind the runner, above it, out of the walls.
///
/// **The platformer's preset of the virtual cameras.** A yaw the player turns
/// with the mouse, a pitch they tilt, the orbit those two describe round the
/// runner, the drift back behind it and the aim up its path are `OrbitFraming`
/// in `flutter3d_camera`; easing without overshoot, knocks and shakes
/// that fade and staying out of the walls are the engine's [CameraRig] under
/// it. This class is the runner's side of that: the numbers in [FollowSettings]
/// and the call a frame. Hand [virtualCamera] to a `CameraDirector` to blend to
/// a cutscene's shot and back.
///
/// Nothing here knows what a renderer is: it answers with two points and a
/// number, and the application copies them into whatever it is drawing with.
final class FollowCamera {
  FollowCamera({
    required this.world,
    this.tuning = const FollowSettings(),
    double yaw = 0.0,
    String name = 'follow',
    CameraFraming Function(OrbitFraming preset)? reframe,
  }) : rig = CameraRig(
         world: world,
         impulseDecay: tuning.impulseDecay,
         nearClearance: tuning.nearClearance,
         minDistance: tuning.minDistance,
       ),
       framing = OrbitFraming(
         distance: tuning.distance,
         height: tuning.height,
         aimHeight: tuning.aimHeight,
         lag: tuning.lag,
         pitch: tuning.pitch,
         minPitch: tuning.minPitch,
         maxPitch: tuning.maxPitch,
         sensitivity: tuning.sensitivity,
         lookAhead: tuning.lookAhead,
         lookAheadLimit: tuning.lookAheadLimit,
         recenter: tuning.recenter,
         recenterAbove: tuning.recenterAbove,
         yaw: yaw,
       ) {
    virtualCamera = VirtualCamera(
      name,
      reframe?.call(framing) ?? framing,
      rig: rig,
    );
  }

  /// Where the walls are, for keeping the camera out of them.
  final CollisionWorld world;

  final FollowSettings tuning;

  /// The shared half: where the camera actually is, and everything that gets it
  /// there.
  final CameraRig rig;

  /// Where the camera wants to be: the orbit, turned by [look] and fed by
  /// [follow].
  final OrbitFraming framing;

  /// This camera as one of a director's: the [framing] carried out by [rig].
  ///
  /// **Its framing can be replaced.** Pass `reframe` to the constructor and
  /// the camera takes its shots from what that returns, given the orbit
  /// preset in [framing]: a framing of the game's own that wraps the preset
  /// and changes what it asks for, or one that ignores it. The preset is
  /// still the one the calls here feed, so a replacement that wraps it
  /// keeps the subject and the look it is given.
  late final VirtualCamera virtualCamera;

  /// Which way the camera faces, in radians. The runner takes this as the
  /// direction "forward" means.
  double get yaw => framing.yaw;

  /// How far it tilts, in radians.
  double get pitch => framing.pitch;

  /// Where the camera is. Valid after the first [follow].
  Vector3 get eye => rig.eye;

  /// What it is looking at.
  Vector3 get target => rig.target;

  /// How much of the camera's involuntary movement to keep — see
  /// [CameraRig.motion]. Was `shakeScale`, and covered only the shake.
  double get motion => rig.motion;
  set motion(double value) => rig.motion = value;

  /// Extra field of view, in radians, that decays away. Read by the
  /// application, which owns the projection.
  double get extraFovY => rig.extraFovY;

  /// Knocks the camera along [direction] by its length, in metres.
  ///
  /// For a landing: a dip the size of the impact, gone in a quarter of a
  /// second.
  void kick(Vector3 direction) => rig.kick(direction);

  /// Shakes the camera for [seconds], [amount] metres wide.
  void shake(double amount, {double seconds = 0.35}) =>
      rig.shake(amount, seconds: seconds);

  /// Widens the view by [radians], which decays back. For speed and a dash.
  void widen(double radians) => rig.widen(radians);

  /// Turns the camera by a look delta from a mouse or a stick.
  void look(Vector2 delta) => framing.look(delta);

  /// Places the camera for a frame, given where the runner is.
  ///
  /// Called once a frame with the *interpolated* position rather than once a
  /// step with the simulated one: this is presentation, and a camera that
  /// steps at 60 Hz on a 120 Hz display judders even when the runner does not.
  ///
  /// With the camera in a `CameraDirector`, call [aim] instead and let the
  /// director place it.
  void follow(Vector3 runner, double dt, {Vector3? traveling}) {
    aim(runner, traveling: traveling);
    virtualCamera.update(dt);
  }

  /// Hands the runner to the framing without placing the camera: for a camera
  /// a `CameraDirector` places in the loop's `camera` phase.
  void aim(Vector3 runner, {Vector3? traveling}) {
    framing.subject.setFrom(runner);
    framing.traveling = traveling;
  }

  /// Puts the camera behind the runner at once, without a chase.
  ///
  /// For a respawn: easing from where the player died to where they came back
  /// is a second of the level flying past for no reason.
  void cut() => virtualCamera.cut();
}
