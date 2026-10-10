import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// The camera a paused game hands the player for taking a picture — `N8`.
///
/// Flown rather than chased: it has a position, a heading, a pitch, a roll and
/// a field of view, and nothing it watches. What makes it more than a debug
/// fly-camera is where it is **not allowed to go**, which is the whole of the
/// design.
///
/// ## Held inside the level, three ways
///
/// * **On a tether** of [reach] metres from [anchor] — where the player was
///   standing when photo mode opened. A camera that can fly anywhere shows the
///   back of every wall, the skybox seam and the half-built room past the end
///   of the level, and a player who posts that has posted a bug report.
/// * **Inside [bounds]**, when the game has them — the level's own box, so the
///   tether cannot reach under the floor of a level built on a slab.
/// * **Out of the walls**: every move is a sweep of a small box through the
///   collision world against [wallMask], sliding along what it meets the way
///   the player does. The tether alone would stop at the right distance on the
///   wrong side of a wall.
///
/// The first two together are a sphere cut by a box, which is convex, and that
/// is what makes the third safe to combine with them: from a point inside the
/// region, a straight line to another point inside it never leaves it. The
/// target of every move is pulled into the region first and then swept to.
/// A slide along one wall only pushes the point back towards the side it came
/// from, which keeps it inside; the skin step off each wall and a corner of
/// three faces are not held by that argument, so a slid point is checked, and
/// one that has left the region is thrown away and the move made again
/// straight, stopping short at the first wall.
///
/// **Not in the step, and not in `Portable` maths.** The simulation is paused
/// while this flies, and nothing it does reaches a snapshot or a tape. A
/// photo is the one camera in a game that is allowed to be non-deterministic.
final class PhotoCamera {
  PhotoCamera({
    required this.world,
    this.reach = 12.0,
    this.bounds,
    this.radius = 0.2,
    this.wallMask = CollisionLayers.world,
    this.speed = 4.0,
    this.minFieldOfView = 0.17,
    this.maxFieldOfView = 1.75,
    this.maxRoll = math.pi / 4.0,
  }) : assert(reach > 0.0, 'a tether is a distance'),
       assert(radius > 0.0, 'a camera with no size touches nothing'),
       assert(
         minFieldOfView > 0.0 && maxFieldOfView > minFieldOfView,
         'a zoom range runs from a narrow view to a wider one',
       );

  /// Where the walls are.
  final CollisionWorld world;

  /// How far from [anchor] the camera may go, in metres.
  final double reach;

  /// The level's own box, or null where the game has none to give.
  final Aabb3? bounds;

  /// Half the side of the box swept through the world, in metres. A near
  /// plane has to stay this far in front of a wall or it cuts into it.
  final double radius;

  /// Which layers stop the camera.
  final int wallMask;

  /// Metres a second at full stick.
  final double speed;

  /// How far [zoom] may go each way, in radians of vertical field of view —
  /// about ten degrees to a hundred.
  final double minFieldOfView;

  /// The widest [zoom] may go, in radians of vertical field of view.
  final double maxFieldOfView;

  /// How far the horizon may be tilted either way, in radians. Past
  /// forty-five degrees a
  /// picture stops reading as tilted and starts reading as rotated.
  final double maxRoll;

  final Vector3 _anchor = Vector3.zero();
  final Vector3 _eye = Vector3.zero();
  double _yaw = 0.0;
  double _pitch = 0.0;
  double _roll = 0.0;
  double _fieldOfView = 0.9;

  /// Where the player was when this began; the centre of the tether.
  Vector3 get anchor => _anchor;

  /// Where the camera is.
  Vector3 get eye => _eye;

  /// Heading about +Y, in radians; zero looks down −Z.
  double get yaw => _yaw;

  /// In radians; up is positive, held short of straight up or down, where heading stops
  /// meaning anything and `lookAt` has no way to tell which way is up.
  double get pitch => _pitch;

  /// Tilt of the horizon, in radians; positive leans the top of the camera to the right.
  double get roll => _roll;

  /// Vertical field of view, in radians.
  double get fieldOfView => _fieldOfView;

  /// The unit vector the camera looks along.
  Vector3 get forward => Vector3(
    -math.sin(_yaw) * math.cos(_pitch),
    math.sin(_pitch),
    -math.cos(_yaw) * math.cos(_pitch),
  );

  /// A point one metre ahead, for `CameraNode.lookAt`.
  Vector3 get target => _eye + forward;

  /// The camera's up, turned by [roll] — the vector `lookAt` wants.
  Vector3 get up {
    final ahead = forward;
    final right = ahead.cross(Vector3(0.0, 1.0, 0.0))..normalize();
    final level = right.cross(ahead)..normalize();
    return level * math.cos(_roll) + right * math.sin(_roll);
  }

  /// Takes over from the game's own camera, wherever it was.
  ///
  /// [anchor] is the tether's centre — the player, not the camera: a chase
  /// camera already sits several metres back, and a tether centred on it lets
  /// the player see a little less on one side of themselves than the other.
  ///
  /// **The eye is reached from the anchor, not set.** A chase camera can be
  /// further out than [reach], and a third-person camera pulled in by a wall
  /// can be half a centimetre from it; either way the starting point is swept
  /// to from where the player stands, so it begins inside the region and out of
  /// the walls like every point after it.
  void begin({
    required Vector3 eye,
    required Vector3 target,
    required Vector3 anchor,
    double? fieldOfView,
  }) {
    _anchor.setFrom(anchor);
    final ahead = target - eye;
    if (ahead.length2 > 1e-12) {
      ahead.normalize();
      _yaw = math.atan2(-ahead.x, -ahead.z);
      _pitch = _clampPitch(math.asin(ahead.y.clamp(-1.0, 1.0)));
    }
    _roll = 0.0;
    if (fieldOfView != null) {
      _fieldOfView = fieldOfView.clamp(minFieldOfView, maxFieldOfView);
    }
    _eye.setFrom(_anchor);
    _sweepStraight(_eye, _allowed(eye) - _eye);
  }

  /// Turns the camera by [yaw] and [pitch] radians.
  void look(double yaw, double pitch) {
    _yaw += yaw;
    _pitch = _clampPitch(_pitch + pitch);
  }

  /// Tilts the horizon by [radians], within [maxRoll].
  void tilt(double radians) =>
      _roll = (_roll + radians).clamp(-maxRoll, maxRoll);

  /// Narrows the view by [factor] — above one zooms in.
  void zoom(double factor) {
    if (factor <= 0.0) return;
    _fieldOfView = (_fieldOfView / factor).clamp(
      minFieldOfView,
      maxFieldOfView,
    );
  }

  /// Flies for [dt] seconds along [intent], in the camera's own axes: x to the
  /// right, y up the world, z forward. A length above one is cut to one.
  ///
  /// **Up is the world's, not the camera's.** A camera pitched down that rose
  /// along its own up would drift backwards as it climbed, and a player
  /// lining up a shot reads that as the controls fighting them.
  ///
  /// Returns whether anything held the camera back — a wall, the tether or the
  /// level's box — so a game can say why the camera stopped.
  bool fly(Vector3 intent, double dt) {
    final length = intent.length;
    if (length == 0.0 || dt <= 0.0) return false;
    final scale = speed * dt / math.max(1.0, length);
    final ahead = Vector3(-math.sin(_yaw), 0.0, -math.cos(_yaw));
    final right = Vector3(math.cos(_yaw), 0.0, -math.sin(_yaw));
    final delta =
        (right * intent.x +
              Vector3(0.0, intent.y, 0.0) +
              (ahead * math.cos(_pitch) + Vector3(0.0, math.sin(_pitch), 0.0)) *
                  intent.z)
          ..scale(scale);
    return moveBy(delta);
  }

  /// Moves the eye by [delta] in world space, held inside the level.
  ///
  /// Returns whether anything held it back.
  bool moveBy(Vector3 delta) {
    final wanted = _eye + delta;
    final allowed = _allowed(wanted);
    final clipped = allowed.distanceToSquared(wanted) > 1e-12;

    final slid = _eye.clone();
    final blocked = _slide(slid, allowed - _eye);
    if (_isAllowed(slid)) {
      _eye.setFrom(slid);
      return clipped || blocked;
    }
    // The slide carried the move out of the region. Straight is inside it, by
    // convexity; see the class comment.
    _sweepStraight(_eye, allowed - _eye);
    return true;
  }

  double _clampPitch(double pitch) => pitch.clamp(-1.5, 1.5);

  /// [point] pulled into the tether and the box.
  Vector3 _allowed(Vector3 point) {
    final out = point.clone();
    final box = bounds;
    if (box != null) {
      out
        ..x = out.x.clamp(box.min.x + radius, box.max.x - radius)
        ..y = out.y.clamp(box.min.y + radius, box.max.y - radius)
        ..z = out.z.clamp(box.min.z + radius, box.max.z - radius);
    }
    final away = out - _anchor;
    final distance = away.length;
    if (distance > reach) {
      out
        ..setFrom(_anchor)
        ..addScaled(away, reach / distance);
    }
    return out;
  }

  bool _isAllowed(Vector3 point) =>
      _allowed(point).distanceToSquared(point) <= _tolerance * _tolerance;

  /// The few millimetres a skin step off a wall may carry the eye past the
  /// tether. Below anything that could take it through a wall.
  static const double _tolerance = 0.01;

  static const double _skin = 0.001;

  late final CollisionShape _shape = CollisionSphere(radius);
  final SweepHit _hit = SweepHit();

  /// The character controller's slide, three passes for a room's corner.
  bool _slide(Vector3 point, Vector3 delta) {
    var blocked = false;
    for (var pass = 0; pass < 3; pass++) {
      if (delta.length2 == 0.0) break;
      if (!world.sweep(_shape, point, delta, _hit, mask: wallMask)) {
        point.add(delta);
        break;
      }
      blocked = true;
      final travel = math.max(0.0, _hit.fraction);
      point
        ..addScaled(delta, travel)
        ..addScaled(_hit.normal, _skin);
      delta.scale(1.0 - travel);
      final into = delta.dot(_hit.normal);
      if (into < 0.0) delta.addScaled(_hit.normal, -into);
    }
    return blocked;
  }

  /// One sweep, no slide: the move stops where it meets something.
  void _sweepStraight(Vector3 point, Vector3 delta) {
    if (delta.length2 == 0.0) return;
    if (!world.sweep(_shape, point, delta, _hit, mask: wallMask)) {
      point.add(delta);
      return;
    }
    point
      ..addScaled(delta, math.max(0.0, _hit.fraction))
      ..addScaled(_hit.normal, _skin);
  }
}
