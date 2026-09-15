import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// A body that walks a level: it collides, jumps and runs, turns where it is
/// dragged, and carries a camera at eye height.
///
/// **The base a game starts from, before it is any genre.**
/// `packages/flutter3d_game/example` wrote this out in its own `main.dart`,
/// and every project scaffolded from it got a copy: the spawn lifted off the
/// floor, the wish direction turned by the yaw, the pitch kept short of
/// straight up. None of it belongs to one kind of game, and a game that wants a
/// different body replaces this rather than editing it.
///
/// It reads an [InputState] and writes a [CameraNode]; how the input arrived
/// and how the frame is drawn are somebody else's.
final class LevelWalk {
  LevelWalk({
    required CollisionWorld world,
    required Vector3 at,
    this.yaw = 0.0,
    this.eyeHeight = 0.7,
    this.lookSpeed = 0.0032,
  }) : body = CharacterController(world: world, position: at);

  /// Where the author said somebody stands, lifted by [lift], and which way
  /// they face.
  ///
  /// A spawn is authored at the feet, which is the only place an author can
  /// see, and a body put there starts inside the floor. The first entity whose
  /// type names a spawn wins; a level with none starts at the origin.
  static ({Vector3 at, double yaw}) spawnIn(Level level, {double lift = 0.9}) {
    final spawn = level.entities
        .where((EntityDef it) => it.type.contains('spawn'))
        .firstOrNull;
    return (
      at: (spawn?.position ?? Vector3.zero()) + Vector3(0.0, lift, 0.0),
      yaw: spawn?.yaw ?? 0.0,
    );
  }

  /// How far the eye may look up or down, in radians: short of straight up,
  /// where a view has no forward left to be built from.
  static const double pitchLimit = 1.5;

  /// The body that collides with the level.
  final CharacterController body;

  /// How far above the body's centre the eye is.
  final double eyeHeight;

  /// Radians turned per logical pixel dragged.
  final double lookSpeed;

  /// Which way the body faces, in radians about world up; nought looks down -Z.
  double yaw;

  /// How far the eye looks up (positive) or down, in radians.
  double pitch = 0.0;

  /// Where [axis] — sideways, then forwards — asks to go, turned by [yaw] and
  /// kept level: looking at the floor while walking forwards does not walk
  /// into it.
  Vector3 wishFor(Vector2 axis) {
    final forward = Vector3(math.sin(yaw), 0.0, -math.cos(yaw));
    final right = Vector3(-forward.z, 0.0, forward.x);
    return Vector3(
      forward.x * axis.y + right.x * axis.x,
      0.0,
      forward.z * axis.y + right.z * axis.x,
    );
  }

  /// One frame of walking: a jump if one was pressed, the wish from the move
  /// axis, and a run while sprint is held.
  ///
  /// [dt] is clamped to a tenth of a second, so a frame that stalled moves the
  /// body a tenth of a second's worth rather than the whole stall's.
  void step(double dt, InputState input) {
    if (input.pressed(GameAction.jump)) body.requestJump();
    body.step(
      dt.clamp(0.0, 0.1),
      wishDirection: wishFor(input.moveAxis),
      sprint: input.held(GameAction.sprint),
    );
  }

  /// Turns the view by a drag of [dx] and [dy] logical pixels.
  void look(double dx, double dy) {
    yaw -= dx * lookSpeed;
    pitch = (pitch - dy * lookSpeed).clamp(-pitchLimit, pitchLimit);
  }

  /// Puts [camera] at eye height above the body, looking where [yaw] and
  /// [pitch] point.
  void placeCamera(CameraNode camera) {
    final eye = body.position + Vector3(0.0, eyeHeight, 0.0);
    final level = math.cos(pitch);
    camera
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(
        eye +
            Vector3(
              math.sin(yaw) * level,
              math.sin(pitch),
              -math.cos(yaw) * level,
            ),
        up: Vector3(0.0, 1.0, 0.0),
      );
  }
}

/// A kind for a type the application has not been taught yet.
///
/// **A level names things a game does not spawn yet**, and a registry that has
/// never heard of them refuses the document at all. So every type is accepted
/// and none is given a meaning: they are coordinates with words attached until
/// there is something to spawn them into.
final class OpenKind extends EntityKind {
  const OpenKind(super.type);
}

/// A registry that accepts every type [level] names and gives none of them a
/// meaning — see [OpenKind].
EntityRegistry openRegistryFor(Level level) => EntityRegistry(<EntityKind>[
  for (final type in level.entities.map((EntityDef e) => e.type).toSet())
    OpenKind(type),
]);
