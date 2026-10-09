/// The framings the engine's own games were built from, as presets anybody
/// can take.
///
/// **Each was a game's camera before it was a preset**, and kept that game's
/// numbers and arithmetic exactly, so the game that moved onto the virtual
/// cameras looks the way it did. The names say what a camera does rather than
/// which game it came from: a chase camera suits a boat as well as a car, an
/// orbit a third-person anything, an overhead view any map.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show easeFactor, shortestAngle;
import 'package:vector_math/vector_math.dart';

import 'framing.dart';
import 'shot.dart';

/// Behind where a subject is *going*, looking a little way up the road, and
/// wider the faster it goes.
///
/// * It sits behind a blend of the subject's nose and its direction of
///   travel, which is what makes a slide sideways readable: a camera behind
///   the nose keeps the subject pointing straight up the screen and the slide
///   is invisible.
/// * It looks part of the way towards a point ahead ([ahead]), which opens a
///   corner up before the subject reaches it while keeping the subject the
///   thing being watched.
/// * It widens with speed, which is most of what speed looks like on a
///   screen: speed is how fast the edges of the frame move.
final class ChaseFraming extends CameraFraming {
  /// A chase with these numbers. The defaults are a car's.
  ChaseFraming({
    this.distance = 8.0,
    this.height = 3.0,
    this.aimHeight = 1.0,
    this.lag = 7.0,
    this.headingBlend = 0.75,
    this.headingFrom = 4.0,
    this.headingTo = 14.0,
    this.lookAheadWeight = 0.35,
    this.baseFovY = 1.05,
    this.fovYPerSpeed = 0.006,
    this.maxFov = 1.45,
  });

  /// How far behind the subject the camera sits, in metres.
  final double distance;

  /// How far above the subject the camera sits, in metres.
  final double height;

  /// How far up the subject it looks, in metres.
  final double aimHeight;

  /// How fast the camera closes the gap, as a rate per second.
  @override
  final double lag;

  /// How far the camera swings from behind the nose towards behind the
  /// direction of travel, nought to one. Not all the way: a camera that
  /// ignores the nose stops reporting which way the subject is about to go.
  final double headingBlend;

  /// The speeds the swing starts and is complete at. Below [headingFrom] the
  /// direction of travel is rounding error, and the nose is followed. In
  /// metres a second.
  final double headingFrom;

  /// The speed the swing is complete at, in metres a second.
  final double headingTo;

  /// How much of the way towards [ahead] the aim moves.
  final double lookAheadWeight;

  /// The field of view standing still, how much wider per metre a second, and
  /// the widest it may get, in radians.
  final double baseFovY;

  /// How much wider the field of view gets per metre a second of speed, in
  /// radians.
  final double fovYPerSpeed;

  /// The widest the field of view may get, in radians.
  final double maxFov;

  /// Where the subject is. Written by the game before every update.
  final Vector3 position = Vector3.zero();

  /// How it is moving, in metres a second.
  final Vector3 velocity = Vector3.zero();

  /// Which way its nose points, in radians about the vertical: nought along
  /// plus Z.
  double facing = 0.0;

  /// How fast it is going, in metres a second. Separate from [velocity]
  /// because a game may mean speed along its own path rather than through
  /// the air.
  double speed = 0.0;

  /// A point up the road to look partly towards, or null to look along the
  /// subject — which is the same thing on a straight.
  Vector3? ahead;

  /// Which way the camera is facing, in radians: what the last frame settled
  /// on.
  double get heading => _heading;
  double _heading = 0.0;

  @override
  void frame(CameraShot wanted, double dt) {
    _heading = _headingNow();

    wanted.target
      ..setFrom(position)
      ..y += aimHeight;

    final up = ahead;
    if (up != null) {
      wanted.target
        ..x += (up.x - wanted.target.x) * lookAheadWeight
        ..z += (up.z - wanted.target.z) * lookAheadWeight;
    }

    wanted.eye.setValues(
      position.x - math.sin(_heading) * distance,
      position.y + height,
      position.z - math.cos(_heading) * distance,
    );

    wanted.fovY = math.min(baseFovY + speed * fovYPerSpeed, maxFov);
  }

  double _headingNow() {
    final traveling = math.atan2(velocity.x, velocity.z);
    final reach = ((speed - headingFrom) / (headingTo - headingFrom)).clamp(
      0.0,
      1.0,
    );
    return facing + shortestAngle(facing, traveling) * reach * headingBlend;
  }
}

/// Behind and above a subject, on an orbit the player turns: a third-person
/// camera.
///
/// A yaw the player turns with a mouse or a stick, a pitch they tilt, and the
/// orbit those two describe round the subject. Two things on top make a long
/// level bearable: it drifts back behind the subject once it is moving
/// ([recenter]), and it aims a fraction of a second up the subject's path
/// ([lookAhead]), horizontally only — leading a jump vertically points the
/// camera at the sky and the floor twice a second.
final class OrbitFraming extends CameraFraming {
  /// An orbit with these numbers, starting at [yaw]. The defaults are a
  /// runner's.
  ///
  /// `pitch` and `yaw` are plain parameters copied into private fields, not
  /// `this._pitch`: a private named parameter puts the private name in the
  /// API and needs the newest language version to call.
  OrbitFraming({
    this.distance = 7.0,
    this.height = 2.6,
    this.aimHeight = 1.2,
    this.lag = 9.0,
    double pitch = -0.22,
    this.minPitch = -1.2,
    this.maxPitch = 0.9,
    this.sensitivity = 0.0035,
    this.lookAhead = 0.34,
    this.lookAheadLimit = 4.0,
    this.recenter = 1.6,
    this.recenterAbove = 3.0,
    this.fovY = 1.0,
    double yaw = 0.0,
  }) : _pitch = pitch, // ignore: prefer_initializing_formals
       _yaw = yaw; // ignore: prefer_initializing_formals

  /// How far behind the orbit's middle the camera sits, in metres.
  final double distance;

  /// How far above the orbit's middle the camera sits, in metres.
  final double height;

  /// How far up the subject the orbit's middle is, in metres.
  final double aimHeight;

  /// How fast the camera closes the gap, as a rate per second.
  @override
  final double lag;

  /// The tilt's lower limit, in radians.
  final double minPitch;

  /// The tilt's upper limit, in radians.
  final double maxPitch;

  /// Radians of turn per unit of look delta.
  final double sensitivity;

  /// How far ahead of the subject it aims, in seconds of travel, and the most
  /// that may ever be, in metres.
  final double lookAhead;

  /// The most the aim may lead the subject by, in metres.
  final double lookAheadLimit;

  /// How fast the camera drifts back behind a moving subject, in radians a
  /// second, and how fast the subject has to be going first, in metres a
  /// second. Nought [recenter] never drifts.
  final double recenter;

  /// How fast the subject has to be going before the camera drifts back
  /// behind it, in metres a second.
  final double recenterAbove;

  /// The field of view it asks for, in radians.
  double fovY;

  /// Where the subject is. Written by the game before every update.
  final Vector3 subject = Vector3.zero();

  /// How it is moving, or null when the game does not say — which turns the
  /// drift and the look ahead off.
  Vector3? traveling;

  /// Which way the camera faces, in radians.
  double get yaw => _yaw;
  double _yaw;

  /// How far it tilts, in radians.
  double get pitch => _pitch;
  double _pitch;

  /// Turns the orbit by a look delta from a mouse or a stick.
  void look(Vector2 delta) {
    _yaw -= delta.x * sensitivity;
    _pitch = (_pitch - delta.y * sensitivity).clamp(minPitch, maxPitch);
  }

  @override
  void frame(CameraShot wanted, double dt) {
    final moving = traveling;
    _drift(moving, dt);

    wanted.target
      ..setFrom(subject)
      ..y += aimHeight;
    _aimAhead(wanted.target, moving);

    final cosPitch = math.cos(_pitch);
    wanted.eye.setValues(
      wanted.target.x - math.sin(_yaw) * distance * cosPitch,
      wanted.target.y + height - math.sin(_pitch) * distance,
      wanted.target.z - math.cos(_yaw) * distance * cosPitch,
    );
    wanted.fovY = fovY;
  }

  void _aimAhead(Vector3 target, Vector3? moving) {
    if (moving == null || lookAhead <= 0.0) return;
    var x = moving.x * lookAhead;
    var z = moving.z * lookAhead;
    final reach = math.sqrt(x * x + z * z);
    if (reach > lookAheadLimit) {
      final scale = lookAheadLimit / reach;
      x *= scale;
      z *= scale;
    }
    target
      ..x += x
      ..z += z;
  }

  /// Eases the yaw round towards the way the subject is going, the shortest
  /// way, faster the further over [recenterAbove] it is.
  void _drift(Vector3? moving, double dt) {
    if (moving == null || recenter <= 0.0) return;
    final speed = math.sqrt(moving.x * moving.x + moving.z * moving.z);
    if (speed < recenterAbove) return;

    final wanted = math.atan2(moving.x, moving.z);
    final away = shortestAngle(_yaw, wanted);
    final urgency = ((speed - recenterAbove) / 4.0).clamp(0.0, 1.0);
    _yaw += away * easeFactor(recenter * urgency, dt);
  }
}

/// A view over a map: it pans, it zooms, and it follows nothing.
///
/// It watches a place, the [focus], which moves because a player pushed the
/// view rather than because anything in the world did. The focus rides the
/// ground ([groundHeight]), so a view over a hill is as far above the hill as
/// one over a valley is above the valley, and it is held between [minX],
/// [minZ] and [maxX], [maxZ]: the edge of the ground is the edge of the game. The yaw is fixed, because
/// a map that turns is a map a player has to read again.
final class OverheadFraming extends CameraFraming {
  /// A view over the ground between the corners ([minX], [minZ]) and
  /// ([maxX], [maxZ]), whose height at a point [groundHeight] answers,
  /// watching ([startX], [startZ]) — the middle of the ground when they are
  /// not given.
  OverheadFraming({
    required this.minX,
    required this.minZ,
    required this.maxX,
    required this.maxZ,
    required this.groundHeight,
    double? startX,
    double? startZ,
    this.pitch = 0.95,
    this.minDistance = 12.0,
    this.maxDistance = 90.0,
    this.lag = 12.0,
    this.fovY = 1.0,
  }) : _distance = (minDistance + maxDistance) / 2.0 {
    _focus.setValues(
      startX ?? (minX + maxX) / 2.0,
      0.0,
      startZ ?? (minZ + maxZ) / 2.0,
    );
  }

  /// The corners of the ground, in metres. Plain numbers rather than a
  /// vector, which would round them to single precision.
  final double minX;

  /// The ground's smallest Z, in metres.
  final double minZ;

  /// The ground's largest X, in metres.
  final double maxX;

  /// The ground's largest Z, in metres.
  final double maxZ;

  /// The height of the ground at a point.
  final double Function(double x, double z) groundHeight;

  /// How far the view tilts down from the horizon, in radians.
  final double pitch;

  /// The closest the eye may be to the focus, in metres.
  final double minDistance;

  /// The furthest the eye may be from the focus, in metres.
  final double maxDistance;

  /// How fast the camera closes the gap, as a rate per second.
  @override
  final double lag;

  /// The field of view it asks for, in radians.
  double fovY;

  /// Where the view is pointed, on the ground.
  Vector3 get focus => _focus;
  final Vector3 _focus = Vector3.zero();

  /// How far the eye is from [focus], in metres.
  double get distance => _distance;
  double _distance;

  /// Pushes the view across the map, in metres, held to the ground.
  void pan(double x, double z) {
    _focus
      ..x = (_focus.x + x).clamp(minX, maxX)
      ..z = (_focus.z + z).clamp(minZ, maxZ);
  }

  /// Moves the eye closer to or further from the ground.
  void zoom(double by) {
    _distance = (_distance + by).clamp(minDistance, maxDistance);
  }

  @override
  void frame(CameraShot wanted, double dt) {
    _focus.y = groundHeight(_focus.x, _focus.z);
    wanted.target.setFrom(_focus);

    final double back = Portable.cos(pitch) * _distance;
    final double up = Portable.sin(pitch) * _distance;
    wanted.eye.setValues(_focus.x, _focus.y + up, _focus.z + back);
    wanted.fovY = fovY;
  }
}

/// Out of a head: the eye where the game says, looking where it says.
///
/// No smoothing — a first-person view that lags the mouse is a view that
/// makes people ill — and no pulling out of walls, because the eye is inside
/// a body the physics already keeps out of them. What the virtual camera
/// still adds is what a head feels: a kick, a shake, a widening, and a blend
/// when the view leaves the head for another camera and comes back.
final class FirstPersonFraming extends CameraFraming {
  /// A first-person view [fovY] radians wide.
  FirstPersonFraming({this.fovY = 1.0});

  /// Where the eye is. Written by the game before every update.
  final Vector3 eye = Vector3.zero();

  /// Which way it looks, a unit vector. Written by the game before every
  /// update.
  final Vector3 direction = Vector3(0.0, 0.0, -1.0);

  /// The field of view it asks for, in radians.
  double fovY;

  /// Infinite, as a rate per second: the eye goes where it is put, with
  /// no smoothing.
  @override
  double get lag => double.infinity;

  @override
  void frame(CameraShot wanted, double dt) {
    wanted.eye.setFrom(eye);
    wanted.target
      ..setFrom(eye)
      ..add(direction);
    wanted.fovY = fovY;
  }
}
