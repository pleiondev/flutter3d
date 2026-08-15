import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// Something that walks a route and will not walk off the end of the world.
///
/// The whole brain a platformer's first enemy needs, and deliberately not more:
/// it does not chase, it does not notice the player, and it holds its own
/// waypoints rather than asking the engine for a route. `ActorSystem` has one
/// flow field because everything in a shooter walks towards the same place, and
/// a patrol is the case that wants the opposite — see `Mind.steerTowards`,
/// which is why that exists separately from `steerTowardsFocus`.
///
/// **The ledge probe is the part that matters.** An enemy that walks off its
/// own platform is an enemy the level cannot rely on, and one that turns at a
/// wall but not at a drop looks fine in a room and is useless outdoors.
base class Patrol extends Brain {
  Patrol({
    required List<Vector3> route,
    this.speed = 0.55,
    this.pause = 0.6,
    this.ledgeProbe = 0.9,
  })  : _route = <Vector3>[for (final at in route) at.clone()],
        assert(route.length >= 2, 'a patrol between fewer than two posts is a '
            'thing standing still, and that is `halt`');

  final List<Vector3> _route;

  /// A fraction of the body's walking speed: a patrol that moves at a run has
  /// nothing left to do when it notices anything.
  final double speed;

  /// How long it waits at each post, in seconds. Zero paces without stopping.
  final double pause;

  /// How far ahead to look for floor, in metres.
  final double ledgeProbe;

  int _target = 1;
  double _waiting = 0.0;

  /// Which post it is walking towards. For a test, and for a save.
  int get target => _target;

  Vector3 get destination => _route[_target];

  @override
  void act(Mind it) {
    final body = it.actor.body;
    if (body == null) return;

    if (_waiting > 0.0) {
      _waiting -= it.dt;
      it.halt();
      return;
    }

    final to = destination;
    final dx = to.x - body.position.x;
    final dz = to.z - body.position.z;
    if (dx * dx + dz * dz < 0.36) {
      _arrive();
      it.halt();
      return;
    }

    // A ledge ahead is a reason to turn round rather than a reason to stop:
    // an enemy that stands at the edge for ever is an enemy the player learns
    // to ignore.
    if (_atALedge(it, dx, dz)) {
      _arrive();
      it.halt();
      return;
    }

    it
      ..steerTowards(to)
      ..turnTowards(dx, dz);
    // Scaled after steering, because `steerTowards` normalises: the length of
    // the wish is the speed asked for.
    final body2 = it.actor.body;
    if (body2 != null) it.steer(_scaled(to, body2.position));
  }

  Vector3 _scaled(Vector3 to, Vector3 from) {
    final wish = Vector3(to.x - from.x, 0.0, to.z - from.z);
    final length = wish.length;
    if (length < 1e-6) return Vector3.zero();
    return wish..scale(speed / length);
  }

  void _arrive() {
    _target = (_target + 1) % _route.length;
    _waiting = pause;
  }

  /// Whether there is floor under the next step.
  ///
  /// A sweep down from a point ahead of the feet, against the world only: an
  /// actor standing on another actor is not floor worth walking onto.
  bool _atALedge(Mind it, double dx, double dz) {
    final body = it.actor.body;
    if (body == null || !body.isGrounded) return false;
    final length = math.sqrt(dx * dx + dz * dz);
    if (length < 1e-6) return false;

    _ahead
      ..setFrom(body.position)
      ..x += dx / length * ledgeProbe
      ..z += dz / length * ledgeProbe;
    _down.setValues(0.0, -(body.halfExtents.y + 0.6), 0.0);
    return !body.world.sweep(
      body.shape,
      _ahead,
      _down,
      _hit,
      ignore: body.collider,
      mask: CollisionLayers.world,
    );
  }

  final Vector3 _ahead = Vector3.zero();
  final Vector3 _down = Vector3.zero();
  final SweepHit _hit = SweepHit();

  @override
  Map<String, Object?> save() => <String, Object?>{
        'target': _target,
        'waiting': _waiting,
      };

  @override
  void restore(Map<String, Object?> from) {
    final target = from['target'];
    if (target is num) _target = target.toInt() % _route.length;
    final waiting = from['waiting'];
    if (waiting is num) _waiting = waiting.toDouble();
  }
}

/// A patrol that jumps the gaps in its route instead of turning at them.
///
/// The second archetype, and it exists to make one point: a brain asks the body
/// to jump through the same buffered request the player's jump goes through, so
/// a brain that asks every step does not fly. Writing `velocity.y` would work
/// once and then keep working, in the air, for ever.
final class Leaper extends Patrol {
  Leaper({
    required super.route,
    super.speed,
    super.pause,
    super.ledgeProbe,
    this.reach = 5.0,
  });

  /// How wide a gap it will try. Beyond this it turns round like any patrol.
  final double reach;

  @override
  void act(Mind it) {
    final body = it.actor.body;
    if (body == null) {
      super.act(it);
      return;
    }

    final to = destination;
    final dx = to.x - body.position.x;
    final dz = to.z - body.position.z;
    final length = math.sqrt(dx * dx + dz * dz);

    if (length > 1e-6 && body.isGrounded && _atALedge(it, dx, dz)) {
      // Is there floor on the far side, within a jump? If there is, jump; if
      // there is not, this is a patrol and patrols turn round.
      _landing
        ..setFrom(body.position)
        ..x += dx / length * reach
        ..z += dz / length * reach;
      _probe.setValues(0.0, -(body.halfExtents.y + 1.2), 0.0);
      final ground = body.world.sweep(
        body.shape,
        _landing,
        _probe,
        _far,
        ignore: body.collider,
        mask: CollisionLayers.world,
      );
      if (ground) {
        it
          ..jump()
          ..steer(_toward(to, body.position));
        return;
      }
    }

    super.act(it);
  }

  Vector3 _toward(Vector3 to, Vector3 from) {
    final wish = Vector3(to.x - from.x, 0.0, to.z - from.z);
    final length = wish.length;
    if (length < 1e-6) return Vector3.zero();
    return wish..scale(1.0 / length);
  }

  final Vector3 _landing = Vector3.zero();
  final Vector3 _probe = Vector3.zero();
  final SweepHit _far = SweepHit();
}
