import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// A camera that goes where it is told and stops for nothing.
///
/// **Not [CameraRig], and not because the rig is wrong.** Every camera in this
/// repository follows something and is kept out of walls, which is right for
/// all three games and exactly wrong here: the thing an editor most needs to
/// look at is the inside of a wall, from where the wall is. A camera that
/// pushed itself out of geometry would be a camera that cannot be flown to the
/// brush somebody wants to move.
final class FlyCamera {
  FlyCamera({Vector3? at, this.yaw = 0.0, this.pitch = 0.0})
      : position = at?.clone() ?? Vector3(0.0, 1.7, 8.0);

  final Vector3 position;

  /// Where it is looking, about the vertical.
  double yaw;

  /// And how far up or down. Clamped a little short of straight up, because at
  /// exactly vertical the horizontal direction stops existing and the camera
  /// rolls.
  double pitch;

  /// Metres per second, and the reason there are two: a level is a hundred
  /// metres across and a brush is two, so one speed is either a crawl across
  /// the level or an overshoot at the brush.
  double speed = 12.0;
  double fastSpeed = 48.0;

  /// Radians per pixel of mouse movement.
  double sensitivity = 0.0032;

  static const double _limit = math.pi / 2 - 0.02;

  final Vector3 _forward = Vector3(0.0, 0.0, -1.0);
  final Vector3 _right = Vector3(1.0, 0.0, 0.0);
  final Vector3 _up = Vector3(0.0, 1.0, 0.0);
  final Vector3 _ground = Vector3(0.0, 0.0, -1.0);

  /// Which way it is looking. Recomputed by [step]; do not write to it.
  ///
  /// This is what a click is traced along; [ground] is what W walks along.
  Vector3 get forward => _forward;

  /// Which way it is facing, with the tilt taken out.
  Vector3 get ground => _ground;
  Vector3 get right => _right;
  Vector3 get up => _up;

  /// Turns by a mouse movement in pixels.
  void look(Vector2 delta) {
    yaw -= delta.x * sensitivity;
    pitch = (pitch - delta.y * sensitivity).clamp(-_limit, _limit);
  }

  /// Moves for [dt] seconds, given what is held.
  ///
  /// **Along the ground, not along the view, and that is the whole difference
  /// between a camera somebody can use and one they cannot.** A fly camera
  /// moves where it looks; look down at the floor to see what you are about to
  /// move and the next press of W puts you underneath the level. The first
  /// person to try this got exactly that — "I am looking at the floor and W
  /// flies me through it" — and it is not a preference: in a corridor you look
  /// at things and walk past other things, and those are two different
  /// directions.
  ///
  /// So the horizontal keys keep the height they were at, and the vertical pair
  /// are absolute: Q and E go straight down and up whatever the camera is
  /// looking at. Nothing here stops at a wall — see the note on the class about
  /// why an editor's camera goes into geometry on purpose.
  void step(
    double dt,
    InputState input, {
    required GameAction forward,
    required GameAction back,
    required GameAction left,
    required GameAction right,
    required GameAction down,
    required GameAction up,
    required GameAction fast,
  }) {
    _rebuild();
    final metres = (input.held(fast) ? fastSpeed : speed) * dt;
    void go(Vector3 axis, double amount) =>
        position.addScaled(axis, amount * metres);

    if (input.held(forward)) go(_ground, 1.0);
    if (input.held(back)) go(_ground, -1.0);
    if (input.held(right)) go(_right, 1.0);
    if (input.held(left)) go(_right, -1.0);
    if (input.held(up)) position.y += metres;
    if (input.held(down)) position.y -= metres;
  }

  /// Puts [node] where this camera is and points it the same way.
  void placeOn(CameraNode node) {
    _rebuild();
    node
      ..setPosition(position.x, position.y, position.z)
      ..lookAt(position + _forward, up: Vector3(0.0, 1.0, 0.0));
  }

  void _rebuild() {
    final cosPitch = math.cos(pitch);
    _forward.setValues(
      math.sin(yaw) * cosPitch,
      math.sin(pitch),
      -math.cos(yaw) * cosPitch,
    );
    _forward.normalize();
    // **`forward × up`, and the sign is not a detail.** Written the other way
    // round this is a camera whose right is left: strafing goes the wrong way,
    // and — because the up vector is built from it — a click ray comes out
    // rotated a half turn, so pointing at a wall selects whatever is behind
    // you. Every test this file had passed anyway, because each one asked
    // about a property the mirrored vectors also have: that the horizon stays
    // level, that the length is one, that strafing does not change height.
    //
    // Across the world's up rather than the camera's, so the horizon stays
    // level: a right vector built from the tilted up rolls the whole view as
    // soon as the camera looks anywhere but straight ahead.
    _right
      ..setValues(-_forward.z, 0.0, _forward.x)
      ..normalize();
    _up
      ..setFrom(_right.cross(_forward))
      ..normalize();
    // Straight ahead at this heading, level with the floor. Falls back to the
    // last one when the camera is looking exactly up or down, where "ahead"
    // horizontally is not a thing the view can answer.
    _ground.setValues(_forward.x, 0.0, _forward.z);
    if (_ground.length2 > 1e-9) {
      _ground.normalize();
    } else {
      _ground.setValues(math.sin(yaw), 0.0, -math.cos(yaw));
    }
  }
}
