import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import '../math/motion.dart';
import '../physics/layers.dart';

/// The part of a chasing camera that every chasing camera has.
///
/// Not a camera. It has no idea where it wants to be — a caller works that out,
/// from a heading and a pitch in one game and from a car's speed and the track
/// ahead in another — and hands it over. What lives here is everything after
/// that: easing towards it without overshooting, carrying knocks and shakes
/// that fade, and staying out of the walls.
///
/// **Composed rather than inherited from.** A base class would have had to
/// carry the platformer's yaw and pitch, which a car does not have, or the
/// racing camera's track distance, which a runner does not — and a base class
/// that knows about both is the engine learning what a lap is.
///
/// ## The ordering is the point
///
/// [place] does five things in an order that took a property test to get right,
/// which is why it is one method and not five. In particular the wall check runs
/// **on both sides of the impulses**, and both are needed: before, so that a
/// knock is added to a camera already where it belongs rather than to one
/// halfway inside a wall; after, because a knock is a displacement like any
/// other and a camera inside a brush is the one thing this exists to prevent.
/// Three hundred random impulses in a boxed room found it half a metre into the
/// wall behind the player.
final class CameraRig {
  CameraRig({
    required this.world,
    this.impulseDecay = 9.0,
    this.nearClearance = 0.35,
    this.minDistance = 1.2,
    this.wallMask = CollisionLayers.world,
  });

  /// Where the walls are, for keeping the camera out of them.
  final CollisionWorld world;

  /// How fast a kick, a widening and a shake fade, per second.
  final double impulseDecay;

  /// How far in front of a wall the camera stops.
  final double nearClearance;

  /// How close to what it is watching the camera may be pulled before giving up.
  final double minDistance;

  /// Which layers count as something to be kept out of.
  final int wallMask;

  final Vector3 _eye = Vector3.zero();
  final Vector3 _target = Vector3.zero();
  bool _placed = false;

  /// Where the camera is. Valid after the first [place].
  /// Where the camera is this frame, walls and impulses and all.
  ///
  /// **Not the same vector as the one being smoothed**, and that separation is
  /// the whole of what stops the camera oscillating — see [place].
  Vector3 get eye => _shown;

  /// Where the camera would be with nothing in the way and nothing shaking it.
  ///
  /// The smoothed state, and the *only* thing [place] eases. Exposed because a
  /// test that wants to know whether the camera has settled has to ask about
  /// this and not about what came out the other end.
  Vector3 get freeEye => _eye;

  /// What [eye] hands back: the free eye, plus the impulses, pulled out of the
  /// walls. Rebuilt from scratch every frame, which is why nothing it does can
  /// accumulate.
  final Vector3 _shown = Vector3.zero();

  /// What it is looking at.
  Vector3 get target => _target;

  /// A knock, in metres, that decays away. The camera's own recoil.
  final Vector3 _kick = Vector3.zero();

  double _shake = 0.0;
  double _shakeTime = 0.0;
  double _shakeSeconds = 0.0;

  /// How much of the camera's **involuntary** movement the player asked for,
  /// from nought to one.
  ///
  /// A setting rather than a constant because a camera that moves by itself
  /// makes some people ill, and a game that cannot be turned down is a game they
  /// cannot play. Zero is not "broken", it is "off".
  ///
  /// **This was `shakeScale` and covered only the shake**, which was half the
  /// accommodation: a landing that knocks the camera down and a dash that widens
  /// the view move it just as involuntarily, and a player who turned the shake
  /// off still got both. It is one knob rather than three because it is one
  /// question — *how much should the camera move on its own* — and three would
  /// have been three sliders asking it.
  ///
  /// What is **not** scaled is the following. A camera chasing a runner is the
  /// game; the flinches are an effect on top of it. Turning this to nought
  /// leaves the same game in a camera that no longer flinches.
  ///
  /// Nought rather than a bool because the middle is real: plenty of people want
  /// a quarter of it rather than none. Games save it as `a11y.cameraMotion` —
  /// see `GameConfig.settings`.
  double motion = 1.0;

  /// Extra field of view, in radians, that decays away. Read by whoever owns
  /// the projection.
  double get extraFov => _fov;
  double _fov = 0.0;

  /// Whether the camera has been put anywhere yet.
  bool get isPlaced => _placed;

  /// Knocks the camera along [direction] by its length, in metres.
  ///
  /// For a landing, or a car meeting a wall: a dip the size of the impact, gone
  /// in a quarter of a second.
  void kick(Vector3 direction) {
    if (motion <= 0.0) return;
    _kick.add(direction * motion);
  }

  /// Shakes the camera for [seconds], [amount] metres wide.
  void shake(double amount, {double seconds = 0.35}) {
    if (motion <= 0.0) return;
    _shake = math.max(_shake, amount * seconds * motion);
    _shakeSeconds = math.max(_shakeSeconds, seconds);
  }

  /// Widens the view by [radians], which decays back. For speed, a dash, a
  /// boost.
  void widen(double radians) => _fov = math.max(_fov, radians * motion);

  /// Puts the camera where it should be for this frame.
  ///
  /// [lag] is how much of the remaining gap is closed in a second. Exponential
  /// rather than a fixed speed, so it is frame-rate independent and so it never
  /// overshoots — a camera that oscillates around what it is watching is a
  /// camera that makes people ill.
  void place({
    required Vector3 desiredEye,
    required Vector3 desiredTarget,
    required double lag,
    required double dt,
  }) {
    _target.setFrom(desiredTarget);

    if (!_placed) {
      // The first frame is a cut, not a chase. Easing in from wherever the
      // vectors happened to start means the game begins with the camera flying
      // across the level.
      _eye.setFrom(desiredEye);
      _shown.setFrom(desiredEye);
      _placed = true;
    } else {
      final t = easeFactor(lag, dt);
      _eye
        ..x += (desiredEye.x - _eye.x) * t
        ..y += (desiredEye.y - _eye.y) * t
        ..z += (desiredEye.z - _eye.z) * t;
    }

    // **Everything below writes to [_shown] and nothing writes to [_eye].**
    //
    // It used to write to `_eye`, and that is what made a still camera jitter:
    // `keepOutOfWalls` pulled the eye in to three metres, the smoother spent
    // the next frame easing from three back towards six, the wall pulled it in
    // again, and the picture bounced by whatever fraction of the gap the lag
    // closes — measured at a hundred and eighty millimetres a frame, standing
    // perfectly still, at twenty-seven places in the teaching level. It reads
    // as the player being drawn twice, and it was reported as exactly that.
    //
    // The rule the fix comes from: **a constraint is not a state.** What is
    // smoothed is where the camera wants to be; where it is allowed to be is
    // worked out afresh from that, every frame, and thrown away.
    _decay(dt);
    _shown.setFrom(_eye);
    _shown.add(_kick);
    if (_shake > 0.0) {
      _shown
        ..x += math.sin(_shakeTime * 47.0) * _shake
        ..y += math.sin(_shakeTime * 39.0 + 1.7) * _shake
        ..z += math.sin(_shakeTime * 53.0 + 3.1) * _shake;
    }

    // Last, so that nothing after it can put the camera back inside a brush —
    // which is what the two calls this replaced were reaching for.
    keepOutOfWalls();
  }

  void _decay(double dt) {
    _shakeTime += dt;
    final gone = easeFactor(impulseDecay, dt);
    _kick.scale(1.0 - gone);
    _fov *= 1.0 - gone;
    if (_shakeSeconds > 0.0) {
      _shake = math.max(0.0, _shake - dt * _shake / _shakeSeconds - 1e-4);
    }
  }

  /// Pulls the camera in until the line from what it watches to it is clear.
  ///
  /// A ray out from the target rather than a sweep of the camera's shape: the
  /// camera has no shape, and what matters is that the player can see the thing
  /// the camera is for. [nearClearance] is what stops the near plane from
  /// clipping into the wall it stopped against.
  void keepOutOfWalls() {
    final toEye = _shown - _target;
    final reach = toEye.length;
    if (reach <= 1e-4) return;
    toEye.scale(1.0 / reach);

    final hit = RayHit();
    if (!world.raycast(_target, toEye, reach, hit, mask: wallMask)) return;

    final pulled = math.max(minDistance, hit.distance - nearClearance);
    _shown
      ..setFrom(_target)
      ..addScaled(toEye, pulled);
  }

  /// Forgets where the camera was, so the next [place] is a cut.
  ///
  /// For a respawn, or the start of a lap: easing from where the player died to
  /// where they came back is a second of the level flying past for no reason.
  /// Clears the impulses too — a camera that arrives still shaking from the
  /// crash is a camera reporting an event that has been undone.
  void cut() {
    _placed = false;
    _kick.setZero();
    _shake = 0.0;
    _fov = 0.0;
  }
}
